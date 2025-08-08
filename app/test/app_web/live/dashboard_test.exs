defmodule AppWeb.DashboardLiveTest do
  use AppWeb.ConnCase
  import Phoenix.LiveViewTest
  import App.Factory

  test "user can edit a location inline", %{conn: conn} do
    user = insert(:user)
    location = insert(:location, user: user, name: "Home", latitude: 40.7128, longitude: -74.0060, radius: 5000)

    conn = Plug.Test.init_test_session(conn, user_id: user.id)

    {:ok, view, _html} = live(conn, ~p"/dashboard")

    # Start editing
    view
    |> element("button[phx-click='start_edit_location'][phx-value-id='#{location.id}']")
    |> render_click()

    # Submit new values
    params = %{
      "_id" => location.id,
      "name" => "New Name",
      "latitude" => "37.7749",
      "longitude" => "-122.4194",
      "radius" => "8000"
    }

    view
    |> form("#edit-location-form-#{location.id}", params)
    |> render_submit()

    # Assert updated render shows new values
    html = render(view)
    assert html =~ "New Name"
    assert html =~ "37.7749"
    assert html =~ "-122.4194"
    assert html =~ "8000"
  end
end

