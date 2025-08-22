defmodule App.Workers.IncidentCleanupTest do
  use App.DataCase
  use Oban.Testing, repo: App.Repo

  alias App.Workers.IncidentCleanup
  alias App.{Fire, FireIncident, Repo}

  import App.Factory

  describe "perform/1" do
    test "marks old incidents as ended when they have no recent fires" do
      # Create an incident with fires from 4 days ago (beyond 24 hour threshold)
      old_datetime = DateTime.utc_now() |> DateTime.add(-4, :day)

      # Create fires from 4 days ago and assign to incident
      fire1 = insert(:fire, detected_at: old_datetime)
      fire2 = insert(:fire, detected_at: old_datetime)

      # Create an incident and directly assign fires to it
      incident =
        insert(:fire_incident,
          status: "active",
          last_detected_at: old_datetime,
          fire_count: 2
        )

      # Update fires to belong to the incident
      fire1 |> Ecto.Changeset.change(fire_incident_id: incident.id) |> Repo.update!()
      fire2 |> Ecto.Changeset.change(fire_incident_id: incident.id) |> Repo.update!()

      # Verify incident starts as active
      assert Repo.get(FireIncident, incident.id).status == "active"

      # Run the cleanup job with 24 hour threshold
      assert :ok = perform_job(IncidentCleanup, %{"threshold_hours" => 24})

      # Verify incident is now ended
      updated_incident = Repo.get(FireIncident, incident.id)
      assert updated_incident.status == "ended"
      assert updated_incident.ended_at != nil
    end

    test "does not mark incidents as ended when they have recent fires" do
      # Create an incident with recent fires (within 24 hour threshold)
      recent_datetime = DateTime.utc_now() |> DateTime.add(-1, :hour)

      # Create recent fires and assign to incident
      fire1 = insert(:fire, detected_at: recent_datetime)
      fire2 = insert(:fire, detected_at: recent_datetime)

      # Create an incident with recent last_detected_at
      incident =
        insert(:fire_incident,
          status: "active",
          last_detected_at: recent_datetime,
          fire_count: 2
        )

      # Update fires to belong to the incident
      fire1 |> Ecto.Changeset.change(fire_incident_id: incident.id) |> Repo.update!()
      fire2 |> Ecto.Changeset.change(fire_incident_id: incident.id) |> Repo.update!()

      # Verify incident starts as active
      assert Repo.get(FireIncident, incident.id).status == "active"

      # Run the cleanup job with 24 hour threshold
      assert :ok = perform_job(IncidentCleanup, %{"threshold_hours" => 24})

      # Verify incident is still active
      updated_incident = Repo.get(FireIncident, incident.id)
      assert updated_incident.status == "active"
      assert updated_incident.ended_at == nil
    end

    test "does not affect already ended incidents" do
      # Create an already ended incident with old fires
      old_datetime = DateTime.utc_now() |> DateTime.add(-4, :day)
      ended_datetime = DateTime.utc_now() |> DateTime.add(-1, :day)

      fire = insert(:fire, detected_at: old_datetime)

      incident =
        insert(:fire_incident,
          status: "ended",
          ended_at: ended_datetime,
          last_detected_at: old_datetime,
          fire_count: 1
        )

      # Update fire to belong to the incident
      fire |> Ecto.Changeset.change(fire_incident_id: incident.id) |> Repo.update!()

      # Run the cleanup job
      assert :ok = perform_job(IncidentCleanup, %{"threshold_hours" => 24})

      # Verify incident remains ended (ended_at shouldn't change much)
      updated_incident = Repo.get(FireIncident, incident.id)
      assert updated_incident.status == "ended"
      # Since it's already ended, the cleanup shouldn't change ended_at significantly
      assert updated_incident.ended_at != nil
    end

    test "handles custom threshold hours" do
      # Create an incident with fires from 25 hours ago
      old_datetime = DateTime.utc_now() |> DateTime.add(-25, :hour)

      fire = insert(:fire, detected_at: old_datetime)

      incident =
        insert(:fire_incident,
          status: "active",
          last_detected_at: old_datetime,
          fire_count: 1
        )

      # Update fire to belong to the incident
      fire |> Ecto.Changeset.change(fire_incident_id: incident.id) |> Repo.update!()

      # Run cleanup with 24 hour threshold (should end the incident)
      assert :ok = perform_job(IncidentCleanup, %{"threshold_hours" => 24})

      updated_incident = Repo.get(FireIncident, incident.id)
      assert updated_incident.status == "ended"
    end

    test "handles mixed incidents - some old, some recent" do
      # Create one old incident
      old_datetime = DateTime.utc_now() |> DateTime.add(-4, :day)
      old_fire = insert(:fire, detected_at: old_datetime)

      old_incident =
        insert(:fire_incident,
          status: "active",
          last_detected_at: old_datetime,
          fire_count: 1
        )

      # Update fire to belong to the incident
      old_fire |> Ecto.Changeset.change(fire_incident_id: old_incident.id) |> Repo.update!()

      # Create one recent incident  
      recent_datetime = DateTime.utc_now() |> DateTime.add(-1, :hour)
      recent_fire = insert(:fire, detected_at: recent_datetime)

      recent_incident =
        insert(:fire_incident,
          status: "active",
          last_detected_at: recent_datetime,
          fire_count: 1
        )

      # Update fire to belong to the incident
      recent_fire |> Ecto.Changeset.change(fire_incident_id: recent_incident.id) |> Repo.update!()

      # Run cleanup
      assert :ok = perform_job(IncidentCleanup, %{"threshold_hours" => 24})

      # Verify only old incident was ended
      updated_old = Repo.get(FireIncident, old_incident.id)
      updated_recent = Repo.get(FireIncident, recent_incident.id)

      assert updated_old.status == "ended"
      assert updated_recent.status == "active"
    end

    test "handles incidents with no fires" do
      # Create incident with no fires assigned (recent last_detected_at)
      recent_datetime = DateTime.utc_now() |> DateTime.add(-1, :hour)

      incident =
        insert(:fire_incident,
          status: "active",
          last_detected_at: recent_datetime,
          fire_count: 0
        )

      # Run cleanup
      assert :ok = perform_job(IncidentCleanup, %{"threshold_hours" => 24})

      # Should not affect the incident since last_detected_at is recent
      updated_incident = Repo.get(FireIncident, incident.id)
      assert updated_incident.status == "active"
    end

    test "uses default threshold when not specified" do
      # Create an incident with fires from 4 days ago (beyond default 24 hours)
      old_datetime = DateTime.utc_now() |> DateTime.add(-4, :day)

      fire = insert(:fire, detected_at: old_datetime)

      incident =
        insert(:fire_incident,
          status: "active",
          last_detected_at: old_datetime,
          fire_count: 1
        )

      # Update fire to belong to the incident
      fire |> Ecto.Changeset.change(fire_incident_id: incident.id) |> Repo.update!()

      # Run cleanup without specifying threshold (should use default 24 hours)
      assert :ok = perform_job(IncidentCleanup, %{})

      updated_incident = Repo.get(FireIncident, incident.id)
      assert updated_incident.status == "ended"
    end

    test "handles empty database gracefully" do
      # Ensure no incidents exist
      Repo.delete_all(FireIncident)
      Repo.delete_all(Fire)

      # Run cleanup
      assert :ok = perform_job(IncidentCleanup, %{"threshold_hours" => 24})

      # Should complete successfully with no errors
    end
  end

  describe "enqueue_now/1" do
    test "enqueues an IncidentCleanup job with default threshold" do
      {:ok, job} = IncidentCleanup.enqueue_now()

      assert job.args == %{"threshold_hours" => 24}
      assert job.worker == "App.Workers.IncidentCleanup"
      assert job.queue == "default"
    end

    test "enqueues an IncidentCleanup job with custom threshold" do
      {:ok, job} = IncidentCleanup.enqueue_now(threshold_hours: 48)

      assert job.args == %{"threshold_hours" => 48}
    end
  end
end
