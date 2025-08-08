defmodule AppWeb.Router do
  use AppWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", AppWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/session/login/:user_id", SessionController, :login
    get "/session/logout", SessionController, :logout

    live_session :unauthenticated,
      on_mount: [{AppWeb.Live.Auth, :redirect_if_user_is_authenticated}] do
      live "/login", AuthLive.Login
      live "/verify/:email", AuthLive.Verify
    end

    live_session :authenticated,
      on_mount: [{AppWeb.Live.Auth, :require_authenticated_user}] do
      live "/dashboard", AuthLive.Dashboard
    end

    import Phoenix.LiveDashboard.Router
    import Oban.Web.Router
    
    live_dashboard "/admin/dashboard", 
      metrics: AppWeb.Telemetry,
      on_mount: [{AppWeb.Live.Auth, :require_admin}]
    
    oban_dashboard "/admin/oban",
      on_mount: [{AppWeb.Live.Auth, :require_admin}],
      resolver: AppWeb.ObanResolver
  end

  # Other scopes may use custom stacks.
  # scope "/api", AppWeb do
  #   pipe_through :api
  # end
end
