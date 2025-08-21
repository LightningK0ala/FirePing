defmodule App.Factory do
  use ExMachina.Ecto, repo: App.Repo

  def user_factory do
    %App.User{
      email: sequence(:email, &"user#{&1}@example.com")
    }
  end

  def location_factory do
    %App.Location{
      name: sequence(:name, &"Location #{&1}"),
      # NYC coordinates (default)
      latitude: 40.7128,
      longitude: -74.0060,
      # 5km default radius
      radius: 5000,
      point: %Geo.Point{coordinates: {-74.0060, 40.7128}, srid: 4326},
      user: build(:user)
    }
  end

  # Use ExMachina's callback to update geometry when lat/lng change
  def location_factory(attrs) when is_map(attrs) do
    location = location_factory()
    updated_location = struct!(location, attrs)

    # Regenerate point if coordinates changed
    if Map.has_key?(attrs, :latitude) or Map.has_key?(attrs, :longitude) do
      point = %Geo.Point{
        coordinates: {updated_location.longitude, updated_location.latitude},
        srid: 4326
      }

      %{updated_location | point: point}
    else
      updated_location
    end
  end

  def fire_factory do
    %App.Fire{
      latitude: 66.59672,
      longitude: 76.99258,
      point: %Geo.Point{coordinates: {76.99258, 66.59672}, srid: 4326},
      satellite: "N21",
      instrument: "VIIRS",
      version: "2.0NRT",
      detected_at: DateTime.utc_now(),
      confidence: "n",
      daynight: "D",
      bright_ti4: 338.39,
      bright_ti5: 284.88,
      frp: 7.55,
      scan: 0.79,
      track: 0.78,
      nasa_id: sequence(:nasa_id, &"66.5967_76.9926_2025-08-07_105_N21_#{&1}")
    }
  end

  def fire_factory(attrs) when is_map(attrs) do
    fire = fire_factory()
    updated_fire = struct!(fire, attrs)

    # Regenerate point and nasa_id if coordinates changed
    if Map.has_key?(attrs, :latitude) or Map.has_key?(attrs, :longitude) do
      point = %Geo.Point{coordinates: {updated_fire.longitude, updated_fire.latitude}, srid: 4326}

      nasa_id =
        "#{Float.round(updated_fire.latitude, 4)}_#{Float.round(updated_fire.longitude, 4)}_2025-08-07_105_N21_#{System.unique_integer()}"

      %{updated_fire | point: point, nasa_id: nasa_id}
    else
      updated_fire
    end
  end

  def fire_incident_factory do
    %App.FireIncident{
      status: "active",
      center_latitude: 37.7749,
      center_longitude: -122.4194,
      center_point: %Geo.Point{coordinates: {-122.4194, 37.7749}, srid: 4326},
      fire_count: 0,
      first_detected_at: ~U[2024-01-01 12:00:00Z],
      last_detected_at: ~U[2024-01-01 12:00:00Z],
      max_frp: 0.0,
      min_frp: 0.0,
      avg_frp: 0.0,
      total_frp: 0.0
    }
  end

  def fire_incident_factory(attrs) when is_map(attrs) do
    incident = fire_incident_factory()
    updated_incident = struct!(incident, attrs)

    # Regenerate center_point if coordinates changed
    if Map.has_key?(attrs, :center_latitude) or Map.has_key?(attrs, :center_longitude) do
      point = %Geo.Point{
        coordinates: {updated_incident.center_longitude, updated_incident.center_latitude},
        srid: 4326
      }

      %{updated_incident | center_point: point}
    else
      updated_incident
    end
  end
end
