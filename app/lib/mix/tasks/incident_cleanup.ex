defmodule Mix.Tasks.IncidentCleanup do
  use Mix.Task

  @shortdoc "Manually trigger incident cleanup job"

  @moduledoc """
  Manually enqueue an incident cleanup job.

  ## Examples

      mix incident_cleanup
      mix incident_cleanup 48

  The first argument is the threshold hours (defaults to configured value).
  """

  def run(args) do
    Mix.Task.run("app.start")

    threshold_hours =
      case args do
        [hours_str] ->
          case Integer.parse(hours_str) do
            {hours, ""} when hours > 0 ->
              hours

            _ ->
              Mix.shell().error("Invalid threshold hours: #{hours_str}")
              System.halt(1)
          end

        [] ->
          App.Config.incident_cleanup_threshold_hours()

        _ ->
          Mix.shell().error("Usage: mix incident_cleanup [threshold_hours]")
          System.halt(1)
      end

    Mix.shell().info("Enqueuing incident cleanup job with #{threshold_hours} hour threshold...")

    case App.Workers.IncidentCleanup.enqueue_now(threshold_hours: threshold_hours) do
      {:ok, job} ->
        Mix.shell().info("✓ IncidentCleanup job enqueued successfully!")
        Mix.shell().info("  Job ID: #{job.id}")
        Mix.shell().info("  Threshold: #{threshold_hours} hours")
        Mix.shell().info("  Queue: #{job.queue}")

      {:error, reason} ->
        Mix.shell().error("✗ Failed to enqueue IncidentCleanup job: #{inspect(reason)}")
        System.halt(1)
    end
  end
end
