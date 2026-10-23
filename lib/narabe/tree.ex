defmodule Narabe.Tree do
  @moduledoc """
  A tree's items, flat, as a page shows them: each after its parent, with
  its level and its place among its siblings.

  `Narabe.Components.tree/1` and `tree_picker/1` take the items as the
  database has them, a flat list with a parent id each, in their order
  (`Narabe.Ecto.ordered/2`), and lay them out with `rows/2`.
  """

  @typedoc "A row of a tree."
  @type row :: %{
          item: term(),
          id: term(),
          parent: term(),
          level: pos_integer(),
          index: non_neg_integer(),
          count: pos_integer(),
          children: boolean()
        }

  @doc """
  The rows of a tree, in the order a page shows them: depth first, each
  item's children after it, siblings in the order of `items`.

  An item whose parent is not among the items is at the top: a tree may
  show a branch, or the levels loaded so far.

  Options:

    * `:id` - the item's id: a key or a function (`:id`).
    * `:parent` - its parent's id: a key or a function (`:parent_id`).
    * `:children` - whether it has children that are not loaded yet: a key
      or a function, or nil (none). An item with loaded children has
      children either way.

  ## Examples

      iex> items = [%{id: 1, parent_id: nil}, %{id: 2, parent_id: nil}, %{id: 3, parent_id: 1}]
      iex> for row <- Narabe.Tree.rows(items), do: {row.id, row.level, row.index, row.count, row.children}
      [{1, 1, 0, 2, true}, {3, 2, 0, 1, false}, {2, 1, 1, 2, false}]

  """
  @spec rows([term()], keyword()) :: [row()]
  def rows(items, opts \\ []) do
    id = getter(Keyword.get(opts, :id, :id))
    parent = getter(Keyword.get(opts, :parent, :parent_id))
    lazy = if f = Keyword.get(opts, :children), do: getter(f), else: fn _ -> false end

    entries = Enum.map(items, &{id.(&1), parent.(&1), &1})
    ids = MapSet.new(entries, &elem(&1, 0))

    by_parent =
      entries
      |> Enum.reverse()
      |> Enum.reduce(%{}, fn {i, p, item}, acc ->
        p = if MapSet.member?(ids, p), do: p, else: :top
        Map.update(acc, p, [{i, item}], &[{i, item} | &1])
      end)

    by_parent
    |> Map.get(:top, [])
    |> walk(nil, 1, by_parent, lazy, %{}, [])
    |> Enum.reverse()
  end

  # Depth first, with a set of the ids above, so that a cycle in the data
  # (a parent under its own child) ends instead of looping.
  defp walk(siblings, parent, level, by_parent, lazy, above, acc) do
    count = length(siblings)

    siblings
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {{id, item}, index}, acc ->
      kids = if Map.has_key?(above, id), do: [], else: Map.get(by_parent, id, [])

      row = %{
        item: item,
        id: id,
        parent: parent,
        level: level,
        index: index,
        count: count,
        children: kids != [] or !!lazy.(item)
      }

      walk(kids, id, level + 1, by_parent, lazy, Map.put(above, id, true), [row | acc])
    end)
  end

  @doc false
  def getter(f) when is_function(f, 1), do: f
  def getter(key) when is_atom(key) or is_binary(key), do: &fetch(&1, key)

  defp fetch(%{} = item, key), do: Map.get(item, key)
  defp fetch(item, key) when is_list(item), do: Keyword.get(item, key)
end
