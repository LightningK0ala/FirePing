defmodule Mix.Tasks.FireTest do
  @moduledoc """
  Test fire data processing end-to-end without using Oban.
  This runs the same logic as FireFetch but synchronously with full logging.
  """
  use Mix.Task

  def run([]), do: run(["1"])

  def run([days_back]) do
    Mix.Task.run("app.start")

    days = String.to_integer(days_back)

    Mix.shell().info("🔥 Testing FireFetch logic synchronously...")
    Mix.shell().info("📅 Days back: #{days}")
    Mix.shell().info("")

    # Test the same logic as the worker but with immediate feedback
    case test_fetch_viirs_data(days) do
      {:ok, total_fires} ->
        Mix.shell().info("✅ Success! Processed #{total_fires} fires")
        Mix.shell().info("")
        Mix.shell().info("📊 Final database check:")

        # Check database
        alias App.{Fire, Repo}
        import Ecto.Query

        total_count = Repo.aggregate(Fire, :count)
        Mix.shell().info("  Total fires in DB: #{total_count}")

        if total_count > 0 do
          recent =
            Fire
            |> order_by(desc: :inserted_at)
            |> limit(3)
            |> Repo.all()

          Mix.shell().info("  Recent fires:")

          Enum.each(recent, fn fire ->
            Mix.shell().info(
              "    #{fire.satellite}: #{fire.latitude}, #{fire.longitude} (#{fire.frp} MW)"
            )
          end)
        end

      {:error, reason} ->
        Mix.shell().error("❌ Error: #{inspect(reason)}")
    end
  end

  defp test_fetch_viirs_data(days_back) do
    satellites = [
      "VIIRS_SNPP_NRT",
      "VIIRS_NOAA20_NRT",
      "VIIRS_NOAA21_NRT"
    ]

    Mix.shell().info("📡 Testing #{length(satellites)} satellites...")
    Mix.shell().info("")

    # Test each satellite synchronously
    results =
      satellites
      |> Enum.map(fn satellite ->
        Mix.shell().info("🛰️  Testing #{satellite}...")
        result = test_fetch_satellite_data(satellite, days_back)

        case result do
          {:ok, count} ->
            Mix.shell().info("   ✅ #{count} fires processed")

          {:error, reason} ->
            Mix.shell().error("   ❌ Failed: #{reason}")
        end

        result
      end)

    # Calculate results
    {successes, failures} =
      Enum.split_with(results, fn
        {:ok, _} -> true
        _ -> false
      end)

    Mix.shell().info("")
    Mix.shell().info("📈 Summary:")
    Mix.shell().info("  Successful satellites: #{length(successes)}")
    Mix.shell().info("  Failed satellites: #{length(failures)}")

    if length(failures) == length(satellites) do
      {:error, "All satellites failed"}
    else
      total_fires =
        successes
        |> Enum.map(fn {:ok, count} -> count end)
        |> Enum.sum()

      {:ok, total_fires}
    end
  end

  defp test_fetch_satellite_data(satellite, days_back) do
    api_key = System.get_env("NASA_FIRMS_API_KEY") || "your_key_here"

    url =
      "https://firms.modaps.eosdis.nasa.gov/api/area/csv/#{api_key}/#{satellite}/world/#{days_back}"

    headers = [
      {"User-Agent", "FirePing/1.0 (https://github.com/yourorg/fireping)"},
      {"Accept", "text/csv"}
    ]

    case HTTPoison.get(url, headers, timeout: 30_000, recv_timeout: 30_000) do
      {:ok, %{status_code: 200, body: csv_body}} ->
        Mix.shell().info("   📥 Got #{byte_size(csv_body)} bytes")
        test_process_csv_data(csv_body, satellite)

      {:ok, %{status_code: status_code, body: body}} ->
        {:error, "HTTP #{status_code}: #{String.slice(body, 0, 100)}"}

      {:error, reason} ->
        {:error, "Network: #{inspect(reason)}"}
    end
  end

  defp test_process_csv_data("", _satellite) do
    Mix.shell().info("   📭 Empty response")
    {:ok, 0}
  end

  defp test_process_csv_data(csv_body, _satellite) do
    lines = String.split(csv_body, "\n", trim: true)

    case lines do
      [header | data_lines] when data_lines != [] ->
        columns = String.split(header, ",")

        Mix.shell().info("   📄 #{length(data_lines)} data rows, #{length(columns)} columns")

        # Parse data
        nasa_data_list =
          data_lines
          |> Enum.map(&parse_csv_row(&1, columns))
          |> Enum.reject(&is_nil/1)

        # Apply quality filter
        high_quality_fires = Enum.filter(nasa_data_list, &high_quality_fire?/1)

        total_count = length(nasa_data_list)
        quality_count = length(high_quality_fires)
        filtered_out = total_count - quality_count

        Mix.shell().info(
          "   🎯 #{total_count} total, #{quality_count} quality, #{filtered_out} filtered"
        )

        # Show FRP distribution
        if total_count > 0 do
          frp_values =
            nasa_data_list
            |> Enum.map(fn data -> Map.get(data, "frp", 0.0) end)
            |> Enum.sort()

          min_frp = List.first(frp_values)
          max_frp = List.last(frp_values)
          median_frp = Enum.at(frp_values, div(length(frp_values), 2))

          Mix.shell().info("   🔥 FRP: #{min_frp}-#{max_frp} MW (median: #{median_frp})")
        end

        # Try to insert
        if quality_count > 0 do
          Mix.shell().info("   💾 Attempting database insert...")

          case App.Fire.bulk_insert(high_quality_fires) do
            {fire_count, _} when is_integer(fire_count) ->
              Mix.shell().info("   ✅ Inserted #{fire_count} fires")
              {:ok, fire_count}

            error ->
              Mix.shell().error("   ❌ DB error: #{inspect(error)}")
              {:error, "Database error"}
          end
        else
          Mix.shell().info("   ⚠️  No quality fires to insert")
          {:ok, 0}
        end

      [] ->
        Mix.shell().info("   📭 Empty CSV")
        {:ok, []}

      [_header_only] ->
        Mix.shell().info("   📝 Header only, no data")
        {:ok, []}

      _ ->
        Mix.shell().error("   ❌ Invalid CSV format")
        {:error, "Invalid CSV"}
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

  defp high_quality_fire?(nasa_data) do
    confidence = Map.get(nasa_data, "confidence", "")
    frp = Map.get(nasa_data, "frp", 0.0)
    lat = Map.get(nasa_data, "latitude", 0.0)
    lng = Map.get(nasa_data, "longitude", 0.0)

    confidence in ["n", "h"] and
      frp >= 0.5 and
      lat >= -90 and lat <= 90 and
      lng >= -180 and lng <= 180
  end
end
