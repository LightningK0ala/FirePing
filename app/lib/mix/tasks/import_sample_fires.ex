defmodule Mix.Tasks.ImportSampleFires do
  @moduledoc """
  Import sample NASA FIRMS fire data from CSV fixture.

  Usage: mix import_sample_fires
  """

  use Mix.Task
  alias App.Fire

  @shortdoc "Import sample fire data from test fixture"

  def run(_args) do
    Mix.Task.run("app.start")

    # Use relative path from project root
    csv_path = Path.join(["test", "fixtures", "viirs_noaa21_sample.csv"])

    IO.puts("Importing fire data from: #{csv_path}")

    if File.exists?(csv_path) do
      import_csv(csv_path)
    else
      IO.puts("❌ CSV file not found at: #{csv_path}")
      IO.puts("Make sure the sample data exists in test/fixtures/viirs_noaa21_sample.csv")
    end
  end

  defp import_csv(csv_path) do
    start_time = System.monotonic_time(:millisecond)

    csv_path
    |> File.stream!()
    |> CSV.decode!(headers: true)
    |> Stream.map(&convert_csv_row/1)
    # Process in batches of 1000
    |> Stream.chunk_every(1000)
    |> Enum.reduce(0, fn batch, total_inserted ->
      {inserted_count, _} = Fire.bulk_insert(batch)
      total_inserted + inserted_count
    end)
    |> then(fn total_inserted ->
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      IO.puts("✅ Successfully imported #{total_inserted} fire records")
      IO.puts("⏱️  Processing time: #{duration}ms")
      IO.puts("📊 Database now contains #{App.Repo.aggregate(Fire, :count)} total fire records")
    end)
  rescue
    error ->
      IO.puts("❌ Error importing CSV: #{inspect(error)}")
  end

  defp convert_csv_row(row) do
    %{
      "latitude" => String.to_float(row["latitude"]),
      "longitude" => String.to_float(row["longitude"]),
      "bright_ti4" => parse_float(row["bright_ti4"]),
      "scan" => parse_float(row["scan"]),
      "track" => parse_float(row["track"]),
      "acq_date" => row["acq_date"],
      "acq_time" => String.to_integer(row["acq_time"]),
      "satellite" => row["satellite"],
      "instrument" => row["instrument"],
      "confidence" => row["confidence"],
      "version" => row["version"],
      "bright_ti5" => parse_float(row["bright_ti5"]),
      "frp" => parse_float(row["frp"]),
      "daynight" => row["daynight"]
    }
  rescue
    error ->
      IO.puts("⚠️  Skipping invalid row: #{inspect(row)} - Error: #{inspect(error)}")
      nil
  end

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float_val, _} -> float_val
      :error -> 0.0
    end
  end

  defp parse_float(value), do: value
end
