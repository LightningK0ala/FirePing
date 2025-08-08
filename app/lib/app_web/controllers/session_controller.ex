defmodule AppWeb.SessionController do
  use AppWeb, :controller

  def login(conn, %{"user_id" => user_id}) do
    conn
    |> put_session(:user_id, user_id)
    # Quiet login: no flash needed
    |> redirect(to: ~p"/dashboard")
  end

  def logout(conn, _params) do
    conn
    |> delete_session(:user_id)
    |> put_flash(:info, "Logged out successfully")
    |> redirect(to: ~p"/login")
  end
end