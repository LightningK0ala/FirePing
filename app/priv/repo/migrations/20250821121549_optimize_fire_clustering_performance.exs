defmodule App.Repo.Migrations.OptimizeFireClusteringPerformance do
  use Ecto.Migration

  def change do
    # Composite index for clustering query optimization
    # This will dramatically speed up the find_incident_for_fire query
    create index(:fires, [:detected_at, :fire_incident_id], name: :fires_clustering_lookup_idx)

    # Partial index for fires WITH incidents (for spatial searches)
    create index(:fires, [:point],
             using: :gist,
             where: "fire_incident_id IS NOT NULL",
             name: :fires_point_with_incident_idx
           )

    # Partial index for fires WITHOUT incidents (for processing)
    create index(:fires, [:inserted_at],
             where: "fire_incident_id IS NULL",
             name: :fires_unassigned_idx
           )

    # Separate indexes for datetime and spatial (can't combine in single GIST)
    create index(:fires, [:detected_at],
             where: "fire_incident_id IS NOT NULL",
             name: :fires_recent_with_incident_idx
           )
  end
end
