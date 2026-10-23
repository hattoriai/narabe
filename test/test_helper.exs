# Narabe.Ecto's databases: those of NARABE_DBS, created and migrated
# afresh for each run; the others' tests are left out.
File.mkdir_p!("tmp")
databases = NarabeTest.Databases.start()
skipped = for db <- ~w(postgres mysql sqlite), db not in databases, do: {:db, db}

{:ok, _pid} = Phoenix.PubSub.Supervisor.start_link(name: NarabeTest.PubSub)
{:ok, _pid} = NarabeTest.Endpoint.start_link()
# The Issho instance of the lists that show who is moving what
# (Narabe.Issho): everyone may do everything.
defmodule NarabeTest.Policy do
  @moduledoc false
  @behaviour Issho.Policy
  @impl true
  def authorize(_identity, _room, _action), do: :ok
end

{:ok, _pid} =
  Issho.start_link(
    name: NarabeTest.Issho,
    pubsub: NarabeTest.PubSub,
    policy: NarabeTest.Policy,
    secret_key_base: String.duplicate("narabe-test-secret-key-base-", 3),
    ttl: 50,
    awareness_interval: 5
  )

# The :build tests run `mix narabe.build` (npm and network on the first
# run) and `mix hex.build`: `mix test --include build`.
ExUnit.start(exclude: [:build | skipped])
