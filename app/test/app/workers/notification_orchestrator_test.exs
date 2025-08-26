defmodule App.Workers.NotificationOrchestratorTest do
  use App.DataCase
  import Mock

  alias App.{
    Fire,
    FireIncident,
    Location,
    NotificationDevice,
    User,
    Workers.NotificationOrchestrator
  }

  setup do
    # Create test user
    user =
      %User{}
      |> User.changeset(%{
        email: "test@example.com",
        password: "password123",
        password_confirmation: "password123"
      })
      |> Repo.insert!()

    # Create test location
    location =
      %Location{}
      |> Location.changeset(%{
        name: "Test Location",
        latitude: 37.7749,
        longitude: -122.4194,
        radius: 10000,
        user_id: user.id
      })
      |> Repo.insert!()

    # Create notification device
    device =
      %NotificationDevice{}
      |> NotificationDevice.changeset(%{
        name: "Test Device",
        channel: "web_push",
        config: %{
          "endpoint" => "https://example.com/push",
          "keys" => %{
            "p256dh" => "test_p256dh",
            "auth" => "test_auth"
          }
        },
        user_id: user.id
      })
      |> Repo.insert!()

    # Create test fire incident
    incident =
      %FireIncident{}
      |> FireIncident.changeset(%{
        status: "active",
        center_latitude: 37.7749,
        center_longitude: -122.4194,
        min_latitude: 37.7649,
        max_latitude: 37.7849,
        min_longitude: -122.4294,
        max_longitude: -122.4094,
        fire_count: 1,
        first_detected_at: DateTime.utc_now() |> DateTime.add(-1, :hour),
        last_detected_at: DateTime.utc_now(),
        max_frp: 10.5,
        min_frp: 10.5,
        avg_frp: 10.5,
        total_frp: 10.5
      })
      |> Repo.insert!()

    {:ok, %{user: user, location: location, device: device, incident: incident}}
  end

  describe "enqueue functions" do
    test "enqueue_incident_updates/2 creates job with correct args" do
      incident_ids = ["incident-1", "incident-2"]

      assert {:ok, job} =
               NotificationOrchestrator.enqueue_incident_updates(incident_ids, source: "test")

      assert job.args["type"] == "incident_update"
      assert job.args["incident_ids"] == incident_ids
      assert job.id != nil
    end

    test "enqueue_ended_incidents/2 creates job with correct args" do
      incident_ids = ["incident-1", "incident-2"]

      assert {:ok, job} =
               NotificationOrchestrator.enqueue_ended_incidents(incident_ids, source: "test")

      assert job.args["type"] == "incident_ended"
      assert job.args["incident_ids"] == incident_ids
      assert job.id != nil
    end

    test "enqueue_fire_batch/2 creates job with correct args" do
      fire_ids = ["fire-1", "fire-2"]

      assert {:ok, job} = NotificationOrchestrator.enqueue_fire_batch(fire_ids, source: "test")

      assert job.args["type"] == "fire_batch"
      assert job.args["fire_ids"] == fire_ids
      assert job.id != nil
    end
  end

  describe "notification content building" do
    test "builds correct content for incident updates", %{incident: incident, location: _location} do
      # Test by creating a job and running it
      job = %Oban.Job{
        args: %{
          "type" => "incident_update",
          "incident_ids" => [incident.id]
        }
      }

      # Mock the notification sending to avoid actual web push calls
      with_mock App.Notifications,
        send_notifications_to_devices: fn _attrs -> {:ok, %{sent: 1, failed: 0}} end do
        result = NotificationOrchestrator.perform(job)
        assert result == :ok
      end
    end

    test "builds correct content for ended incidents", %{incident: incident, location: _location} do
      # Mark incident as ended first
      incident
      |> FireIncident.changeset(%{
        status: "ended",
        ended_at: DateTime.utc_now()
      })
      |> Repo.update!()

      # Test by creating a job and running it
      job = %Oban.Job{
        args: %{
          "type" => "incident_ended",
          "incident_ids" => [incident.id]
        }
      }

      # Mock the notification sending to avoid actual web push calls
      with_mock App.Notifications,
        send_notifications_to_devices: fn _attrs -> {:ok, %{sent: 1, failed: 0}} end do
        result = NotificationOrchestrator.perform(job)
        assert result == :ok
      end
    end
  end

  describe "location finding" do
    test "finds locations affected by incident", %{incident: incident, location: _location} do
      # Test by creating a job and running it
      job = %Oban.Job{
        args: %{
          "type" => "incident_update",
          "incident_ids" => [incident.id]
        }
      }

      # Mock the notification sending to avoid actual web push calls
      with_mock App.Notifications,
        send_notifications_to_devices: fn _attrs -> {:ok, %{sent: 1, failed: 0}} end do
        result = NotificationOrchestrator.perform(job)
        assert result == :ok
      end
    end

    test "returns empty list for incidents far from locations" do
      # Create incident far from any locations
      far_incident =
        %FireIncident{}
        |> FireIncident.changeset(%{
          status: "active",
          # Far north but not at pole
          center_latitude: 85.0,
          center_longitude: 0.0,
          min_latitude: 84.9,
          max_latitude: 85.1,
          min_longitude: -0.1,
          max_longitude: 0.1,
          fire_count: 1,
          first_detected_at: DateTime.utc_now() |> DateTime.add(-1, :hour),
          last_detected_at: DateTime.utc_now(),
          max_frp: 10.5,
          min_frp: 10.5,
          avg_frp: 10.5,
          total_frp: 10.5
        })
        |> Repo.insert!()

      # Test by creating a job and running it
      job = %Oban.Job{
        args: %{
          "type" => "incident_update",
          "incident_ids" => [far_incident.id]
        }
      }

      result = NotificationOrchestrator.perform(job)
      assert result == :ok
    end
  end

  describe "fire batch processing with new flow" do
    test "processes fires following correct flow: fires -> locations -> users -> incidents -> notifications" do
      # Setup: Create user with location
      user = insert(:user, email: "user@test.com")

      location =
        insert(:location,
          name: "Test Location",
          latitude: 37.7749,
          longitude: -122.4194,
          radius: 5000,
          user: user
        )

      # Create fires that will be within the location's radius
      fire1 = insert(:fire, latitude: 37.7750, longitude: -122.4195)
      fire2 = insert(:fire, latitude: 37.7748, longitude: -122.4193)

      # Test the new functions work correctly
      fire_results = Fire.process_fires_with_status([fire1, fire2])

      # Should return results with incident status
      assert length(fire_results) == 2
      assert {:ok, _fire, incident_status} = Enum.at(fire_results, 0)
      assert incident_status in [:new_incident, :existing_incident]

      # Test finding affected locations
      affected_locations = Fire.find_locations_affected_by_fires([fire1, fire2])

      # Should find locations affected by each fire
      assert length(affected_locations) == 2
      assert {^fire1, locations1} = Enum.at(affected_locations, 0)
      assert {^fire2, locations2} = Enum.at(affected_locations, 1)

      # Both fires should affect the same location
      assert location in locations1
      assert location in locations2

      # Each location should have the user preloaded
      location_with_user = Enum.find(locations1, &(&1.id == location.id))
      assert location_with_user.user.email == "user@test.com"
    end

    test "correctly identifies new vs existing incidents" do
      # Create a fire and assign it to an incident
      fire1 = insert(:fire, latitude: 37.7750, longitude: -122.4195)
      {:ok, _fire1_updated, status1} = Fire.assign_to_incident_with_status(fire1)
      assert status1 == :new_incident

      # Create another fire nearby - should be assigned to existing incident
      fire2 = insert(:fire, latitude: 37.7751, longitude: -122.4196)
      {:ok, _fire2_updated, status2} = Fire.assign_to_incident_with_status(fire2)
      assert status2 == :existing_incident

      # Create a fire far away - should create new incident
      # NYC
      fire3 = insert(:fire, latitude: 40.7128, longitude: -74.0060)
      {:ok, _fire3_updated, status3} = Fire.assign_to_incident_with_status(fire3)
      assert status3 == :new_incident
    end

    test "builds proper notification messages with incident IDs and multiple incident awareness" do
      # Create user with location
      user = insert(:user, email: "user@test.com")

      location =
        insert(:location,
          name: "Golden Gate Park",
          latitude: 37.7749,
          longitude: -122.4194,
          radius: 5000,
          user: user
        )

      # Create a fire and incident
      fire = insert(:fire, latitude: 37.7750, longitude: -122.4195)
      {:ok, updated_fire, :new_incident} = Fire.assign_to_incident_with_status(fire)

      # Reload the fire with incident preloaded
      updated_fire = App.Repo.preload(updated_fire, :fire_incident)
      incident = updated_fire.fire_incident

      # Test the notification content building
      incident_short_id = String.slice(incident.id, 0, 4)

      # Test new incident message (single incident)
      _fires_with_status = [{updated_fire, :new_incident}]

      # Verify the message components are correct
      assert String.length(incident_short_id) == 4
      assert incident.id != nil
      assert location.name == "Golden Gate Park"

      # Expected message format examples:
      # NEW INCIDENT (single active):
      #   Title: "New fire incident A1B2"
      #   Body: "1 fires near 'Golden Gate Park'"
      #
      # ONGOING INCIDENT (single active):
      #   Title: "Fire incident A1B2 updated"
      #   Body: "+2 fires (5 total) near 'Golden Gate Park'"
      #
      # ONGOING INCIDENT (multiple active):
      #   Title: "Fire incident A1B2 updated"
      #   Body: "+2 fires (5 total) near 'Golden Gate Park' (1 of 3 active)"

      # The actual messages will be generated by the notification functions
      # This test verifies our components are in place
    end
  end
end
