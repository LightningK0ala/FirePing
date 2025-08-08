defmodule Mix.Tasks.FireDebug do
  @moduledoc """
  Debug task to manually test NASA FIRMS API calls and see raw responses.

  Usage:
    mix fire_debug        # Test VIIRS S-NPP for last 1 day
    mix fire_debug 3      # Test VIIRS S-NPP for last 3 days
  """
  use Mix.Task

  def run([]), do: run(["1"])

  def run([days_back]) do
    Mix.Task.run("app.start")

    days = String.to_integer(days_back)
    satellite = "VIIRS_SNPP_NRT"
    api_key = System.get_env("NASA_FIRMS_API_KEY") || "your_key_here"

    url =
      "https://firms.modaps.eosdis.nasa.gov/api/area/csv/#{api_key}/#{satellite}/world/#{days}"

    Mix.shell().info("🔥 Testing NASA FIRMS API...")
    Mix.shell().info("📡 Satellite: #{satellite}")
    Mix.shell().info("📅 Days back: #{days}")
    Mix.shell().info("🔑 API key: #{String.slice(api_key, 0, 8)}...")
    Mix.shell().info("🌐 URL: #{url}")
    Mix.shell().info("")

    headers = [
      {"User-Agent", "FirePing/1.0 (https://github.com/yourorg/fireping)"},
      {"Accept", "text/csv"}
    ]

    case HTTPoison.get(url, headers, timeout: 30_000, recv_timeout: 30_000) do
      {:ok, %{status_code: 200, body: body}} ->
        lines = String.split(body, "\n", trim: true)

        Mix.shell().info("✅ Success! Got response:")
        Mix.shell().info("📊 Response size: #{byte_size(body)} bytes")
        Mix.shell().info("📄 Number of lines: #{length(lines)}")

        if length(lines) > 0 do
          Mix.shell().info("📋 First few lines:")

          lines
          |> Enum.take(5)
          |> Enum.with_index(1)
          |> Enum.each(fn {line, i} ->
            Mix.shell().info("  #{i}: #{line}")
          end)

          if length(lines) > 1 do
            # Parse and analyze first data row
            [header | data_lines] = lines
            columns = String.split(header, ",")

            Mix.shell().info("")
            Mix.shell().info("🔍 Analysis:")
            Mix.shell().info("  Headers: #{length(columns)} columns")
            Mix.shell().info("  Data rows: #{length(data_lines)}")

            if length(data_lines) > 0 do
              first_row = List.first(data_lines)
              values = String.split(first_row, ",")

              # Create a sample fire record
              fire_data =
                columns
                |> Enum.zip(values)
                |> Enum.into(%{})

              # Check quality filtering
              confidence = Map.get(fire_data, "confidence", "")

              frp =
                case Float.parse(Map.get(fire_data, "frp", "0")) do
                  {f, _} -> f
                  :error -> 0.0
                end

              Mix.shell().info("  Sample fire:")
              Mix.shell().info("    Latitude: #{Map.get(fire_data, "latitude")}")
              Mix.shell().info("    Longitude: #{Map.get(fire_data, "longitude")}")
              Mix.shell().info("    Confidence: #{confidence}")
              Mix.shell().info("    FRP: #{frp} MW")
              Mix.shell().info("    Satellite: #{Map.get(fire_data, "satellite")}")

              is_quality = confidence in ["n", "h"] and frp >= 5.0
              Mix.shell().info("    High quality? #{is_quality}")
            end
          end
        else
          Mix.shell().info("📭 Empty response - no fire data available")
        end

      {:ok, %{status_code: status_code, body: body}} ->
        Mix.shell().error("❌ HTTP Error #{status_code}")
        Mix.shell().error("Response: #{String.slice(body, 0, 200)}")

      {:error, reason} ->
        Mix.shell().error("❌ Network Error: #{inspect(reason)}")
    end
  end
end
