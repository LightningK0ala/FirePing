defmodule Mix.Tasks.Stats do
  @moduledoc """
  Show basic FirePing database statistics.

  Usage:
    mix stats
  """
  use Mix.Task
  require Logger
  import Ecto.Query

  def run([]) do
    Mix.Task.run("app.start")

    # Set log level to info to avoid debug noise
    Logger.configure(level: :info)

    alias App.{Fire, FireIncident, Location, User, Repo}

    Mix.shell().info("🔥 FirePing Statistics")
    Mix.shell().info("")

    # Total fire records
    total_fires = Repo.aggregate(Fire, :count)
    Mix.shell().info("📊 Total fire records: #{total_fires}")

    # Unassigned fires
    unassigned_fires = Fire |> where([f], is_nil(f.fire_incident_id)) |> Repo.aggregate(:count)
    Mix.shell().info("🌋 Unassigned fires: #{unassigned_fires}")

    # Total fire incidents
    total_incidents = Repo.aggregate(FireIncident, :count)
    Mix.shell().info("🔥 Total fire incidents: #{total_incidents}")

    # Active fire incidents
    active_incidents = FireIncident |> where([i], i.status == "active") |> Repo.aggregate(:count)
    Mix.shell().info("🚨 Active fire incidents: #{active_incidents}")

    # Ended fire incidents
    ended_incidents = FireIncident |> where([i], i.status == "ended") |> Repo.aggregate(:count)
    Mix.shell().info("✅ Ended fire incidents: #{ended_incidents}")

    # Total locations
    total_locations = Repo.aggregate(Location, :count)
    Mix.shell().info("📍 Total locations: #{total_locations}")

    # Total users
    total_users = Repo.aggregate(User, :count)
    Mix.shell().info("👥 Total users: #{total_users}")
  end
end
