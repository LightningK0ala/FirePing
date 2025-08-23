defmodule App.FireIncident do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @derive {Jason.Encoder,
           only: [
             :id,
             :status,
             :center_latitude,
             :center_longitude,
             :min_latitude,
             :max_latitude,
             :min_longitude,
             :max_longitude,
             :fire_count,
             :first_detected_at,
             :last_detected_at,
             :max_frp,
             :avg_frp
           ]}
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "fire_incidents" do
    # Status tracking
    field :status, :string, default: "active"

    # Center point for map display
    field :center_latitude, :float
    field :center_longitude, :float
    field :center_point, Geo.PostGIS.Geometry

    # Bounding box for efficient map display
    field :min_latitude, :float
    field :max_latitude, :float
    field :min_longitude, :float
    field :max_longitude, :float

    # Incident metrics
    field :fire_count, :integer, default: 0
    field :first_detected_at, :utc_datetime
    field :last_detected_at, :utc_datetime

    # Fire intensity metrics
    field :max_frp, :float
    field :min_frp, :float
    field :avg_frp, :float
    field :total_frp, :float

    # Incident lifecycle
    field :ended_at, :utc_datetime

    # Associations
    has_many :fires, App.Fire, foreign_key: :fire_incident_id

    timestamps()
  end

  @valid_statuses ~w(active ended)

  def changeset(fire_incident, attrs) do
    fire_incident
    |> cast(attrs, [
      :status,
      :center_latitude,
      :center_longitude,
      :min_latitude,
      :max_latitude,
      :min_longitude,
      :max_longitude,
      :fire_count,
      :first_detected_at,
      :last_detected_at,
      :max_frp,
      :min_frp,
      :avg_frp,
      :total_frp,
      :ended_at
    ])
    |> validate_required([
      :center_latitude,
      :center_longitude,
      :first_detected_at,
      :last_detected_at
    ])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_latitude()
    |> validate_longitude()
    |> validate_fire_count()
    |> maybe_create_center_point()
  end

  defp validate_latitude(changeset) do
    validate_number(changeset, :center_latitude,
      greater_than_or_equal_to: -90,
      less_than_or_equal_to: 90,
      message: "must be between -90 and 90"
    )
  end

  defp validate_longitude(changeset) do
    validate_number(changeset, :center_longitude,
      greater_than_or_equal_to: -180,
      less_than_or_equal_to: 180,
      message: "must be between -180 and 180"
    )
  end

  defp validate_fire_count(changeset) do
    validate_number(changeset, :fire_count,
      greater_than_or_equal_to: 0,
      message: "must be greater than or equal to 0"
    )
  end

  defp maybe_create_center_point(changeset) do
    latitude = get_field(changeset, :center_latitude) || get_change(changeset, :center_latitude)

    longitude =
      get_field(changeset, :center_longitude) || get_change(changeset, :center_longitude)

    case {latitude, longitude} do
      {lat, lng} when is_number(lat) and is_number(lng) ->
        point = %Geo.Point{coordinates: {lng, lat}, srid: 4326}
        put_change(changeset, :center_point, point)

      _ ->
        changeset
    end
  end

  @doc """
  Creates a new fire incident from a fire detection.
  """
  def create_from_fire(fire) do
    attrs = %{
      status: "active",
      center_latitude: fire.latitude,
      center_longitude: fire.longitude,
      min_latitude: fire.latitude,
      max_latitude: fire.latitude,
      min_longitude: fire.longitude,
      max_longitude: fire.longitude,
      fire_count: 1,
      first_detected_at: fire.detected_at,
      last_detected_at: fire.detected_at,
      max_frp: fire.frp,
      min_frp: fire.frp,
      avg_frp: fire.frp,
      total_frp: fire.frp
    }

    %__MODULE__{}
    |> changeset(attrs)
    |> App.Repo.insert()
  end

  @doc """
  Updates incident metrics when a new fire is added.
  """
  def add_fire(incident, fire) do
    new_fire_count = incident.fire_count + 1
    new_total_frp = (incident.total_frp || 0) + (fire.frp || 0)
    new_avg_frp = if new_fire_count > 0, do: new_total_frp / new_fire_count, else: 0

    # Calculate new center point (weighted average)
    total_lat = incident.center_latitude * incident.fire_count + fire.latitude
    total_lng = incident.center_longitude * incident.fire_count + fire.longitude
    new_center_lat = total_lat / new_fire_count
    new_center_lng = total_lng / new_fire_count

    attrs = %{
      fire_count: new_fire_count,
      last_detected_at: max_datetime(incident.last_detected_at, fire.detected_at),
      max_frp: max_float(incident.max_frp, fire.frp),
      min_frp: min_float(incident.min_frp, fire.frp),
      avg_frp: new_avg_frp,
      total_frp: new_total_frp,
      center_latitude: new_center_lat,
      center_longitude: new_center_lng,
      # Expand bounds to include new fire
      min_latitude: min_float(incident.min_latitude, fire.latitude),
      max_latitude: max_float(incident.max_latitude, fire.latitude),
      min_longitude: min_float(incident.min_longitude, fire.longitude),
      max_longitude: max_float(incident.max_longitude, fire.longitude)
    }

    incident
    |> changeset(attrs)
    |> App.Repo.update()
  end

  @doc """
  Recalculates incident center point and bounds from all associated fires.
  """
  def recalculate_center(incident) do
    fires = App.Repo.preload(incident, :fires).fires

    case fires do
      [] ->
        {:error, :no_fires}

      fires ->
        {total_lat, total_lng, min_lat, max_lat, min_lng, max_lng} =
          fires
          |> Enum.reduce({0.0, 0.0, nil, nil, nil, nil}, fn fire,
                                                            {lat_acc, lng_acc, min_lat, max_lat,
                                                             min_lng, max_lng} ->
            {
              lat_acc + fire.latitude,
              lng_acc + fire.longitude,
              if(min_lat, do: min(min_lat, fire.latitude), else: fire.latitude),
              if(max_lat, do: max(max_lat, fire.latitude), else: fire.latitude),
              if(min_lng, do: min(min_lng, fire.longitude), else: fire.longitude),
              if(max_lng, do: max(max_lng, fire.longitude), else: fire.longitude)
            }
          end)

        fire_count = length(fires)
        center_lat = total_lat / fire_count
        center_lng = total_lng / fire_count

        incident
        |> changeset(%{
          center_latitude: center_lat,
          center_longitude: center_lng,
          min_latitude: min_lat,
          max_latitude: max_lat,
          min_longitude: min_lng,
          max_longitude: max_lng
        })
        |> App.Repo.update()
    end
  end

  @doc """
  Marks an incident as ended.
  """
  def mark_as_ended(incident) do
    incident
    |> changeset(%{
      status: "ended",
      ended_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> App.Repo.update()
  end

  @doc """
  Returns active incidents that were last detected within the given hours.
  """
  def active_incidents_within_hours(hours) do
    cutoff = DateTime.utc_now() |> DateTime.add(-hours, :hour)

    __MODULE__
    |> where([i], i.status == "active")
    |> where([i], i.last_detected_at >= ^cutoff)
    |> App.Repo.all()
  end

  @doc """
  Returns incidents that should be ended (no activity for threshold hours).
  """
  def incidents_to_end(threshold_hours \\ nil) do
    threshold_hours = threshold_hours || App.Config.incident_cleanup_threshold_hours()
    cutoff = DateTime.utc_now() |> DateTime.add(-threshold_hours, :hour)

    __MODULE__
    |> where([i], i.status == "active")
    |> where([i], i.last_detected_at < ^cutoff)
    |> App.Repo.all()
  end

  @doc """
  Returns incidents for the given list of fires by extracting their incident IDs.
  """
  def incidents_from_fires(fires) when is_list(fires) do
    incident_ids =
      fires
      |> Enum.map(& &1.fire_incident_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case incident_ids do
      [] ->
        []

      ids ->
        __MODULE__
        |> where([i], i.id in ^ids)
        |> order_by([i], desc: i.last_detected_at)
        |> App.Repo.all()
    end
  end

  @doc """
  Deletes a fire incident and all associated fires (via cascade delete).
  """
  def delete_incident(incident) do
    case App.Repo.get(__MODULE__, incident.id) do
      nil ->
        {:error, :not_found}

      found_incident ->
        App.Repo.delete(found_incident)
    end
  end

  @doc """
  Deletes ended incidents older than the specified number of days.
  Returns {deleted_incidents_count, deleted_fires_count}.
  """
  def delete_ended_incidents(days_old) do
    cutoff_date = DateTime.utc_now() |> DateTime.add(-days_old, :day)

    # Get incidents to be deleted and count their fires first
    incidents_to_delete =
      __MODULE__
      |> where([i], i.status == "ended")
      |> where([i], i.ended_at < ^cutoff_date)
      |> App.Repo.all()

    # Count fires that will be deleted (for reporting)
    fire_count =
      if length(incidents_to_delete) > 0 do
        incident_ids = Enum.map(incidents_to_delete, & &1.id)

        App.Fire
        |> where([f], f.fire_incident_id in ^incident_ids)
        |> App.Repo.aggregate(:count)
      else
        0
      end

    # Delete incidents (fires will cascade delete)
    {deleted_count, _} =
      __MODULE__
      |> where([i], i.status == "ended")
      |> where([i], i.ended_at < ^cutoff_date)
      |> App.Repo.delete_all()

    {deleted_count, fire_count}
  end

  # Helper functions
  defp max_datetime(dt1, dt2) do
    case DateTime.compare(dt1, dt2) do
      :lt -> dt2
      _ -> dt1
    end
  end

  defp max_float(nil, val), do: val
  defp max_float(val, nil), do: val
  defp max_float(val1, val2), do: max(val1, val2)

  defp min_float(nil, val), do: val
  defp min_float(val, nil), do: val
  defp min_float(val1, val2), do: min(val1, val2)
end
