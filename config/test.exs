import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :kitrank, Kitrank.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "kitrank_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :kitrank, KitrankWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "TaXf8falY+MmDZ4brdPS7OTaIA1efk2IN2bqM/OECoLlp2fT1O6rVVtTaSUVU21A",
  server: false

# Im Test ist die Registrierung offen, damit der komplette Ablauf geprueft wird –
# er soll ja funktionieren, wenn der Schalter spaeter umgelegt wird. Dass sie in
# Produktion zu ist und das Umschalten wirkt, prueft
# KitrankWeb.RegistrationGateTest ausdruecklich fuer beide Zustaende.
config :kitrank, :registration_open, true

# Mails werden im Test nur gesammelt, nicht verschickt.
config :kitrank, Kitrank.Mailer, adapter: Swoosh.Adapters.Test
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
