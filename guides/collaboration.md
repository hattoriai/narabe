# Collaboration

Several people, and agents, can move items in the same list at once.
There are two parts: the order, which your app keeps and sends to every
viewer, and, with [Issho](https://hex.pm/packages/issho), who is moving
what, shown as it happens.

## Moves at the same moment

A move says where by ids ("after Roadmap"), not by an index, so a move
made on a screen a moment out of date still lands where the person saw.
It writes the moved rows only, so two people moving different items do
not touch each other's rows.

Two drops into the same gap at the same moment may get the same key;
`Narabe.Ecto.ordered/2` orders them by id, the same on every screen.
With `:serialize`, moves in one list run one after the other and get
different keys:

```elixir
Narabe.Ecto.move(Repo, where(Card, board_id: ^board.id), move,
  serialize: where(Board, id: ^board.id)
)
```

## The order on every screen

After a move, tell the other viewers. A list in a stream puts the moved
items in place with `Narabe.Live.stream_move/4`; a tree or a board reads
its items again:

```elixir
def mount(%{"id" => id}, _session, socket) do
  if connected?(socket), do: Phoenix.PubSub.subscribe(MyApp.PubSub, "board:#{id}")
  {:ok, socket |> assign(board: Boards.get_board!(id)) |> load_board()}
end

def handle_event("move", params, socket) do
  board = socket.assigns.board
  result = Narabe.Ecto.move(Repo, where(Card, board_id: ^board.id), Narabe.Move.parse!(params, Card))

  if match?({:ok, _}, result) do
    Phoenix.PubSub.broadcast_from(MyApp.PubSub, self(), "board:#{board.id}", :changed)
  end

  {:reply, Narabe.Live.reply(result), load_board(socket)}
end

def handle_info(:changed, socket), do: {:noreply, load_board(socket)}
```

## Who is moving what, with Issho

With Issho in your deps, a list, a tree or a board shows the item each
person is on, the items someone is dragging (in their color, with their
name), and the line where they would drop them.

```elixir
{:issho, "~> 0.4"}
```

Start an Issho instance in your supervision tree and join its rooms from
the LiveView with `on_mount Issho.Live` (see Issho's docs for the
instance's options and its policy). Then give the list its room and the
person:

```heex
<.board
  id="sprint"
  columns={@columns}
  cards={@cards}
  on_move="move"
  issho={[instance: MyApp.Issho, document: "board:#{@board.id}/cards"]}
  user={@current_user}
/>
```

The part of `document` before the first `/` is the room. `user` is the
person, as Issho reads them. `issho` takes the keys of `Issho.Join`; with
`can: :read`, the person sees the others but their own place is not
shared.

The order is not shared through Issho: it stays your app's, sent as
above. Issho carries only who is moving what, and where to.

## Locks

The person who lifts an item holds it until they drop it or let go. The
others cannot lift it meanwhile: it shows dimmed, with the holder's name,
and Space on it says who is moving it. `lock: false` in `issho` turns the
locks off.

A lock keeps people from moving over each other; it is not a check on
the server. Two moves that reach the server both apply, in the order
they come.

## An agent

An agent's tool moves items as the app does. `Narabe.Issho.move/5` lets
the people see it first: it takes the items' lock, goes to the first
item, picks it up, drags it to where it lands, waits a moment, runs your
function, and lets go.

```elixir
def call(%{"card" => card, "column" => column}, ctx) do
  {:ok, participant} = Issho.Tool.Context.join(ctx, "board:7")
  move = %Narabe.Move{ids: [card], parent: column, index: 0}

  Narabe.Issho.move(participant, "board:7/cards", move, fn ->
    with {:ok, _} = ok <- Narabe.Ecto.move(Repo, Card, move) do
      Phoenix.PubSub.broadcast(MyApp.PubSub, "board:7", :changed)
      ok
    end
  end)
end
```

It gives what the function gives. When someone else holds one of the
items, the agent does not move it: `{:error, {:locked, key}}`. A person
who paused or stopped the agent stops it before the move lands:
`{:error, {:interrupted, by}}`.

`:pace` is how long the agent stays at the item and at the place it
drops it (500 ms; 0 for none); `travel: false` puts it there at once.

## Places

A person's place in a list is `%{"item" => id}`, or, while they drag,
`%{"item" => id, "count" => n, "drag" => gap}`, where the gap is
`%{"parent" => id, "after" => id, "before" => id, "level" => n}`.
`Narabe.Issho.place/2` makes one for `Issho.Motion`, and
`Narabe.Issho.validate/1` checks one.
