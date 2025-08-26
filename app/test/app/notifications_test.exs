defmodule App.NotificationsTest do
  use App.DataCase

  alias App.Notifications
  import Mock

  describe "notification_devices" do
    alias App.NotificationDevice

    import App.Factory

    test "list_notification_devices/1 returns devices for a user" do
      user1 = insert(:user)
      user2 = insert(:user)

      device1 = insert(:notification_device, user: user1)
      device2 = insert(:notification_device, user: user1)
      _device3 = insert(:notification_device, user: user2)

      devices = Notifications.list_notification_devices(user1.id)
      device_ids = Enum.map(devices, & &1.id)

      assert length(devices) == 2
      assert device1.id in device_ids
      assert device2.id in device_ids
    end

    test "get_user_notification_device/2 returns device if it belongs to user" do
      user1 = insert(:user)
      user2 = insert(:user)
      device = insert(:notification_device, user: user1)

      result = Notifications.get_user_notification_device(user1.id, device.id)
      assert result.id == device.id
      assert Notifications.get_user_notification_device(user2.id, device.id) == nil
    end

    test "create_notification_device/1 with valid data creates a device" do
      user = insert(:user)

      valid_attrs = %{
        user_id: user.id,
        name: "My Phone",
        channel: "web_push",
        config: %{
          "endpoint" => "https://fcm.googleapis.com/fcm/send/test",
          "keys" => %{
            "p256dh" => "test-key",
            "auth" => "test-auth"
          }
        }
      }

      assert {:ok, %NotificationDevice{} = device} =
               Notifications.create_notification_device(valid_attrs)

      assert device.name == "My Phone"
      assert device.channel == "web_push"
      assert device.active == true
      assert device.user_id == user.id
    end

    test "create_notification_device/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Notifications.create_notification_device(%{})
    end

    test "update_notification_device/2 with valid data updates the device" do
      device = insert(:notification_device)
      update_attrs = %{name: "Updated Name", active: false}

      assert {:ok, %NotificationDevice{} = updated_device} =
               Notifications.update_notification_device(device, update_attrs)

      assert updated_device.name == "Updated Name"
      assert updated_device.active == false
    end

    test "delete_notification_device/1 deletes the device" do
      device = insert(:notification_device)
      assert {:ok, %NotificationDevice{}} = Notifications.delete_notification_device(device)

      assert_raise Ecto.NoResultsError, fn ->
        Notifications.get_notification_device!(device.id)
      end
    end
  end

  describe "notifications" do
    alias App.Notification

    import App.Factory

    test "create_test_notification/1 creates a test notification" do
      user = insert(:user)

      assert {:ok, %Notification{} = notification} =
               Notifications.create_test_notification(user.id)

      assert notification.title == "Test Notification"
      assert notification.type == "test"
      assert notification.status == "pending"
      assert notification.user_id == user.id
    end

    test "create_notification/1 broadcasts notification_created event" do
      user = insert(:user)

      # Subscribe to the user's notification topic
      Phoenix.PubSub.subscribe(App.PubSub, "notifications:#{user.id}")

      notification_attrs = %{
        user_id: user.id,
        title: "Test Notification",
        body: "Test body",
        type: "test"
      }

      assert {:ok, %Notification{} = notification} =
               Notifications.create_notification(notification_attrs)

      # Should receive the broadcast
      assert_receive {:notification_created, ^notification}
    end

    test "create_notification/1 broadcasts to correct user topic" do
      user1 = insert(:user)
      user2 = insert(:user)

      # Subscribe to both users' notification topics
      Phoenix.PubSub.subscribe(App.PubSub, "notifications:#{user1.id}")
      Phoenix.PubSub.subscribe(App.PubSub, "notifications:#{user2.id}")

      notification_attrs = %{
        user_id: user1.id,
        title: "Test Notification",
        body: "Test body",
        type: "test"
      }

      assert {:ok, %Notification{} = notification} =
               Notifications.create_notification(notification_attrs)

      # Should only receive broadcast for user1
      assert_receive {:notification_created, ^notification}
      refute_receive {:notification_created, _}
    end

    test "list_notifications/2 returns notifications for a user" do
      user1 = insert(:user)
      user2 = insert(:user)

      notification1 = insert(:notification, user: user1)
      notification2 = insert(:notification, user: user1)
      _notification3 = insert(:notification, user: user2)

      notifications = Notifications.list_notifications(user1.id)
      notification_ids = Enum.map(notifications, & &1.id)

      assert length(notifications) == 2
      assert notification1.id in notification_ids
      assert notification2.id in notification_ids
    end

    test "send_notification/1 sends to webhook devices" do
      user = insert(:user)

      _webhook_device =
        insert(:notification_device,
          user: user,
          channel: "webhook",
          config: %{"url" => "https://example.com/webhook"}
        )

      notification = insert(:notification, user: user)

      with_mock App.Webhook, [:passthrough],
        send_notification: fn _notification, _device -> :ok end do
        assert {:ok, %{sent: 1, failed: 0}} = Notifications.send_notification(notification)
      end
    end

    test "send_notification/1 handles webhook failures" do
      user = insert(:user)

      _webhook_device =
        insert(:notification_device,
          user: user,
          channel: "webhook",
          config: %{"url" => "https://example.com/webhook"}
        )

      notification = insert(:notification, user: user)

      with_mock App.Webhook, [:passthrough],
        send_notification: fn _notification, _device ->
          {:error, "HTTP 500"}
        end do
        assert {:ok, %{sent: 0, failed: 1}} = Notifications.send_notification(notification)
      end
    end
  end
end
