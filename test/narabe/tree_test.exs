defmodule Narabe.TreeTest do
  use ExUnit.Case, async: true
  doctest Narabe.Tree

  alias Narabe.Tree

  test "children follow their parent, siblings keep their order" do
    items = [
      %{id: "b", parent_id: nil},
      %{id: "a1", parent_id: "a"},
      %{id: "a", parent_id: nil},
      %{id: "a2", parent_id: "a"},
      %{id: "a2x", parent_id: "a2"}
    ]

    assert Enum.map(Tree.rows(items), &{&1.id, &1.level, &1.parent}) == [
             {"b", 1, nil},
             {"a", 1, nil},
             {"a1", 2, "a"},
             {"a2", 2, "a"},
             {"a2x", 3, "a2"}
           ]
  end

  test "a branch: items whose parent is not here are at the top" do
    rows = Tree.rows([%{id: 5, parent_id: 1}, %{id: 6, parent_id: 5}])
    assert Enum.map(rows, &{&1.id, &1.level}) == [{5, 1}, {6, 2}]
  end

  test "lazy children, keys and functions" do
    items = [[key: 1, up: nil, more: true], [key: 2, up: nil, more: false]]
    rows = Tree.rows(items, id: :key, parent: :up, children: :more)
    assert Enum.map(rows, & &1.children) == [true, false]
  end

  test "a deep tree" do
    items = for i <- 1..3000, do: %{id: i, parent_id: if(i > 1, do: i - 1)}
    rows = Tree.rows(items)
    assert List.last(rows).level == 3000
  end
end
