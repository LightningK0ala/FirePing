defmodule App.NotificationDevice do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @channels ["web_push", "email", "sms", "webhook"]

  schema "notification_devices" do
    field :name, :string
    field :channel, :string
    field :active, :boolean, default: true
    field :config, :map
    field :last_used_at, :utc_datetime
    field :user_agent, :string

    belongs_to :user, App.User

    timestamps(type: :utc_datetime)
  end

  def changeset(notification_device, attrs) do
    notification_device
    |> cast(attrs, [:name, :channel, :active, :config, :user_agent, :user_id])
    |> validate_required([:name, :channel, :config, :user_id])
    |> validate_inclusion(:channel, @channels)
    |> validate_config_by_channel()
    |> foreign_key_constraint(:user_id)
  end

  defp validate_config_by_channel(changeset) do
    case get_change(changeset, :channel) do
      "web_push" -> validate_web_push_config(changeset)
      "email" -> validate_email_config(changeset)
      "sms" -> validate_sms_config(changeset)
      "webhook" -> validate_webhook_config(changeset)
      _ -> changeset
    end
  end

  defp validate_web_push_config(changeset) do
    case get_change(changeset, :config) do
      %{"endpoint" => endpoint, "keys" => %{"p256dh" => _, "auth" => _}}
      when is_binary(endpoint) ->
        changeset

      _ ->
        add_error(
          changeset,
          :config,
          "must include endpoint and keys.p256dh, keys.auth for web push"
        )
    end
  end

  defp validate_email_config(changeset) do
    case get_change(changeset, :config) do
      %{"email" => email} when is_binary(email) ->
        changeset
        |> validate_change(:config, fn :config, %{"email" => email} ->
          if String.match?(email, ~r/^[^\s]+@[^\s]+$/),
            do: [],
            else: [config: "email must be valid"]
        end)

      _ ->
        add_error(changeset, :config, "must include valid email for email channel")
    end
  end

  defp validate_sms_config(changeset) do
    case get_change(changeset, :config) do
      %{"phone" => phone} when is_binary(phone) ->
        changeset

      _ ->
        add_error(changeset, :config, "must include phone number for SMS channel")
    end
  end

  defp validate_webhook_config(changeset) do
    case get_change(changeset, :config) do
      %{"url" => url} when is_binary(url) ->
        changeset

      _ ->
        add_error(changeset, :config, "must include URL for webhook channel")
    end
  end

  def channels, do: @channels

  def update_last_used(device) do
    device
    |> change(%{last_used_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> App.Repo.update()
  end
end
