defmodule App.WebPush do
  @moduledoc """
  Web Push notifications service using web_push_elixir library.
  """

  require Logger

  alias App.{Notification, NotificationDevice}

  @doc """
  Sends a web push notification to a device using the Web Push Protocol.
  """
  def send_notification(%Notification{} = notification, %NotificationDevice{} = device) do
    %{
      "endpoint" => endpoint,
      "keys" => %{"p256dh" => p256dh, "auth" => auth}
    } = device.config

    # Create the subscription object in the format expected by web_push_elixir
    subscription = %{
      "endpoint" => endpoint,
      "keys" => %{
        "p256dh" => p256dh,
        "auth" => auth
      }
    }

    # Convert subscription to JSON string as expected by web_push_elixir
    subscription_json = Jason.encode!(subscription)

    # Create the notification payload
    payload = %{
      title: notification.title,
      body: notification.body,
      type: notification.type,
      data: notification.data || %{},
      icon: "/images/notification-icon.svg",
      badge: "/images/notification-badge.svg",
      image: "/images/logo.svg",
      tag: "fireping-#{notification.id}",
      requireInteraction: true,
      actions: [
        %{
          action: "view",
          title: "View Dashboard"
        },
        %{
          action: "dismiss",
          title: "Dismiss"
        }
      ]
    }

    Logger.info("Sending web push notification to #{device.name} (#{device.id})")

    try do
      # Convert payload to JSON
      json_payload = Jason.encode!(payload)

      # Send notification using web_push_elixir
      case WebPushElixir.send_notification(subscription_json, json_payload) do
        {:ok, _response} ->
          Logger.info("Web push notification sent successfully to device #{device.id}")
          :ok

        {:error, reason} ->
          Logger.error(
            "Failed to send web push notification to device #{device.id}: #{inspect(reason)}"
          )

          {:error, reason}
      end
    rescue
      error ->
        Logger.error(
          "Failed to send web push notification to device #{device.id}: #{inspect(error)}"
        )

        {:error, "Web push error: #{inspect(error)}"}
    end
  end

  @doc """
  Gets the VAPID public key for client-side subscription.
  """
  def get_vapid_public_key() do
    case Application.get_env(:web_push_elixir, :vapid_public_key) do
      nil ->
        Logger.warning("VAPID_PUBLIC_KEY not set in environment variables")
        nil

      key when is_binary(key) and key != "" ->
        key

      _ ->
        Logger.warning("Invalid VAPID_PUBLIC_KEY in environment variables")
        nil
    end
  end

  @doc """
  Gets the VAPID private key for server-side signing.
  """
  def get_vapid_private_key() do
    case Application.get_env(:web_push_elixir, :vapid_private_key) do
      nil ->
        Logger.warning("VAPID_PRIVATE_KEY not set in environment variables")
        nil

      key when is_binary(key) and key != "" ->
        key

      _ ->
        Logger.warning("Invalid VAPID_PRIVATE_KEY in environment variables")
        nil
    end
  end

  @doc """
  Gets the VAPID subject for JWT claims.
  """
  def get_vapid_subject() do
    case Application.get_env(:web_push_elixir, :vapid_subject) do
      nil ->
        Logger.warning("VAPID_SUBJECT not set in environment variables")
        "mailto:support@fireping.net"

      subject when is_binary(subject) and subject != "" ->
        subject

      _ ->
        Logger.warning("Invalid VAPID_SUBJECT in environment variables")
        "mailto:support@fireping.net"
    end
  end
end
