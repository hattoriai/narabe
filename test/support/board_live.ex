defmodule NarabeTest.BoardLive do
  @moduledoc "A board, a tree, a list and a tree picker, kept in memory (Narabe.Move.apply/3), for Narabe.Test's tests."
  use Phoenix.LiveView

  import Narabe.Components

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       tasks: for(i <- 1..4, do: %{id: i, title: "Task #{i}"}),
       columns: [%{id: 1, name: "To do"}, %{id: 2, name: "Done"}],
       cards: [
         %{id: 1, title: "A", column_id: 1},
         %{id: 2, title: "B", column_id: 1},
         %{id: 3, title: "C", column_id: 2}
       ],
       pages: [
         %{id: 1, title: "Docs", parent_id: nil},
         %{id: 2, title: "Intro", parent_id: 1},
         %{id: 3, title: "Blog", parent_id: nil}
       ],
       loaded: false,
       selected: [],
       form: to_form(%{"parent_id" => "1"}, as: :move),
       picked: nil
     )}
  end

  def render(assigns) do
    ~H"""
    <.sortable_list id="tasks" items={@tasks} on_move="move_task" on_select="select" multiple item_label={:title} />
    <.board id="board" columns={@columns} cards={@cards} on_move="move_card" move_columns item_label={:title} />
    <.tree
      id="pages"
      items={@pages}
      item_label={:title}
      item_children={&(&1.id == 3 and not @loaded)}
      on_move="move_page"
      on_expand="expand"
      on_rename="rename"
    />
    <.form for={@form} id="move-form" phx-change="pick">
      <.tree_picker field={@form[:parent_id]} items={@pages} item_label={:title} />
    </.form>
    <p id="picked">{@picked}</p>
    <p id="selected">{Enum.join(@selected, ",")}</p>
    """
  end

  def handle_event("move_task", params, socket),
    do: apply_move(socket, :tasks, params, [])

  def handle_event("move_card", %{"columns" => true} = params, socket),
    do: apply_move(socket, :columns, params, [])

  def handle_event("move_card", params, socket),
    do: apply_move(socket, :cards, params, group: :column_id)

  def handle_event("move_page", params, socket),
    do: apply_move(socket, :pages, params, group: :parent_id, tree: true)

  def handle_event("expand", %{"id" => "3"}, socket) do
    pages = socket.assigns.pages ++ [%{id: 4, title: "Post", parent_id: 3}]
    {:noreply, assign(socket, pages: pages, loaded: true)}
  end

  def handle_event("rename", %{"id" => id, "name" => name}, socket) do
    id = String.to_integer(id)
    pages = Enum.map(socket.assigns.pages, &if(&1.id == id, do: %{&1 | title: name}, else: &1))
    {:noreply, assign(socket, pages: pages)}
  end

  def handle_event("select", %{"ids" => ids}, socket),
    do: {:noreply, assign(socket, selected: ids)}

  def handle_event("pick", %{"move" => %{"parent_id" => id}}, socket),
    do: {:noreply, assign(socket, picked: id)}

  defp apply_move(socket, key, params, opts) do
    move = Narabe.Move.parse!(params, :id)

    case Narabe.Move.apply(socket.assigns[key], move, opts) do
      {:ok, items} -> {:reply, %{ok: true}, assign(socket, key, items)}
      error -> {:reply, Narabe.Live.reply(error), socket}
    end
  end
end
