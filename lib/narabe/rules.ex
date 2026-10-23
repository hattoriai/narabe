defmodule Narabe.Rules do
  @moduledoc """
  What may go where: the same rules in the browser, as people drag (a drop
  that breaks them is not offered), and on the server, as `Narabe.Ecto`
  applies a move (one that breaks them is refused).

      rules = Narabe.Rules.new(nest: true, max_depth: 4, leaves: ["file"])

  Options:

    * `:nest` - whether an item may hold others (a tree). A list's and a
      board's items do not nest (`false`, the default for them).
    * `:max_depth` - the deepest level an item may be at, the top level
      being 1. A moved item's own children count: a page with two levels
      under it cannot go to the deepest level.
    * `:leaves` - the kinds of items that hold nothing (`["file"]`).
    * `:accepts` - which kinds of items a kind of parent takes:
      `%{"section" => ["page"], "root" => ["section"]}`. `"root"` is the
      top level; a board's columns are parents of their kind (`"column"`).
      A kind with no entry takes anything.

  An item's kind is its `kind` (`data-kind` in the browser, the `:kind`
  field of `Narabe.Ecto`'s schema); without one it is `"item"`.

  The browser and the server give the same answers, held by
  `test/fixtures/rules.json`.
  """

  defstruct nest: false, max_depth: nil, leaves: [], accepts: nil

  @type t :: %__MODULE__{
          nest: boolean(),
          max_depth: pos_integer() | nil,
          leaves: [String.t()],
          accepts: %{String.t() => [String.t()]} | nil
        }

  @typedoc "Why a move is refused."
  @type reason :: :into_itself | :not_accepted | :too_deep

  @typedoc """
  A move, as the rules see it: the kinds of the items, the kind of their new
  parent (`nil` at the top level) and its depth (0 for the top level or a
  board's column), the height of the tallest item's subtree (1 for an item
  with no children), and whether the parent is one of the items or under
  one.
  """
  @type move :: %{
          kinds: [String.t()],
          parent_kind: String.t() | nil,
          parent_depth: non_neg_integer(),
          height: pos_integer(),
          into_itself: boolean()
        }

  @doc """
  Rules from options (see the moduledoc), or the rules themselves.

      iex> Narabe.Rules.new(nest: true, max_depth: 3)
      %Narabe.Rules{nest: true, max_depth: 3, leaves: [], accepts: nil}
  """
  @spec new(t() | keyword() | nil) :: t()
  def new(nil), do: %__MODULE__{}
  def new(%__MODULE__{} = rules), do: rules

  def new(opts) when is_list(opts) do
    Enum.reduce(opts, %__MODULE__{}, fn
      {:nest, nest}, rules when is_boolean(nest) ->
        %{rules | nest: nest}

      {:max_depth, depth}, rules when is_integer(depth) and depth > 0 ->
        %{rules | max_depth: depth}

      {:max_depth, nil}, rules ->
        rules

      {:leaves, kinds}, rules when is_list(kinds) ->
        %{rules | leaves: Enum.map(kinds, &to_string/1)}

      {:accepts, nil}, rules ->
        rules

      {:accepts, map}, rules when is_map(map) ->
        %{
          rules
          | accepts: Map.new(map, fn {k, v} -> {to_string(k), Enum.map(v, &to_string/1)} end)
        }

      {key, value}, _rules ->
        raise ArgumentError, "Narabe: not a rule: #{inspect(key)} => #{inspect(value)}"
    end)
  end

  @doc """
  Checks a move: `:ok`, or `{:error, reason}`.

      iex> rules = Narabe.Rules.new(nest: true, max_depth: 2)
      iex> Narabe.Rules.check(rules, %{kinds: ["page"], parent_kind: "page", parent_depth: 1, height: 1, into_itself: false})
      :ok
      iex> Narabe.Rules.check(rules, %{kinds: ["page"], parent_kind: "page", parent_depth: 1, height: 2, into_itself: false})
      {:error, :too_deep}
  """
  @spec check(t(), move()) :: :ok | {:error, reason()}
  def check(%__MODULE__{} = rules, move) do
    nested = move.parent_depth > 0

    cond do
      move.into_itself -> {:error, :into_itself}
      nested and not rules.nest -> {:error, :not_accepted}
      nested and move.parent_kind in rules.leaves -> {:error, :not_accepted}
      not accepted?(rules, move) -> {:error, :not_accepted}
      too_deep?(rules, move) -> {:error, :too_deep}
      true -> :ok
    end
  end

  defp accepted?(%{accepts: nil}, _move), do: true

  defp accepted?(%{accepts: accepts}, move) do
    case Map.get(accepts, move.parent_kind || "root") do
      nil -> true
      kinds -> Enum.all?(move.kinds, &(&1 in kinds))
    end
  end

  defp too_deep?(%{max_depth: nil}, _move), do: false
  defp too_deep?(%{max_depth: max}, move), do: move.parent_depth + move.height > max

  @doc """
  The rules as the browser takes them (`data-config`), with keys in camel
  case and nothing that is a default.

      iex> Narabe.Rules.to_client(Narabe.Rules.new(nest: true, max_depth: 3))
      %{"nest" => true, "maxDepth" => 3}
  """
  @spec to_client(t()) :: map()
  def to_client(%__MODULE__{} = rules) do
    %{
      "nest" => rules.nest,
      "maxDepth" => rules.max_depth,
      "leaves" => rules.leaves,
      "accepts" => rules.accepts
    }
    |> Enum.reject(fn {_k, v} -> v in [nil, false, []] end)
    |> Map.new()
  end
end
