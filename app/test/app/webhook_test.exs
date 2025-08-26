defmodule App.WebhookTest do
  use App.DataCase

  alias App.{Webhook, Notification, NotificationDevice}

  import Mock

  setup do
    # Set up test webhook keys (raw Ed25519 keys)
    Application.put_env(
      :app,
      :webhook_private_key,
      "mlrAtR18R96Vm39nXsGXxCS/5nqs45YTDdljV/eaxh4="
    )

    Application.put_env(:app, :webhook_public_key, "HY9a5C20R0I/ErKfoP1cwYUnBoFrk0InBWEDfIXphmI=")
    :ok
  end

  describe "webhook sending" do
    test "send_notification/2 sends HTTP POST to webhook URL" do
      with_mock HTTPoison, [:passthrough],
        post: fn url, payload, headers, _opts ->
          assert url == "https://example.com/webhook"
          assert headers == [{"Content-Type", "application/json"}]

          # Parse and verify the payload
          payload_data = Jason.decode!(payload)
          assert payload_data["notification_id"] != nil
          assert payload_data["title"] == "Test Notification"
          assert payload_data["body"] == "Test body"
          assert payload_data["type"] == "test"
          assert payload_data["data"] == %{"key" => "value"}
          assert payload_data["sent_at"] != nil
          assert payload_data["signature"] != nil
          assert payload_data["signature_timestamp"] != nil

          {:ok, %{status_code: 200}}
        end do
        notification = %Notification{
          id: "test-notification-id",
          title: "Test Notification",
          body: "Test body",
          type: "test",
          data: %{"key" => "value"}
        }

        device = %NotificationDevice{
          id: "test-device-id",
          name: "Test Webhook",
          channel: "webhook",
          config: %{"url" => "https://example.com/webhook"}
        }

        assert :ok = Webhook.send_notification(notification, device)
      end
    end

    test "send_notification/2 returns error for HTTP failure" do
      with_mock HTTPoison, [:passthrough],
        post: fn _url, _payload, _headers, _opts ->
          {:ok, %{status_code: 403}}
        end do
        notification = %Notification{
          id: "test-notification-id",
          title: "Test Notification",
          body: "Test body",
          type: "test"
        }

        device = %NotificationDevice{
          id: "test-device-id",
          name: "Test Webhook",
          channel: "webhook",
          config: %{"url" => "https://example.com/webhook"}
        }

        assert {:error, "HTTP 403"} = Webhook.send_notification(notification, device)
      end
    end

    test "send_notification/2 returns error for network failure" do
      with_mock HTTPoison, [:passthrough],
        post: fn _url, _payload, _headers, _opts ->
          {:error, %HTTPoison.Error{reason: :timeout}}
        end do
        notification = %Notification{
          id: "test-notification-id",
          title: "Test Notification",
          body: "Test body",
          type: "test"
        }

        device = %NotificationDevice{
          id: "test-device-id",
          name: "Test Webhook",
          channel: "webhook",
          config: %{"url" => "https://example.com/webhook"}
        }

        assert {:error, %HTTPoison.Error{reason: :timeout}} =
                 Webhook.send_notification(notification, device)
      end
    end
  end

  describe "webhook signature" do
    test "generate_signature/2 creates valid signature" do
      payload = %{"test" => "data"}
      timestamp = "1234567890"

      signature = Webhook.generate_signature(payload, timestamp)

      assert is_binary(signature)
      assert byte_size(signature) > 0
    end

    test "verify_signature/3 verifies valid signature" do
      payload = %{"test" => "data"}
      # Use a recent timestamp
      timestamp = DateTime.utc_now() |> DateTime.to_unix() |> to_string()
      signature = Webhook.generate_signature(payload, timestamp)

      assert Webhook.verify_signature(payload, timestamp, signature) == :ok
    end

    test "verify_signature/3 rejects invalid signature" do
      payload = %{"test" => "data"}
      timestamp = "1234567890"
      invalid_signature = "invalid_signature"

      assert Webhook.verify_signature(payload, timestamp, invalid_signature) == :error
    end

    test "verify_signature/3 rejects expired timestamp" do
      payload = %{"test" => "data"}
      # Use a timestamp that's definitely old (2 hours ago)
      old_timestamp = ((DateTime.utc_now() |> DateTime.to_unix()) - 7200) |> to_string()
      signature = Webhook.generate_signature(payload, old_timestamp)

      assert Webhook.verify_signature(payload, old_timestamp, signature) == :error
    end
  end

  describe "webhook configuration" do
    test "get_webhook_public_key/0 returns configured public key" do
      # The test config should have a public key set
      public_key = App.Config.webhook_public_key()
      assert is_binary(public_key)
      # Should be base64-encoded raw key
      assert byte_size(Base.decode64!(public_key)) > 0
    end

    test "get_webhook_private_key/0 returns configured private key" do
      # The test config should have a private key set
      private_key = App.Config.webhook_private_key()
      assert is_binary(private_key)
      # Should be base64-encoded raw key
      assert byte_size(Base.decode64!(private_key)) > 0
    end

    test "get_webhook_public_key/0 returns nil when not configured" do
      # Temporarily unset the public key
      original_key = Application.get_env(:app, :webhook_public_key)
      Application.put_env(:app, :webhook_public_key, nil)

      assert Webhook.get_webhook_public_key() == nil

      # Restore the original key
      Application.put_env(:app, :webhook_public_key, original_key)
    end

    test "get_webhook_private_key/0 returns nil when not configured" do
      # Temporarily unset the private key
      original_key = Application.get_env(:app, :webhook_private_key)
      Application.put_env(:app, :webhook_private_key, nil)

      assert Webhook.get_webhook_private_key() == nil

      # Restore the original key
      Application.put_env(:app, :webhook_private_key, original_key)
    end
  end

  describe "webhook payload building" do
    test "build_payload/1 creates proper payload structure" do
      notification = %Notification{
        id: "test-id",
        title: "Test Title",
        body: "Test Body",
        type: "fire_alert",
        data: %{"location" => "San Francisco"}
      }

      payload = Webhook.build_payload(notification)

      assert payload["notification_id"] == "test-id"
      assert payload["title"] == "Test Title"
      assert payload["body"] == "Test Body"
      assert payload["type"] == "fire_alert"
      assert payload["data"] == %{"location" => "San Francisco"}
      assert payload["sent_at"] != nil
      assert is_binary(payload["sent_at"])
    end

    test "build_payload/1 handles nil data" do
      notification = %Notification{
        id: "test-id",
        title: "Test Title",
        body: "Test Body",
        type: "test",
        data: nil
      }

      payload = Webhook.build_payload(notification)
      assert payload["data"] == %{}
    end
  end

  describe "signature generation with missing keys" do
    test "generate_signature/2 uses fallback when private key missing" do
      # Temporarily unset the private key
      original_key = Application.get_env(:app, :webhook_private_key)
      Application.put_env(:app, :webhook_private_key, nil)

      payload = %{"test" => "data"}
      timestamp = "1234567890"

      signature = Webhook.generate_signature(payload, timestamp)

      # Should still return a signature (SHA256 fallback)
      assert is_binary(signature)
      assert byte_size(signature) > 0

      # Restore the original key
      Application.put_env(:app, :webhook_private_key, original_key)
    end

    test "verify_signature/3 returns error when public key missing" do
      # Temporarily unset the public key
      original_key = Application.get_env(:app, :webhook_public_key)
      Application.put_env(:app, :webhook_public_key, nil)

      payload = %{"test" => "data"}
      timestamp = DateTime.utc_now() |> DateTime.to_unix() |> to_string()
      signature = "some_signature"

      assert Webhook.verify_signature(payload, timestamp, signature) == :error

      # Restore the original key
      Application.put_env(:app, :webhook_public_key, original_key)
    end
  end

  describe "timestamp verification" do
    test "verify_timestamp/1 accepts recent timestamp" do
      recent_timestamp = DateTime.utc_now() |> DateTime.to_unix() |> to_string()
      assert Webhook.verify_timestamp(recent_timestamp) == :ok
    end

    test "verify_timestamp/1 rejects old timestamp" do
      # 2 hours ago
      old_timestamp = ((DateTime.utc_now() |> DateTime.to_unix()) - 7200) |> to_string()
      assert Webhook.verify_timestamp(old_timestamp) == :error
    end

    test "verify_timestamp/1 rejects future timestamp" do
      # 2 hours in the future
      future_timestamp = ((DateTime.utc_now() |> DateTime.to_unix()) + 7200) |> to_string()
      assert Webhook.verify_timestamp(future_timestamp) == :error
    end

    test "verify_timestamp/1 rejects invalid timestamp format" do
      assert Webhook.verify_timestamp("not_a_number") == :error
      assert Webhook.verify_timestamp("123.456") == :error
      assert Webhook.verify_timestamp("") == :error
    end
  end

  describe "error handling" do
    test "get_webhook_public_key_b64/0 returns base64 key for display" do
      expected_key = "HY9a5C20R0I/ErKfoP1cwYUnBoFrk0InBWEDfIXphmI="
      assert Webhook.get_webhook_public_key_b64() == expected_key
    end

    test "verify_signature/3 handles invalid base64 signature" do
      payload = %{"test" => "data"}
      timestamp = DateTime.utc_now() |> DateTime.to_unix() |> to_string()
      invalid_base64_signature = "invalid-base64!@#"

      assert Webhook.verify_signature(payload, timestamp, invalid_base64_signature) == :error
    end
  end
end
