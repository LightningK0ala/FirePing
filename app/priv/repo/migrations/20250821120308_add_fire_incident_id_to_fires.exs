defmodule App.Repo.Migrations.AddFireIncidentIdToFires do
  use Ecto.Migration

  def change do
    alter table(:fires) do
      add :fire_incident_id, references(:fire_incidents, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:fires, [:fire_incident_id])
  end
end
