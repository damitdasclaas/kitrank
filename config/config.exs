# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :kitrank, :scopes,
  user: [
    default: true,
    module: Kitrank.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Kitrank.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :kitrank,
  ecto_repos: [Kitrank.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :kitrank, KitrankWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: KitrankWeb.ErrorHTML, json: KitrankWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Kitrank.PubSub,
  live_view: [signing_salt: "6ybyvPTD"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  kitrank: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  kitrank: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Mails des Logins (Magic Link, Bestaetigung, Adresswechsel). Lokal landen sie
# im Postfach unter /dev/mailbox, in Produktion setzt runtime.exs einen echten
# Adapter.
config :kitrank, Kitrank.Mailer, adapter: Swoosh.Adapters.Local
config :swoosh, api_client: Swoosh.ApiClient.Req

# Neue Nutzerkonten sind standardmaessig zu. Der Login funktioniert, aber
# registrieren kann sich niemand – aufgemacht wird ueber die Umgebungsvariable
# REGISTRATION_OPEN (siehe config/runtime.exs).
config :kitrank, :registration_open, false

# Deutsch ist die Quellsprache: die msgid im Code *ist* der deutsche Text.
# Das haelt die Templates lesbar und vermeidet eine zweite Uebersetzungsebene.
config :kitrank, KitrankWeb.Gettext, default_locale: "de", locales: ~w(de en)

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
