# Boards

`board/1` is columns of cards that people move within a column and
across them, and, with `move_columns`, columns that move too: a kanban,
a sprint, a pipeline.

```heex
<.board id="sprint" columns={@columns} cards={@cards} on_move="move" move_columns label="Sprint">
  <:column :let={column}>{column.name}</:column>
  <:card :let={card}>{card.title}</:card>
  <:footer :let={column}>
    <button type="button" phx-click="add" phx-value-column={column.id}>Add a card</button>
  </:footer>
</.board>
```

## The columns and the cards

`columns` are in their order. `cards` are flat, each with its column's
id (`card_column`, `:column_id` by default), in their order: the board
puts each in its column. Both are lists.

A column's id, label and kind come from `column_id` (`:id`),
`column_label` (`:name`, `:title` or `:label` by default) and
`column_kind`. A card's come from `item_id`, `item_label` and
`item_kind`, as a list's items.

The slots: `column` is a column's header (its label by default), `card`
(or `item`) a card's content, `footer` the end of each column, and
`actions` the buttons a finger swipes into view on a phone. Each column's
header shows how many cards it has.

## The schemas

```elixir
defmodule MyApp.Boards.Column do
  use Ecto.Schema

  schema "columns" do
    field :name, :string
    field :position, :string
    belongs_to :board, MyApp.Boards.Board
  end

  use Narabe.Ordered
end

defmodule MyApp.Boards.Card do
  use Ecto.Schema

  schema "cards" do
    field :title, :string
    field :position, :string
    belongs_to :column, MyApp.Boards.Column
    belongs_to :board, MyApp.Boards.Board
  end

  use Narabe.Ordered, group: :column_id
end
```

`group: :column_id` makes each column a list of its own: a move writes
the card's position and, when it changes, its column.

## The moves

A card's move says its new column as `"parent"`. A column's move has
`"columns" => true`, with the columns' ids. Handle them in two clauses:

```elixir
import Ecto.Query

def handle_event("move", %{"columns" => true} = params, socket) do
  board = socket.assigns.board
  move = Narabe.Move.parse!(params, Column)
  result = Narabe.Ecto.move(Repo, where(Column, board_id: ^board.id), move)
  {:reply, Narabe.Live.reply(result), load_board(socket)}
end

def handle_event("move", params, socket) do
  board = socket.assigns.board
  move = Narabe.Move.parse!(params, Card)

  result =
    Narabe.Ecto.move(Repo, where(Card, board_id: ^board.id), move,
      serialize: where(MyApp.Boards.Board, id: ^board.id)
    )

  {:reply, Narabe.Live.reply(result), load_board(socket)}
end
```

The queryable is the whole of what may be moved: a card of another
board, or a column of another board as the new parent, is refused as
`:not_found`. `:serialize` locks the board's row first, so that moves on
one board run one after the other (see the [Database](database.md)
guide).

In memory, `Narabe.Move.apply(cards, move, group: :column_id)` moves the
cards and sets their column.

## Adding a card

`Narabe.Ecto.insert_position/4` gives the key of a new card, at the end
of its column with `in:`:

```elixir
def handle_event("add", %{"column" => column_id}, socket) do
  column_id = String.to_integer(column_id)
  position = Narabe.Ecto.insert_position(Repo, Card, :last, in: column_id)

  Repo.insert!(%Card{
    title: "New card",
    column_id: column_id,
    board_id: socket.assigns.board.id,
    position: position
  })

  {:noreply, load_board(socket)}
end
```

`Narabe.Ecto.put_position/4` does the same in a changeset, from the
changeset's `column_id`.

## The keyboard

Up and Down go through a column's cards, Left and Right to the card at
the same place in the next column. Space lifts a card; Up and Down move
it in its column, Left and Right to another column; Space drops it,
Escape puts it back.

Columns move with a pointer, by the handle in their header.

## Kinds

A column may refuse some cards. In the browser, the rules' `accepts` see
a column's kind (`column_kind`, `"column"` when it has none) as the
parent's kind:

```heex
<.board id="sprint" columns={@columns} cards={@cards} item_kind={:type} rules={[accepts: %{"column" => ["task", "bug"]}]} on_move="move" />
```

On the server, `Narabe.Ecto` takes one kind for every column, the
`:group_kind` option, `"column"` by default, as in the browser:

```elixir
use Narabe.Ordered, group: :column_id, kind: :type,
  rules: [accepts: %{"column" => ["task", "bug"]}]
```

Columns that each take other kinds (`column_kind`) are checked in the
browser only; check them yourself in the event, and reply
`{:error, "a message"}` to refuse.

## On a phone

A finger holds a card a moment to lift it; a quick swipe scrolls. The
columns are at most 85% of the screen wide and snap into place as the
board scrolls sideways. While a card is dragged near an edge, the column
and the page scroll.
