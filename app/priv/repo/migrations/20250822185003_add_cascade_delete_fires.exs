defmodule App.Repo.Migrations.AddCascadeDeleteFires do
  use Ecto.Migration

  def change do
    # Drop existing foreign key constraint and recreate with CASCADE DELETE
    drop constraint(:fires, "fires_fire_incident_id_fkey")

    alter table(:fires) do
      modify :fire_incident_id,
             references(:fire_incidents, on_delete: :delete_all, type: :binary_id)
    end
  end
end
