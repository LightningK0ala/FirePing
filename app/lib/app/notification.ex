defmodule App.Notification do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @types ["fire_alert", "test", "system"]
  @statuses ["pending", "sent", "failed", "delivered"]

  schema "notifications" do
    field :title, :string
    field :body, :string
    field :type, :string
    field :status, :string, default: "pending"
    field :data, :map
    field :sent_at, :utc_datetime
    field :delivered_at, :utc_datetime
    field :failed_at, :utc_datetime
    field :failure_reason, :string

    belongs_to :user, App.User
    belongs_to :fire_incident, App.FireIncident

    timestamps(type: :utc_datetime)
  end

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:title, :body, :type, :status, :data, :user_id, :fire_incident_id])
    |> validate_required([:title, :body, :type, :user_id])
    |> validate_inclusion(:type, @types)
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:fire_incident_id)
  end

  def mark_as_sent(notification) do
    notification
    |> change(%{status: "sent", sent_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> App.Repo.update()
  end

  def mark_as_delivered(notification) do
    notification
    |> change(%{
      status: "delivered",
      delivered_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> App.Repo.update()
  end

  def mark_as_failed(notification, reason) do
    notification
    |> change(%{
      status: "failed",
      failed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      failure_reason: reason
    })
    |> App.Repo.update()
  end

  def types, do: @types
  def statuses, do: @statuses
end
