defmodule App.Webhook do
  @moduledoc """
  Webhook notifications service with signature support.
  """

  require Logger

  alias App.{Notification, NotificationDevice}

  @doc """
  Sends a webhook notification to a device using HTTP POST.
  """
  def send_notification(%Notification{} = notification, %NotificationDevice{} = device) do
    %{"url" => url} = device.config

    # Create the notification payload
    payload = build_payload(notification)

    # Generate signature
    timestamp = DateTime.utc_now() |> DateTime.to_unix() |> to_string()
    signature = generate_signature(payload, timestamp)

    # Add signature to payload
    signed_payload =
      Map.merge(payload, %{
        "signature" => signature,
        "signature_timestamp" => timestamp
      })

    Logger.info("Sending webhook notification to #{device.name} (#{device.id})")

    try do
      # Convert payload to JSON
      json_payload = Jason.encode!(signed_payload)

      # Send notification using HTTPoison
      case HTTPoison.post(url, json_payload, [{"Content-Type", "application/json"}]) do
        {:ok, %{status_code: status_code}} when status_code in 200..299 ->
          Logger.info("Webhook notification sent successfully to device #{device.id}")
          :ok

        {:ok, %{status_code: status_code}} ->
          Logger.error(
            "Failed to send webhook notification to device #{device.id}: HTTP #{status_code}"
          )

          {:error, "HTTP #{status_code}"}

        {:error, reason} ->
          Logger.error(
            "Failed to send webhook notification to device #{device.id}: #{inspect(reason)}"
          )

          {:error, reason}
      end
    rescue
      error ->
        Logger.error(
          "Failed to send webhook notification to device #{device.id}: #{inspect(error)}"
        )

        {:error, "Webhook error: #{inspect(error)}"}
    end
  end

  @doc """
  Builds the webhook payload from a notification.
  """
  def build_payload(%Notification{} = notification) do
    %{
      "notification_id" => notification.id,
      "title" => notification.title,
      "body" => notification.body,
      "type" => notification.type,
      "data" => notification.data || %{},
      "sent_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  @doc """
  Generates an Ed25519 signature for the webhook payload.
  """
  def generate_signature(payload, timestamp) do
    # Create the string to sign: payload + timestamp
    payload_string = Jason.encode!(payload)
    string_to_sign = payload_string <> timestamp

    # Get the private key
    private_key = get_webhook_private_key()

    if private_key do
      # Sign the string using Ed25519
      signature = Ed25519.signature(string_to_sign, private_key)
      Base.encode64(signature)
    else
      # Fallback if no private key is configured
      Logger.warning("No webhook private key configured, using fallback signature")

      :crypto.hash(:sha256, string_to_sign)
      |> Base.encode64()
    end
  end

  @doc """
  Verifies an Ed25519 webhook signature.
  """
  def verify_signature(payload, timestamp, signature) do
    # Check if timestamp is not too old or too far in the future (1 hour tolerance)
    case verify_timestamp(timestamp) do
      :ok ->
        # Get the public key
        public_key = get_webhook_public_key()

        if public_key do
          # Create the string that was signed: payload + timestamp
          payload_string = Jason.encode!(payload)
          string_to_verify = payload_string <> timestamp

          # Decode the signature from base64
          case Base.decode64(signature) do
            {:ok, decoded_signature} ->
              # Verify Ed25519 signature
              if Ed25519.valid_signature?(decoded_signature, string_to_verify, public_key) do
                :ok
              else
                :error
              end

            :error ->
              :error
          end
        else
          Logger.warning("No webhook public key configured, cannot verify signature")
          :error
        end

      :error ->
        :error
    end
  end

  @doc """
  Verifies that the timestamp is not too old or too far in the future.
  """
  def verify_timestamp(timestamp) do
    case Integer.parse(timestamp) do
      {timestamp_int, ""} ->
        current_time = DateTime.utc_now() |> DateTime.to_unix()
        # 1 hour tolerance
        max_age = 3600

        time_diff = abs(current_time - timestamp_int)

        if time_diff <= max_age do
          :ok
        else
          :error
        end

      _ ->
        :error
    end
  end

  @doc """
  Gets the webhook public key for signature verification.
  """
  def get_webhook_public_key() do
    case App.Config.webhook_public_key() do
      nil ->
        nil

      key ->
        case Base.decode64(key) do
          {:ok, decoded_key} ->
            decoded_key

          :error ->
            Logger.warning("Invalid webhook public key format (not base64)")
            nil
        end
    end
  end

  @doc """
  Gets the raw webhook public key (base64-encoded) for display.
  """
  def get_webhook_public_key_b64() do
    App.Config.webhook_public_key()
  end

  @doc """
  Gets the webhook private key for signature generation.
  """
  def get_webhook_private_key() do
    case App.Config.webhook_private_key() do
      nil ->
        nil

      key ->
        case Base.decode64(key) do
          {:ok, decoded_key} ->
            decoded_key

          :error ->
            Logger.warning("Invalid webhook private key format (not base64)")
            nil
        end
    end
  end
end
