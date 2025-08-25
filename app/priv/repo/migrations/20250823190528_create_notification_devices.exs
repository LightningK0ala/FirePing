defmodule App.Repo.Migrations.CreateNotificationDevices do
  use Ecto.Migration

  def change do
    create table(:notification_devices, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
      add :name, :string, null: false
      # "web_push", "email", "sms", "webhook"
      add :channel, :string, null: false
      add :active, :boolean, default: true, null: false

      # Channel-specific configuration stored as JSON
      # e.g. {"endpoint": "...", "keys": {...}} for web push
      add :config, :map, null: false

      # Metadata
      add :last_used_at, :utc_datetime
      # For web push devices
      add :user_agent, :string

      timestamps()
    end

    create index(:notification_devices, [:user_id])
    create index(:notification_devices, [:channel])
    create index(:notification_devices, [:user_id, :channel])
    create index(:notification_devices, [:active])
  end
end
