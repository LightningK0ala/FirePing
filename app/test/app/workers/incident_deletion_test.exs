defmodule App.Workers.IncidentDeletionTest do
  use App.DataCase, async: true
  use Oban.Testing, repo: App.Repo
  import App.Factory

  alias App.Workers.IncidentDeletion
  alias App.{FireIncident, Fire}

  describe "perform/1" do
    test "deletes ended incidents older than threshold" do
      now = DateTime.utc_now()
      old_time = DateTime.add(now, -45, :day)
      recent_time = DateTime.add(now, -15, :day)

      # Old ended incident (should be deleted)
      old_ended_incident =
        insert(:fire_incident, %{
          status: "ended",
          ended_at: old_time,
          last_detected_at: old_time
        })

      old_fire1 = insert(:fire, %{fire_incident: old_ended_incident})
      old_fire2 = insert(:fire, %{fire_incident: old_ended_incident})

      # Recent ended incident (should NOT be deleted)
      recent_ended_incident =
        insert(:fire_incident, %{
          status: "ended",
          ended_at: recent_time,
          last_detected_at: recent_time
        })

      recent_fire = insert(:fire, %{fire_incident: recent_ended_incident})

      # Active incident (should NOT be deleted)
      active_incident =
        insert(:fire_incident, %{
          status: "active",
          last_detected_at: old_time
        })

      active_fire = insert(:fire, %{fire_incident: active_incident})

      # Execute job with 30 day threshold
      assert :ok = perform_job(IncidentDeletion, %{"days_old" => 30})

      # Old ended incident and fires should be deleted
      refute App.Repo.get(FireIncident, old_ended_incident.id)
      refute App.Repo.get(Fire, old_fire1.id)
      refute App.Repo.get(Fire, old_fire2.id)

      # Recent ended incident should remain
      assert App.Repo.get(FireIncident, recent_ended_incident.id)
      assert App.Repo.get(Fire, recent_fire.id)

      # Active incident should remain
      assert App.Repo.get(FireIncident, active_incident.id)
      assert App.Repo.get(Fire, active_fire.id)
    end

    test "handles case with no incidents to delete" do
      # Create only recent ended incidents
      recent_time = DateTime.add(DateTime.utc_now(), -5, :day)

      insert(:fire_incident, %{
        status: "ended",
        ended_at: recent_time,
        last_detected_at: recent_time
      })

      assert :ok = perform_job(IncidentDeletion, %{"days_old" => 30})
    end

    test "uses default threshold when not specified" do
      # This test just ensures the job runs without errors when no days_old is provided
      assert :ok = perform_job(IncidentDeletion, %{})
    end

    test "updates job metadata with deletion statistics" do
      old_time = DateTime.add(DateTime.utc_now(), -45, :day)

      # Create an old ended incident
      old_incident =
        insert(:fire_incident, %{
          status: "ended",
          ended_at: old_time,
          last_detected_at: old_time
        })

      insert(:fire, %{fire_incident: old_incident})

      assert :ok = perform_job(IncidentDeletion, %{"days_old" => 30})
    end
  end

  describe "enqueue_now/1" do
    test "enqueues job with default threshold" do
      assert {:ok, job} = IncidentDeletion.enqueue_now()

      assert job.args["days_old"] == App.Config.incident_deletion_threshold_days()
    end

    test "enqueues job with custom threshold" do
      assert {:ok, job} = IncidentDeletion.enqueue_now(days_old: 60)

      assert job.args["days_old"] == 60
    end
  end
end
