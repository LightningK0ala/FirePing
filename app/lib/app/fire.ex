defmodule App.Fire do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @derive {Jason.Encoder, only: [:id, :latitude, :longitude, :detected_at, :confidence, :frp, :satellite]}
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

    timestamps()
  end

  def changeset(fire, attrs) do
    fire
    |> cast(attrs, [
      :latitude, :longitude, :satellite, :instrument, :version,
      :detected_at, :confidence, :daynight, :bright_ti4, :bright_ti5,
      :frp, :scan, :track, :nasa_id
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
      _ -> changeset
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
    lat = Float.round(nasa_data["latitude"], 4)
    lng = Float.round(nasa_data["longitude"], 4)
    date = nasa_data["acq_date"]
    time = nasa_data["acq_time"]
    satellite = nasa_data["satellite"]
    
    "#{lat}_#{lng}_#{date}_#{time}_#{satellite}"
  end

  def create_from_nasa_data(nasa_data) do
    with {:ok, detected_at} <- parse_nasa_datetime(nasa_data["acq_date"], nasa_data["acq_time"]) do
      attrs = Map.merge(nasa_data, %{
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

  def recent_fires(hours_back), do: recent_fires(hours_back, [])

  def recent_fires(hours_back, opts) when is_integer(hours_back) and is_list(opts) do
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

    App.Repo.all(query)
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

    # Build OR of ST_DWithin for each location with its radius
    location_condition =
      Enum.reduce(locations, nil, fn loc, acc ->
        loc_point = %Geo.Point{coordinates: {loc.longitude, loc.latitude}, srid: 4326}
        cond_expr = dynamic([f], fragment("ST_DWithin(ST_Transform(?, 3857), ST_Transform(?, 3857), ?)", f.point, ^loc_point, ^loc.radius))

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

    App.Repo.all(query)
  end


  def near_location(latitude, longitude, radius_meters) do
    # Fast bounding box pre-filter to reduce candidates
    lat_offset = radius_meters / 111_000.0  # ~111km per degree latitude
    lng_offset = radius_meters / (111_000.0 * :math.cos(latitude * :math.pi() / 180))
    
    location_point = %Geo.Point{coordinates: {longitude, latitude}, srid: 4326}
    
    __MODULE__
    |> where([f], f.latitude >= ^(latitude - lat_offset))
    |> where([f], f.latitude <= ^(latitude + lat_offset))  
    |> where([f], f.longitude >= ^(longitude - lng_offset))
    |> where([f], f.longitude <= ^(longitude + lng_offset))
    |> where([f], fragment("ST_DWithin(ST_Transform(?, 3857), ST_Transform(?, 3857), ?)", 
                          f.point, ^location_point, ^radius_meters))
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
    batch_size = 3000  # Safe batch size
    
    processed_data
    |> Enum.chunk_every(batch_size)
    |> Enum.reduce({0, nil}, fn batch, {total_count, _} ->
      {count, _} = App.Repo.insert_all(__MODULE__, batch, on_conflict: :nothing)
      {total_count + count, nil}
    end)
  end

  defp process_nasa_data_for_insert(nasa_data) do
    with {:ok, detected_at} <- parse_nasa_datetime(nasa_data["acq_date"], nasa_data["acq_time"]) do
      lat = nasa_data["latitude"]
      lng = nasa_data["longitude"]
      
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
        bright_ti4: nasa_data["bright_ti4"],
        bright_ti5: nasa_data["bright_ti5"],
        frp: nasa_data["frp"],
        scan: nasa_data["scan"],
        track: nasa_data["track"],
        nasa_id: generate_nasa_id(nasa_data),
        inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
        updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      }
    else
      _ -> nil
    end
  end
end