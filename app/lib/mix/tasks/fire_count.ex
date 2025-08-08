defmodule Mix.Tasks.FireCount do
  @moduledoc """
  Count fires in the database with breakdown by satellite and time.
  
  Usage:
    mix fire_count
  """
  use Mix.Task
  
  def run([]) do
    Mix.Task.run("app.start")
    
    alias App.{Fire, Repo}
    import Ecto.Query
    
    Mix.shell().info("🔥 FirePing Database Statistics")
    Mix.shell().info("")
    
    # Total count
    total_count = Repo.aggregate(Fire, :count)
    Mix.shell().info("📊 Total fires: #{total_count}")
    
    if total_count > 0 do
      # By satellite
      by_satellite = 
        Fire
        |> group_by([f], f.satellite)
        |> select([f], {f.satellite, count()})
        |> Repo.all()
      
      Mix.shell().info("")
      Mix.shell().info("📡 By satellite:")
      Enum.each(by_satellite, fn {satellite, count} ->
        Mix.shell().info("  #{satellite}: #{count} fires")
      end)
      
      # By confidence
      by_confidence = 
        Fire
        |> group_by([f], f.confidence)
        |> select([f], {f.confidence, count()})
        |> Repo.all()
      
      Mix.shell().info("")
      Mix.shell().info("🎯 By confidence:")
      Enum.each(by_confidence, fn {confidence, count} ->
        confidence_name = case confidence do
          "l" -> "Low"
          "n" -> "Normal"
          "h" -> "High"
          other -> other
        end
        Mix.shell().info("  #{confidence_name} (#{confidence}): #{count} fires")
      end)
      
      # Recent activity (last 24 hours)
      cutoff = DateTime.utc_now() |> DateTime.add(-24, :hour)
      recent_count = 
        Fire
        |> where([f], f.detected_at >= ^cutoff)
        |> Repo.aggregate(:count)
      
      Mix.shell().info("")
      Mix.shell().info("⏰ Recent activity (last 24 hours): #{recent_count} fires")
      
      # FRP statistics
      frp_stats = 
        Fire
        |> select([f], %{
          min: min(f.frp),
          max: max(f.frp),
          avg: avg(f.frp)
        })
        |> Repo.one()
      
      if frp_stats do
        Mix.shell().info("")
        Mix.shell().info("🔥 Fire Radiative Power (FRP):")
        Mix.shell().info("  Min: #{Float.round(frp_stats.min || 0.0, 2)} MW")
        Mix.shell().info("  Max: #{Float.round(frp_stats.max || 0.0, 2)} MW")
        Mix.shell().info("  Avg: #{Float.round(frp_stats.avg || 0.0, 2)} MW")
      end
      
      # Oldest and newest fires
      oldest = Fire |> order_by([f], asc: f.detected_at) |> limit(1) |> Repo.one()
      newest = Fire |> order_by([f], desc: f.detected_at) |> limit(1) |> Repo.one()
      
      if oldest && newest do
        Mix.shell().info("")
        Mix.shell().info("📅 Time range:")
        Mix.shell().info("  Oldest: #{oldest.detected_at}")
        Mix.shell().info("  Newest: #{newest.detected_at}")
      end
    else
      Mix.shell().info("")
      Mix.shell().info("📭 No fires in database. Try running:")
      Mix.shell().info("  make fire-fetch")
      Mix.shell().info("  Check Oban dashboard at /admin/oban for job status")
    end
  end
end