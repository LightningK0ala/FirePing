defmodule App.Repo.Migrations.CreateFireIncidents do
  use Ecto.Migration

  def change do
    create table(:fire_incidents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      
      # Status tracking (:active, :ended)
      add :status, :string, null: false, default: "active"
      
      # Center point for map display (calculated from associated fires)
      add :center_latitude, :float, null: false
      add :center_longitude, :float, null: false
      add :center_point, :geometry, null: false
      
      # Incident metrics
      add :fire_count, :integer, null: false, default: 0
      add :first_detected_at, :utc_datetime, null: false
      add :last_detected_at, :utc_datetime, null: false
      
      # Fire intensity metrics (calculated from associated fires)
      add :max_frp, :float
      add :min_frp, :float
      add :avg_frp, :float
      add :total_frp, :float
      
      # Incident lifecycle
      add :ended_at, :utc_datetime
      
      timestamps()
    end

    # Indexes for performance
    create index(:fire_incidents, [:status])
    create index(:fire_incidents, [:first_detected_at])
    create index(:fire_incidents, [:last_detected_at])
    create index(:fire_incidents, [:ended_at])
    
    # Spatial index for geographic queries
    create index(:fire_incidents, [:center_point], using: :gist)
    
    # Composite indexes for common queries
    create index(:fire_incidents, [:status, :last_detected_at])
  end
end
