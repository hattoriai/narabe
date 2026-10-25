defmodule Narabe.Ecto.Mixed do
  @moduledoc """
  A tree whose items are rows of several schemas: folders and the pages
  in them, sections and their lessons, categories and their products.
  Each schema keeps its own table, its own position, and its own parent
  field, and a folder's children, folders and pages alike, are one list
  in one order.

      tree =
        Narabe.Ecto.Mixed.new(
          [
            folder: [from: where(Folder, space_id: ^space.id), parent: :parent_id],
            page: [from: where(Page, space_id: ^space.id), parent: :folder_id]
          ],
          parents: :folder,
          rules: [accepts: %{"root" => ["folder", "page"], "folder" => ["folder", "page"]}]
        )

  Each kind's `:from` is the whole of what may be moved of it (one space's
  folders), and its `:parent` is the field that holds its parent's id. The
  parents are rows of one kind, `parents:`, whose parent field holds a row
  of the same kind: a folder in a folder. The other kinds hold nothing.

  An item's id in the tree is its kind and its primary key, `"folder:3"`
  or `"page:9"` (`id/2`), so that two tables' ids never meet. The items
  go to `Narabe.Components.tree/1` as `items/2` gives them, and the moves
  it sends come back to `move/3`:

      <.tree id="pages" items={@items} item_kind={:kind} item_label={&label/1}
        rules={@tree.rules} on_move="move" />

      def handle_event("move", params, socket) do
        tree = socket.assigns.tree
        result = Narabe.Ecto.Mixed.move(Repo, tree, Narabe.Move.parse!(params))
        {:reply, Narabe.Live.reply(result), assign(socket, items: Narabe.Ecto.Mixed.items(Repo, tree))}
      end

  A move works as `Narabe.Ecto.move/4` does (see its moduledoc): it
  writes the moved rows only, their key and their parent, in one
  transaction; it lands after `move.after`, else before `move.before`,
  else at `move.index`, else at the end, among the siblings of every
  kind; it never goes into an item itself or under it, and it keeps the
  rules (`:max_depth` counts the levels of every kind under the moved
  items). Siblings of different kinds with the same key (two inserted at
  once) are in the order of the kinds, then by id.

  ## Options of `new/2`

    * `:parents` - the kind whose rows hold others (required).
    * `:rules` - `Narabe.Rules`, or its options. An item's kind is its
      kind in the tree, `"folder"` or `"page"`; the kinds other than
      `:parents` are leaves, and a mixed tree nests.
    * `:position` - the position field of every kind (`:position`); a
      kind's own `:position` wins.
    * `:serialize`, `:lock`, `:rebalance_at` - as `Narabe.Ecto`'s.

  ## Errors

    * `:not_found` - an id that is not of the tree, an item or the new
      parent not in its kind's `:from`.
    * `:into_itself`, `:not_accepted`, `:too_deep` - the rules
      (`Narabe.Rules`).
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Narabe.{Move, Position, Rules}

  @rebalance_at 32

  @enforce_keys [:kinds, :order, :parents, :rules]
  defstruct [:kinds, :order, :parents, :rules, :serialize, :lock, rebalance_at: @rebalance_at]

  @typedoc "A kind of the tree: its queryable, schema, primary key and fields."
  @type kind :: %{
          name: String.t(),
          queryable: Ecto.Queryable.t(),
          schema: module(),
          pk: atom(),
          pk_type: term(),
          parent: atom(),
          position: atom()
        }

  @type t :: %__MODULE__{
          kinds: %{String.t() => kind()},
          order: [String.t()],
          parents: String.t(),
          rules: Rules.t(),
          serialize: Ecto.Queryable.t() | nil,
          lock: boolean() | nil,
          rebalance_at: pos_integer()
        }

  @typedoc "An item of `items/2`: its id in the tree, its parent's, its kind, and its row."
  @type item :: %{id: String.t(), parent_id: String.t() | nil, kind: String.t(), record: struct()}

  @doc "A tree of several schemas: see the moduledoc."
  @spec new(keyword() | [{atom() | String.t(), keyword()}], keyword()) :: t()
  def new(kinds, opts) do
    position = Keyword.get(opts, :position, :position)

    kinds =
      for {name, kind_opts} <- kinds do
        name = to_string(name)
        queryable = Keyword.fetch!(kind_opts, :from)
        schema = schema(queryable)

        [pk] =
          case schema.__schema__(:primary_key) do
            [pk] -> [pk]
            _other -> raise ArgumentError, "Narabe: #{inspect(schema)} needs one primary key"
          end

        %{
          name: name,
          queryable: queryable,
          schema: schema,
          pk: pk,
          pk_type: schema.__schema__(:type, pk),
          parent: Keyword.fetch!(kind_opts, :parent),
          position: Keyword.get(kind_opts, :position, position)
        }
      end

    parents = opts |> Keyword.fetch!(:parents) |> to_string()
    order = Enum.map(kinds, & &1.name)

    unless parents in order do
      raise ArgumentError, "Narabe: parents: #{inspect(parents)} is not a kind of the tree"
    end

    rules = Rules.new(Keyword.get(opts, :rules) || [])
    leaves = Enum.uniq(rules.leaves ++ (order -- [parents]))

    %__MODULE__{
      kinds: Map.new(kinds, &{&1.name, &1}),
      order: order,
      parents: parents,
      rules: %{rules | nest: true, leaves: leaves},
      serialize: Keyword.get(opts, :serialize),
      lock: Keyword.get(opts, :lock),
      rebalance_at: Keyword.get(opts, :rebalance_at, @rebalance_at)
    }
  end

  defp schema(queryable) do
    case Ecto.Queryable.to_query(queryable).from.source do
      {_table, schema} when schema != nil -> schema
      _other -> raise ArgumentError, "Narabe: the queryable needs a schema"
    end
  end

  @doc """
  An item's id in the tree, from its kind and its primary key, or from
  its row.

      iex> Narabe.Ecto.Mixed.id(:folder, 3)
      "folder:3"
  """
  @spec id(atom() | String.t(), term()) :: String.t()
  def id(kind, pk), do: "#{kind}:#{pk}"

  @doc "The id in the tree of a row of one of its kinds."
  @spec id_of(t(), struct()) :: String.t()
  def id_of(%__MODULE__{} = tree, %{__struct__: schema} = record) do
    kind = kind_of_schema!(tree, schema)
    id(kind.name, Map.fetch!(record, kind.pk))
  end

  @doc """
  An id of the tree read back: `{:ok, {kind, primary key}}`, the key cast
  to its schema's type, or `:error` for an id that is not of the tree.
  """
  @spec parse_id(t(), String.t()) :: {:ok, {String.t(), term()}} | :error
  def parse_id(%__MODULE__{} = tree, id) when is_binary(id) do
    with [name, value] <- String.split(id, ":", parts: 2),
         %{} = kind <- Map.get(tree.kinds, name),
         {:ok, pk} <- Ecto.Type.cast(kind.pk_type, value),
         false <- is_nil(pk) do
      {:ok, {name, pk}}
    else
      _ -> :error
    end
  end

  def parse_id(_tree, _id), do: :error

  @doc """
  Every item of the tree, flat, each siblings' list in its order, as
  `Narabe.Components.tree/1` takes them (`item_kind={:kind}`; the row is
  the item's `:record`).
  """
  @spec items(Ecto.Repo.t(), t()) :: [item()]
  def items(repo, %__MODULE__{} = tree) do
    for name <- tree.order,
        kind = tree.kinds[name],
        record <- repo.all(kind.queryable) do
      parent = Map.fetch!(record, kind.parent)

      %{
        id: id(name, Map.fetch!(record, kind.pk)),
        parent_id: parent && id(tree.parents, parent),
        kind: name,
        record: record,
        sort:
          {is_nil(Map.fetch!(record, kind.position)), Map.fetch!(record, kind.position),
           rank(tree, name), Map.fetch!(record, kind.pk)}
      }
    end
    |> Enum.sort_by(& &1.sort)
    |> Enum.map(&Map.delete(&1, :sort))
  end

  defp rank(tree, name), do: Enum.find_index(tree.order, &(&1 == name))

  @doc """
  Applies a move in a transaction: `{:ok, rows}`, the moved rows as they
  are now, in their new order; or `{:error, reason}`, with nothing
  changed. The move's ids are ids of the tree (`"page:9"`), as
  `Narabe.Move.parse/2` gives them by default.
  """
  @spec move(Ecto.Repo.t(), t(), Move.t()) :: {:ok, [struct()]} | {:error, term()}
  def move(repo, %__MODULE__{} = tree, %Move{} = move) do
    Multi.new()
    |> move_multi(:narabe_move, tree, move)
    |> repo.transaction()
    |> case do
      {:ok, %{narabe_move: rows}} -> {:ok, rows}
      {:error, :narabe_move, reason, _changes} -> {:error, reason}
    end
  end

  @doc "A move as a step of an `Ecto.Multi`, as `Narabe.Ecto.move_multi/5`."
  @spec move_multi(Multi.t(), Multi.name(), t(), Move.t() | (map() -> Move.t())) :: Multi.t()
  def move_multi(multi, name, %__MODULE__{} = tree, move) do
    Multi.run(multi, name, fn repo, changes ->
      move = if is_function(move, 1), do: move.(changes), else: move
      run_move(context(repo, tree), move)
    end)
  end

  @doc """
  A key for a new row: `:last` (the default), `:first`, `{:after, id}` or
  `{:before, id}`, among the children of `in:` (an id of the tree, or nil
  for the top level), of every kind.

      position = Narabe.Ecto.Mixed.insert_position(Repo, tree, :last, in: "folder:3")
  """
  @spec insert_position(Ecto.Repo.t(), t(), atom() | {atom(), String.t()}, keyword()) ::
          Position.t()
  def insert_position(repo, %__MODULE__{} = tree, at \\ :last, opts \\ []) do
    ctx = context(repo, tree)
    group = parent_pk!(tree, Keyword.get(opts, :in))

    {a, b} =
      case at do
        :last -> {max_key(ctx, group, []), nil}
        :first -> {nil, min_key(ctx, group, [])}
        {:after, id} -> after_gap(ctx, group, [], existing_key!(ctx, group, id))
        {:before, id} -> before_gap(ctx, group, [], existing_key!(ctx, group, id))
      end

    Position.between(a, b)
  end

  @doc """
  Puts a position in a changeset for a new row of one of the tree's
  kinds, unless it has one: at `:last` (or `:first`, …) among the
  children of its parent field's value.

      %Page{space_id: space.id}
      |> Page.changeset(attrs)
      |> Narabe.Ecto.Mixed.put_position(Repo, tree)
      |> Repo.insert()
  """
  @spec put_position(Ecto.Changeset.t(), Ecto.Repo.t(), t(), atom() | {atom(), String.t()}) ::
          Ecto.Changeset.t()
  def put_position(%Ecto.Changeset{} = changeset, repo, %__MODULE__{} = tree, at \\ :last) do
    kind = kind_of_schema!(tree, changeset.data.__struct__)

    if Ecto.Changeset.get_field(changeset, kind.position) do
      changeset
    else
      parent = Ecto.Changeset.get_field(changeset, kind.parent)
      key = insert_position(repo, tree, at, in: parent && id(tree.parents, parent))
      Ecto.Changeset.put_change(changeset, kind.position, key)
    end
  end

  @doc """
  Writes the keys of a parent's children anew, evenly, in their current
  order: for keys grown long, or tables that had no positions. `in:` is
  the parent, an id of the tree or nil. Returns how many rows it wrote.
  """
  @spec rebalance(Ecto.Repo.t(), t(), keyword()) :: non_neg_integer()
  def rebalance(repo, %__MODULE__{} = tree, opts \\ []) do
    ctx = context(repo, tree)
    group = parent_pk!(tree, Keyword.get(opts, :in))
    {:ok, count} = repo.transaction(fn -> rewrite(ctx, group) end)
    count
  end

  # -- The context of a call ------------------------------------------------

  defp context(repo, tree) do
    lock =
      case tree.lock do
        nil ->
          repo.__adapter__() |> Module.split() |> List.last() |> Kernel.in(["Postgres", "MyXQL"])

        lock ->
          lock
      end

    %{repo: repo, tree: tree, lock: lock}
  end

  defp kind_of_schema!(tree, schema) do
    Enum.find(Map.values(tree.kinds), &(&1.schema == schema)) ||
      raise ArgumentError, "Narabe: #{inspect(schema)} is not a kind of the tree"
  end

  defp parent_pk!(_tree, nil), do: nil

  defp parent_pk!(tree, id) do
    case parse_id(tree, id) do
      {:ok, {name, pk}} when name == tree.parents -> pk
      _other -> raise ArgumentError, "Narabe: #{inspect(id)} is not a parent of the tree"
    end
  end

  # -- A move -----------------------------------------------------------------

  defp run_move(ctx, move) do
    serialize(ctx)

    with {:ok, ids} <- parse_all(ctx.tree, move.ids),
         {:ok, items} <- load_items(ctx, ids),
         {:ok, target} <- target(ctx, move, ids),
         :ok <- Rules.check(ctx.tree.rules, rule_move(ctx, ids, target)) do
      {:ok, place(ctx, items, target.group, move, ids)}
    end
  end

  defp serialize(%{tree: %{serialize: nil}}), do: :ok

  defp serialize(%{tree: %{serialize: owner}} = ctx) do
    query = from(o in owner, select: 1)
    query = if ctx.lock, do: lock(query, "FOR UPDATE"), else: query
    ctx.repo.all(query)
    :ok
  end

  defp parse_all(tree, ids) do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, acc} ->
      case parse_id(tree, to_string(id)) do
        {:ok, parsed} -> {:cont, {:ok, [parsed | acc]}}
        :error -> {:halt, {:error, :not_found}}
      end
    end)
    |> case do
      {:ok, ids} -> {:ok, ids |> Enum.reverse() |> Enum.uniq()}
      error -> error
    end
  end

  # The moved rows, in the order of the move's ids.
  defp load_items(ctx, ids) do
    by_id =
      ids
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.flat_map(fn {name, pks} ->
        kind = ctx.tree.kinds[name]
        query = from(q in kind.queryable, where: field(q, ^kind.pk) in ^pks)
        query = if ctx.lock, do: lock(query, "FOR UPDATE"), else: query
        for row <- ctx.repo.all(query), do: {{name, Map.fetch!(row, kind.pk)}, row}
      end)
      |> Map.new()

    if map_size(by_id) == length(ids),
      do: {:ok, Enum.map(ids, &{&1, Map.fetch!(by_id, &1)})},
      else: {:error, :not_found}
  end

  defp target(_ctx, %Move{parent: nil}, _ids),
    do: {:ok, %{group: nil, depth: 0, kind: nil, into_itself: false}}

  defp target(ctx, %Move{parent: parent}, ids) do
    tree = ctx.tree

    with {:ok, {name, pk}} <- parse_id(tree, to_string(parent)),
         true <- name == tree.parents || {:error, :not_accepted},
         kind = tree.kinds[name],
         %{} <- ctx.repo.one(from(q in kind.queryable, where: field(q, ^kind.pk) == ^pk)) do
      # The new parent and its ancestors, in one query.
      parents = ctx |> tree_rows([pk], :up) |> Map.new()
      line = [pk | chain(parents, Map.get(parents, pk), [])]
      moved_parents = for {^name, moved} <- ids, do: moved

      {:ok,
       %{
         group: pk,
         depth: length(line),
         kind: name,
         into_itself: Enum.any?(line, &(&1 in moved_parents))
       }}
    else
      {:error, reason} -> {:error, reason}
      _other -> {:error, :not_found}
    end
  end

  defp rule_move(ctx, ids, target) do
    %{
      kinds: Enum.map(ids, &elem(&1, 0)),
      parent_kind: target.kind,
      parent_depth: target.depth,
      # Only a depth limit needs the levels under the items.
      height: if(ctx.tree.rules.max_depth, do: height(ctx, ids), else: 1),
      into_itself: target.into_itself
    }
  end

  # The levels of the moved items' subtrees: the parents under them, and,
  # one level further, the rows of the other kinds in those.
  defp height(ctx, ids) do
    tree = ctx.tree
    roots = for {name, pk} <- ids, name == tree.parents, do: pk

    if roots == [] do
      1
    else
      children = ctx |> tree_rows(roots, :down) |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
      depths = depths(children, roots, 1, %{})
      parents = Map.keys(depths)

      leaf_depths =
        for name <- tree.order,
            name != tree.parents,
            kind = tree.kinds[name],
            parent <-
              ctx.repo.all(
                from(q in kind.queryable,
                  where: field(q, ^kind.parent) in ^parents,
                  distinct: true,
                  select: field(q, ^kind.parent)
                )
              ),
            do: Map.fetch!(depths, load_id(ctx, parent)) + 1

      Enum.max([1 | Map.values(depths) ++ leaf_depths])
    end
  end

  # The depth of each parent under the moved ones, the moved ones at 1.
  defp depths(_children, [], _depth, acc), do: acc

  defp depths(children, ids, depth, acc) do
    ids = Enum.reject(ids, &Map.has_key?(acc, &1))
    acc = Enum.reduce(ids, acc, &Map.put(&2, &1, depth))
    next = Enum.flat_map(ids, &Map.get(children, &1, []))
    depths(children, next, depth + 1, acc)
  end

  # -- The parents' tree, one recursive query at a time ----------------------

  # The {id, parent} of the parents' rows from `ids` up to the top (:up) or
  # down to the last (:down), as Narabe.Ecto reads a tree.
  defp tree_rows(ctx, ids, direction) do
    kind = ctx.tree.kinds[ctx.tree.parents]

    initial =
      from(q in kind.queryable,
        where: field(q, ^kind.pk) in ^ids,
        select: %{id: field(q, ^kind.pk), parent: field(q, ^kind.parent)}
      )

    step =
      case direction do
        :up ->
          from(q in kind.queryable,
            join: t in "narabe_tree",
            on: field(q, ^kind.pk) == t.parent,
            select: %{id: field(q, ^kind.pk), parent: field(q, ^kind.parent)}
          )

        :down ->
          from(q in kind.queryable,
            join: t in "narabe_tree",
            on: field(q, ^kind.parent) == t.id,
            select: %{id: field(q, ^kind.pk), parent: field(q, ^kind.parent)}
          )
      end

    from(t in "narabe_tree", select: %{id: t.id, parent: t.parent})
    |> recursive_ctes(true)
    |> with_cte("narabe_tree", as: ^union(initial, ^step))
    |> ctx.repo.all()
    |> Enum.map(fn %{id: id, parent: parent} -> {load_id(ctx, id), load_id(ctx, parent)} end)
  end

  defp load_id(_ctx, nil), do: nil

  defp load_id(ctx, value) do
    case Ecto.Type.load(ctx.tree.kinds[ctx.tree.parents].pk_type, value) do
      {:ok, id} -> id
      :error -> value
    end
  end

  defp chain(_parents, nil, acc), do: Enum.reverse(acc)

  defp chain(parents, id, acc) do
    if id in acc, do: Enum.reverse(acc), else: chain(parents, Map.get(parents, id), [id | acc])
  end

  # -- Placing the items ----------------------------------------------------

  defp place(ctx, items, group, move, ids) do
    if missing_keys?(ctx, group), do: rewrite(ctx, group)
    {a, b} = gap(ctx, group, ids, move)
    keys = Position.between_many(a, b, length(items))

    for {{{name, pk}, _row}, key} <- Enum.zip(items, keys) do
      kind = ctx.tree.kinds[name]

      ctx.repo.update_all(from(q in kind.schema, where: field(q, ^kind.pk) == ^pk),
        set: [{kind.position, key}, {kind.parent, group}]
      )
    end

    if Enum.any?(keys, &(byte_size(&1) > ctx.tree.rebalance_at)), do: rewrite(ctx, group)

    # The moved rows as they are now, in their new order.
    rows =
      for {{name, pk}, _row} <- items do
        kind = ctx.tree.kinds[name]
        ctx.repo.one!(from(q in kind.queryable, where: field(q, ^kind.pk) == ^pk))
      end

    Enum.sort_by(rows, fn row ->
      kind = kind_of_schema!(ctx.tree, row.__struct__)
      {Map.fetch!(row, kind.position), rank(ctx.tree, kind.name), Map.fetch!(row, kind.pk)}
    end)
  end

  # A kind's rows under the parent `group` (nil: the top level), without
  # the moved ones.
  defp siblings(kind, group, ids) do
    pks = for {name, pk} <- ids, name == kind.name, do: pk
    query = from(q in kind.queryable, where: field(q, ^kind.pk) not in ^pks)

    if group == nil,
      do: where(query, [q], is_nil(field(q, ^kind.parent))),
      else: where(query, [q], field(q, ^kind.parent) == ^group)
  end

  defp kinds(ctx), do: Enum.map(ctx.tree.order, &ctx.tree.kinds[&1])

  defp missing_keys?(ctx, group) do
    Enum.any?(kinds(ctx), fn kind ->
      ctx.repo.exists?(
        from(q in siblings(kind, group, []), where: is_nil(field(q, ^kind.position)))
      )
    end)
  end

  # The keys around the place a move names (see Narabe.Ecto's moduledoc).
  defp gap(ctx, group, ids, move) do
    cond do
      key = move.after && sibling_key(ctx, group, ids, move.after) ->
        after_gap(ctx, group, ids, key)

      key = move.before && sibling_key(ctx, group, ids, move.before) ->
        before_gap(ctx, group, ids, key)

      move.index != nil ->
        index_gap(ctx, group, ids, move.index)

      true ->
        {max_key(ctx, group, ids), nil}
    end
  end

  # The key of a sibling named by its id in the tree, or nil.
  defp sibling_key(ctx, group, ids, id) do
    case parse_id(ctx.tree, to_string(id)) do
      {:ok, {name, pk}} ->
        kind = ctx.tree.kinds[name]

        ctx.repo.one(
          from(q in siblings(kind, group, ids),
            where: field(q, ^kind.pk) == ^pk,
            select: field(q, ^kind.position)
          )
        )

      :error ->
        nil
    end
  end

  defp existing_key!(ctx, group, id) do
    sibling_key(ctx, group, [], id) ||
      raise ArgumentError, "Narabe: #{inspect(id)} is not among the children, or has no position"
  end

  # One key from each kind's (parent, position) index, then the nearest.
  defp after_gap(ctx, group, ids, key) do
    next = edges(ctx, group, ids, &where(&1, [q], field(q, ^&2) > ^key), :asc)
    {key, Enum.min(next, fn -> nil end)}
  end

  defp before_gap(ctx, group, ids, key) do
    previous = edges(ctx, group, ids, &where(&1, [q], field(q, ^&2) < ^key), :desc)
    {Enum.max(previous, fn -> nil end), key}
  end

  defp edges(ctx, group, ids, filter, direction) do
    for kind <- kinds(ctx),
        key <- [edge(ctx, filter.(siblings(kind, group, ids), kind.position), kind, direction)],
        key != nil,
        do: key
  end

  defp edge(ctx, query, kind, direction) do
    ctx.repo.one(
      from(q in query,
        where: not is_nil(field(q, ^kind.position)),
        order_by: [{^direction, field(q, ^kind.position)}],
        select: field(q, ^kind.position),
        limit: 1
      )
    )
  end

  # The keys around an index among the siblings of every kind: at most
  # index + 1 keys of each kind, merged.
  defp index_gap(ctx, group, ids, index) do
    keys =
      kinds(ctx)
      |> Enum.flat_map(fn kind ->
        ctx.repo.all(
          from(q in siblings(kind, group, ids),
            where: not is_nil(field(q, ^kind.position)),
            order_by: [asc: field(q, ^kind.position)],
            select: field(q, ^kind.position),
            limit: ^(index + 1)
          )
        )
      end)
      |> Enum.sort()
      |> Enum.uniq()

    case {index, Enum.slice(keys, max(index - 1, 0), 2)} do
      {0, [first | _]} -> {nil, first}
      {0, []} -> {nil, nil}
      {_, [a, b]} -> {a, b}
      {_, [a]} -> {a, nil}
      {_, []} -> {max_key(ctx, group, ids), nil}
    end
  end

  defp max_key(ctx, group, ids) do
    kinds(ctx)
    |> Enum.map(
      &ctx.repo.one(from(q in siblings(&1, group, ids), select: max(field(q, ^&1.position))))
    )
    |> Enum.reject(&is_nil/1)
    |> Enum.max(fn -> nil end)
  end

  defp min_key(ctx, group, ids) do
    kinds(ctx)
    |> Enum.map(
      &ctx.repo.one(from(q in siblings(&1, group, ids), select: min(field(q, ^&1.position))))
    )
    |> Enum.reject(&is_nil/1)
    |> Enum.min(fn -> nil end)
  end

  # Every child of a parent, of every kind, gets a key, evenly, in their
  # current order (rows without a key last).
  defp rewrite(ctx, group) do
    rows =
      kinds(ctx)
      |> Enum.flat_map(fn kind ->
        rank = rank(ctx.tree, kind.name)

        for {pk, key} <-
              ctx.repo.all(
                from(q in siblings(kind, group, []),
                  select: {field(q, ^kind.pk), field(q, ^kind.position)}
                )
              ),
            do: {{is_nil(key), key, rank, pk}, kind, pk}
      end)
      |> Enum.sort_by(&elem(&1, 0))

    keys = Position.between_many(nil, nil, length(rows))

    for {{_sort, kind, pk}, key} <- Enum.zip(rows, keys) do
      ctx.repo.update_all(from(q in kind.schema, where: field(q, ^kind.pk) == ^pk),
        set: [{kind.position, key}]
      )
    end

    length(rows)
  end
end
