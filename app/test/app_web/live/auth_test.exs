defmodule AppWeb.Live.AuthTest do
  use App.DataCase

  alias AppWeb.Live.Auth
  alias Phoenix.LiveView.Socket

  describe "on_mount :require_admin" do
    test "allows access for admin user" do
      admin_user =
        insert(:user, email: "admin@example.com", admin: true, verified_at: DateTime.utc_now())

      session = %{"user_id" => admin_user.id}
      socket = %Socket{assigns: %{__changed__: %{}, flash: %{}}}

      assert {:cont, _socket} = Auth.on_mount(:require_admin, %{}, session, socket)
    end

    test "denies access for non-admin user" do
      regular_user =
        insert(:user, email: "user@example.com", admin: false, verified_at: DateTime.utc_now())

      session = %{"user_id" => regular_user.id}
      socket = %Socket{assigns: %{__changed__: %{}, flash: %{}}}

      assert {:halt, _socket} = Auth.on_mount(:require_admin, %{}, session, socket)
    end

    test "redirects to login for unauthenticated user" do
      socket = %Socket{assigns: %{__changed__: %{}, flash: %{}}}

      assert {:halt, _socket} = Auth.on_mount(:require_admin, %{}, %{}, socket)
    end

    test "redirects for invalid session" do
      invalid_user_id = Ecto.UUID.generate()
      session = %{"user_id" => invalid_user_id}
      socket = %Socket{assigns: %{__changed__: %{}, flash: %{}}}

      assert {:halt, _socket} = Auth.on_mount(:require_admin, %{}, session, socket)
    end
  end
end
