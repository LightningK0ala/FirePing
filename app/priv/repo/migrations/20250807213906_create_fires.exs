defmodule App.Repo.Migrations.CreateFires do
  use Ecto.Migration

  def change do
    create table(:fires, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Core identification
      add :latitude, :float, null: false
      add :longitude, :float, null: false
      add :point, :geometry, null: false

      # NASA identifiers & metadata
      add :satellite, :string, null: false
      add :instrument, :string
      add :version, :string

      # Detection details
      add :detected_at, :utc_datetime, null: false
      add :confidence, :string, null: false
      add :daynight, :string

      # Fire intensity data
      add :bright_ti4, :float
      add :bright_ti5, :float
      add :frp, :float

      # Pixel quality
      add :scan, :float
      add :track, :float

      # Deduplication key
      add :nasa_id, :string, null: false

      timestamps()
    end

    # Indexes for performance
    create unique_index(:fires, [:nasa_id])
    create index(:fires, [:detected_at])
    create index(:fires, [:confidence])
    create index(:fires, [:satellite])
    # Composite index for bounding box queries
    create index(:fires, [:latitude, :longitude])

    # Spatial index for PostGIS queries
    create index(:fires, [:point], using: :gist)
  end
end
