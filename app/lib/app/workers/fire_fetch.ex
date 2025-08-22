defmodule App.Workers.FireFetch do
  @moduledoc """
  Oban worker for fetching fire data from NASA FIRMS API.

  Fetches from VIIRS constellation (S-NPP, NOAA-20, NOAA-21) for comprehensive
  global fire coverage with 375m resolution and up to 6 daily passes.

  Scheduled to run every 10 minutes via Oban.Plugins.Cron.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  alias App.{Fire, Repo}

  @nasa_base_url "https://firms.modaps.eosdis.nasa.gov/api"
  @user_agent "FirePing/1.0 (https://github.com/yourorg/fireping)"
  # 90 seconds
  @timeout 90_000

  defp api_key do
    System.get_env("NASA_FIRMS_API_KEY") || "your_key_here"
  end

  # VIIRS constellation satellites (modern, high-resolution fire detection)
  @viirs_satellites [
    # Suomi NPP (2011)
    "VIIRS_SNPP_NRT",
    # NOAA-20/JPSS-1 (2017)
    "VIIRS_NOAA20_NRT",
    # NOAA-21/JPSS-2 (2022)
    "VIIRS_NOAA21_NRT"
  ]

  def perform(%Oban.Job{} = job) do
    args = job.args
    Logger.info("FireFetch: Starting NASA FIRMS data fetch", args: args)

    days_back = Map.get(args, "days_back", 1)
    start_time = System.monotonic_time(:millisecond)

    case fetch_viirs_fire_data(days_back) do
      {:ok, {total_fires, satellite_stats}} ->
        end_time = System.monotonic_time(:millisecond)
        duration_ms = end_time - start_time

        # Add rich metadata for Oban dashboard
        metadata = %{
          total_fires_inserted: total_fires,
          duration_ms: duration_ms,
          duration_seconds: Float.round(duration_ms / 1000, 1),
          days_back: days_back,
          satellites_queried: length(@viirs_satellites),
          satellite_results: satellite_stats,
          completed_at: DateTime.utc_now() |> DateTime.to_iso8601()
        }

        # Persist metadata to the job so it shows in Oban Web
        _ = persist_job_meta(job, metadata)

        Logger.info(
          "FireFetch: Successfully processed #{total_fires} fire records from VIIRS constellation",
          duration: "#{Float.round(duration_ms / 1000, 1)}s",
          satellites: length(@viirs_satellites),
          metadata: metadata
        )

        # Enqueue fire clustering job if we inserted new fires
        if total_fires > 0 do
          case App.Workers.FireClustering.enqueue_now() do
            {:ok, clustering_job} ->
              Logger.info("FireFetch: Enqueued fire clustering job",
                clustering_job_id: clustering_job.id
              )

            {:error, reason} ->
              Logger.warning("FireFetch: Failed to enqueue fire clustering job",
                reason: inspect(reason)
              )
          end
        end

        :ok

      {:error, reason} ->
        end_time = System.monotonic_time(:millisecond)
        duration_ms = end_time - start_time

        # Add error metadata
        error_metadata = %{
          error: true,
          error_reason: inspect(reason),
          duration_ms: duration_ms,
          days_back: days_back,
          satellites_queried: length(@viirs_satellites),
          failed_at: DateTime.utc_now() |> DateTime.to_iso8601()
        }

        # Persist error metadata to the job so it shows in Oban Web
        _ = persist_job_meta(job, error_metadata)

        log_level = if Mix.env() == :test, do: :debug, else: :error

        Logger.log(log_level, "FireFetch: Failed to fetch fire data",
          reason: inspect(reason),
          metadata: error_metadata
        )

        {:error, reason}
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

  def fetch_viirs_fire_data(days_back) do
    Logger.info("FireFetch: Fetching from #{length(@viirs_satellites)} VIIRS satellites")

    # Fetch from all VIIRS satellites in parallel
    tasks =
      @viirs_satellites
      |> Enum.with_index()
      |> Enum.map(fn {satellite, index} ->
        Task.async(fn ->
          {satellite, index, fetch_satellite_data(satellite, days_back)}
        end)
      end)

    results = Task.await_many(tasks, @timeout + 5_000)

    # Build detailed satellite statistics
    satellite_stats =
      results
      |> Enum.map(fn {satellite, _index, result} ->
        case result do
          {:ok, count} ->
            %{satellite: satellite, status: "success", fires_inserted: count}

          {:error, reason} ->
            %{satellite: satellite, status: "error", error: reason, fires_inserted: 0}
        end
      end)

    # Process results
    {successes, failures} =
      Enum.split_with(results, fn
        {_satellite, _index, {:ok, _count}} -> true
        _ -> false
      end)

    if length(failures) == length(@viirs_satellites) do
      {:error, "All VIIRS satellites failed: #{inspect(failures)}"}
    else
      total_fires =
        successes
        |> Enum.map(fn {_satellite, _index, {:ok, count}} -> count end)
        |> Enum.sum()

      if length(failures) > 0 do
        log_level = if Mix.env() == :test, do: :debug, else: :warning
        Logger.log(log_level, "FireFetch: Some satellites failed", failures: failures)
      end

      {:ok, {total_fires, satellite_stats}}
    end
  end

  defp fetch_satellite_data(satellite, days_back) do
    url = "#{@nasa_base_url}/area/csv/#{api_key()}/#{satellite}/world/#{days_back}"

    Logger.info("FireFetch: Fetching #{satellite} data",
      satellite: satellite,
      days_back: days_back
    )

    headers = [
      {"User-Agent", @user_agent},
      {"Accept", "text/csv"}
    ]

    case HTTPoison.get(url, headers, timeout: @timeout, recv_timeout: @timeout) do
      {:ok, %{status_code: 200, body: csv_body}} ->
        Logger.info("FireFetch: Got response from #{satellite}",
          bytes: byte_size(csv_body),
          lines: length(String.split(csv_body, "\n", trim: true))
        )

        process_csv_data(csv_body, satellite)

      {:ok, %{status_code: status_code, body: body}} ->
        log_level = if Mix.env() == :test, do: :debug, else: :error

        Logger.log(log_level, "FireFetch: HTTP error for #{satellite}",
          status: status_code,
          body: String.slice(body, 0, 200)
        )

        {:error, "HTTP #{status_code} for #{satellite}"}

      {:error, reason} ->
        log_level = if Mix.env() == :test, do: :debug, else: :error

        Logger.log(log_level, "FireFetch: Network error for #{satellite}",
          reason: inspect(reason)
        )

        {:error, "Network error for #{satellite}: #{inspect(reason)}"}
    end
  end

  defp process_csv_data("", satellite) do
    Logger.info("FireFetch: Empty response from #{satellite} - no fires or data not ready")
    {:ok, 0}
  end

  defp process_csv_data(csv_body, satellite) do
    Logger.info("FireFetch: Processing CSV data for #{satellite}")

    case parse_csv(csv_body) do
      {:ok, nasa_data_list} ->
        total_count = length(nasa_data_list)

        Logger.info("FireFetch: #{satellite} - #{total_count} rows parsed (no filtering)")

        # Sample FRP distribution for debugging
        _frp_stats =
          if total_count > 0 do
            frp_values =
              nasa_data_list
              |> Enum.map(fn data -> Map.get(data, "frp", 0.0) end)
              |> Enum.sort()

            min_frp = List.first(frp_values)
            max_frp = List.last(frp_values)
            median_frp = Enum.at(frp_values, div(length(frp_values), 2))

            Logger.info(
              "FireFetch: #{satellite} FRP range - min: #{min_frp}, median: #{median_frp}, max: #{max_frp} MW"
            )

            %{min_frp: min_frp, max_frp: max_frp, median_frp: median_frp}
          else
            nil
          end

        # Bulk insert with conflict resolution (upserts based on nasa_id)
        case Fire.bulk_insert(nasa_data_list) do
          {fire_count, _} when is_integer(fire_count) ->
            Logger.info("FireFetch: Inserted/updated #{fire_count} fires from #{satellite}")
            {:ok, fire_count}

          {fire_count, nil} when is_integer(fire_count) ->
            Logger.info("FireFetch: Inserted/updated #{fire_count} fires from #{satellite}")
            {:ok, fire_count}

          error ->
            log_level = if Mix.env() == :test, do: :debug, else: :error

            Logger.log(log_level, "FireFetch: Database error for #{satellite}",
              error: inspect(error)
            )

            {:error, "Database error: #{inspect(error)}"}
        end

      {:error, reason} ->
        log_level = if Mix.env() == :test, do: :debug, else: :error
        Logger.log(log_level, "FireFetch: CSV parsing error for #{satellite}", reason: reason)
        {:error, "CSV parsing error: #{reason}"}
    end
  end

  defp parse_csv(csv_body) do
    lines = String.split(csv_body, "\n", trim: true)

    case lines do
      [header | data_lines] when data_lines != [] ->
        columns = String.split(header, ",")

        nasa_data_list =
          data_lines
          |> Enum.map(&parse_csv_row(&1, columns))
          |> Enum.reject(&is_nil/1)

        {:ok, nasa_data_list}

      [] ->
        {:ok, []}

      [_header_only] ->
        {:ok, []}

      _ ->
        {:error, "Invalid CSV format"}
    end
  end

  defp parse_csv_row(row, columns) do
    values = String.split(row, ",")

    if length(values) == length(columns) do
      columns
      |> Enum.zip(values)
      |> Enum.into(%{})
      |> normalize_nasa_data()
    else
      log_level = if Mix.env() == :test, do: :debug, else: :warning
      Logger.log(log_level, "FireFetch: Skipping malformed CSV row", row: row)
      nil
    end
  end

  defp normalize_nasa_data(raw_data) do
    %{
      "latitude" => get_float(raw_data, "latitude"),
      "longitude" => get_float(raw_data, "longitude"),
      "bright_ti4" => get_float(raw_data, "bright_ti4"),
      "bright_ti5" => get_float(raw_data, "bright_ti5"),
      "scan" => get_float(raw_data, "scan"),
      "track" => get_float(raw_data, "track"),
      "acq_date" => Map.get(raw_data, "acq_date"),
      "acq_time" => get_integer(raw_data, "acq_time"),
      "satellite" => Map.get(raw_data, "satellite"),
      "instrument" => Map.get(raw_data, "instrument"),
      "confidence" => Map.get(raw_data, "confidence"),
      "version" => Map.get(raw_data, "version"),
      "frp" => get_float(raw_data, "frp"),
      "daynight" => Map.get(raw_data, "daynight")
    }
  end

  defp get_float(map, key) do
    case Map.get(map, key) do
      val when is_binary(val) ->
        case Float.parse(val) do
          {float_val, _} -> float_val
          :error -> 0.0
        end

      val when is_number(val) ->
        val * 1.0

      _ ->
        0.0
    end
  end

  defp get_integer(map, key) do
    case Map.get(map, key) do
      val when is_binary(val) ->
        case Integer.parse(val) do
          {int_val, _} -> int_val
          :error -> 0
        end

      val when is_integer(val) ->
        val

      _ ->
        0
    end
  end

  # Note: No quality filtering — we persist all rows from NASA FIRMS.

  @doc """
  Manually trigger a fire fetch job (useful for testing).
  """
  def enqueue_now(days_back \\ 1) do
    base_meta = %{
      source: "manual",
      requested_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      satellites_queried: length(@viirs_satellites)
    }

    %{"days_back" => days_back}
    |> __MODULE__.new(meta: base_meta)
    |> Oban.insert()
  end

  @doc """
  Check if API key is configured properly
  """
  def api_key_configured? do
    key = api_key()
    key != "your_key_here" and String.length(key) > 10
  end
end
