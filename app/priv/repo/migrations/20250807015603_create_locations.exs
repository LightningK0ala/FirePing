defmodule App.Repo.Migrations.CreateLocations do
  use Ecto.Migration

  def change do
    create table(:locations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :latitude, :float, null: false
      add :longitude, :float, null: false
      add :radius, :integer, null: false
      add :point, :geometry
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:locations, [:user_id])
    create index(:locations, [:point], using: :gist)
  end
end
