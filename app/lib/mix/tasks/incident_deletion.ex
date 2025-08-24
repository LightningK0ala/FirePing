defmodule Mix.Tasks.IncidentDeletion do
  @moduledoc """
  Mix task to manually trigger incident deletion jobs.

  Usage:
    mix incident_deletion                  # Use default threshold (3 days)
    mix incident_deletion 60               # Delete incidents ended more than 60 days ago
    mix incident_deletion 60 500           # Delete incidents with custom batch size
  """
  use Mix.Task

  def run([]) do
    run([Integer.to_string(App.Config.incident_deletion_threshold_days())])
  end

  def run([days_str]) do
    run([days_str, "1000"])
  end

  def run([days_str, batch_size_str]) do
    Mix.Task.run("app.start")

    days = String.to_integer(days_str)
    batch_size = String.to_integer(batch_size_str)

    Mix.shell().info("🗑️  Enqueuing incident deletion job...")
    Mix.shell().info("   Deletion threshold: #{days} days")
    Mix.shell().info("   Batch size: #{batch_size}")

    {:ok, job} =
      App.Workers.IncidentDeletion.enqueue_now(days_old: days, batch_size: batch_size)

    Mix.shell().info("✅ Incident deletion job enqueued with ID: #{job.id}")
    Mix.shell().info("📊 Check progress at: http://localhost:4000/admin/oban")
  end
end
