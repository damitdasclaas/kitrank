defmodule KitrankWeb.Router do
  use KitrankWeb, :router

  import KitrankWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {KitrankWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
    plug KitrankWeb.Locale
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", KitrankWeb do
    pipe_through :browser

    # Drei Routen, ein LiveView: Raster, Team-Detail als Modal darueber und der
    # Direktvergleich. Team und Vergleich sind eigene URLs, damit beides
    # verlinkbar bleibt und der Zurueck-Button tut, was man erwartet.
    get "/sprache/:locale", LocaleController, :update

    live_session :public,
      on_mount: [{KitrankWeb.UserAuth, :mount_current_scope}, KitrankWeb.Locale] do
      live "/", OverviewLive, :index
      live "/teams/:id", OverviewLive, :team
      live "/vergleich", OverviewLive, :compare

      # Ranglisten. Kein Login – der Zugriff haengt am Link: /rankings/:token
      # darf aendern, /r/:slug darf lesen. Beide zeigen denselben Datensatz,
      # der Teilen-Link ist deshalb immer aktuell.
      live "/rankings/new", Ranking.NewLive, :new
      live "/rankings/:edit_token/auswahl", Ranking.EditLive, :select
      live "/rankings/:edit_token/duell", Ranking.EditLive, :duel
      live "/rankings/:edit_token/edit", Ranking.EditLive, :sort
      live "/r/:share_slug", Ranking.ShowLive, :show

      # Reveal. Geteilt wird der Raumcode; die Steuerung haengt an einem
      # eigenen Token, das nur im Browser des Hosts liegt.
      live "/reveal/new", Reveal.NewLive, :new
      live "/reveal/:room_code", Reveal.RoomLive, :show
    end
  end

  ## Admin – Datenpflege

  scope "/admin", KitrankWeb.Admin, as: :admin do
    pipe_through [:browser, :require_authenticated_user]

    live_session :admin,
      on_mount: [
        {KitrankWeb.UserAuth, :require_authenticated},
        {KitrankWeb.UserAuth, :require_admin},
        KitrankWeb.Locale
      ] do
      live "/", DashboardLive, :index

      live "/sportarten", SportLive, :index
      live "/sportarten/neu", SportLive, :new
      live "/sportarten/:id", SportLive, :edit

      live "/ligen", CompetitionLive, :index
      live "/ligen/neu", CompetitionLive, :new
      live "/ligen/:id", CompetitionLive, :edit

      live "/vereine", TeamLive, :index
      live "/vereine/neu", TeamLive, :new
      live "/vereine/:id", TeamLive, :edit

      live "/saison", TeamSeasonLive, :index
      live "/saison/neu", TeamSeasonLive, :new
      live "/saison/:id", TeamSeasonLive, :edit

      live "/trikots", KitLive, :index
      live "/trikots/neu", KitLive, :new
      live "/trikots/:id", KitLive, :edit
    end
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
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", KitrankWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{KitrankWeb.UserAuth, :require_authenticated}, KitrankWeb.Locale] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", KitrankWeb do
    pipe_through [:browser]

    # Die Registrierung ist vollstaendig gebaut, aber zu – siehe
    # Kitrank.Accounts.registration_open?/0. Aufmachen ist ein Schalter.
    live_session :registration,
      on_mount: [{KitrankWeb.UserAuth, :require_open_registration}, KitrankWeb.Locale] do
      live "/users/register", UserLive.Registration, :new
    end

    live_session :current_user,
      on_mount: [{KitrankWeb.UserAuth, :mount_current_scope}, KitrankWeb.Locale] do
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
