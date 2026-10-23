defmodule Narabe.PositionTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Narabe.Position

  doctest Narabe.Position

  @fixture "test/fixtures/position.json" |> File.read!() |> JSON.decode!()

  test "the same keys as the browser (test/fixtures/position.json)" do
    for %{"a" => a, "b" => b, "key" => key} <- @fixture["between"] do
      assert Position.between(a, b) == key, "between(#{inspect(a)}, #{inspect(b)})"
    end

    for %{"a" => a, "b" => b, "n" => n, "keys" => keys} <- @fixture["many"] do
      assert Position.between_many(a, b, n) == keys
    end

    for key <- @fixture["invalid"] do
      refute Position.valid?(key), inspect(key)
      assert_raise ArgumentError, fn -> Position.between(key, nil) end
    end
  end

  test "a key out of order, or not a key, is refused" do
    assert_raise ArgumentError, ~r/is not before/, fn -> Position.between("a1", "a0") end
    assert_raise ArgumentError, ~r/is not before/, fn -> Position.between("a1", "a1") end
    refute Position.valid?(nil)
  end

  property "a key is strictly between its neighbours, and valid" do
    check all(inserts <- list_of(integer(0..1000), max_length: 200)) do
      keys =
        Enum.reduce(inserts, [], fn at, keys ->
          index = rem(at, length(keys) + 1)
          a = if index > 0, do: Enum.at(keys, index - 1)
          b = Enum.at(keys, index)
          key = Position.between(a, b)
          assert Position.valid?(key)
          assert a == nil or a < key
          assert b == nil or key < b
          List.insert_at(keys, index, key)
        end)

      assert keys == Enum.sort(keys)
    end
  end

  property "many keys are in order, between their ends" do
    check all(n <- integer(0..60), split <- integer(0..2)) do
      {a, b} = Enum.at([{nil, nil}, {"a0", "a1"}, {"Zz", nil}], split)
      keys = Position.between_many(a, b, n)
      assert length(keys) == n
      assert keys == Enum.sort(keys)
      assert keys == Enum.uniq(keys)
      assert Enum.all?(keys, &((a == nil or a < &1) and (b == nil or &1 < b)))
    end
  end
end
