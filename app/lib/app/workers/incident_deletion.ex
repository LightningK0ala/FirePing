defmodule App.Workers.IncidentDeletion do
  @moduledoc """
  Oban worker for deleting ended fire incidents older than a specified threshold.

  This worker helps keep the database clean by removing old ended incidents
  and their associated fires, preventing unbounded growth of historical data.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    # Only one IncidentDeletion job at a time
    unique: [states: [:available, :executing]]

  require Logger
  alias App.FireIncident

  def perform(%Oban.Job{} = job) do
    args = job.args
    Logger.info("IncidentDeletion: Starting cleanup of ended incidents", args: args)

    days_old = Map.get(args, "days_old", App.Config.incident_deletion_threshold_days())
    batch_size = Map.get(args, "batch_size", 1000)
    start_time = System.monotonic_time(:millisecond)

    Logger.info("IncidentDeletion: Using batch size of #{batch_size} for deletion")

    case FireIncident.delete_ended_incidents(days_old, batch_size) do
      {deleted_incidents, deleted_fires} ->
        end_time = System.monotonic_time(:millisecond)
        duration_ms = end_time - start_time

        # Add metadata for Oban dashboard
        metadata = %{
          incidents_deleted: deleted_incidents,
          fires_deleted: deleted_fires,
          duration_ms: duration_ms,
          duration_seconds: Float.round(duration_ms / 1000, 1),
          days_old_threshold: days_old,
          batch_size: batch_size,
          completed_at: DateTime.utc_now() |> DateTime.to_iso8601()
        }

        # Persist metadata to the job
        _ = persist_job_meta(job, metadata)

        if deleted_incidents > 0 do
          Logger.info(
            "IncidentDeletion: Successfully deleted #{deleted_incidents} ended incidents and #{deleted_fires} associated fires",
            duration: "#{Float.round(duration_ms / 1000, 1)}s",
            threshold: "#{days_old} days",
            batch_size: batch_size,
            metadata: metadata
          )
        else
          Logger.info(
            "IncidentDeletion: No ended incidents found older than #{days_old} days",
            duration: "#{Float.round(duration_ms / 1000, 1)}s",
            metadata: metadata
          )
        end

        :ok
    end
  end

  defp persist_job_meta(%Oban.Job{} = job, new_meta) when is_map(new_meta) do
    merged_meta = Map.merge(job.meta || %{}, new_meta)

    job
    |> Ecto.Changeset.change(meta: merged_meta)
    |> App.Repo.update()
  rescue
    _ -> :ok
  end

  @doc """
  Manually enqueue an incident deletion job.
  """
  def enqueue_now(opts \\ []) do
    days_old = Keyword.get(opts, :days_old, App.Config.incident_deletion_threshold_days())
    batch_size = Keyword.get(opts, :batch_size, 1000)

    base_meta = %{
      source: "manual",
      requested_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    %{
      "days_old" => days_old,
      "batch_size" => batch_size
    }
    |> __MODULE__.new(meta: base_meta)
    |> Oban.insert()
  end
end
