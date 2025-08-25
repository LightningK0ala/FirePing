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

  defp process_notifications(%{
         "type" => "fire_batch_with_status",
         "fires_with_status" => fires_with_status
       }) do
    # Process a batch of fires with incident status information
    Logger.info("Processing fire batch notification with status",
      fire_count: length(fires_with_status)
    )

    process_fire_batch_with_status(fires_with_status)
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
    # Get fires with their incident associations
    fires =
      Fire
      |> where([f], f.id in ^fire_ids)
      |> where([f], not is_nil(f.fire_incident_id))
      |> preload(:fire_incident)
      |> Repo.all()

    # Step 1: Find locations affected by these fires
    fire_location_pairs = Fire.find_locations_affected_by_fires(fires)

    # Step 2: Group by user -> location -> incident -> fires
    notifications_data =
      fire_location_pairs
      |> Enum.flat_map(fn {fire, locations} ->
        # Create a {user, location, incident, fire} tuple for each affected location
        Enum.map(locations, fn location ->
          {location.user, location, fire.fire_incident, fire}
        end)
      end)
      |> Enum.group_by(fn {user, _location, _incident, _fire} -> user.id end)
      |> Enum.map(fn {_user_id, user_data} ->
        # Group by location within each user
        user = elem(List.first(user_data), 0)

        locations_data =
          user_data
          |> Enum.group_by(fn {_user, location, _incident, _fire} -> location.id end)
          |> Enum.map(fn {_location_id, location_data} ->
            # Group by incident within each location
            location = elem(List.first(location_data), 1)

            incidents_data =
              location_data
              |> Enum.group_by(fn {_user, _location, incident, _fire} -> incident.id end)
              |> Enum.map(fn {_incident_id, incident_data} ->
                incident = elem(List.first(incident_data), 2)

                fires =
                  Enum.map(incident_data, fn {_user, _location, _incident, fire} -> fire end)

                {incident, fires}
              end)

            {location, incidents_data}
          end)

        {user, locations_data}
      end)

    # Step 3: Send notifications grouped by user/location/incident
    results =
      notifications_data
      |> Enum.reduce(
        %{incidents_processed: 0, notifications_sent: 0, users_notified: 0},
        fn {user, locations_data}, acc ->
          user_notification_count =
            locations_data
            |> Enum.reduce(0, fn {location, incidents_data}, location_acc ->
              incidents_data
              |> Enum.reduce(location_acc, fn {incident, fires}, incident_acc ->
                case send_location_incident_notification(user, location, incident, fires) do
                  {:ok, notification_count} ->
                    incident_acc + notification_count

                  {:error, reason} ->
                    Logger.warning(
                      "Failed to send notification for incident #{incident.id} to user #{user.id}",
                      reason: reason
                    )

                    incident_acc
                end
              end)
            end)

          incidents_count =
            locations_data
            |> Enum.flat_map(fn {_location, incidents_data} -> incidents_data end)
            |> length()

          %{
            incidents_processed: acc.incidents_processed + incidents_count,
            notifications_sent: acc.notifications_sent + user_notification_count,
            users_notified: acc.users_notified + if(user_notification_count > 0, do: 1, else: 0)
          }
        end
      )

    {:ok, results}
  end

  defp process_fire_batch_with_status(fires_with_status) do
    # Extract fire IDs and get fires with their incident associations
    fire_ids = Enum.map(fires_with_status, &(Map.get(&1, "fire_id") || Map.get(&1, :fire_id)))

    fires =
      Fire
      |> where([f], f.id in ^fire_ids)
      |> where([f], not is_nil(f.fire_incident_id))
      |> preload(:fire_incident)
      |> Repo.all()

    # Create a map of fire_id -> incident_status for quick lookup
    status_map =
      fires_with_status
      |> Enum.into(%{}, fn fire_status ->
        fire_id = Map.get(fire_status, "fire_id") || Map.get(fire_status, :fire_id)
        status = Map.get(fire_status, "incident_status") || Map.get(fire_status, :incident_status)
        {fire_id, status}
      end)

    # Step 1: Find locations affected by these fires
    fire_location_pairs = Fire.find_locations_affected_by_fires(fires)

    # Step 2: Group by user -> location -> incident -> fires (with status)
    notifications_data =
      fire_location_pairs
      |> Enum.flat_map(fn {fire, locations} ->
        # Get the incident status for this fire
        incident_status = Map.get(status_map, fire.id, :existing_incident)

        # Create a {user, location, incident, fire, status} tuple for each affected location
        Enum.map(locations, fn location ->
          {location.user, location, fire.fire_incident, fire, incident_status}
        end)
      end)
      |> Enum.group_by(fn {user, _location, _incident, _fire, _status} -> user.id end)
      |> Enum.map(fn {_user_id, user_data} ->
        # Group by location within each user
        user = elem(List.first(user_data), 0)

        locations_data =
          user_data
          |> Enum.group_by(fn {_user, location, _incident, _fire, _status} -> location.id end)
          |> Enum.map(fn {_location_id, location_data} ->
            # Group by incident within each location
            location = elem(List.first(location_data), 1)

            incidents_data =
              location_data
              |> Enum.group_by(fn {_user, _location, incident, _fire, _status} -> incident.id end)
              |> Enum.map(fn {_incident_id, incident_data} ->
                incident = elem(List.first(incident_data), 2)

                fires_with_statuses =
                  Enum.map(incident_data, fn {_user, _location, _incident, fire, status} ->
                    {fire, status}
                  end)

                {incident, fires_with_statuses}
              end)

            {location, incidents_data}
          end)

        {user, locations_data}
      end)

    # Step 3: Send notifications grouped by user/location/incident with status info
    results =
      notifications_data
      |> Enum.reduce(
        %{incidents_processed: 0, notifications_sent: 0, users_notified: 0},
        fn {user, locations_data}, acc ->
          user_notification_count =
            locations_data
            |> Enum.reduce(0, fn {location, incidents_data}, location_acc ->
              incidents_data
              |> Enum.reduce(location_acc, fn {incident, fires_with_statuses}, incident_acc ->
                case send_location_incident_notification_with_status(
                       user,
                       location,
                       incident,
                       fires_with_statuses
                     ) do
                  {:ok, notification_count} ->
                    incident_acc + notification_count

                  {:error, reason} ->
                    Logger.warning(
                      "Failed to send notification for incident #{incident.id} to user #{user.id}",
                      reason: reason
                    )

                    incident_acc
                end
              end)
            end)

          incidents_count =
            locations_data
            |> Enum.flat_map(fn {_location, incidents_data} -> incidents_data end)
            |> length()

          %{
            incidents_processed: acc.incidents_processed + incidents_count,
            notifications_sent: acc.notifications_sent + user_notification_count,
            users_notified: acc.users_notified + if(user_notification_count > 0, do: 1, else: 0)
          }
        end
      )

    {:ok, results}
  end

  defp send_location_incident_notification(user, location, incident, fires) do
    # Determine if this is a new incident or ongoing (this will be improved in next step)
    # For now, treat all as ongoing since we don't have the status info yet
    incident_type = :ongoing

    # Count new fires (for now, all fires in this batch are "new")
    new_fire_count = length(fires)

    # Get total fire count for the incident
    total_fire_count = get_incident_fire_count(incident.id)

    # Get truncated incident ID (first 4 characters)
    incident_short_id = String.slice(incident.id, 0, 4)

    # Count active incidents affecting this location
    active_incidents_count = count_active_incidents_for_location(location.id)

    # Build notification content with location context and proper new/ongoing status
    {title, body} =
      build_incident_notification_content(
        incident_type,
        incident_short_id,
        location.name,
        new_fire_count,
        total_fire_count,
        active_incidents_count
      )

    # Create notification record
    notification_attrs = %{
      user_id: user.id,
      fire_incident_id: incident.id,
      title: title,
      body: body,
      type: "fire_alert",
      data: %{
        incident_id: incident.id,
        incident_short_id: incident_short_id,
        location_id: location.id,
        location_name: location.name,
        fire_count: new_fire_count,
        total_fire_count: total_fire_count,
        incident_type: incident_type,
        active_incidents_count: active_incidents_count
      }
    }

    case Notifications.create_notification(notification_attrs) do
      {:ok, notification} ->
        # Send to all user's devices
        case Notifications.send_notification(notification) do
          {:ok, %{sent: _sent_count, failed: failed_count}} ->
            if failed_count > 0 do
              Logger.warning("Some notification devices failed for user #{user.id}",
                failed: failed_count
              )
            end

            {:ok, 1}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_location_incident_notification_with_status(
         user,
         location,
         incident,
         fires_with_statuses
       ) do
    # Determine if this incident has any new fires
    has_new_incidents =
      Enum.any?(fires_with_statuses, fn {_fire, status} -> status == :new_incident end)

    incident_type = if has_new_incidents, do: :new, else: :ongoing

    # Count new fires in this batch
    new_fire_count = length(fires_with_statuses)

    # Get total fire count for the incident
    total_fire_count = get_incident_fire_count(incident.id)

    # Get truncated incident ID (first 4 characters)
    incident_short_id = String.slice(incident.id, 0, 4)

    # Count active incidents affecting this location
    active_incidents_count = count_active_incidents_for_location(location.id)

    # Build notification content with location context and proper new/ongoing status
    {title, body} =
      build_incident_notification_content(
        incident_type,
        incident_short_id,
        location.name,
        new_fire_count,
        total_fire_count,
        active_incidents_count
      )

    # Create notification record
    notification_attrs = %{
      user_id: user.id,
      fire_incident_id: incident.id,
      title: title,
      body: body,
      type: "fire_alert",
      data: %{
        incident_id: incident.id,
        incident_short_id: incident_short_id,
        location_id: location.id,
        location_name: location.name,
        fire_count: new_fire_count,
        total_fire_count: total_fire_count,
        incident_type: incident_type,
        has_new_incidents: has_new_incidents,
        active_incidents_count: active_incidents_count
      }
    }

    case Notifications.create_notification(notification_attrs) do
      {:ok, notification} ->
        # Send to all user's devices
        case Notifications.send_notification(notification) do
          {:ok, %{sent: _sent_count, failed: failed_count}} ->
            if failed_count > 0 do
              Logger.warning("Some notification devices failed for user #{user.id}",
                failed: failed_count
              )
            end

            {:ok, 1}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_incident_fire_count(incident_id) do
    Fire
    |> where([f], f.fire_incident_id == ^incident_id)
    |> select([f], count(f.id))
    |> Repo.one()
  end

  defp count_active_incidents_for_location(location_id) do
    # Find all active incidents that have fires within this location's radius
    # This is a simplified version - in production you might want to cache this
    location = App.Repo.get!(App.Location, location_id)

    Fire
    |> join(:inner, [f], i in App.FireIncident, on: f.fire_incident_id == i.id)
    # Active incidents only
    |> where([f, i], is_nil(i.ended_at))
    |> where(
      [f, i],
      fragment(
        "ST_DWithin(ST_Transform(?, 3857), ST_Transform(?, 3857), ?)",
        f.point,
        ^%Geo.Point{coordinates: {location.longitude, location.latitude}, srid: 4326},
        ^location.radius
      )
    )
    |> select([f, i], i.id)
    |> distinct(true)
    |> Repo.all()
    |> length()
  end

  defp build_incident_notification_content(
         incident_type,
         incident_short_id,
         location_name,
         new_fire_count,
         total_fire_count,
         active_incidents_count
       ) do
    # Build base message
    {title, body_base} =
      case incident_type do
        :new ->
          title = "New fire incident (ID: #{incident_short_id})"
          body = "#{new_fire_count} new fires detected"
          {title, body}

        :ongoing ->
          title = "Fire incident updated (ID: #{incident_short_id})"
          body = "#{new_fire_count} new fires detected (#{total_fire_count} total)"
          {title, body}
      end

    # Add location context
    body_with_location = "#{body_base} near '#{location_name}'"

    # Add multiple incident context if relevant
    final_body =
      if active_incidents_count > 1 do
        "#{body_with_location} (1 of #{active_incidents_count} active incidents)"
      else
        body_with_location
      end

    {title, final_body}
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

    IO.inspect(affected_locations, label: "affected_locations")

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
    # Use a reasonable radius based on the incident's bounds
    # Calculate approximate radius from bounds
    lat_span = incident.max_latitude - incident.min_latitude
    lng_span = incident.max_longitude - incident.min_longitude
    max_span = max(lat_span, lng_span)

    # Convert to meters (approximate: 1 degree ≈ 111,000 meters)
    # Use half the span as radius
    radius_meters = max_span * 111_000 * 0.5
    # Minimum radius based on clustering distance
    radius_meters = max(radius_meters, App.Config.fire_clustering_distance_meters())

    # Use the reusable spatial query function from Fire module
    App.Fire.spatial_query_within_radius(
      Location,
      :point,
      incident.center_latitude,
      incident.center_longitude,
      radius_meters
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
        cutoff_hours = App.Config.incident_cleanup_threshold_hours()
        incident_short_id = String.slice(incident.id, 0, 4)
        title = "Fire incident ended (ID: #{incident_short_id})"

        body =
          "The fire incident near #{location_names} has ended. No new fires have been detected for #{cutoff_hours} hours."

        data = %{
          incident_id: incident.id,
          incident_short_id: incident_short_id,
          location_names: location_names,
          center_lat: incident.center_latitude,
          center_lng: incident.center_longitude,
          total_fire_count: incident.fire_count,
          ended_at: DateTime.to_iso8601(incident.ended_at),
          cutoff_hours: cutoff_hours
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

  def enqueue_fire_batch_with_status(fires_with_status, opts \\ []) do
    base_meta = %{
      source: Keyword.get(opts, :source, "system"),
      requested_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    %{
      "type" => "fire_batch_with_status",
      "fires_with_status" => fires_with_status
    }
    |> __MODULE__.new(meta: base_meta)
    |> Oban.insert()
  end
end
