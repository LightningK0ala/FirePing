defmodule AppWeb.Live.Auth do
  @moduledoc """
  Authentication hooks for LiveView sessions
  """
  import Phoenix.LiveView
  import Phoenix.Component
  alias App.User

  def on_mount(:default, _params, _session, socket) do
    {:cont, socket}
  end

  def on_mount(:require_authenticated_user, _params, %{"user_id" => user_id} = _session, socket) do
    case App.Repo.get(User, user_id) do
      %User{} = user -> 
        {:cont, assign(socket, :current_user, user)}
      nil -> 
        # Clear invalid session and redirect
        socket = put_flash(socket, :error, "Session expired. Please log in again.")
        {:halt, redirect(socket, to: "/session/logout")}
    end
  end

  def on_mount(:require_authenticated_user, _params, _session, socket) do
    {:halt, redirect(socket, to: "/login")}
  end

  def on_mount(:redirect_if_user_is_authenticated, _params, %{"user_id" => user_id} = _session, socket) do
    if user_id do
      {:halt, redirect(socket, to: "/dashboard")}
    else
      {:cont, socket}
    end
  end

  def on_mount(:redirect_if_user_is_authenticated, _params, _session, socket) do
    {:cont, socket}
  end

  def on_mount(:require_admin, _params, %{"user_id" => user_id} = _session, socket) do
    case App.Repo.get(User, user_id) do
      %User{admin: true} = user -> 
        {:cont, assign(socket, :current_user, user)}
      %User{admin: false} -> 
        socket = put_flash(socket, :error, "Access denied. Admin privileges required.")
        {:halt, redirect(socket, to: "/dashboard")}
      nil -> 
        socket = put_flash(socket, :error, "Session expired. Please log in again.")
        {:halt, redirect(socket, to: "/session/logout")}
    end
  end

  def on_mount(:require_admin, _params, _session, socket) do
    {:halt, redirect(socket, to: "/login")}
  end
end