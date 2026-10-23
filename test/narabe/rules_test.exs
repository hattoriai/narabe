defmodule Narabe.RulesTest do
  use ExUnit.Case, async: true

  alias Narabe.Rules

  doctest Narabe.Rules

  @fixture "test/fixtures/rules.json" |> File.read!() |> JSON.decode!()

  test "the same answers as the browser (test/fixtures/rules.json)" do
    for %{"name" => name, "rules" => rules, "move" => move, "result" => result} <-
          @fixture["cases"] do
      rules =
        Rules.new(
          nest: Map.get(rules, "nest", false),
          max_depth: rules["maxDepth"],
          leaves: Map.get(rules, "leaves", []),
          accepts: rules["accepts"]
        )

      move = %{
        kinds: move["kinds"],
        parent_kind: move["parentKind"],
        parent_depth: move["parentDepth"],
        height: move["height"],
        into_itself: move["intoItself"]
      }

      expected = if result == "ok", do: :ok, else: {:error, String.to_existing_atom(result)}
      assert Rules.check(rules, move) == expected, name
    end
  end

  test "a rule that is not one says so" do
    assert_raise ArgumentError, ~r/not a rule: :depth/, fn -> Rules.new(depth: 3) end
    assert_raise ArgumentError, ~r/not a rule: :max_depth/, fn -> Rules.new(max_depth: 0) end
  end

  test "the rules for the browser round-trip through the fixture's shape" do
    rules = Rules.new(nest: true, leaves: [:file], accepts: %{folder: [:file, :folder]})

    assert Rules.to_client(rules) == %{
             "nest" => true,
             "leaves" => ["file"],
             "accepts" => %{"folder" => ["file", "folder"]}
           }
  end
end
