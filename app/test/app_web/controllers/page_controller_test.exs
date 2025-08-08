defmodule AppWeb.PageControllerTest do
  use AppWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Fire alerts for your locations"
    assert html_response(conn, 200) =~ "Get started"
    assert html_response(conn, 200) =~ "Log in"
  end
end
