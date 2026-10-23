# Database

`Narabe.Ecto` keeps the order in your database: a move applied in one
transaction, positions for new rows, a scope's keys spread out again,
and the order to read it in. It works the same on Postgres, MySQL and
SQLite.

## Position keys

Each row keeps a position key among the rows of its scope: its list, its
board's column, or its parent in a tree. A key is a short text that sorts
between its neighbours (`Narabe.Position`, fractional indexing in base
62):

```elixir
Narabe.Position.between(nil, nil)    #=> "a0"
Narabe.Position.between("a0", nil)   #=> "a1"
Narabe.Position.between("a0", "a1")  #=> "a0V"
```

A move writes the moved rows only: their key, and their column or parent
when that changes. No other row is renumbered, so a move costs about the
same in a list of ten or of a million, and two people moving at once do
not write each other's rows. The browser has the same keys
(`between` and `betweenMany` in the `narabe` package).

## The column

Keys compare byte by byte. `Narabe.Migration.position/2` adds a `:string`
column with the collation that does: `COLLATE "C"` on Postgres,
`utf8mb4_bin` on MySQL; SQLite compares bytes already.

```elixir
create table(:cards) do
  add :title, :string
  add :column_id, references(:columns)
  position()
end

create index(:cards, [:column_id, :position])
```

Index the position after the scope. For a position column added before
Narabe, `Narabe.Migration.alter_position/2` changes its collation in an
`alter table`.

## The options

Declare them once on the schema with `use Narabe.Ordered`; an option
given to a call wins over the schema's.

| Option | |
| --- | --- |
| `:group` | the field of the scope that a move may change: a board's `:column_id`, a tree's `:parent_id`; without it, the queryable is one list |
| `:tree` | `true` when `:group` is a parent in the same table |
| `:position` | the position field (`:position`) |
| `:rules` | `Narabe.Rules`, or its options |
| `:kind` | the field of an item's kind, for the rules |
| `:group_kind` | the kind of a board's columns, for the rules (`"column"`) |
| `:lock` | lock the moved rows as they are read (`FOR UPDATE`); the default on Postgres and MySQL |
| `:rebalance_at` | the key length past which a scope's keys are written anew (32) |

`:serialize` is given to each call (see below).

## A move

```elixir
{:ok, cards} = Narabe.Ecto.move(Repo, where(Card, board_id: ^board.id), move)
```

`Narabe.Ecto.move/4` gives `{:ok, items}`, the moved rows as they are
now, in their new order, or `{:error, reason}` with nothing changed. The
queryable is the whole of what may be moved: an item, or a new parent,
outside it is `:not_found`. The rules give `:into_itself`,
`:not_accepted` and `:too_deep`.

The items land right after `move.after`, among the rows of the new scope
as they are now; else right before `move.before`; else at `move.index`;
else at the end.

`Narabe.Ecto.move_multi/5` is the same move as a step of an
`Ecto.Multi`, for a transaction that does more:

```elixir
Ecto.Multi.new()
|> Narabe.Ecto.move_multi(:move, Card, move)
|> Ecto.Multi.insert(:log, fn %{move: cards} -> Activity.moved(user, cards) end)
|> Repo.transaction()
```

`Narabe.Live.reply/1` reads its result too.

## New rows

`Narabe.Ecto.insert_position/4` gives a key at `:last` (the default),
`:first`, `{:after, id}` or `{:before, id}`, in the queryable, or with
`in: value` among its rows whose `:group` is that value.
`Narabe.Ecto.put_position/4` puts one in a changeset that has none, in
the scope of the changeset's `:group` value:

```elixir
%Card{}
|> Card.changeset(attrs)
|> Narabe.Ecto.put_position(Repo)
|> Repo.insert()
```

## Reading in order

`Narabe.Ecto.ordered/2` orders a queryable by key, then by id:

```elixir
Card |> where(column_id: ^id) |> Narabe.Ecto.ordered() |> Repo.all()
```

Two rows can get the same key: two drops into the same gap at the same
moment, or two rows inserted at once at the same place. Ordered by id
after the key, they show in the same order on every screen.

## Serialize

`serialize:` takes a queryable of the row that owns the list (the board,
the playlist's user). The move locks it (`FOR UPDATE`) before it reads
anything, so that moves in one list run one after the other and two
drops into the same gap get different keys:

```elixir
Narabe.Ecto.move(Repo, where(Card, board_id: ^board.id), move,
  serialize: where(Board, id: ^board.id)
)
```

SQLite locks the whole database as it writes, and has no row locks.

## Rebalance

Keys grow only when items keep landing in the same gap. When a key in
the scope grows past `:rebalance_at`, the move writes every key of that
scope anew, evenly, in the same transaction. `Narabe.Ecto.rebalance/3`
does it on demand, and gives how many rows it wrote:

```elixir
Narabe.Ecto.rebalance(Repo, where(Card, column_id: ^id))
```

A table that had no positions needs nothing: rows without a key get keys
in their current order (by key, then id) as a move first touches their
scope. Or rebalance each scope once.

## Trees

Narabe reads a tree's ancestors and descendants with one recursive query
each (`WITH RECURSIVE`, on all three databases), however deep. A move
checks the new parent's ancestors, and, only when the rules have a
`:max_depth`, the levels under the moved items.
`Narabe.Ecto.ancestors/4` and `Narabe.Ecto.descendants/4` give the ids.

MySQL stops a recursive query at 1,000 levels
(`cte_max_recursion_depth`).

## MySQL

Give the repo `socket_options: [nodelay: true]`. Without it, delayed
ACKs add about 40 ms to each statement, and a move has several:

```elixir
config :my_app, MyApp.Repo,
  socket_options: [nodelay: true]
```

## How long it takes

Measured locally, with `MIX_ENV=test mix run bench/ecto.exs` in Narabe's
repository:

| | Postgres | MySQL | SQLite |
| --- | --- | --- | --- |
| Move in a list of 100,000 | 1.3 ms | 4.0 ms | 0.9 ms |
| Move 20 at once | 5.6 ms | 9.3 ms | 6.0 ms |
| Move in a tree 900 levels deep | 62 ms | 13 ms | 5 ms |
| Rebalance 10,000 rows | 1 s | 3 s | 0.55 s |
