# Lists

`sortable_list/1` is a list that people reorder: tasks, a playlist, the
links of a menu.

```heex
<.sortable_list id="tasks" items={@streams.tasks} on_move="move" multiple label="Tasks">
  <:item :let={task}>{task.title}</:item>
</.sortable_list>
```

## The items

`items` is a list or a stream. Each item is a struct or a map. The list
reads its id from `:id`, and its label from `:name`, `:title` or `:label`;
`item_id` and `item_label` take another key or a function:

```heex
<.sortable_list id="songs" items={@songs} on_move="move" item_id={& &1.uuid} item_label={:song_name} />
```

The label is what a screen reader hears as the item moves, and what
shows when there is no `item` slot. Give the list a `label` too: it names
the whole list.

## The move

A drop sends `on_move` to the LiveView, or to the component of the
list's `phx-target`:

```elixir
%{"v" => 1, "ids" => ["7"], "parent" => nil, "after" => "3", "before" => "9", "index" => 2}
```

The items moved (several when selected), and where: right after one
item, right before another, at an index among the new neighbours. Ids are
text. `Narabe.Move.parse/2` reads the params into a `Narabe.Move` with
the ids cast to the type of a schema's primary key (or to an Ecto type
such as `:id`, `:binary_id` or `:string`). `Narabe.Move.parse!/2` raises
for params that are no move.

The place is said by ids, not only by an index, so that a screen a moment
out of date still means what the person saw. `after` wins over `before`;
`index` is for a neighbour that is gone.

```elixir
def handle_event("move", params, socket) do
  move = Narabe.Move.parse!(params, Task)
  result = Narabe.Ecto.move(Repo, Task, move)
  {:reply, Narabe.Live.reply(result), socket}
end
```

The browser has moved the items already. Reply `%{ok: true}` to keep
them there, or `%{error: reason}` to put them back. `Narabe.Live.reply/1`
builds the reply from `{:ok, _}`, `{:error, atom}`, a failed
`Ecto.Multi`, or `{:error, "a message"}`, which the person hears. A drop
where the items already were sends nothing.

## Keeping the order yourself

`Narabe.Move.apply/3` applies a move to a list in memory, for an app
that keeps the order without `Narabe.Ecto`:

```elixir
def handle_event("move", params, socket) do
  move = Narabe.Move.parse!(params, :id)

  case Narabe.Move.apply(socket.assigns.tasks, move) do
    {:ok, tasks} -> {:reply, %{ok: true}, assign(socket, tasks: tasks)}
    error -> {:reply, Narabe.Live.reply(error), socket}
  end
end
```

## Streams and other viewers

With a stream, the person who moved an item sees it in its place already.
Tell the other viewers, and put it in its place in their stream with
`Narabe.Live.stream_move/4`:

```elixir
def handle_event("move", params, socket) do
  move = Narabe.Move.parse!(params, Task)
  result = Narabe.Ecto.move(Repo, Task, move)

  with {:ok, tasks} <- result do
    Phoenix.PubSub.broadcast_from(MyApp.PubSub, self(), "tasks", {:moved, tasks, move})
  end

  {:reply, Narabe.Live.reply(result), socket}
end

def handle_info({:moved, tasks, move}, socket) do
  {:noreply, Narabe.Live.stream_move(socket, :tasks, tasks, move)}
end
```

Subscribe to the topic in `mount/3` when connected. Insert and delete in
the stream as usual.

## Selecting several

With `multiple`, a click selects an item, Shift+click a range and
Ctrl+click (Cmd+click) one more; Shift+arrows extend the selection,
Ctrl+A (Cmd+A) selects all, Escape clears it. Dragging or lifting a
selected item moves every selected item, in their order.

`on_select` sends `%{"v" => 1, "ids" => [...]}` when the selection
changes. `Narabe.Live.select/3` selects items from the server, with no
event back.

## Handles

By default an item drags from anywhere on it. With `handle`, each item
shows a handle, and a mouse starts a drag only there; a finger still
holds the item anywhere, since a handle is small under a finger.

A drag never starts on a link, a button, a form field, a label, editable
text, or an element with `data-narabe-nodrag`, so they keep their clicks.

## Locked items

`item_locked` gives a text for an item that may not move, or nil. The
item shows a lock and cannot be lifted; the person hears the `"locked"`
message ("{name} is moving this") with the text as `{name}`. Change that
message with `messages` if your text is not a name.

## Swipe actions

The `actions` slot holds buttons that a finger swipes into view on a
phone: a swipe left shows them, past half their width they stay open. On
a mouse they are hidden.

```heex
<:actions :let={task}>
  <button type="button" phx-click="done" phx-value-id={task.id}>Done</button>
</:actions>
```

## Read-only

`readonly`, or no `on_move`, keeps focus and selection and moves
nothing.

## Events in the page

The list dispatches DOM events that bubble: `narabe:move` (its `detail`
is the move sent), `narabe:refused` (the server's error reply) and, in a
`group`, `narabe:leave` (items that went to another list of it).

## Between lists

Lists, trees and boards with the same `group` take each other's items;
a list's `parent` is what its moves say as their parent. See the
[Groups](groups.md) guide.

## Without LiveView

On a page without a LiveSocket, `mountNarabe()` mounts the lists: they
focus, select, filter and expand, but a move has no server to go to.

```js
import { mountNarabe } from "narabe"

window.addEventListener("DOMContentLoaded", () => mountNarabe())
```
