defmodule App.FireClusteringTest do
  use App.DataCase, async: true
  import App.Factory

  alias App.{Fire, FireIncident}

  describe "find_incident_for_fire/3" do
    test "returns nil when no recent fires within clustering distance" do
      # Create an old fire with incident (outside expiry window)
      old_fire = insert(:fire, %{
        latitude: 37.7749,
        longitude: -122.4194,
        detected_at: DateTime.add(DateTime.utc_now(), -73, :hour)
      })

      old_incident = insert(:fire_incident)
      Fire.update_fire_incident(old_fire, old_incident.id)

      # New fire near the old one
      new_fire = build(:fire, %{
        latitude: 37.7750,
        longitude: -122.4195
      })

      assert Fire.find_incident_for_fire(new_fire) == nil
    end

    test "returns nil when no fires within clustering distance" do
      # Create a recent fire with incident (but far away)
      distant_fire = insert(:fire, %{
        latitude: 37.0000,
        longitude: -122.0000,
        detected_at: DateTime.add(DateTime.utc_now(), -1, :hour)
      })

      distant_incident = insert(:fire_incident)
      Fire.update_fire_incident(distant_fire, distant_incident.id)

      # New fire far from the existing one
      new_fire = build(:fire, %{
        latitude: 38.0000,
        longitude: -123.0000
      })

      assert Fire.find_incident_for_fire(new_fire, 1000) == nil
    end

    test "returns incident_id when recent fire exists within clustering distance" do
      # Create a recent fire with incident
      nearby_fire = insert(:fire, %{
        latitude: 37.7749,
        longitude: -122.4194,
        detected_at: DateTime.add(DateTime.utc_now(), -1, :hour)
      })

      nearby_incident = insert(:fire_incident)
      Fire.update_fire_incident(nearby_fire, nearby_incident.id)

      # New fire very close to the existing one (about 100m away)
      new_fire = build(:fire, %{
        latitude: 37.7750,
        longitude: -122.4195
      })

      assert Fire.find_incident_for_fire(new_fire, 5000) == nearby_incident.id
    end

    test "respects custom clustering distance" do
      # Create a recent fire with incident
      nearby_fire = insert(:fire, %{
        latitude: 37.7749,
        longitude: -122.4194,
        detected_at: DateTime.add(DateTime.utc_now(), -1, :hour)
      })

      nearby_incident = insert(:fire_incident)
      Fire.update_fire_incident(nearby_fire, nearby_incident.id)

      # New fire about 2km away
      new_fire = build(:fire, %{
        latitude: 37.7930,
        longitude: -122.4194
      })

      # Should find with 5km clustering distance
      assert Fire.find_incident_for_fire(new_fire, 5000) == nearby_incident.id

      # Should not find with 1km clustering distance
      assert Fire.find_incident_for_fire(new_fire, 1000) == nil
    end
  end

  describe "assign_to_incident/3" do
    test "creates new incident when no nearby fires exist" do
      fire = insert(:fire, %{
        latitude: 37.7749,
        longitude: -122.4194,
        detected_at: DateTime.utc_now(),
        frp: 15.5
      })

      assert {:ok, updated_fire} = Fire.assign_to_incident(fire)

      # Check fire was updated with incident_id
      assert updated_fire.fire_incident_id != nil

      # Check incident was created with correct attributes
      incident = App.Repo.get!(FireIncident, updated_fire.fire_incident_id)
      assert incident.status == "active"
      assert incident.center_latitude == 37.7749
      assert incident.center_longitude == -122.4194
      assert incident.fire_count == 1
      assert incident.max_frp == 15.5
    end

    test "adds fire to existing incident when nearby fire exists" do
      # Create first fire and incident
      first_fire = insert(:fire, %{
        latitude: 37.7749,
        longitude: -122.4194,
        detected_at: DateTime.add(DateTime.utc_now(), -1, :hour),
        frp: 10.0
      })

      {:ok, _} = Fire.assign_to_incident(first_fire)
      first_fire = App.Repo.reload(first_fire)
      incident = App.Repo.get!(FireIncident, first_fire.fire_incident_id)

      # Create second fire nearby
      second_fire = insert(:fire, %{
        latitude: 37.7750,
        longitude: -122.4195,
        detected_at: DateTime.utc_now(),
        frp: 20.0
      })

      assert {:ok, updated_fire} = Fire.assign_to_incident(second_fire)

      # Check second fire was assigned to same incident
      assert updated_fire.fire_incident_id == incident.id

      # Check incident metrics were updated
      updated_incident = App.Repo.reload(incident)
      assert updated_incident.fire_count == 2
      assert updated_incident.max_frp == 20.0
      assert updated_incident.min_frp == 10.0
      assert updated_incident.avg_frp == 15.0
      assert updated_incident.total_frp == 30.0
    end

    test "recalculates incident center when adding fires" do
      # Create first fire at one location
      first_fire = insert(:fire, %{
        latitude: 37.0000,
        longitude: -122.0000,
        detected_at: DateTime.add(DateTime.utc_now(), -1, :hour)
      })

      {:ok, _} = Fire.assign_to_incident(first_fire)
      first_fire = App.Repo.reload(first_fire)
      incident = App.Repo.get!(FireIncident, first_fire.fire_incident_id)

      # Verify initial center
      assert incident.center_latitude == 37.0000
      assert incident.center_longitude == -122.0000

      # Add second fire at different location (about 1km away)
      second_fire = insert(:fire, %{
        latitude: 37.0090,
        longitude: -122.0000,
        detected_at: DateTime.utc_now()
      })

      assert {:ok, _} = Fire.assign_to_incident(second_fire)

      # Check that center was recalculated (should be midpoint)
      updated_incident = App.Repo.reload(incident)
      assert_in_delta updated_incident.center_latitude, 37.0045, 0.0001
      assert updated_incident.center_longitude == -122.0000
    end
  end

  describe "process_fires_with_clustering/2" do
    @tag timeout: 30000
    test "processes NASA data and creates incidents" do
      nasa_data = [
        %{
          "latitude" => "37.7749",
          "longitude" => "-122.4194",
          "frp" => "15.5",
          "confidence" => "h",
          "satellite" => "N21",
          "instrument" => "VIIRS",
          "version" => "2.0NRT",
          "acq_date" => "2024-01-01",
          "acq_time" => "1200",
          "daynight" => "D",
          "bright_ti4" => "320.0",
          "bright_ti5" => "290.0",
          "scan" => "1.0",
          "track" => "1.0"
        },
        %{
          "latitude" => "37.7750",
          "longitude" => "-122.4195",
          "frp" => "12.0",
          "confidence" => "h",
          "satellite" => "N21",
          "instrument" => "VIIRS",
          "version" => "2.0NRT",
          "acq_date" => "2024-01-01",
          "acq_time" => "1205",
          "daynight" => "D",
          "bright_ti4" => "315.0",
          "bright_ti5" => "285.0",
          "scan" => "1.0",
          "track" => "1.0"
        }
      ]

      assert {2, nil} = Fire.process_fires_with_clustering(nasa_data)

      # Check that fires were created and assigned to incidents
      fires = Fire |> App.Repo.all()
      assert length(fires) == 2

      # Both fires should be assigned to incidents
      assert Enum.all?(fires, &(&1.fire_incident_id != nil))

      # Since they're close together, they should be in the same incident
      incident_ids = Enum.map(fires, & &1.fire_incident_id) |> Enum.uniq()
      assert length(incident_ids) == 1

      # Check incident was created with correct metrics
      incident = App.Repo.get!(FireIncident, hd(incident_ids))
      assert incident.fire_count == 2
      assert incident.status == "active"
    end

    test "creates separate incidents for distant fires" do
      nasa_data = [
        %{
          "latitude" => "37.0000",
          "longitude" => "-122.0000",
          "frp" => "15.5",
          "confidence" => "h",
          "satellite" => "N21",
          "instrument" => "VIIRS",
          "version" => "2.0NRT",
          "acq_date" => "2024-01-01",
          "acq_time" => "1200",
          "daynight" => "D",
          "bright_ti4" => "320.0",
          "bright_ti5" => "290.0",
          "scan" => "1.0",
          "track" => "1.0"
        },
        %{
          "latitude" => "38.0000",
          "longitude" => "-123.0000",
          "frp" => "12.0",
          "confidence" => "h",
          "satellite" => "N21",
          "instrument" => "VIIRS",
          "version" => "2.0NRT",
          "acq_date" => "2024-01-01",
          "acq_time" => "1205",
          "daynight" => "D",
          "bright_ti4" => "315.0",
          "bright_ti5" => "285.0",
          "scan" => "1.0",
          "track" => "1.0"
        }
      ]

      # Use smaller clustering distance to ensure separate incidents
      assert {2, nil} = Fire.process_fires_with_clustering(nasa_data, clustering_distance: 1000)

      # Check that fires were created and assigned to different incidents
      fires = Fire |> App.Repo.all()
      assert length(fires) == 2

      # Both fires should be assigned to incidents
      assert Enum.all?(fires, &(&1.fire_incident_id != nil))

      # Since they're far apart, they should be in different incidents
      incident_ids = Enum.map(fires, & &1.fire_incident_id) |> Enum.uniq()
      assert length(incident_ids) == 2
    end
  end

  describe "update_fire_incident/2" do
    test "updates fire with incident association" do
      fire = insert(:fire)
      incident = insert(:fire_incident)

      assert {:ok, updated_fire} = Fire.update_fire_incident(fire, incident.id)
      assert updated_fire.fire_incident_id == incident.id
    end
  end
end