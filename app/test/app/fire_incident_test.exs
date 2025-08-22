defmodule App.FireIncidentTest do
  use App.DataCase, async: true
  import App.Factory

  alias App.FireIncident

  describe "changeset/2" do
    test "valid changeset with required fields" do
      attrs = %{
        status: "active",
        center_latitude: 37.7749,
        center_longitude: -122.4194,
        first_detected_at: ~U[2024-01-01 12:00:00Z],
        last_detected_at: ~U[2024-01-01 12:00:00Z]
      }

      changeset = FireIncident.changeset(%FireIncident{}, attrs)

      assert changeset.valid?
      # Status should use default value since it wasn't provided
      assert get_field(changeset, :status) == "active"
      assert get_change(changeset, :center_latitude) == 37.7749
      assert get_change(changeset, :center_longitude) == -122.4194
      # Check that center_point is automatically created
      assert get_change(changeset, :center_point) != nil
    end

    test "requires coordinates and timestamps" do
      changeset = FireIncident.changeset(%FireIncident{}, %{})

      refute changeset.valid?

      assert errors_on(changeset) == %{
               center_latitude: ["can't be blank"],
               center_longitude: ["can't be blank"],
               first_detected_at: ["can't be blank"],
               last_detected_at: ["can't be blank"]
             }
    end

    test "validates status inclusion" do
      attrs = %{
        status: "invalid_status",
        center_latitude: 37.7749,
        center_longitude: -122.4194,
        first_detected_at: ~U[2024-01-01 12:00:00Z],
        last_detected_at: ~U[2024-01-01 12:00:00Z]
      }

      changeset = FireIncident.changeset(%FireIncident{}, attrs)

      refute changeset.valid?
      assert errors_on(changeset) == %{status: ["is invalid"]}
    end

    test "validates latitude range" do
      attrs = %{
        status: "active",
        center_latitude: 91.0,
        center_longitude: -122.4194,
        first_detected_at: ~U[2024-01-01 12:00:00Z],
        last_detected_at: ~U[2024-01-01 12:00:00Z]
      }

      changeset = FireIncident.changeset(%FireIncident{}, attrs)

      refute changeset.valid?
      assert errors_on(changeset) == %{center_latitude: ["must be between -90 and 90"]}
    end

    test "validates longitude range" do
      attrs = %{
        status: "active",
        center_latitude: 37.7749,
        center_longitude: 181.0,
        first_detected_at: ~U[2024-01-01 12:00:00Z],
        last_detected_at: ~U[2024-01-01 12:00:00Z]
      }

      changeset = FireIncident.changeset(%FireIncident{}, attrs)

      refute changeset.valid?
      assert errors_on(changeset) == %{center_longitude: ["must be between -180 and 180"]}
    end
  end

  describe "create_from_fire/1" do
    test "creates incident from fire detection" do
      fire =
        build(:fire, %{
          latitude: 37.7749,
          longitude: -122.4194,
          detected_at: ~U[2024-01-01 12:00:00Z],
          frp: 10.5
        })

      assert {:ok, incident} = FireIncident.create_from_fire(fire)

      assert incident.status == "active"
      assert incident.center_latitude == 37.7749
      assert incident.center_longitude == -122.4194
      assert incident.fire_count == 1
      assert incident.first_detected_at == ~U[2024-01-01 12:00:00Z]
      assert incident.last_detected_at == ~U[2024-01-01 12:00:00Z]
      assert incident.max_frp == 10.5
      assert incident.min_frp == 10.5
      assert incident.avg_frp == 10.5
      assert incident.total_frp == 10.5
    end
  end

  describe "add_fire/2" do
    test "updates incident metrics when fire is added" do
      incident =
        insert(:fire_incident, %{
          fire_count: 1,
          last_detected_at: ~U[2024-01-01 12:00:00Z],
          max_frp: 10.0,
          min_frp: 10.0,
          avg_frp: 10.0,
          total_frp: 10.0
        })

      new_fire =
        build(:fire, %{
          detected_at: ~U[2024-01-01 13:00:00Z],
          frp: 20.0
        })

      assert {:ok, updated_incident} = FireIncident.add_fire(incident, new_fire)

      assert updated_incident.fire_count == 2
      assert updated_incident.last_detected_at == ~U[2024-01-01 13:00:00Z]
      assert updated_incident.max_frp == 20.0
      assert updated_incident.min_frp == 10.0
      assert updated_incident.avg_frp == 15.0
      assert updated_incident.total_frp == 30.0
    end

    test "handles nil FRP values" do
      incident =
        insert(:fire_incident, %{
          fire_count: 1,
          total_frp: 10.0,
          avg_frp: 10.0
        })

      new_fire = build(:fire, %{frp: nil})

      assert {:ok, updated_incident} = FireIncident.add_fire(incident, new_fire)

      assert updated_incident.fire_count == 2
      assert updated_incident.total_frp == 10.0
      assert updated_incident.avg_frp == 5.0
    end
  end

  describe "mark_as_ended/1" do
    test "marks incident as ended with timestamp" do
      incident = insert(:fire_incident, %{status: "active"})

      assert {:ok, ended_incident} = FireIncident.mark_as_ended(incident)

      assert ended_incident.status == "ended"
      assert ended_incident.ended_at != nil
      assert DateTime.diff(ended_incident.ended_at, DateTime.utc_now(), :second) < 5
    end
  end

  describe "active_incidents_within_hours/1" do
    test "returns only active incidents within time range" do
      now = DateTime.utc_now()
      recent_time = DateTime.add(now, -2, :hour)
      old_time = DateTime.add(now, -25, :hour)

      # Active incident within range
      recent_incident =
        insert(:fire_incident, %{
          status: "active",
          last_detected_at: recent_time
        })

      # Active incident outside range
      insert(:fire_incident, %{
        status: "active",
        last_detected_at: old_time
      })

      # Ended incident within range
      insert(:fire_incident, %{
        status: "ended",
        last_detected_at: recent_time
      })

      incidents = FireIncident.active_incidents_within_hours(24)

      assert length(incidents) == 1
      assert hd(incidents).id == recent_incident.id
    end
  end

  describe "incidents_to_end/1" do
    test "returns active incidents past threshold" do
      now = DateTime.utc_now()
      recent_time = DateTime.add(now, -2, :hour)
      old_time = DateTime.add(now, -73, :hour)

      # Recent active incident (should not be ended)
      insert(:fire_incident, %{
        status: "active",
        last_detected_at: recent_time
      })

      # Old active incident (should be ended)
      old_incident =
        insert(:fire_incident, %{
          status: "active",
          last_detected_at: old_time
        })

      # Already ended incident
      insert(:fire_incident, %{
        status: "ended",
        last_detected_at: old_time
      })

      incidents = FireIncident.incidents_to_end(24)

      assert length(incidents) == 1
      assert hd(incidents).id == old_incident.id
    end
  end

  describe "recalculate_center/1" do
    test "recalculates center from associated fires" do
      incident = insert(:fire_incident)

      # Create fires at different locations
      _fire1 =
        insert(:fire, %{
          latitude: 37.0,
          longitude: -122.0,
          fire_incident: incident
        })

      _fire2 =
        insert(:fire, %{
          latitude: 38.0,
          longitude: -123.0,
          fire_incident: incident
        })

      assert {:ok, updated_incident} = FireIncident.recalculate_center(incident)

      # Center should be average of fire locations
      assert updated_incident.center_latitude == 37.5
      assert updated_incident.center_longitude == -122.5
    end

    test "returns error when no fires associated" do
      incident = insert(:fire_incident)

      assert {:error, :no_fires} = FireIncident.recalculate_center(incident)
    end
  end
end
