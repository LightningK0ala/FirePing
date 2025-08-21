defmodule Mix.Tasks.FireCluster do
  @moduledoc """
  Mix task to manually trigger fire clustering jobs.

  Usage:
    mix fire_cluster                    # Use default clustering parameters
    mix fire_cluster 3000 48           # Custom distance (3000m) and expiry (48h)
  """
  use Mix.Task

  def run([]) do
    run(["5000", "72"])
  end

  def run([distance]) do
    run([distance, "72"])
  end

  def run([distance_str, expiry_str]) do
    Mix.Task.run("app.start")

    distance = String.to_integer(distance_str)
    expiry = String.to_integer(expiry_str)

    Mix.shell().info("🔥 Enqueuing fire clustering job...")
    Mix.shell().info("   Clustering distance: #{distance}m")
    Mix.shell().info("   Expiry window: #{expiry}h")

    {:ok, job} =
      App.Workers.FireClustering.enqueue_now(
        clustering_distance: distance,
        expiry_hours: expiry
      )

    Mix.shell().info("✅ Fire clustering job enqueued with ID: #{job.id}")
    Mix.shell().info("📊 Check progress at: http://localhost:4000/admin/oban")
  end
end
