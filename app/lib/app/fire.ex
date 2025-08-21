defmodule App.Fire do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @derive {Jason.Encoder,
           only: [:latitude, :longitude, :detected_at, :confidence, :frp, :satellite]}
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "fires" do
    # Core identification
    field :latitude, :float
    field :longitude, :float
    field :point, Geo.PostGIS.Geometry

    # NASA identifiers & metadata
    field :satellite, :string
    field :instrument, :string
    field :version, :string

    # Detection details
    field :detected_at, :utc_datetime
    field :confidence, :string
    field :daynight, :string

    # Fire intensity data
    field :bright_ti4, :float
    field :bright_ti5, :float
    field :frp, :float

    # Pixel quality
    field :scan, :float
    field :track, :float

    # Deduplication key
    field :nasa_id, :string

    # Associations
    belongs_to :fire_incident, App.FireIncident

    timestamps()
  end

  def changeset(fire, attrs) do
    fire
    |> cast(attrs, [
      :latitude,
      :longitude,
      :satellite,
      :instrument,
      :version,
      :detected_at,
      :confidence,
      :daynight,
      :bright_ti4,
      :bright_ti5,
      :frp,
      :scan,
      :track,
      :nasa_id,
      :fire_incident_id
    ])
    |> cast_nasa_numeric_fields(attrs)
    |> validate_required([:latitude, :longitude, :detected_at, :confidence, :satellite])
    |> validate_latitude()
    |> validate_longitude()
    |> unique_constraint(:nasa_id)
    |> maybe_create_point()
  end

  defp cast_nasa_numeric_fields(changeset, attrs) do
    # Handle NASA data where numeric fields come as strings
    changeset
    |> maybe_cast_float(:latitude, attrs)
    |> maybe_cast_float(:longitude, attrs)
    |> maybe_cast_float(:bright_ti4, attrs)
    |> maybe_cast_float(:bright_ti5, attrs)
    |> maybe_cast_float(:frp, attrs)
    |> maybe_cast_float(:scan, attrs)
    |> maybe_cast_float(:track, attrs)
  end

  defp maybe_cast_float(changeset, field, attrs) do
    field_str = to_string(field)

    case Map.get(attrs, field_str) do
      value when is_binary(value) ->
        case Float.parse(value) do
          {float_val, _} -> put_change(changeset, field, float_val)
          :error -> changeset
        end

      _ ->
        changeset
    end
  end

  defp validate_latitude(changeset) do
    validate_number(changeset, :latitude,
      greater_than_or_equal_to: -90,
      less_than_or_equal_to: 90,
      message: "must be between -90 and 90"
    )
  end

  defp validate_longitude(changeset) do
    validate_number(changeset, :longitude,
      greater_than_or_equal_to: -180,
      less_than_or_equal_to: 180,
      message: "must be between -180 and 180"
    )
  end

  defp maybe_create_point(changeset) do
    latitude = get_field(changeset, :latitude) || get_change(changeset, :latitude)
    longitude = get_field(changeset, :longitude) || get_change(changeset, :longitude)

    case {latitude, longitude} do
      {lat, lng} when is_number(lat) and is_number(lng) ->
        point = %Geo.Point{coordinates: {lng, lat}, srid: 4326}
        put_change(changeset, :point, point)

      _ ->
        changeset
    end
  end

  def parse_nasa_datetime(acq_date, acq_time) do
    # Pad time to 4 digits: 105 -> "0105", 1842 -> "1842"
    time_str = String.pad_leading(to_string(acq_time), 4, "0")
    hour = String.slice(time_str, 0, 2)
    minute = String.slice(time_str, 2, 2)

    # Create ISO datetime string
    datetime_str = "#{acq_date}T#{hour}:#{minute}:00Z"

    case DateTime.from_iso8601(datetime_str) do
      {:ok, datetime, 0} -> {:ok, datetime}
      {:error, reason} -> {:error, reason}
    end
  end

  def generate_nasa_id(nasa_data) do
    lat = parse_float_value(nasa_data["latitude"]) |> Float.round(4)
    lng = parse_float_value(nasa_data["longitude"]) |> Float.round(4)
    date = nasa_data["acq_date"]
    time = nasa_data["acq_time"]
    satellite = nasa_data["satellite"]

    "#{lat}_#{lng}_#{date}_#{time}_#{satellite}"
  end

  defp parse_float_value(value) when is_binary(value) do
    case Float.parse(value) do
      {float_val, _} -> float_val
      :error -> 0.0
    end
  end

  defp parse_float_value(value) when is_number(value), do: value * 1.0
  defp parse_float_value(_), do: 0.0

  def create_from_nasa_data(nasa_data) do
    with {:ok, detected_at} <- parse_nasa_datetime(nasa_data["acq_date"], nasa_data["acq_time"]) do
      attrs =
        Map.merge(nasa_data, %{
          "detected_at" => detected_at,
          "nasa_id" => generate_nasa_id(nasa_data)
        })

      %__MODULE__{}
      |> changeset(attrs)
      |> App.Repo.insert()
    end
  end

  def high_quality?(fire) do
    fire.confidence in ["n", "h"] and
      fire.frp >= 5.0
  end

  @doc """
  Returns a compact representation of fire data for frontend consumption.
  Uses arrays instead of objects to minimize payload size.
  Format: [lat, lng, unix_timestamp, confidence, frp, satellite]
  """
  def to_compact_array(fire) do
    unix_timestamp = DateTime.to_unix(fire.detected_at)

    [
      fire.latitude,
      fire.longitude,
      unix_timestamp,
      fire.confidence,
      fire.frp,
      fire.satellite
    ]
  end

  @doc """
  Converts a list of fires to a compact MessagePack-optimized format.
  Returns a map with metadata and compact fire data arrays.
  """
  def to_compact_msgpack(fires) when is_list(fires) do
    compact_fires = Enum.map(fires, &to_compact_array/1)

    %{
      # Metadata for frontend to understand the array format
      format: "compact_v1",
      fields: ["lat", "lng", "timestamp", "confidence", "frp", "satellite"],
      count: length(fires),
      data: compact_fires
    }
  end

  def recent_fires(hours_back), do: recent_fires(hours_back, [])

  def recent_fires(hours_back, opts) when is_integer(hours_back) and is_list(opts) do
    :telemetry.span([:fire, :recent_fires], %{hours_back: hours_back, opts: opts}, fn ->
      cutoff = DateTime.utc_now() |> DateTime.add(-hours_back, :hour)
      limit_count = Keyword.get(opts, :limit)
      quality = Keyword.get(opts, :quality, :all)

      base =
        __MODULE__
        |> where([f], f.detected_at >= ^cutoff)

      filtered =
        case quality do
          :high -> where(base, [f], f.confidence in ["n", "h"] and f.frp >= 5.0)
          _ -> base
        end

      query =
        filtered
        |> order_by([f], desc: f.detected_at)

      query = if is_integer(limit_count), do: limit(query, ^limit_count), else: query

      result = App.Repo.all(query)
      {result, %{result_count: length(result)}}
    end)
  end

  @doc """
  Returns recent fires within each of the given locations' monitoring radius.

  - `locations`: list of `%App.Location{}` with `point` and `radius`
  - `hours_back`: integer hours window
  - opts:
    - `:limit` optional integer limit
    - `:quality` optional `:all | :high` filter (same as `recent_fires/2`)
  """
  def recent_fires_near_locations(locations, hours_back, opts \\ [])
  def recent_fires_near_locations([], _hours_back, _opts), do: []

  def recent_fires_near_locations(locations, hours_back, opts) when is_list(locations) do
    :telemetry.span(
      [:fire, :recent_fires_near_locations],
      %{hours_back: hours_back, opts: opts, location_count: length(locations)},
      fn ->
        cutoff = DateTime.utc_now() |> DateTime.add(-hours_back, :hour)
        limit_count = Keyword.get(opts, :limit)
        quality = Keyword.get(opts, :quality, :all)

        # Calculate bounding box to pre-filter spatially
        bounding_box = calculate_bounding_box(locations)

        base =
          __MODULE__
          |> where([f], f.detected_at >= ^cutoff)
          # Add bounding box pre-filter to reduce spatial candidates
          |> where([f], f.latitude >= ^bounding_box.min_lat)
          |> where([f], f.latitude <= ^bounding_box.max_lat)
          |> where([f], f.longitude >= ^bounding_box.min_lng)
          |> where([f], f.longitude <= ^bounding_box.max_lng)

        filtered =
          case quality do
            :high -> where(base, [f], f.confidence in ["n", "h"] and f.frp >= 5.0)
            _ -> base
          end

        # Build OR of ST_DWithin for each location with its radius
        location_condition =
          Enum.reduce(locations, nil, fn loc, acc ->
            loc_point = %Geo.Point{coordinates: {loc.longitude, loc.latitude}, srid: 4326}

            cond_expr =
              dynamic(
                [f],
                fragment(
                  "ST_DWithin(ST_Transform(?, 3857), ST_Transform(?, 3857), ?)",
                  f.point,
                  ^loc_point,
                  ^loc.radius
                )
              )

            if acc do
              dynamic([f], ^acc or ^cond_expr)
            else
              cond_expr
            end
          end)

        query =
          filtered
          |> where(^location_condition)
          |> order_by([f], desc: f.detected_at)

        query = if is_integer(limit_count), do: limit(query, ^limit_count), else: query

        result = App.Repo.all(query)
        {result, %{result_count: length(result)}}
      end
    )
  end

  def near_location(latitude, longitude, radius_meters) do
    # Fast bounding box pre-filter to reduce candidates
    # ~111km per degree latitude
    lat_offset = radius_meters / 111_000.0
    lng_offset = radius_meters / (111_000.0 * :math.cos(latitude * :math.pi() / 180))

    location_point = %Geo.Point{coordinates: {longitude, latitude}, srid: 4326}

    __MODULE__
    |> where([f], f.latitude >= ^(latitude - lat_offset))
    |> where([f], f.latitude <= ^(latitude + lat_offset))
    |> where([f], f.longitude >= ^(longitude - lng_offset))
    |> where([f], f.longitude <= ^(longitude + lng_offset))
    |> where(
      [f],
      fragment(
        "ST_DWithin(ST_Transform(?, 3857), ST_Transform(?, 3857), ?)",
        f.point,
        ^location_point,
        ^radius_meters
      )
    )
    |> App.Repo.all()
  end

  def cleanup_old(days_back) do
    cutoff = DateTime.utc_now() |> DateTime.add(-days_back, :day)

    __MODULE__
    |> where([f], f.detected_at < ^cutoff)
    |> App.Repo.delete_all()
  end

  def bulk_insert(nasa_data_list) do
    processed_data =
      nasa_data_list
      |> Enum.map(&process_nasa_data_for_insert/1)
      |> Enum.reject(&is_nil/1)

    # PostgreSQL has a parameter limit of 65535
    # With 18 fields per fire: 65535 ÷ 18 ≈ 3640 fires per batch
    # Safe batch size
    batch_size = 3000

    processed_data
    |> Enum.chunk_every(batch_size)
    |> Enum.reduce({0, nil}, fn batch, {total_count, _} ->
      {count, _} = App.Repo.insert_all(__MODULE__, batch, on_conflict: :nothing)
      {total_count + count, nil}
    end)
  end

  defp process_nasa_data_for_insert(nasa_data) do
    with {:ok, detected_at} <- parse_nasa_datetime(nasa_data["acq_date"], nasa_data["acq_time"]) do
      lat = parse_float_value(nasa_data["latitude"])
      lng = parse_float_value(nasa_data["longitude"])

      %{
        id: Ecto.UUID.generate(),
        latitude: lat,
        longitude: lng,
        point: %Geo.Point{coordinates: {lng, lat}, srid: 4326},
        satellite: nasa_data["satellite"],
        instrument: nasa_data["instrument"],
        version: nasa_data["version"],
        detected_at: detected_at,
        confidence: nasa_data["confidence"],
        daynight: nasa_data["daynight"],
        bright_ti4: parse_float_value(nasa_data["bright_ti4"]),
        bright_ti5: parse_float_value(nasa_data["bright_ti5"]),
        frp: parse_float_value(nasa_data["frp"]),
        scan: parse_float_value(nasa_data["scan"]),
        track: parse_float_value(nasa_data["track"]),
        nasa_id: generate_nasa_id(nasa_data),
        inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
        updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      }
    else
      _ -> nil
    end
  end

  @doc """
  Finds an existing incident for a new fire based on spatial clustering.
  Returns the incident_id if found, nil otherwise.
  """
  def find_incident_for_fire(new_fire, clustering_distance_meters \\ 5000, expiry_hours \\ 72) do
    cutoff = DateTime.utc_now() |> DateTime.add(-expiry_hours, :hour)
    
    # Pre-calculate bounding box for much faster initial filtering
    # ~111km per degree latitude, adjust for longitude by latitude
    lat_offset = clustering_distance_meters / 111_000.0
    lng_offset = clustering_distance_meters / (111_000.0 * :math.cos(new_fire.latitude * :math.pi() / 180))

    # Get candidates using bounding box (very fast with regular indexes)
    candidates = 
      __MODULE__
      |> where([f], f.detected_at >= ^cutoff)
      |> where([f], not is_nil(f.fire_incident_id))
      |> where([f], f.latitude >= ^(new_fire.latitude - lat_offset))
      |> where([f], f.latitude <= ^(new_fire.latitude + lat_offset))
      |> where([f], f.longitude >= ^(new_fire.longitude - lng_offset))
      |> where([f], f.longitude <= ^(new_fire.longitude + lng_offset))
      |> select([f], %{fire_incident_id: f.fire_incident_id, latitude: f.latitude, longitude: f.longitude})
      |> App.Repo.all()

    # Filter candidates by actual distance (in memory - much faster for small sets)
    clustering_distance_degrees = clustering_distance_meters / 111_000.0
    
    candidates
    |> Enum.find(fn candidate ->
      distance = haversine_distance(
        new_fire.latitude, new_fire.longitude,
        candidate.latitude, candidate.longitude
      )
      distance <= clustering_distance_degrees
    end)
    |> case do
      nil -> nil
      candidate -> candidate.fire_incident_id
    end
  end

  # Simple haversine distance calculation (returns degrees)
  defp haversine_distance(lat1, lon1, lat2, lon2) do
    d_lat = (lat2 - lat1) * :math.pi() / 180
    d_lon = (lon2 - lon1) * :math.pi() / 180
    
    a = :math.sin(d_lat / 2) * :math.sin(d_lat / 2) +
        :math.cos(lat1 * :math.pi() / 180) * :math.cos(lat2 * :math.pi() / 180) *
        :math.sin(d_lon / 2) * :math.sin(d_lon / 2)
    
    c = 2 * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))
    c * 180 / :math.pi()  # Return in degrees
  end

  @doc """
  Assigns a fire to an incident, either creating a new incident or updating an existing one.
  """
  def assign_to_incident(fire, clustering_distance_meters \\ 5000, expiry_hours \\ 72) do
    case find_incident_for_fire(fire, clustering_distance_meters, expiry_hours) do
      nil ->
        # Create new incident
        case App.FireIncident.create_from_fire(fire) do
          {:ok, incident} ->
            # Update fire with incident_id
            update_fire_incident(fire, incident.id)

          error ->
            error
        end

      incident_id ->
        # Add to existing incident
        incident = App.Repo.get!(App.FireIncident, incident_id)

        with {:ok, _updated_incident} <- App.FireIncident.add_fire(incident, fire),
             {:ok, updated_fire} <- update_fire_incident(fire, incident_id) do
          # Recalculate incident center after adding fire
          App.FireIncident.recalculate_center(incident)
          {:ok, updated_fire}
        else
          error -> error
        end
    end
  end

  @doc """
  Updates a fire's incident association.
  """
  def update_fire_incident(fire, incident_id) do
    fire
    |> changeset(%{fire_incident_id: incident_id})
    |> App.Repo.update()
  end

  @doc """
  Processes fires from NASA data and assigns them to incidents.
  """
  def process_fires_with_clustering(nasa_data_list, opts \\ []) do
    clustering_distance = Keyword.get(opts, :clustering_distance, 5000)
    expiry_hours = Keyword.get(opts, :expiry_hours, 72)

    processed_data =
      nasa_data_list
      |> Enum.map(&process_nasa_data_for_insert/1)
      |> Enum.reject(&is_nil/1)

    # Insert fires first (without incident assignment)
    batch_size = 3000

    {total_inserted, _} =
      processed_data
      |> Enum.chunk_every(batch_size)
      |> Enum.reduce({0, nil}, fn batch, {total_count, _} ->
        {count, _} = App.Repo.insert_all(__MODULE__, batch, on_conflict: :nothing)
        {total_count + count, nil}
      end)

    # Now assign newly inserted fires to incidents
    if total_inserted > 0 do
      # Get fires that don't have incident assignments yet
      # Use recent cutoff to focus on newly processed fires
      recent_cutoff = DateTime.utc_now() |> DateTime.add(-1, :hour)
      
      unassigned_fires =
        __MODULE__
        |> where([f], is_nil(f.fire_incident_id))
        |> where([f], f.inserted_at >= ^recent_cutoff)
        |> order_by([f], asc: f.detected_at)
        |> App.Repo.all()

      # Process each unassigned fire for clustering
      clustering_results =
        unassigned_fires
        |> Enum.map(fn fire ->
          case assign_to_incident(fire, clustering_distance, expiry_hours) do
            {:ok, _} -> :ok
            {:error, reason} -> {:error, fire.id, reason}
          end
        end)

      clustering_errors = Enum.filter(clustering_results, &match?({:error, _, _}, &1))

      if length(clustering_errors) > 0 do
        require Logger
        Logger.warning("Some fires could not be assigned to incidents: #{inspect(clustering_errors)}")
      end
    end

    {total_inserted, nil}
  end

  # Calculate bounding box for all locations to pre-filter spatially
  defp calculate_bounding_box(locations) do
    # Add padding to account for the largest radius
    max_radius_degrees =
      locations
      |> Enum.map(& &1.radius)
      |> Enum.max()
      # Convert meters to degrees (approximate)
      |> Kernel./(111_000.0)

    # Find the bounds of all location points
    lats = Enum.map(locations, & &1.latitude)
    lngs = Enum.map(locations, & &1.longitude)

    %{
      min_lat: Enum.min(lats) - max_radius_degrees,
      max_lat: Enum.max(lats) + max_radius_degrees,
      min_lng: Enum.min(lngs) - max_radius_degrees,
      max_lng: Enum.max(lngs) + max_radius_degrees
    }
  end
end
