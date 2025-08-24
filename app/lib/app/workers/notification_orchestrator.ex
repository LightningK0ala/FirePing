defmodule App.Workers.NotificationOrchestrator do
  @moduledoc """
  Oban worker for orchestrating fire incident notifications.

  This worker groups fires by incident and sends consolidated notifications to users
  whose monitored locations are affected by fire incidents. It prevents duplicate
  notifications by grouping all fires for an incident into a single notification.

  The worker handles:
  - New/updated incidents with new fires
  - Ended incidents (for cleanup notifications)
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    # Only one NotificationOrchestrator job at a time to prevent race conditions
    unique: [states: [:available, :executing]]

  require Logger
  import Ecto.Query
  alias App.{Fire, FireIncident, Location, Notifications, Repo}

  def perform(%Oban.Job{} = job) do
    args = job.args
    Logger.info("NotificationOrchestrator: Starting notification orchestration", args: args)

    start_time = System.monotonic_time(:millisecond)

    case process_notifications(args) do
      {:ok, results} ->
        end_time = System.monotonic_time(:millisecond)
        duration_ms = end_time - start_time

        # Add metadata for Oban dashboard
        metadata = %{
          incidents_processed: results.incidents_processed,
          notifications_sent: results.notifications_sent,
          users_notified: results.users_notified,
          duration_ms: duration_ms,
          duration_seconds: Float.round(duration_ms / 1000, 1),
          completed_at: DateTime.utc_now() |> DateTime.to_iso8601()
        }

        # Persist metadata to the job
        _ = persist_job_meta(job, metadata)

        Logger.info(
          "NotificationOrchestrator: Successfully processed #{results.incidents_processed} incidents, sent #{results.notifications_sent} notifications to #{results.users_notified} users",
          duration: "#{Float.round(duration_ms / 1000, 1)}s",
          metadata: metadata
        )

        :ok

      {:error, reason} ->
        Logger.error("NotificationOrchestrator: Failed to process notifications", reason: reason)
        {:error, reason}
    end
  end

  defp process_notifications(%{"type" => "incident_update", "incident_ids" => incident_ids}) do
    # Process incidents with new fires
    process_incident_updates(incident_ids)
  end

  defp process_notifications(%{"type" => "incident_ended", "incident_ids" => incident_ids}) do
    # Process ended incidents
    process_ended_incidents(incident_ids)
  end

  defp process_notifications(%{"type" => "fire_batch", "fire_ids" => fire_ids}) do
    # Process a batch of new fires by grouping them by incident
    process_fire_batch(fire_ids)
  end

  defp process_notifications(_args) do
    {:error, "Invalid notification type"}
  end

  defp process_incident_updates(incident_ids) do
    # Get incidents with their recent fires
    incidents = get_incidents_with_recent_fires(incident_ids)

    results =
      incidents
      |> Enum.reduce(
        %{incidents_processed: 0, notifications_sent: 0, users_notified: 0},
        fn incident, acc ->
          case process_incident_notification(incident, :update) do
            {:ok, notification_count, user_count} ->
              %{
                incidents_processed: acc.incidents_processed + 1,
                notifications_sent: acc.notifications_sent + notification_count,
                users_notified: acc.users_notified + user_count
              }

            {:error, reason} ->
              Logger.warning("Failed to process notification for incident #{incident.id}",
                reason: reason
              )

              acc
          end
        end
      )

    {:ok, results}
  end

  defp process_ended_incidents(incident_ids) do
    # Get ended incidents
    incidents =
      FireIncident
      |> where([i], i.id in ^incident_ids)
      |> where([i], i.status == "ended")
      |> Repo.all()

    results =
      incidents
      |> Enum.reduce(
        %{incidents_processed: 0, notifications_sent: 0, users_notified: 0},
        fn incident, acc ->
          case process_incident_notification(incident, :ended) do
            {:ok, notification_count, user_count} ->
              %{
                incidents_processed: acc.incidents_processed + 1,
                notifications_sent: acc.notifications_sent + notification_count,
                users_notified: acc.users_notified + user_count
              }

            {:error, reason} ->
              Logger.warning("Failed to process ended notification for incident #{incident.id}",
                reason: reason
              )

              acc
          end
        end
      )

    {:ok, results}
  end

  defp process_fire_batch(fire_ids) do
    # Get fires and group them by incident
    fires =
      Fire
      |> where([f], f.id in ^fire_ids)
      |> where([f], not is_nil(f.fire_incident_id))
      |> preload(:fire_incident)
      |> Repo.all()

    # Group fires by incident
    fires_by_incident = Enum.group_by(fires, & &1.fire_incident_id)

    results =
      fires_by_incident
      |> Enum.reduce(
        %{incidents_processed: 0, notifications_sent: 0, users_notified: 0},
        fn {incident_id, fires}, acc ->
          incident = List.first(fires).fire_incident

          case process_incident_notification(incident, :update, fires) do
            {:ok, notification_count, user_count} ->
              %{
                incidents_processed: acc.incidents_processed + 1,
                notifications_sent: acc.notifications_sent + notification_count,
                users_notified: acc.users_notified + user_count
              }

            {:error, reason} ->
              Logger.warning("Failed to process notification for incident #{incident_id}",
                reason: reason
              )

              acc
          end
        end
      )

    {:ok, results}
  end

  defp get_incidents_with_recent_fires(incident_ids) do
    # Get incidents and their recent fires (last 24 hours)
    cutoff = DateTime.utc_now() |> DateTime.add(-24, :hour)

    FireIncident
    |> where([i], i.id in ^incident_ids)
    |> where([i], i.status == "active")
    |> preload(:fires)
    |> Repo.all()
    |> Enum.map(fn incident ->
      # Filter fires after loading to get only recent ones
      recent_fires =
        incident.fires
        |> Enum.filter(fn fire -> DateTime.compare(fire.detected_at, cutoff) == :gt end)
        |> Enum.sort_by(& &1.detected_at, {:desc, DateTime})

      %{incident | fires: recent_fires}
    end)
  end

  defp process_incident_notification(incident, type, fires \\ nil) do
    # Find locations affected by this incident
    affected_locations = find_affected_locations(incident)

    if length(affected_locations) == 0 do
      Logger.debug("No locations affected by incident #{incident.id}")
      {:ok, 0, 0}
    else
      # Group locations by user
      locations_by_user = Enum.group_by(affected_locations, & &1.user_id)

      # Create and send notifications for each user
      {notification_count, user_count} =
        locations_by_user
        |> Enum.reduce({0, 0}, fn {user_id, user_locations}, {notif_acc, user_acc} ->
          case create_and_send_notification(incident, user_id, user_locations, type, fires) do
            {:ok, _notification} ->
              {notif_acc + 1, user_acc + 1}

            {:error, reason} ->
              Logger.warning("Failed to send notification to user #{user_id}", reason: reason)
              {notif_acc, user_acc}
          end
        end)

      {:ok, notification_count, user_count}
    end
  end

  defp find_affected_locations(incident) do
    # Find all locations that intersect with the incident's bounding box
    # and are within the incident's spatial extent
    incident_point = %Geo.Point{
      coordinates: {incident.center_longitude, incident.center_latitude},
      srid: 4326
    }

    # Use a reasonable radius based on the incident's bounds
    # Calculate approximate radius from bounds
    lat_span = incident.max_latitude - incident.min_latitude
    lng_span = incident.max_longitude - incident.min_longitude
    max_span = max(lat_span, lng_span)

    # Convert to meters (approximate: 1 degree ≈ 111,000 meters)
    # Use half the span as radius
    radius_meters = max_span * 111_000 * 0.5
    # Minimum 5km radius
    radius_meters = max(radius_meters, 5000)

    Location
    |> where(
      [l],
      fragment(
        "ST_DWithin(ST_Transform(?, 3857), ST_Transform(?, 3857), ?)",
        l.point,
        ^incident_point,
        ^radius_meters
      )
    )
    |> preload(:user)
    |> Repo.all()
  end

  defp create_and_send_notification(incident, user_id, user_locations, type, fires) do
    # Create notification content based on type
    {title, body, notification_data} =
      build_notification_content(incident, user_locations, type, fires)

    # Create notification record
    notification_attrs = %{
      user_id: user_id,
      fire_incident_id: incident.id,
      title: title,
      body: body,
      type: "fire_alert",
      data: notification_data
    }

    case Notifications.create_notification(notification_attrs) do
      {:ok, notification} ->
        # Send to all user's devices
        case Notifications.send_notification(notification) do
          {:ok, %{sent: sent_count, failed: failed_count}} ->
            if failed_count > 0 do
              Logger.warning("Some notification devices failed for user #{user_id}",
                sent: sent_count,
                failed: failed_count
              )
            end

            {:ok, notification}

          {:error, reason} ->
            Logger.error("Failed to send notification to user #{user_id}", reason: reason)
            {:error, reason}
        end

      {:error, changeset} ->
        Logger.error("Failed to create notification for user #{user_id}", changeset: changeset)
        {:error, changeset}
    end
  end

  defp build_notification_content(incident, user_locations, type, fires) do
    location_names = Enum.map_join(user_locations, ", ", & &1.name)

    case type do
      :update ->
        # For incident updates, show new fire count
        new_fire_count = if fires, do: length(fires), else: incident.fire_count

        title =
          "Fire Alert: #{new_fire_count} new fire#{if new_fire_count == 1, do: "", else: "s"} detected"

        body =
          case new_fire_count do
            1 -> "A new fire has been detected near #{location_names}."
            count -> "#{count} new fires have been detected near #{location_names}."
          end

        data = %{
          incident_id: incident.id,
          fire_count: new_fire_count,
          location_names: location_names,
          center_lat: incident.center_latitude,
          center_lng: incident.center_longitude,
          max_frp: incident.max_frp,
          last_detected: DateTime.to_iso8601(incident.last_detected_at)
        }

        {title, body, data}

      :ended ->
        title = "Fire Incident Ended"

        body =
          "The fire incident near #{location_names} has ended. No new fires have been detected for 24 hours."

        data = %{
          incident_id: incident.id,
          location_names: location_names,
          center_lat: incident.center_latitude,
          center_lng: incident.center_longitude,
          total_fire_count: incident.fire_count,
          ended_at: DateTime.to_iso8601(incident.ended_at)
        }

        {title, body, data}
    end
  end

  defp persist_job_meta(%Oban.Job{} = job, new_meta) when is_map(new_meta) do
    merged_meta = Map.merge(job.meta || %{}, new_meta)

    job
    |> Ecto.Changeset.change(meta: merged_meta)
    |> Repo.update()
  rescue
    _ -> :ok
  end

  @doc """
  Enqueue notification orchestration for incident updates.
  """
  def enqueue_incident_updates(incident_ids, opts \\ []) do
    base_meta = %{
      source: Keyword.get(opts, :source, "system"),
      requested_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    %{
      "type" => "incident_update",
      "incident_ids" => incident_ids
    }
    |> __MODULE__.new(meta: base_meta)
    |> Oban.insert()
  end

  @doc """
  Enqueue notification orchestration for ended incidents.
  """
  def enqueue_ended_incidents(incident_ids, opts \\ []) do
    base_meta = %{
      source: Keyword.get(opts, :source, "system"),
      requested_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    %{
      "type" => "incident_ended",
      "incident_ids" => incident_ids
    }
    |> __MODULE__.new(meta: base_meta)
    |> Oban.insert()
  end

  @doc """
  Enqueue notification orchestration for a batch of fires.
  """
  def enqueue_fire_batch(fire_ids, opts \\ []) do
    base_meta = %{
      source: Keyword.get(opts, :source, "system"),
      requested_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    %{
      "type" => "fire_batch",
      "fire_ids" => fire_ids
    }
    |> __MODULE__.new(meta: base_meta)
    |> Oban.insert()
  end
end
