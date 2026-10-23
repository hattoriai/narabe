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
    assert {:ok, %Move{ids: [3], parent: 3}} = Move.parse(%{"v" => 1, "ids" => ["3"], "parent" => "3"}, :id)
  end

  test "params round-trip" do
    move = %Move{ids: [3], parent: 9, after: 4, before: nil, index: 1}
    assert {:ok, ^move} = move |> Move.to_params() |> Move.parse(:id)
    assert_raise ArgumentError, ~r/not a move/, fn -> Move.parse!(%{"ids" => [1]}) end
  end
end
