defmodule Mix.Tasks.FireFetch do
  @moduledoc """
  Mix task to manually trigger FireFetch jobs for testing.
  
  Usage:
    mix fire_fetch        # Fetch last 1 day of data
    mix fire_fetch 3      # Fetch last 3 days of data
  """
  use Mix.Task
  
  def run([]) do
    run(["1"])
  end
  
  def run([days_back]) do
    Mix.Task.run("app.start")
    
    days = String.to_integer(days_back)
    
    Mix.shell().info("🔥 Enqueuing FireFetch job for last #{days} day(s)...")
    
    {:ok, job} = App.Workers.FireFetch.enqueue_now(days)
    
    Mix.shell().info("✅ FireFetch job enqueued with ID: #{job.id}")
    Mix.shell().info("📊 Check progress at: http://localhost:4000/admin/oban")
    Mix.shell().info("🔑 API key configured: #{App.Workers.FireFetch.api_key_configured?()}")
    
    if App.Workers.FireFetch.api_key_configured?() do
      Mix.shell().info("🚀 Job will start processing shortly...")
    else
      Mix.shell().error("❌ NASA_FIRMS_API_KEY not configured - job will fail")
      Mix.shell().error("   Set environment variable: export NASA_FIRMS_API_KEY=your_key_here")
    end
  end
end