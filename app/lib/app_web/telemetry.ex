defmodule AppWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller,
       measurements: periodic_measurements(), period: 10_000, init_delay: 5_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Keep only essential Phoenix metrics for response times
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond},
        description: "HTTP request response times"
      ),

      # Keep essential VM memory metric
      summary("vm.memory.total", unit: {:byte, :kilobyte}),

      # Database Size Metrics
      last_value("app.database.size.gigabytes",
        description: "Database size in gigabytes"
      ),

      # Fire Detection Metrics
      last_value("app.fires.total_count",
        description: "Total fires in database"
      ),
      last_value("app.fires.recent_24h_count",
        description: "Fires detected in last 24 hours"
      ),
      last_value("app.fires.high_quality_count",
        description: "High quality fires (confidence n/h + FRP>=5)"
      ),
      last_value("app.fires.viirs_snpp_count",
        description: "Fires from VIIRS SNPP satellite"
      ),
      last_value("app.fires.viirs_noaa20_count",
        description: "Fires from VIIRS NOAA-20 satellite"
      ),
      last_value("app.fires.viirs_noaa21_count",
        description: "Fires from VIIRS NOAA-21 satellite"
      ),

      # Fire Incident Metrics
      last_value("app.incidents.active_count",
        description: "Currently active fire incidents"
      ),
      last_value("app.incidents.total_count",
        description: "Total fire incidents"
      ),
      last_value("app.incidents.avg_fires_per_incident",
        description: "Average fires per incident"
      ),

      # User Engagement Metrics
      last_value("app.users.total_count",
        description: "Total registered users"
      ),
      last_value("app.locations.total_count",
        description: "Total monitored locations"
      )
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      {__MODULE__, :measure_database_size, []},
      {__MODULE__, :measure_fire_metrics, []},
      {__MODULE__, :measure_incident_metrics, []},
      {__MODULE__, :measure_user_metrics, []}
    ]
  end

  def measure_database_size do
    if Code.ensure_loaded?(App.Repo) and Process.whereis(App.Repo) do
      try do
        case App.Repo.query("SELECT pg_database_size(current_database()) as size") do
          {:ok, %{rows: [[size_bytes]]}} ->
            size_gb = size_bytes / (1024 * 1024 * 1024)
            :telemetry.execute([:app, :database, :size], %{gigabytes: size_gb})

          _error ->
            :ok
        end
      catch
        _kind, _reason ->
          :ok
      end
    end
  end

  def measure_fire_metrics do
    if Code.ensure_loaded?(App.Repo) and Process.whereis(App.Repo) do
      try do
        import Ecto.Query

        # Total fires
        total_fires = App.Repo.aggregate(App.Fire, :count)
        :telemetry.execute([:app, :fires], %{total_count: total_fires})

        # Recent 24h fires
        cutoff_24h = DateTime.utc_now() |> DateTime.add(-24, :hour)
        recent_fires_query = from f in App.Fire, where: f.detected_at >= ^cutoff_24h
        recent_fires = App.Repo.aggregate(recent_fires_query, :count)
        :telemetry.execute([:app, :fires], %{recent_24h_count: recent_fires})

        # High quality fires
        high_quality_query =
          from f in App.Fire,
            where: f.confidence in ["n", "h"] and f.frp >= 5.0

        high_quality_fires = App.Repo.aggregate(high_quality_query, :count)
        :telemetry.execute([:app, :fires], %{high_quality_count: high_quality_fires})

        # Fires by satellite
        satellites = [
          {"VIIRS_SNPP_NRT", :viirs_snpp_count},
          {"VIIRS_NOAA20_NRT", :viirs_noaa20_count},
          {"VIIRS_NOAA21_NRT", :viirs_noaa21_count}
        ]

        for {satellite, metric_key} <- satellites do
          satellite_query = from f in App.Fire, where: f.satellite == ^satellite
          count = App.Repo.aggregate(satellite_query, :count)
          :telemetry.execute([:app, :fires], %{metric_key => count})
        end
      catch
        _kind, _reason ->
          :ok
      end
    end
  end

  def measure_incident_metrics do
    if Code.ensure_loaded?(App.Repo) and Process.whereis(App.Repo) do
      try do
        import Ecto.Query

        # Active incidents
        active_query = from i in App.FireIncident, where: i.status == "active"
        active_incidents = App.Repo.aggregate(active_query, :count)
        :telemetry.execute([:app, :incidents], %{active_count: active_incidents})

        # Total incidents
        total_incidents = App.Repo.aggregate(App.FireIncident, :count)
        :telemetry.execute([:app, :incidents], %{total_count: total_incidents})

        # Average fires per incident
        if total_incidents > 0 do
          avg_fires = App.Repo.aggregate(App.FireIncident, :avg, :fire_count) || 0
          :telemetry.execute([:app, :incidents], %{avg_fires_per_incident: avg_fires})
        else
          :telemetry.execute([:app, :incidents], %{avg_fires_per_incident: 0})
        end
      catch
        _kind, _reason ->
          :ok
      end
    end
  end

  def measure_user_metrics do
    if Code.ensure_loaded?(App.Repo) and Process.whereis(App.Repo) do
      try do
        # Total users (assuming you have a User model)
        total_users =
          if Code.ensure_loaded?(App.User) do
            App.Repo.aggregate(App.User, :count)
          else
            0
          end

        :telemetry.execute([:app, :users], %{total_count: total_users})

        # Total locations
        total_locations =
          if Code.ensure_loaded?(App.Location) do
            App.Repo.aggregate(App.Location, :count)
          else
            0
          end

        :telemetry.execute([:app, :locations], %{total_count: total_locations})
      catch
        _kind, _reason ->
          :ok
      end
    end
  end
end
