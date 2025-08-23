defmodule App.Repo.Migrations.AddBoundsToFireIncidents do
  use Ecto.Migration

  def change do
    alter table(:fire_incidents) do
      add :min_latitude, :float
      add :max_latitude, :float
      add :min_longitude, :float
      add :max_longitude, :float
    end
  end
end
