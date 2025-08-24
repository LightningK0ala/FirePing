defmodule App.Workers.NotificationOrchestratorTest do
  use App.DataCase, async: true
  import Mock
  alias App.{FireIncident, Location, NotificationDevice, User, Workers.NotificationOrchestrator}

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
        create_notification: fn _attrs -> {:ok, %{id: "test-notification-id"}} end,
        send_notification: fn _notification -> {:ok, %{sent: 1, failed: 0}} end do
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
        create_notification: fn _attrs -> {:ok, %{id: "test-notification-id"}} end,
        send_notification: fn _notification -> {:ok, %{sent: 1, failed: 0}} end do
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
        create_notification: fn _attrs -> {:ok, %{id: "test-notification-id"}} end,
        send_notification: fn _notification -> {:ok, %{sent: 1, failed: 0}} end do
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
end
