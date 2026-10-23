import Config

if config_env() == :dev do
  # The picker bundles. NODE_PATH is unset: the bundles never pick up a
  # package from deps/.
  esbuild_args = ~w(
    --bundle
    --minify
    --target=es2020
    --external:phoenix
    --external:phoenix_live_view
  )

  profile = fn args ->
    [
      args: esbuild_args ++ args,
      cd: Path.expand("../assets", __DIR__),
      env: %{"NODE_PATH" => nil}
    ]
  end

  config :esbuild,
    version: "0.28.2",
    narabe_esm: profile.(~w(src/index.ts --format=esm --outfile=../priv/static/narabe.esm.js)),
    narabe_cjs: profile.(~w(src/index.ts --format=cjs --outfile=../priv/static/narabe.cjs.js))
end

if config_env() == :test do
  config :logger, level: :warning

  # Narabe.Ecto's tests run on Postgres, MySQL and SQLite (NARABE_DBS
  # says which: "postgres,mysql,sqlite" by default).
  config :narabe, NarabeTest.Repo,
    url: System.get_env("NARABE_POSTGRES_URL", "ecto://postgres:postgres@localhost/narabe_test"),
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 10

  config :narabe, NarabeTest.MyRepo,
    url: System.get_env("NARABE_MYSQL_URL", "ecto://narabe:narabe@127.0.0.1/narabe_test"),
    # Without TCP_NODELAY, a statement can wait ~40 ms on a delayed ACK.
    socket_options: [nodelay: true],
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 10

  config :narabe, NarabeTest.LiteRepo,
    database: Path.expand("../tmp/narabe_test.sqlite3", __DIR__),
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 5

  config :phoenix, :json_library, JSON

  config :narabe, NarabeTest.Endpoint,
    secret_key_base: String.duplicate("narabe-test-secret-key-base-", 4),
    live_view: [signing_salt: "narabe-test-salt"],
    pubsub_server: NarabeTest.PubSub,
    render_errors: [formats: [html: NarabeTest.ErrorHTML], layout: false],
    server: false
end
