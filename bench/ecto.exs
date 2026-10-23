# Narabe.Ecto's costs on each database: moves in a list of 100,000 rows,
# moves in a tree 900 levels deep, a rebalance of 10,000 rows.
#
#     MIX_ENV=test mix run bench/ecto.exs
#
# NARABE_DBS picks the databases, as in the tests.

import Ecto.Query
alias Narabe.Move
alias NarabeTest.{Card, Column, Page}

repos = %{"postgres" => NarabeTest.Repo, "mysql" => NarabeTest.MyRepo, "sqlite" => NarabeTest.LiteRepo}

time = fn label, runs, fun ->
  {micros, _} = :timer.tc(fn -> for _ <- 1..runs, do: fun.() end)
  IO.puts("  #{String.pad_trailing(label, 44)} #{:erlang.float_to_binary(micros / runs / 1000, decimals: 2)} ms")
end

for name <- NarabeTest.Databases.wanted() do
  repo = Map.fetch!(repos, name)
  config = repo.config() |> Keyword.put(:pool, DBConnection.ConnectionPool) |> Keyword.put(:pool_size, 2)
  adapter = repo.__adapter__()
  _ = adapter.storage_down(config)
  :ok = adapter.storage_up(config)
  {:ok, pid} = repo.start_link(Keyword.merge(config, name: nil))
  repo.put_dynamic_repo(pid)
  Ecto.Migrator.up(repo, 1, NarabeTest.Migration, log: false)
  IO.puts("#{name}:")

  column = repo.insert!(%Column{name: "Big", position: "a0"})
  other = repo.insert!(%Column{name: "Other", position: "a1"})
  keys = Narabe.Position.between_many(nil, nil, 100_000)

  keys
  |> Enum.with_index()
  |> Enum.chunk_every(5_000)
  |> Enum.each(fn chunk ->
    repo.insert_all(Card, Enum.map(chunk, fn {key, i} -> %{title: "card #{i}", column_id: column.id, position: key} end))
  end)

  ids = repo.all(from(c in Card, where: c.column_id == ^column.id, order_by: c.position, select: c.id)) |> List.to_tuple()
  pick = fn -> elem(ids, :rand.uniform(100_000) - 1) end

  time.("move after a card, 100,000 in the list", 200, fn ->
    a = pick.()
    b = pick.()
    if a != b, do: {:ok, _} = Narabe.Ecto.move(repo, Card, %Move{ids: [a], parent: column.id, after: b})
  end)

  time.("move to another column and back", 100, fn ->
    a = pick.()
    {:ok, _} = Narabe.Ecto.move(repo, Card, %Move{ids: [a], parent: other.id})
    {:ok, _} = Narabe.Ecto.move(repo, Card, %Move{ids: [a], parent: column.id, index: 50_000})
  end)

  time.("move 20 cards at once", 50, fn ->
    picked = Enum.uniq(for _ <- 1..20, do: pick.())
    target = pick.()
    picked = picked -- [target]
    {:ok, _} = Narabe.Ecto.move(repo, Card, %Move{ids: picked, parent: column.id, before: target})
  end)

  top = repo.insert!(%Page{title: "level 0", position: "a0"})

  bottom =
    Enum.reduce(1..899, top, fn level, parent ->
      repo.insert!(%Page{title: "level #{level}", parent_id: parent.id, position: "a0"})
    end)

  leaf = repo.insert!(%Page{title: "leaf", position: "a1"})

  time.("move a leaf under level 899 and back", 20, fn ->
    {:ok, _} = Narabe.Ecto.move(repo, Page, %Move{ids: [leaf.id], parent: bottom.id})
    {:ok, _} = Narabe.Ecto.move(repo, Page, %Move{ids: [leaf.id], parent: nil})
  end)

  time.("refuse the top into level 899 (its own)", 20, fn ->
    {:error, :into_itself} = Narabe.Ecto.move(repo, Page, %Move{ids: [top.id], parent: bottom.id})
  end)

  time.("a depth rule over 900 levels below", 10, fn ->
    {:error, :too_deep} =
      Narabe.Ecto.move(repo, Page, %Move{ids: [top.id], parent: nil}, rules: [nest: true, max_depth: 100])
  end)

  time.("rebalance 10,000 rows", 1, fn ->
    Narabe.Ecto.rebalance(repo, from(c in Card, where: c.column_id == ^column.id, limit: 10_000))
  end)

  Supervisor.stop(pid)
end
