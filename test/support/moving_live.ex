defmodule NarabeTest.MovingLive do
  @moduledoc "A board in an Issho room (Narabe.Issho), for its tests."
  use Phoenix.LiveView

  import Narabe.Components

  on_mount(Issho.Live)

  def mount(_params, %{"room" => room, "user" => user}, socket) do
    {:ok,
     assign(socket,
       room: room,
       user: %{id: user, name: String.capitalize(user)},
       columns: [%{id: 1, name: "To do"}, %{id: 2, name: "Done"}],
       cards: [%{id: 1, title: "A", column_id: 1}, %{id: 2, title: "B", column_id: 1}]
     )}
  end

  def render(assigns) do
    ~H"""
    <.board
      id="board"
      columns={@columns}
      cards={@cards}
      on_move="move"
      item_label={:title}
      issho={[instance: NarabeTest.Issho, document: @room <> "/cards"]}
      user={@user}
    />
    """
  end

  def handle_event("move", params, socket) do
    move = Narabe.Move.parse!(params, :id)
    {:ok, cards} = Narabe.Move.apply(socket.assigns.cards, move, group: :column_id)
    {:reply, %{ok: true}, assign(socket, cards: cards)}
  end

  def handle_info({:cards, cards}, socket), do: {:noreply, assign(socket, cards: cards)}
end
