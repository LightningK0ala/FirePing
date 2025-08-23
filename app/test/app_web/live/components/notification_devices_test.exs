defmodule AppWeb.Components.NotificationDevicesTest do
  use AppWeb.ConnCase
  import Phoenix.LiveViewTest
  import App.Factory

  alias AppWeb.Components.NotificationDevices

  test "renders empty state when user has no devices", %{conn: conn} do
    user = insert(:user, verified_at: DateTime.utc_now())
    conn = log_in_user(conn, user)

    {:ok, _view, html} = live(conn, "/")

    assert html =~ "No devices registered"
    assert html =~ "Register Your First Device"
  end

  test "shows registered devices", %{conn: conn} do
    user = insert(:user, verified_at: DateTime.utc_now())
    device = insert(:notification_device, user: user, name: "My iPhone")
    conn = log_in_user(conn, user)

    {:ok, _view, html} = live(conn, "/")

    assert html =~ "My iPhone"
    assert html =~ "Web Push"
    assert html =~ "Active"
  end

  test "allows user to register web push device", %{conn: conn} do
    user = insert(:user, verified_at: DateTime.utc_now())
    conn = log_in_user(conn, user)

    {:ok, view, _html} = live(conn, "/")

    # Click to show registration form
    view
    |> element("[phx-click='show_add_form'][phx-target*='notification-devices']")
    |> render_click()

    # Fill out registration form
    view
    |> element("#web-push-registration")
    |> render_hook("register_web_push", %{
      "name" => "Test Device",
      "endpoint" => "https://fcm.googleapis.com/fcm/send/test",
      "p256dh" => "test-key",
      "auth" => "test-auth",
      "user_agent" => "Mozilla/5.0 Test Browser"
    })

    # Check that device was created
    devices = App.Notifications.list_notification_devices(user.id)
    assert length(devices) == 1

    device = List.first(devices)
    assert device.name == "Test Device"
    assert device.channel == "web_push"
  end

  defp log_in_user(conn, user) do
    # Simulate the authentication process
    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:current_user_id, user.id)
  end
end
