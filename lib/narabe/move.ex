defmodule Narabe.Move do
  @moduledoc """
  A move, as a drop sends it: these items (one, or several selected), into
  this parent (a tree's item, a board's column, or `nil` for the top level
  or a plain list), right after one item, or right before another.

      %Narabe.Move{ids: [42], parent: 7, after: 12, before: 13, index: 3}

  The move says where by ids, not by an index: a screen a moment out of
  date still means what the person saw ("after Roadmap"), whoever moved
  what meanwhile. `after` wins over `before`; `index` is a last resort, for
  a neighbour that is gone.

  A move from another list of the list's `group` says where the items came
  from: `from` is that list's id (`"someday"`); it is nil within one list.

  The browser sends it to the list's `on_move` event:

      def handle_event("moved", params, socket) do
        {:ok, move} = Narabe.Move.parse(params, Card)
        ...
      end
  """

  @enforce_keys [:ids]
  defstruct ids: [], parent: nil, after: nil, before: nil, index: nil, from: nil

  @type id :: term()
  @type t :: %__MODULE__{
          ids: [id()],
          parent: id() | nil,
          after: id() | nil,
          before: id() | nil,
          index: non_neg_integer() | nil,
          from: String.t() | nil
        }

  @doc """
  A move from the params of an `on_move` event, its ids cast to the type of
  a schema's primary key (or to an Ecto type, `:id`, `:binary_id`,
  `:string`); the browser sends ids as text.

      iex> Narabe.Move.parse(%{"v" => 1, "ids" => ["42"], "parent" => "7", "after" => "12", "before" => nil, "index" => 3}, :id)
      {:ok, %Narabe.Move{ids: [42], parent: 7, after: 12, before: nil, index: 3}}

      iex> Narabe.Move.parse(%{"v" => 1, "ids" => []}, :id)
      {:error, :invalid_move}
  """
  @spec parse(map(), module() | atom()) :: {:ok, t()} | {:error, :invalid_move}
  def parse(params, schema_or_type \\ :string)

  def parse(%{"v" => 1, "ids" => [_ | _] = ids} = params, schema_or_type) do
    type = id_type(schema_or_type)

    with {:ok, ids} <- cast_all(ids, type),
         {:ok, parent} <- cast(params["parent"], type),
         {:ok, after_id} <- cast(params["after"], type),
         {:ok, before_id} <- cast(params["before"], type),
         {:ok, index} <- index(params["index"]),
         {:ok, from} <- from(params["from"]),
         :ok <- distinct(ids, [after_id, before_id]) do
      {:ok,
       %__MODULE__{
         ids: ids,
         parent: parent,
         after: after_id,
         before: before_id,
         index: index,
         from: from
       }}
    end
  end

  def parse(_params, _schema_or_type), do: {:error, :invalid_move}

  @doc "As `parse/2`, raising `ArgumentError` for params that are no move."
  @spec parse!(map(), module() | atom()) :: t()
  def parse!(params, schema_or_type \\ :string) do
    case parse(params, schema_or_type) do
      {:ok, move} -> move
      {:error, _} -> raise ArgumentError, "Narabe: not a move: #{inspect(params)}"
    end
  end

  @doc """
  The params of a move, as the browser sends them: for `Narabe.Test` and
  an agent's tool that moves items as a person would. `"from"` is there
  only for a move from another list.

      iex> Narabe.Move.to_params(%Narabe.Move{ids: [42], after: 12})
      %{"v" => 1, "ids" => ["42"], "parent" => nil, "after" => "12", "before" => nil, "index" => nil}

      iex> Narabe.Move.to_params(%Narabe.Move{ids: [42], parent: 3, index: 0, from: "someday"})
      %{"v" => 1, "ids" => ["42"], "parent" => "3", "after" => nil, "before" => nil, "index" => 0, "from" => "someday"}
  """
  @spec to_params(t()) :: map()
  def to_params(%__MODULE__{} = move) do
    params = %{
      "v" => 1,
      "ids" => Enum.map(move.ids, &text/1),
      "parent" => text(move.parent),
      "after" => text(move.after),
      "before" => text(move.before),
      "index" => move.index
    }

    if move.from, do: Map.put(params, "from", move.from), else: params
  end

  defp text(nil), do: nil
  defp text(id), do: to_string(id)

  defp id_type(type) when type in [:id, :binary_id, :string, :integer, Ecto.UUID], do: type

  # A schema's primary key type, or the Ecto type given.
  defp id_type(schema) when is_atom(schema) do
    if Code.ensure_loaded?(schema) and function_exported?(schema, :__schema__, 1) do
      case schema.__schema__(:primary_key) do
        [key] -> schema.__schema__(:type, key)
        _other -> raise ArgumentError, "Narabe: #{inspect(schema)} needs one primary key"
      end
    else
      schema
    end
  end

  defp cast_all(ids, type) do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, acc} ->
      case cast(id, type) do
        {:ok, nil} -> {:halt, {:error, :invalid_move}}
        {:ok, id} -> {:cont, {:ok, [id | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, ids} -> {:ok, ids |> Enum.reverse() |> Enum.uniq()}
      error -> error
    end
  end

  defp cast(nil, _type), do: {:ok, nil}
  defp cast("", _type), do: {:ok, nil}

  defp cast(value, type) do
    case Ecto.Type.cast(type, value) do
      {:ok, value} -> {:ok, value}
      _error -> {:error, :invalid_move}
    end
  end

  defp index(nil), do: {:ok, nil}
  defp index(index) when is_integer(index) and index >= 0, do: {:ok, index}
  defp index(_other), do: {:error, :invalid_move}

  # The id of the list the items came from: a list's id is text.
  defp from(nil), do: {:ok, nil}
  defp from(""), do: {:ok, nil}
  defp from(from) when is_binary(from), do: {:ok, from}
  defp from(_other), do: {:error, :invalid_move}

  # An item is not its own neighbour.
  defp distinct(ids, others) do
    if Enum.any?(others, &(&1 != nil and &1 in ids)), do: {:error, :invalid_move}, else: :ok
  end

  @doc """
  Applies a move to items in memory, in their order: a list, a board's
  cards (each with its column in `:group`), or a tree's items, flat (each
  with its parent in `:group`, and `tree: true`). For apps that keep the
  order themselves, without `Narabe.Ecto`, and for tests.

  Returns `{:ok, items}`, the items in their new order with the moved ones'
  group set, or `{:error, reason}`: `:not_found` (an id that is not among
  the items), or `:into_itself` (a tree item into itself or under itself).

  Options:

    * `:id` - an item's id: a key or a function (`:id`).
    * `:group` - the key of its column or parent (none: one list).
    * `:tree` - whether `:group` is a parent among the items.

  ## Examples

      iex> items = [%{id: 1}, %{id: 2}, %{id: 3}]
      iex> {:ok, moved} = Narabe.Move.apply(items, %Narabe.Move{ids: [1], after: 3})
      iex> Enum.map(moved, & &1.id)
      [2, 3, 1]

      iex> cards = [%{id: 1, col: :todo}, %{id: 2, col: :done}]
      iex> {:ok, moved} = Narabe.Move.apply(cards, %Narabe.Move{ids: [1], parent: :done, before: 2}, group: :col)
      iex> moved
      [%{id: 1, col: :done}, %{id: 2, col: :done}]

  """
  @spec apply([term()], t(), keyword()) :: {:ok, [term()]} | {:error, :not_found | :into_itself}
  def apply(items, %__MODULE__{} = move, opts \\ []) do
    id = Narabe.Tree.getter(Keyword.get(opts, :id, :id))
    group = Keyword.get(opts, :group)
    ids = MapSet.new(move.ids)
    by_id = Map.new(items, &{id.(&1), &1})

    with :ok <- check_apply(move, by_id, ids, group, Keyword.get(opts, :tree, false)) do
      moved = for i <- move.ids, do: put_group(by_id[i], group, move.parent)
      rest = Enum.reject(items, &MapSet.member?(ids, id.(&1)))
      at = insert_at(rest, move, id, group)
      {:ok, Enum.take(rest, at) ++ moved ++ Enum.drop(rest, at)}
    end
  end

  defp check_apply(move, by_id, ids, group, tree?) do
    known? = &Map.has_key?(by_id, &1)

    cond do
      not Enum.all?(move.ids, known?) ->
        {:error, :not_found}

      Enum.any?([move.after, move.before], &(&1 != nil and not known?.(&1))) ->
        {:error, :not_found}

      not tree? or move.parent == nil ->
        :ok

      not known?.(move.parent) ->
        {:error, :not_found}

      under?(by_id, move.parent, ids, group) ->
        {:error, :into_itself}

      true ->
        :ok
    end
  end

  # Whether `parent` is one of the moved items or under one.
  defp under?(by_id, parent, ids, group) do
    Stream.unfold(parent, fn
      nil -> nil
      p -> {p, by_id[p] && fetch(by_id[p], group)}
    end)
    |> Enum.take(map_size(by_id) + 1)
    |> Enum.any?(&MapSet.member?(ids, &1))
  end

  # Where in the remaining items: after `after`, before `before`, at the
  # index among the new siblings, or after the last of them.
  defp insert_at(rest, move, id, group) do
    position = fn target -> Enum.find_index(rest, &(id.(&1) == target)) end

    siblings =
      for {item, i} <- Enum.with_index(rest),
          group == nil or fetch(item, group) == move.parent,
          do: i

    cond do
      move.after != nil -> position.(move.after) + 1
      move.before != nil -> position.(move.before)
      move.index != nil and move.index < length(siblings) -> Enum.at(siblings, move.index)
      siblings != [] -> List.last(siblings) + 1
      true -> length(rest)
    end
  end

  defp put_group(item, nil, _parent), do: item
  defp put_group(%{} = item, key, parent), do: Map.put(item, key, parent)
  defp put_group(item, key, parent) when is_list(item), do: Keyword.put(item, key, parent)

  defp fetch(_item, nil), do: nil
  defp fetch(%{} = item, key), do: Map.get(item, key)
  defp fetch(item, key) when is_list(item), do: Keyword.get(item, key)
end
