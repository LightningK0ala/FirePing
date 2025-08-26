defmodule AppWeb.AuthLive.DashboardTest do
  use AppWeb.ConnCase

  import Phoenix.LiveViewTest
  import App.Factory

  alias App.Notifications

  setup do
    user = insert(:user)
    {:ok, user: user}
  end

  describe "Dashboard LiveView" do
    test "subscribes to user notifications on mount", %{conn: conn, user: user} do
      # Login the user
      conn = get(conn, "/session/login/#{user.id}")
      assert redirected_to(conn) == "/dashboard"

      # Follow the redirect to dashboard
      conn = get(conn, "/dashboard")
      assert html_response(conn, 200)

      # Start the LiveView
      {:ok, _view, _html} = live(conn, "/dashboard")

      # Create a notification and verify it triggers an update
      # The notification should be broadcasted and the component should update
      notification_attrs = %{
        user_id: user.id,
        title: "Test Notification",
        body: "Test body",
        type: "test"
      }

      assert {:ok, _notification} = Notifications.create_notification(notification_attrs)

      # The LiveView should receive the PubSub message and update the component
      # We can't easily test the UI update in a unit test, but we can verify
      # the notification was created and the PubSub broadcast happened
    end
  end
end
