defmodule App.Repo.Migrations.AddFirePerformanceIndexes do
  use Ecto.Migration

  def change do
    # Composite B-tree index for time + quality filtering (covers common queries)
    create index(:fires, [:detected_at, :confidence, :frp],
             where: "confidence IN ('n', 'h') AND frp >= 5.0",
             name: :fires_time_quality_idx
           )

    # Composite index for lat/lng bounding box queries + time
    create index(:fires, [:latitude, :longitude, :detected_at], name: :fires_bbox_time_idx)

    # Spatial index specifically for high-quality fires (most common query)
    create index(:fires, [:point],
             using: :gist,
             where: "confidence IN ('n', 'h') AND frp >= 5.0",
             name: :fires_quality_spatial_idx
           )
  end
end
