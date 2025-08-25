defmodule App.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id), null: false
      add :title, :string, null: false
      add :body, :text, null: false
      # "fire_alert", "test", etc.
      add :type, :string, null: false
      # "pending", "sent", "failed", "delivered"
      add :status, :string, default: "pending", null: false

      # Optional reference to trigger event
      add :fire_incident_id, references(:fire_incidents, on_delete: :nilify_all, type: :binary_id)

      # Delivery tracking
      add :sent_at, :utc_datetime
      add :delivered_at, :utc_datetime
      add :failed_at, :utc_datetime
      add :failure_reason, :string

      # Additional data
      # Additional payload data
      add :data, :map

      timestamps()
    end

    create index(:notifications, [:user_id])
    create index(:notifications, [:status])
    create index(:notifications, [:type])
    create index(:notifications, [:user_id, :status])
    create index(:notifications, [:fire_incident_id])
    create index(:notifications, [:inserted_at])
  end
end
