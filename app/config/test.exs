import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :app, App.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "127.0.0.1",
  database: "app_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  types: App.PostgresTypes

# Override database config with DATABASE_URL if present (for Docker)
if database_url = System.get_env("DATABASE_URL") do
  config :app, App.Repo, url: database_url
end

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :app, AppWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "hi7fOBxCAa1svxbkldlgPkIzkZMYMRuuOg+2o24ouKhMoc4cdtVEf4QlSS4XWnDj",
  server: false

# Configure Oban for testing
config :app, Oban,
  testing: :manual,
  queues: false,
  plugins: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Disable real email sending in tests
config :app,
  send_emails: false
