defmodule App.Workers.FireClustering do
  @moduledoc """
  Oban worker for processing unassigned fires and clustering them into incidents.

  This worker is typically enqueued after a successful FireFetch to ensure
  newly imported fires are properly assigned to fire incidents.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    # Only one FireClustering job at a time
    unique: [states: [:available, :executing]]

  require Logger
  import Ecto.Query
  alias App.{Fire, Repo}

  def perform(%Oban.Job{} = job) do
    args = job.args
    Logger.info("FireClustering: Starting fire incident clustering", args: args)

    clustering_distance = Map.get(args, "clustering_distance", 5000)
    expiry_hours = Map.get(args, "expiry_hours", App.Config.fire_clustering_expiry_hours())
    start_time = System.monotonic_time(:millisecond)

    case Fire.process_unassigned_fires(
           clustering_distance: clustering_distance,
           expiry_hours: expiry_hours
         ) do
      {processed_count, errors} ->
        end_time = System.monotonic_time(:millisecond)
        duration_ms = end_time - start_time
        error_count = length(errors)
        success_count = processed_count - error_count

        # Add metadata for Oban dashboard
        metadata = %{
          fires_processed: processed_count,
          fires_successfully_clustered: success_count,
          clustering_errors: error_count,
          duration_ms: duration_ms,
          duration_seconds: Float.round(duration_ms / 1000, 1),
          clustering_distance_meters: clustering_distance,
          expiry_hours: expiry_hours,
          completed_at: DateTime.utc_now() |> DateTime.to_iso8601()
        }

        # Persist metadata to the job
        _ = persist_job_meta(job, metadata)

        if error_count > 0 do
          Logger.warning(
            "FireClustering: Completed with some errors - #{success_count}/#{processed_count} fires clustered successfully",
            duration: "#{Float.round(duration_ms / 1000, 1)}s",
            errors: error_count,
            metadata: metadata
          )
        else
          Logger.info(
            "FireClustering: Successfully clustered #{success_count} unassigned fires",
            duration: "#{Float.round(duration_ms / 1000, 1)}s",
            metadata: metadata
          )
        end

        # Enqueue incident cleanup after clustering is complete
        case App.Workers.IncidentCleanup.enqueue_now() do
          {:ok, cleanup_job} ->
            Logger.info("FireClustering: Enqueued incident cleanup job",
              cleanup_job_id: cleanup_job.id
            )

          {:error, reason} ->
            Logger.warning("FireClustering: Failed to enqueue incident cleanup job",
              reason: inspect(reason)
            )
        end

        # Trigger notification orchestration for any incidents that were updated
        if success_count > 0 do
          # Get incident IDs that were affected during clustering
          # This is a simplified approach - in practice, you might want to track which incidents were modified
          recent_incidents =
            App.FireIncident
            |> where([i], i.status == "active")
            |> where([i], i.updated_at >= ^DateTime.add(DateTime.utc_now(), -1, :hour))
            |> select([i], i.id)
            |> App.Repo.all()

          if length(recent_incidents) > 0 do
            App.Workers.NotificationOrchestrator.enqueue_incident_updates(recent_incidents,
              source: "fire_clustering"
            )

            Logger.info(
              "FireClustering: Enqueued notification orchestration for #{length(recent_incidents)} incidents"
            )
          end
        end

        :ok
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
  Manually enqueue a fire clustering job.
  """
  def enqueue_now(opts \\ []) do
    clustering_distance = Keyword.get(opts, :clustering_distance, 5000)
    expiry_hours = Keyword.get(opts, :expiry_hours, App.Config.fire_clustering_expiry_hours())

    base_meta = %{
      source: "manual",
      requested_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    %{
      "clustering_distance" => clustering_distance,
      "expiry_hours" => expiry_hours
    }
    |> __MODULE__.new(meta: base_meta)
    |> Oban.insert()
  end
end
