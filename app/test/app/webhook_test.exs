defmodule App.WebhookTest do
  use App.DataCase, async: true

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
        post: fn url, payload, headers ->
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
        post: fn _url, _payload, _headers ->
          {:ok, %{status_code: 500}}
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

        assert {:error, "HTTP 500"} = Webhook.send_notification(notification, device)
      end
    end

    test "send_notification/2 returns error for network failure" do
      with_mock HTTPoison, [:passthrough],
        post: fn _url, _payload, _headers ->
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
  end
end
