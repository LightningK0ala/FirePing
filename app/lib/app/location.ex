defmodule App.Location do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @derive {Jason.Encoder, only: [:id, :name, :latitude, :longitude, :radius]}
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "locations" do
    field :name, :string
    field :latitude, :float
    field :longitude, :float
    field :radius, :integer
    field :point, Geo.PostGIS.Geometry

    belongs_to :user, App.User

    timestamps(type: :utc_datetime)
  end

  def changeset(location, attrs) do
    location
    |> cast(attrs, [:name, :latitude, :longitude, :radius, :user_id])
    |> validate_required([:name, :latitude, :longitude, :radius, :user_id])
    |> validate_latitude()
    |> validate_longitude()
    |> validate_radius()
    |> maybe_create_point()
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

  defp validate_radius(changeset) do
    validate_number(changeset, :radius,
      greater_than: 0,
      message: "must be greater than 0"
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

  def create_location(user, attrs) do
    attrs_with_user = %{
      "name" => attrs["name"],
      "latitude" => attrs["latitude"],
      "longitude" => attrs["longitude"],
      "radius" => attrs["radius"],
      "user_id" => user.id
    }

    %__MODULE__{}
    |> changeset(attrs_with_user)
    |> App.Repo.insert()
  end

  def locations_for_user(user) do
    __MODULE__
    |> where([l], l.user_id == ^user.id)
    |> App.Repo.all()
  end

  def list_for_user(user_id) do
    __MODULE__
    |> where([l], l.user_id == ^user_id)
    |> App.Repo.all()
  end

  def within_radius(fire_lat, fire_lng, radius_meters) do
    fire_point = %Geo.Point{coordinates: {fire_lng, fire_lat}, srid: 4326}

    __MODULE__
    |> where(
      [l],
      fragment(
        "ST_DWithin(ST_Transform(?, 3857), ST_Transform(?, 3857), ?)",
        l.point,
        ^fire_point,
        ^radius_meters
      )
    )
    |> App.Repo.all()
  end

  def delete_location(location) do
    App.Repo.delete(location)
  end

  def update_location(%__MODULE__{} = location, attrs) when is_map(attrs) do
    location
    |> changeset(attrs)
    |> App.Repo.update()
  end
end
