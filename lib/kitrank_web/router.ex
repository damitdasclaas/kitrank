defmodule KitrankWeb.Router do
  use KitrankWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {KitrankWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", KitrankWeb do
    pipe_through :browser

    # Drei Routen, ein LiveView: Raster, Team-Detail als Modal darueber und der
    # Direktvergleich. Team und Vergleich sind eigene URLs, damit beides
    # verlinkbar bleibt und der Zurueck-Button tut, was man erwartet.
    live "/", OverviewLive, :index
    live "/teams/:id", OverviewLive, :team
    live "/vergleich", OverviewLive, :compare
  end

  # Other scopes may use custom stacks.
  # scope "/api", KitrankWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:kitrank, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: KitrankWeb.Telemetry
    end
  end
end
