defmodule Narabe.MoveTest do
  use ExUnit.Case, async: true

  alias Narabe.Move

  doctest Narabe.Move

  test "ids are cast to the schema's primary key" do
    assert {:ok, %Move{ids: [3, 1], parent: 9}} =
             Move.parse(%{"v" => 1, "ids" => ["3", "1", "3"], "parent" => "9"}, NarabeTest.Card)

    assert {:error, :invalid_move} = Move.parse(%{"v" => 1, "ids" => ["x"]}, NarabeTest.Card)
  end

  test "an item is not its own neighbour" do
    assert {:error, :invalid_move} = Move.parse(%{"v" => 1, "ids" => ["3"], "after" => "3"}, :id)
    assert {:error, :invalid_move} = Move.parse(%{"v" => 1, "ids" => ["3"], "before" => "3"}, :id)
  end

  test "a parent may have a moved item's id: a board's column is another table's row" do
    # (In a tree, Narabe.Ecto refuses a move into itself as :into_itself.)
    assert {:ok, %Move{ids: [3], parent: 3}} =
             Move.parse(%{"v" => 1, "ids" => ["3"], "parent" => "3"}, :id)
  end

  test "params round-trip" do
    move = %Move{ids: [3], parent: 9, after: 4, before: nil, index: 1}
    assert {:ok, ^move} = move |> Move.to_params() |> Move.parse(:id)
    assert_raise ArgumentError, ~r/not a move/, fn -> Move.parse!(%{"ids" => [1]}) end
  end

  describe "apply/3" do
    defp ids({:ok, items}), do: Enum.map(items, & &1.id)

    test "a list: after, before, an index, the end" do
      items = for i <- 1..5, do: %{id: i}
      assert ids(Move.apply(items, %Move{ids: [1], after: 3})) == [2, 3, 1, 4, 5]
      assert ids(Move.apply(items, %Move{ids: [5], before: 2})) == [1, 5, 2, 3, 4]
      assert ids(Move.apply(items, %Move{ids: [5, 1], index: 1})) == [2, 5, 1, 3, 4]
      assert ids(Move.apply(items, %Move{ids: [2]})) == [1, 3, 4, 5, 2]
      assert Move.apply(items, %Move{ids: [9]}) == {:error, :not_found}
      assert Move.apply(items, %Move{ids: [1], after: 9}) == {:error, :not_found}
    end

    test "a board: into an empty column, at its end" do
      cards = [%{id: 1, col: "a"}, %{id: 2, col: "a"}, %{id: 3, col: "b"}]
      assert {:ok, moved} = Move.apply(cards, %Move{ids: [1], parent: "c"}, group: :col)
      assert List.last(moved) == %{id: 1, col: "c"}
      assert {:ok, moved} = Move.apply(cards, %Move{ids: [3], parent: "a", index: 1}, group: :col)
      assert Enum.map(moved, &{&1.id, &1.col}) == [{1, "a"}, {3, "a"}, {2, "a"}]
    end

    test "a tree: never into itself" do
      pages = [
        %{id: 1, parent_id: nil},
        %{id: 2, parent_id: 1},
        %{id: 3, parent_id: 2},
        %{id: 4, parent_id: nil}
      ]

      opts = [group: :parent_id, tree: true]
      assert Move.apply(pages, %Move{ids: [1], parent: 3}, opts) == {:error, :into_itself}
      assert Move.apply(pages, %Move{ids: [1], parent: 1}, opts) == {:error, :into_itself}
      assert Move.apply(pages, %Move{ids: [1], parent: 7}, opts) == {:error, :not_found}
      assert {:ok, moved} = Move.apply(pages, %Move{ids: [4], parent: 2}, opts)

      assert Narabe.Tree.rows(moved) |> Enum.map(&{&1.id, &1.level}) == [
               {1, 1},
               {2, 2},
               {3, 3},
               {4, 3}
             ]
    end
  end
end
