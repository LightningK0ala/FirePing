defmodule App.Workers.IncidentCleanup do
  @moduledoc """
  Oban worker for cleaning up fire incidents that have been inactive for too long.

  This worker marks incidents as "ended" when they haven't had any fire detections
  for the configured threshold (default 24 hours).
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    # Only one IncidentCleanup job at a time
    unique: [states: [:available, :executing]]

  require Logger
  alias App.{FireIncident, Repo}

  def perform(%Oban.Job{} = job) do
    args = job.args
    Logger.info("IncidentCleanup: Starting incident cleanup", args: args)

    threshold_hours =
      Map.get(args, "threshold_hours", App.Config.incident_cleanup_threshold_hours())

    start_time = System.monotonic_time(:millisecond)

    case cleanup_incidents(threshold_hours) do
      {ended_count, errors} ->
        end_time = System.monotonic_time(:millisecond)
        duration_ms = end_time - start_time
        error_count = length(errors)
        success_count = ended_count - error_count

        # Add metadata for Oban dashboard
        metadata = %{
          incidents_processed: ended_count,
          incidents_successfully_ended: success_count,
          cleanup_errors: error_count,
          duration_ms: duration_ms,
          duration_seconds: Float.round(duration_ms / 1000, 1),
          threshold_hours: threshold_hours,
          completed_at: DateTime.utc_now() |> DateTime.to_iso8601()
        }

        # Persist metadata to the job
        _ = persist_job_meta(job, metadata)

        if error_count > 0 do
          Logger.warning(
            "IncidentCleanup: Completed with some errors - #{success_count}/#{ended_count} incidents ended successfully",
            duration: "#{Float.round(duration_ms / 1000, 1)}s",
            errors: error_count,
            metadata: metadata
          )
        else
          Logger.info(
            "IncidentCleanup: Successfully ended #{success_count} inactive incidents",
            duration: "#{Float.round(duration_ms / 1000, 1)}s",
            metadata: metadata
          )
        end

        # Trigger incident deletion job after cleanup completes
        enqueue_incident_deletion_job()

        :ok
    end
  end

  defp cleanup_incidents(threshold_hours) do
    # Get incidents that should be ended
    incidents_to_end = FireIncident.incidents_to_end(threshold_hours)
    total_count = length(incidents_to_end)

    if total_count == 0 do
      Logger.info("IncidentCleanup: No incidents found that need to be ended")
      {0, []}
    else
      Logger.info("IncidentCleanup: Found #{total_count} incidents to end")

      # Process each incident
      {cleanup_results, _final_index} =
        incidents_to_end
        |> Enum.with_index(1)
        |> Enum.reduce({[], 0}, fn {incident, index}, {acc, _} ->
          # Log progress for large batches
          if total_count > 10 and rem(index, 5) == 0 do
            Logger.info(
              "IncidentCleanup: Processing incident #{index}/#{total_count} (#{Float.round(index / total_count * 100, 1)}%)"
            )
          end

          result =
            Repo.transaction(fn ->
              case FireIncident.mark_as_ended(incident) do
                {:ok, ended_incident} ->
                  Logger.debug("IncidentCleanup: Ended incident #{ended_incident.id}")
                  :ok

                {:error, reason} ->
                  Logger.warning("IncidentCleanup: Failed to end incident #{incident.id}",
                    reason: inspect(reason)
                  )

                  Repo.rollback({:error, incident.id, reason})
              end
            end)

          new_result =
            case result do
              {:ok, :ok} -> :ok
              {:error, error_tuple} -> error_tuple
            end

          {[new_result | acc], index}
        end)

      cleanup_results = Enum.reverse(cleanup_results)
      cleanup_errors = Enum.filter(cleanup_results, &match?({:error, _, _}, &1))
      success_count = total_count - length(cleanup_errors)

      Logger.info(
        "IncidentCleanup: Completed processing #{total_count} incidents: #{success_count} successful, #{length(cleanup_errors)} failed"
      )

      if length(cleanup_errors) > 0 do
        Logger.warning(
          "IncidentCleanup: Some incidents could not be ended: #{inspect(cleanup_errors)}"
        )
      end

      {total_count, cleanup_errors}
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

  defp enqueue_incident_deletion_job do
    Logger.info("IncidentCleanup: Enqueuing IncidentDeletion job")

    case App.Workers.IncidentDeletion.enqueue_now() do
      {:ok, job} ->
        Logger.info(
          "IncidentCleanup: Successfully enqueued IncidentDeletion job with ID: #{job.id}"
        )

      {:error, reason} ->
        Logger.warning("IncidentCleanup: Failed to enqueue IncidentDeletion job",
          reason: inspect(reason)
        )
    end
  rescue
    error ->
      Logger.error("IncidentCleanup: Error enqueuing IncidentDeletion job", error: inspect(error))
  end

  @doc """
  Manually enqueue an incident cleanup job.
  """
  def enqueue_now(opts \\ []) do
    threshold_hours =
      Keyword.get(opts, :threshold_hours, App.Config.incident_cleanup_threshold_hours())

    base_meta = %{
      source: "manual",
      requested_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    %{
      "threshold_hours" => threshold_hours
    }
    |> __MODULE__.new(meta: base_meta)
    |> Oban.insert()
  end
end
