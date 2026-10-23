defmodule Narabe.Live do
  @moduledoc """
  Helpers for the LiveView of a list, a tree or a board.

      def handle_event("move", params, socket) do
        move = Narabe.Move.parse!(params, Task)
        result = Narabe.Ecto.move(Repo, Task, move)

        socket =
          case result do
            {:ok, moved} -> Narabe.Live.stream_move(socket, :tasks, moved, move)
            {:error, _} -> socket
          end

        {:reply, Narabe.Live.reply(result), socket}
      end

  The browser has moved the items already; the reply says whether it may
  keep them there (`%{ok: true}`) or puts them back (`%{error: ...}`).
  """

  alias Narabe.Move

  @doc """
  The reply to a move event, from what `Narabe.Ecto.move/4` (or a
  transaction, or the app's own code) returned.

  ## Examples

      iex> Narabe.Live.reply({:ok, []})
      %{ok: true}

      iex> Narabe.Live.reply({:error, :too_deep})
      %{error: "too_deep"}

      iex> Narabe.Live.reply({:error, :move, :not_found, %{}})
      %{error: "not_found"}

      iex> Narabe.Live.reply({:error, "Archived boards don't change"})
      %{error: "refused", message: "Archived boards don't change"}

  """
  @spec reply(term()) :: map()
  def reply(:ok), do: %{ok: true}
  def reply({:ok, _}), do: %{ok: true}
  def reply({:error, _name, reason, _changes}), do: reply({:error, reason})
  def reply({:error, reason}) when is_atom(reason), do: %{error: Atom.to_string(reason)}
  def reply({:error, message}) when is_binary(message), do: %{error: "refused", message: message}
  def reply({:error, %Ecto.Changeset{}}), do: %{error: "invalid"}
  def reply({:error, _}), do: %{error: "failed"}

  @doc """
  Puts a moved item in its new place in a stream, for the other viewers
  of a list (the one who moved it sees it there already): it is inserted
  again at its index among the stream's items, as the move says.

  Give the moved items (the rows `Narabe.Ecto.move/4` returned), or one;
  several go one after the other.

  A board's columns are each a stream of their own: delete the card from
  the old column's stream and insert it in the new one's.
  """
  @spec stream_move(Phoenix.LiveView.Socket.t(), atom() | String.t(), term(), Move.t()) ::
          Phoenix.LiveView.Socket.t()
  def stream_move(socket, name, items, %Move{index: index}) do
    items
    |> List.wrap()
    |> Enum.with_index()
    |> Enum.reduce(socket, fn {item, i}, socket ->
      at = if is_integer(index), do: index + i, else: -1

      socket
      |> Phoenix.LiveView.stream_delete(name, item)
      |> Phoenix.LiveView.stream_insert(name, item, at: at)
    end)
  end

  @doc """
  Opens (or closes) rows of a tree from the server: `ids`, or one id.
  Rows whose children are not loaded ask for them (`on_expand`).
  """
  @spec expand(Phoenix.LiveView.Socket.t(), String.t(), term() | [term()], boolean()) ::
          Phoenix.LiveView.Socket.t()
  def expand(socket, list_id, ids, open? \\ true) do
    Phoenix.LiveView.push_event(socket, "narabe:expand", %{
      id: list_id,
      ids: wire(ids),
      expanded: open?
    })
  end

  @doc "Opens a row's ancestors, scrolls to it and focuses it."
  @spec reveal(Phoenix.LiveView.Socket.t(), String.t(), term()) :: Phoenix.LiveView.Socket.t()
  def reveal(socket, list_id, item_id) do
    Phoenix.LiveView.push_event(socket, "narabe:reveal", %{id: list_id, item: to_string(item_id)})
  end

  @doc "Selects rows from the server (no `on_select` event follows)."
  @spec select(Phoenix.LiveView.Socket.t(), String.t(), [term()]) :: Phoenix.LiveView.Socket.t()
  def select(socket, list_id, ids) do
    Phoenix.LiveView.push_event(socket, "narabe:select", %{id: list_id, ids: wire(ids)})
  end

  defp wire(ids), do: ids |> List.wrap() |> Enum.map(&to_string/1)
end
