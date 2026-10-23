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

  The browser sends it to the list's `on_move` event:

      def handle_event("moved", params, socket) do
        {:ok, move} = Narabe.Move.parse(params, Card)
        ...
      end
  """

  @enforce_keys [:ids]
  defstruct ids: [], parent: nil, after: nil, before: nil, index: nil

  @type id :: term()
  @type t :: %__MODULE__{
          ids: [id()],
          parent: id() | nil,
          after: id() | nil,
          before: id() | nil,
          index: non_neg_integer() | nil
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
         :ok <- distinct(ids, [parent, after_id, before_id]) do
      {:ok,
       %__MODULE__{ids: ids, parent: parent, after: after_id, before: before_id, index: index}}
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
  an agent's tool that moves items as a person would.

      iex> Narabe.Move.to_params(%Narabe.Move{ids: [42], after: 12})
      %{"v" => 1, "ids" => ["42"], "parent" => nil, "after" => "12", "before" => nil, "index" => nil}
  """
  @spec to_params(t()) :: map()
  def to_params(%__MODULE__{} = move) do
    %{
      "v" => 1,
      "ids" => Enum.map(move.ids, &text/1),
      "parent" => text(move.parent),
      "after" => text(move.after),
      "before" => text(move.before),
      "index" => move.index
    }
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

  # An item is not its own parent or neighbour.
  defp distinct(ids, others) do
    if Enum.any?(others, &(&1 != nil and &1 in ids)), do: {:error, :invalid_move}, else: :ok
  end
end
