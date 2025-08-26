defmodule App.NotificationStatusTest do
  use App.DataCase, async: true

  alias App.Notifications

  import Mock

  describe "notification status logic" do
    test "handles mixed success and failure scenarios" do
      user = insert(:user)

      # Create a notification
      notification = insert(:notification, user: user)

      # Create two devices - one webhook, one web push
      webhook_device =
        insert(:notification_device,
          user: user,
          channel: "webhook",
          config: %{"url" => "https://example.com/webhook"}
        )

      web_push_device =
        insert(:notification_device,
          user: user,
          channel: "web_push",
          config: %{
            "endpoint" => "https://fcm.googleapis.com/fcm/send/test",
            "keys" => %{"p256dh" => "test", "auth" => "test"}
          }
        )

      # Mock the device sending functions
      with_mock App.Webhook, [:passthrough],
        send_notification: fn _notification, device ->
          if device.id == webhook_device.id do
            {:error, "HTTP 500"}
          else
            :ok
          end
        end do
        with_mock App.WebPush, [:passthrough],
          send_notification: fn _notification, device ->
            if device.id == web_push_device.id do
              :ok
            else
              {:error, "Invalid subscription"}
            end
          end do
          with_mock App.NotificationDevice, [:passthrough],
            update_last_used: fn _device -> :ok end do
            with_mock App.Notification, [:passthrough],
              mark_as_sent: fn notification ->
                {:ok, %{notification | status: "sent"}}
              end do
              # Test the mixed scenario
              result = Notifications.send_notification(notification)

              assert {:ok, %{sent: 1, failed: 1}} = result

              # Verify the notification was marked as sent (since at least one device succeeded)
              assert_called(App.Notification.mark_as_sent(notification))
            end
          end
        end
      end
    end

    test "handles all devices failing" do
      user = insert(:user)
      notification = insert(:notification, user: user)

      _webhook_device =
        insert(:notification_device,
          user: user,
          channel: "webhook",
          config: %{"url" => "https://example.com/webhook"}
        )

      with_mock App.Webhook, [:passthrough],
        send_notification: fn _notification, _device ->
          {:error, "HTTP 500"}
        end do
        with_mock App.Notification, [:passthrough],
          mark_as_failed: fn notification, reason ->
            {:ok, %{notification | status: "failed", failure_reason: reason}}
          end do
          result = Notifications.send_notification(notification)

          assert {:error, "HTTP 500"} = result

          # Verify the notification was marked as failed
          assert_called(App.Notification.mark_as_failed(notification, "HTTP 500"))
        end
      end
    end

    test "handles no active devices" do
      user = insert(:user)
      notification = insert(:notification, user: user)

      # No active devices for this user
      result = Notifications.send_notification(notification)

      assert {:error, "No active notification devices found for user"} = result
    end
  end
end
