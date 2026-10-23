defmodule Narabe.Ecto do
  @moduledoc """
  Order in your database: a move applied in one transaction, positions for
  new rows, a list's keys spread out again, and the order to read it in.
  The same on Postgres, MySQL and SQLite.

  Each row keeps a position key (`Narabe.Position`, a column made with
  `Narabe.Migration.position/2`) among the rows of its scope: its list, its
  board's column, or its parent in a tree. A move writes the moved rows
  only: their key, and their column or parent when that changes. No other
  row is renumbered, so a move costs the same in a list of ten or of a
  million, and two people moving at once do not touch each other's rows.

  Declare the order once, on the schema (`Narabe.Ordered`):

      schema "cards" do
        field :title, :string
        field :position, :string
        belongs_to :column, Column
        belongs_to :board, Board
      end

      use Narabe.Ordered, group: :column_id

  then apply a move from the browser:

      def handle_event("moved", params, socket) do
        board = socket.assigns.board

        result =
          Narabe.Ecto.move(Repo, where(Card, board_id: ^board.id), Narabe.Move.parse!(params, Card),
            serialize: where(Board, id: ^board.id)
          )

        {:reply, Narabe.Live.reply(result), reload_cards(socket)}
      end

  The queryable is the whole of what may be moved (one board's cards):
  a move of anything outside it, or into a parent outside it, is refused
  as `:not_found`.

  ## Options

  Each option may be given to the call, or once in `use Narabe.Ordered`,
  but `:serialize`, which names the row of one call.

    * `:group` - the field of the scope that a move may change: a board's
      `:column_id`, a tree's `:parent_id`. Without it, the queryable is one
      list.
    * `:tree` - `true` when `:group` refers to the same table (a parent):
      a move into the item itself or its descendants is refused, and the
      rules' `:max_depth` counts the levels.
    * `:position` - the position field (`:position`).
    * `:rules` - `Narabe.Rules`, or its options; a tree's default nests.
    * `:kind` - the field of an item's kind, for the rules' `:accepts` and
      `:leaves`; `:group_kind`, the kind of a board's columns (`"column"`).
    * `:serialize` - a queryable of the row that owns the list (the board,
      the playlist's user), locked (`FOR UPDATE`) before the move reads
      anything: moves in one list then run one after the other, and two
      drops into the same gap at the same moment get different keys.
      Without it, they may get the same key, which `ordered/2` orders by id.
    * `:lock` - lock the moved rows as they are read (`FOR UPDATE`); the
      default on Postgres and MySQL. SQLite locks the database as it
      writes, and has no row locks.
    * `:rebalance_at` - when a key in the scope grows past this length,
      the scope's keys are written anew, evenly (32).

  ## Where it lands

  Right after `move.after`, among the rows of the new scope as they are
  now; else right before `move.before`; else at `move.index`; else at the
  end. Rows without a key yet (a table that had no positions) are given
  keys in their current order (by key, then id) as a move first touches
  their scope.

  ## Trees

  A tree is rows with a parent (`group: :parent_id, tree: true`). Moving
  an item moves its subtree with it (its children keep their parent).
  Narabe reads a tree's ancestors and descendants with one recursive query
  each (`WITH RECURSIVE`, on all three databases), however deep: a move
  checks the new parent's ancestors (never into itself), and, only when the
  rules have a `:max_depth`, the levels under the moved items. MySQL stops
  a recursive query at 1,000 levels (`cte_max_recursion_depth`).

  ## Errors

    * `:not_found` - an item, or the new parent, is not in the queryable.
    * `:into_itself`, `:not_accepted`, `:too_deep` - the rules (`Narabe.Rules`).
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Narabe.{Move, Position, Rules}

  @rebalance_at 32
  @options [
    :group,
    :tree,
    :position,
    :rules,
    :kind,
    :group_kind,
    :serialize,
    :lock,
    :rebalance_at
  ]

  @type reason :: :not_found | Rules.reason()

  @doc """
  Applies a move in a transaction: `{:ok, items}`, the moved rows as they
  are now, in their new order; or `{:error, reason}`, with nothing changed.
  See the moduledoc for the options.
  """
  @spec move(Ecto.Repo.t(), Ecto.Queryable.t(), Move.t(), keyword()) ::
          {:ok, [struct()]} | {:error, reason()}
  def move(repo, queryable, %Move{} = move, opts \\ []) do
    Multi.new()
    |> move_multi(:narabe_move, queryable, move, opts)
    |> repo.transaction()
    |> case do
      {:ok, %{narabe_move: items}} -> {:ok, items}
      {:error, :narabe_move, reason, _changes} -> {:error, reason}
    end
  end

  @doc """
  A move as a step of an `Ecto.Multi`, named `name`, for a transaction that
  does more (an activity log, a counter); its result is the moved rows.

      Ecto.Multi.new()
      |> Narabe.Ecto.move_multi(:move, Card, move, group: :column_id)
      |> Ecto.Multi.insert(:log, fn %{move: cards} -> Activity.moved(user, cards) end)
      |> Repo.transaction()

  `move` may also be a function of the changes so far, which gives the move.
  """
  @spec move_multi(
          Multi.t(),
          Multi.name(),
          Ecto.Queryable.t(),
          Move.t() | (map() -> Move.t()),
          keyword()
        ) ::
          Multi.t()
  def move_multi(multi, name, queryable, move, opts \\ []) do
    Multi.run(multi, name, fn repo, changes ->
      move = if is_function(move, 1), do: move.(changes), else: move
      run_move(context(repo, queryable, opts), move)
    end)
  end

  @doc """
  A key for a new row: `:last` (the default), `:first`, `{:after, id}` or
  `{:before, id}`, in a scope. The scope is the queryable itself (already
  scoped to one list), or, with `in: value`, its rows whose `:group` is
  that value:

      position = Narabe.Ecto.insert_position(Repo, Card, :last, in: column.id)
      Repo.insert!(%Card{title: "Write the guide", column_id: column.id, position: position})

  Two rows inserted at once at the same place may get the same key, which
  `ordered/2` orders by id.
  """
  @spec insert_position(Ecto.Repo.t(), Ecto.Queryable.t(), atom() | {atom(), term()}, keyword()) ::
          Position.t()
  def insert_position(repo, queryable, at \\ :last, opts \\ []) do
    ctx = context(repo, queryable, opts)
    scope = if Keyword.has_key?(opts, :in), do: scope(ctx, opts[:in]), else: from(q in queryable)

    {a, b} =
      case at do
        :last -> {max_key(ctx, scope), nil}
        :first -> {nil, min_key(ctx, scope)}
        {:after, id} -> after_gap(ctx, scope, existing_key!(ctx, scope, id))
        {:before, id} -> before_gap(ctx, scope, existing_key!(ctx, scope, id))
      end

    Position.between(a, b)
  end

  @doc """
  Puts a position in a changeset for a new row, unless it has one: at
  `:last` (or `:first`, …) of the scope of the changeset's `:group` value.

      %Card{}
      |> Card.changeset(attrs)
      |> Narabe.Ecto.put_position(Repo)
      |> Repo.insert()
  """
  @spec put_position(Ecto.Changeset.t(), Ecto.Repo.t(), atom() | {atom(), term()}, keyword()) ::
          Ecto.Changeset.t()
  def put_position(%Ecto.Changeset{} = changeset, repo, at \\ :last, opts \\ []) do
    schema = changeset.data.__struct__
    ctx = context(repo, schema, opts)

    if Ecto.Changeset.get_field(changeset, ctx.position) do
      changeset
    else
      opts =
        if ctx.group,
          do: Keyword.put(opts, :in, Ecto.Changeset.get_field(changeset, ctx.group)),
          else: opts

      Ecto.Changeset.put_change(changeset, ctx.position, insert_position(repo, schema, at, opts))
    end
  end

  @doc """
  Writes the keys of a scope anew, evenly, in its current order (by key,
  then id; rows without a key last): for a list whose keys grew long, or a
  table that had no positions. Returns how many rows it wrote.

      Narabe.Ecto.rebalance(Repo, where(Card, column_id: ^id))
  """
  @spec rebalance(Ecto.Repo.t(), Ecto.Queryable.t(), keyword()) :: non_neg_integer()
  def rebalance(repo, queryable, opts \\ []) do
    ctx = context(repo, queryable, opts)
    {:ok, count} = repo.transaction(fn -> rewrite(ctx, from(q in queryable)) end)
    count
  end

  @doc """
  A queryable in its order: by key, then by id.

      Card |> where(column_id: ^id) |> Narabe.Ecto.ordered() |> Repo.all()
  """
  @spec ordered(Ecto.Queryable.t(), keyword()) :: Ecto.Query.t()
  def ordered(queryable, opts \\ []) do
    position = option(queryable, opts, :position) || :position
    [pk] = primary_key(queryable)
    from(q in queryable, order_by: [asc: field(q, ^position), asc: field(q, ^pk)])
  end

  @doc """
  The ids of an item's ancestors in a tree, its parent first; the item
  itself is not among them. One recursive query.
  """
  @spec ancestors(Ecto.Repo.t(), Ecto.Queryable.t(), term(), keyword()) :: [term()]
  def ancestors(repo, queryable, id, opts \\ []) do
    ctx = context(repo, queryable, opts)
    parents = ctx |> tree_rows([id], :up) |> Map.new()
    chain(parents, Map.get(parents, id), [])
  end

  @doc """
  The ids of an item's descendants in a tree (not the item), in no order.
  One recursive query.
  """
  @spec descendants(Ecto.Repo.t(), Ecto.Queryable.t(), term(), keyword()) :: [term()]
  def descendants(repo, queryable, id, opts \\ []) do
    ctx = context(repo, queryable, opts)
    for {child, _parent} <- tree_rows(ctx, [id], :down), child != id, do: child
  end

  # -- The context of a call ------------------------------------------------

  defp context(repo, queryable, opts) do
    [pk] = primary_key(queryable)
    opts = Keyword.merge(schema_options(queryable), Keyword.take(opts, @options))
    tree = Keyword.get(opts, :tree, false)
    group = Keyword.get(opts, :group)

    if tree and group == nil,
      do: raise(ArgumentError, "Narabe: a tree needs its parent field as :group")

    %{
      repo: repo,
      queryable: queryable,
      # Updates go by id to the table: the ids are checked against the
      # queryable already, which may have a limit or an order.
      schema: schema(queryable),
      pk: pk,
      pk_type: schema(queryable).__schema__(:type, pk),
      position: Keyword.get(opts, :position, :position),
      group: group,
      tree: tree,
      kind: Keyword.get(opts, :kind),
      # A board's columns are "column" in the browser too.
      group_kind: Keyword.get(opts, :group_kind, if(group && !tree, do: "column")),
      rules: rules(Keyword.get(opts, :rules), tree),
      serialize: Keyword.get(opts, :serialize),
      lock: Keyword.get_lazy(opts, :lock, fn -> locks?(repo) end),
      rebalance_at: Keyword.get(opts, :rebalance_at, @rebalance_at)
    }
  end

  defp schema(queryable) do
    case Ecto.Queryable.to_query(queryable).from.source do
      {_table, schema} when schema != nil -> schema
      _other -> raise ArgumentError, "Narabe: the queryable needs a schema"
    end
  end

  defp primary_key(queryable), do: schema(queryable).__schema__(:primary_key)

  defp schema_options(queryable) do
    schema = schema(queryable)
    if function_exported?(schema, :__narabe__, 0), do: schema.__narabe__(), else: []
  end

  defp option(queryable, opts, key), do: Keyword.get(opts, key, schema_options(queryable)[key])

  defp locks?(repo) do
    repo.__adapter__() |> Module.split() |> List.last() |> Kernel.in(["Postgres", "MyXQL"])
  end

  # -- A move -----------------------------------------------------------------

  defp run_move(ctx, move) do
    serialize(ctx)

    with {:ok, items} <- load_items(ctx, move.ids),
         {:ok, target} <- target(ctx, move, items),
         :ok <- Rules.check(ctx.rules, rule_move(ctx, items, target)) do
      {:ok, place(ctx, items, target.group, move)}
    end
  end

  defp serialize(%{serialize: nil}), do: :ok

  defp serialize(%{serialize: owner} = ctx) do
    query = from(o in owner, select: 1)
    query = if ctx.lock, do: lock(query, "FOR UPDATE"), else: query
    ctx.repo.all(query)
    :ok
  end

  defp load_items(ctx, ids) do
    query = from(q in ctx.queryable, where: field(q, ^ctx.pk) in ^ids)
    query = if ctx.lock, do: lock(query, "FOR UPDATE"), else: query
    by_id = query |> ctx.repo.all() |> Map.new(&{Map.fetch!(&1, ctx.pk), &1})

    if map_size(by_id) == length(ids),
      do: {:ok, Enum.map(ids, &Map.fetch!(by_id, &1))},
      else: {:error, :not_found}
  end

  defp target(%{tree: true}, %Move{parent: nil}, _items),
    do: {:ok, %{group: nil, depth: 0, kind: nil, into_itself: false}}

  defp target(%{tree: true} = ctx, %Move{parent: parent_id} = move, _items) do
    case ctx.repo.one(from(q in ctx.queryable, where: field(q, ^ctx.pk) == ^parent_id)) do
      nil ->
        {:error, :not_found}

      parent ->
        # The new parent and its ancestors, in one query.
        parents = ctx |> tree_rows([parent_id], :up) |> Map.new()
        line = [parent_id | chain(parents, Map.get(parents, parent_id), [])]

        {:ok,
         %{
           group: parent_id,
           depth: length(line),
           kind: kind_of(ctx, parent),
           into_itself: Enum.any?(line, &(&1 in move.ids))
         }}
    end
  end

  defp target(ctx, move, _items),
    do:
      {:ok,
       %{
         group: if(ctx.group, do: move.parent),
         depth: 0,
         kind: ctx.group_kind,
         into_itself: false
       }}

  defp rule_move(ctx, items, target) do
    ids = Enum.map(items, &Map.fetch!(&1, ctx.pk))

    %{
      kinds: Enum.map(items, &kind_of(ctx, &1)),
      parent_kind: target.kind,
      parent_depth: target.depth,
      # Only a depth limit needs the levels under the items.
      height: if(ctx.tree and ctx.rules.max_depth, do: height(ctx, ids), else: 1),
      into_itself: target.into_itself
    }
  end

  defp kind_of(%{kind: nil}, _item), do: "item"
  defp kind_of(%{kind: field}, item), do: to_string(Map.fetch!(item, field) || "item")

  # -- A tree, one recursive query at a time --------------------------------

  # The {id, parent} of the rows from `ids` up to the top (:up), or down to
  # the leaves (:down), the rows themselves included. UNION (not UNION ALL)
  # drops a row seen before, so a cycle in the data ends the query.
  defp tree_rows(ctx, ids, direction) do
    initial =
      from(q in ctx.queryable,
        where: field(q, ^ctx.pk) in ^ids,
        select: %{id: field(q, ^ctx.pk), parent: field(q, ^ctx.group)}
      )

    step =
      case direction do
        :up ->
          from(q in ctx.queryable,
            join: t in "narabe_tree",
            on: field(q, ^ctx.pk) == t.parent,
            select: %{id: field(q, ^ctx.pk), parent: field(q, ^ctx.group)}
          )

        :down ->
          from(q in ctx.queryable,
            join: t in "narabe_tree",
            on: field(q, ^ctx.group) == t.id,
            select: %{id: field(q, ^ctx.pk), parent: field(q, ^ctx.group)}
          )
      end

    from(t in "narabe_tree", select: %{id: t.id, parent: t.parent})
    |> recursive_ctes(true)
    |> with_cte("narabe_tree", as: ^union(initial, ^step))
    |> ctx.repo.all()
    |> Enum.map(fn %{id: id, parent: parent} -> {load_id(ctx, id), load_id(ctx, parent)} end)
  end

  # A CTE's columns come back as the database gives them: an id as the
  # schema loads it.
  defp load_id(_ctx, nil), do: nil

  defp load_id(ctx, value) do
    case Ecto.Type.load(ctx.pk_type, value) do
      {:ok, id} -> id
      :error -> value
    end
  end

  defp chain(_parents, nil, acc), do: Enum.reverse(acc)

  defp chain(parents, id, acc) do
    if id in acc, do: Enum.reverse(acc), else: chain(parents, Map.get(parents, id), [id | acc])
  end

  # The levels of the moved items' subtrees: 1 for items with no children.
  defp height(ctx, ids) do
    children = ctx |> tree_rows(ids, :down) |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
    levels(children, ids, 0, %{})
  end

  defp levels(_children, [], n, _seen), do: n

  # `seen` is a map of ids (not a MapSet: an opaque type through recursion).
  defp levels(children, ids, n, seen) do
    seen = Enum.reduce(ids, seen, &Map.put(&2, &1, true))

    next =
      ids |> Enum.flat_map(&Map.get(children, &1, [])) |> Enum.reject(&Map.has_key?(seen, &1))

    levels(children, next, n + 1, seen)
  end

  # -- Placing the items ----------------------------------------------------

  defp place(ctx, items, group, move) do
    ids = Enum.map(items, &Map.fetch!(&1, ctx.pk))
    scope = scope(ctx, group)
    if missing_keys?(ctx, scope), do: rewrite(ctx, scope)
    others = from(q in scope, where: field(q, ^ctx.pk) not in ^ids)
    {a, b} = gap(ctx, others, move)
    keys = Position.between_many(a, b, length(ids))

    for {id, key} <- Enum.zip(ids, keys) do
      changes =
        if ctx.group, do: [{ctx.position, key}, {ctx.group, group}], else: [{ctx.position, key}]

      ctx.repo.update_all(from(q in ctx.schema, where: field(q, ^ctx.pk) == ^id), set: changes)
    end

    if Enum.any?(keys, &(byte_size(&1) > ctx.rebalance_at)), do: rewrite(ctx, scope)

    ctx.repo.all(
      ordered(from(q in ctx.queryable, where: field(q, ^ctx.pk) in ^ids), position: ctx.position)
    )
  end

  defp scope(%{group: nil} = ctx, _group), do: from(q in ctx.queryable)
  defp scope(ctx, nil), do: from(q in ctx.queryable, where: is_nil(field(q, ^ctx.group)))
  defp scope(ctx, group), do: from(q in ctx.queryable, where: field(q, ^ctx.group) == ^group)

  defp missing_keys?(ctx, scope),
    do: ctx.repo.exists?(from(q in scope, where: is_nil(field(q, ^ctx.position))))

  # The keys around the place a move names (see the moduledoc).
  defp gap(ctx, others, move) do
    cond do
      key = move.after && key_of(ctx, others, move.after) -> after_gap(ctx, others, key)
      key = move.before && key_of(ctx, others, move.before) -> before_gap(ctx, others, key)
      move.index != nil -> index_gap(ctx, others, move.index)
      true -> {max_key(ctx, others), nil}
    end
  end

  defp key_of(ctx, scope, id) do
    ctx.repo.one(
      from(q in scope, where: field(q, ^ctx.pk) == ^id, select: field(q, ^ctx.position))
    )
  end

  defp existing_key!(ctx, scope, id) do
    key_of(ctx, scope, id) ||
      raise ArgumentError, "Narabe: #{inspect(id)} is not in the scope, or has no position"
  end

  # One key from the (scope, position) index: ORDER BY … LIMIT 1, which
  # every database reads as one step of the index, where MIN/MAX with the
  # moved rows left out may scan.
  defp after_gap(ctx, scope, key) do
    {key, edge(ctx, from(q in scope, where: field(q, ^ctx.position) > ^key), :asc)}
  end

  defp before_gap(ctx, scope, key) do
    {edge(ctx, from(q in scope, where: field(q, ^ctx.position) < ^key), :desc), key}
  end

  defp edge(ctx, query, direction) do
    ctx.repo.one(
      from(q in query,
        where: not is_nil(field(q, ^ctx.position)),
        order_by: [{^direction, field(q, ^ctx.position)}],
        select: field(q, ^ctx.position),
        limit: 1
      )
    )
  end

  defp index_gap(ctx, scope, index) do
    # The keys around the index: two rows from the database, not the list.
    keys =
      ctx.repo.all(
        from(q in scope,
          where: not is_nil(field(q, ^ctx.position)),
          order_by: [asc: field(q, ^ctx.position)],
          select: field(q, ^ctx.position),
          offset: ^max(index - 1, 0),
          limit: 2
        )
      )

    case {index, keys} do
      {0, [first | _]} -> {nil, first}
      {0, []} -> {nil, nil}
      {_, [a, b]} -> {a, if(a == b, do: nil, else: b)} |> fix_tie(ctx, scope)
      {_, [a]} -> {a, nil}
      {_, []} -> {max_key(ctx, scope), nil}
    end
  end

  defp fix_tie({a, nil}, ctx, scope), do: after_gap(ctx, scope, a)
  defp fix_tie(gap, _ctx, _scope), do: gap

  defp max_key(ctx, scope),
    do: ctx.repo.one(from(q in scope, select: max(field(q, ^ctx.position))))

  defp min_key(ctx, scope),
    do: ctx.repo.one(from(q in scope, select: min(field(q, ^ctx.position))))

  # Every row of a scope gets a key, evenly, in its current order.
  defp rewrite(ctx, scope) do
    ids =
      ctx.repo.all(
        from(q in scope,
          order_by: [
            asc: is_nil(field(q, ^ctx.position)),
            asc: field(q, ^ctx.position),
            asc: field(q, ^ctx.pk)
          ],
          select: field(q, ^ctx.pk)
        )
      )

    for {id, key} <- Enum.zip(ids, Position.between_many(nil, nil, length(ids))) do
      ctx.repo.update_all(from(q in ctx.schema, where: field(q, ^ctx.pk) == ^id),
        set: [{ctx.position, key}]
      )
    end

    length(ids)
  end

  # A tree nests unless its rules say otherwise.
  defp rules(nil, tree), do: Rules.new(nest: tree)
  defp rules(rules, tree) when is_list(rules), do: Rules.new(Keyword.put_new(rules, :nest, tree))
  defp rules(rules, _tree), do: Rules.new(rules)
end
