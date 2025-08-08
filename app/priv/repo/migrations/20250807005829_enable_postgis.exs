defmodule App.Repo.Migrations.EnablePostgis do
  use Ecto.Migration

  def change do
    execute("CREATE EXTENSION IF NOT EXISTS postgis", "DROP EXTENSION IF EXISTS postgis")
  end
end
