# Groups

Lists, trees and boards with the same `group` take each other's items: a
task dragged to another project's list, a card to another board, a page
of the main view into a folder of the sidebar's tree.

```heex
<.board id="week" columns={@projects} cards={@tasks} card_column={:project_id} group="tasks" on_move="move" />

<.sortable_list id="someday" items={@someday_tasks} parent={@someday.id} group="tasks" on_move="move" />
```

A drag finds where it would land in the list under the pointer; with the
keyboard, Tab takes a lifted item to the next list of the group (Shift+Tab
to the one before), and the arrows move it there. The list it would land
in shows a dashed outline.

## The move

The drop sends one move, to the list it lands in: its `on_move`, to its
LiveView or the component of its `phx-target`. The move is the usual one
(see the [Lists](lists.md) guide), with the id of the list the items came
from as `"from"`:

```elixir
%{"v" => 1, "ids" => ["7"], "parent" => "3", "after" => "12", "before" => nil, "index" => 2, "from" => "someday"}
```

`Narabe.Move.parse/2` reads it as `%Narabe.Move{from: "someday"}`.

The new parent is the target's: a tree's row, a board's column, or a
list's `parent`. A list's moves say its `parent` attribute (nil when it
has none), as a board's column says its id, so that a list of a
project's tasks moves them into that project:

```elixir
use Narabe.Ordered, group: :project_id

def handle_event("move", params, socket) do
  move = Narabe.Move.parse!(params, Task)
  result = Narabe.Ecto.move(Repo, where(Task, owner_id: ^socket.assigns.user.id), move)
  {:reply, Narabe.Live.reply(result), load(socket)}
end
```

The queryable is all a move may touch: the rows of every list of the
group, and the parents they may go to. One handler serves every list of
a LiveView.

## The list the items left

The browser takes the items out of their list at once. The list's
server learns that they left when it renders again: in one LiveView,
the move's own render does it. A list in another LiveView, or one that
keeps its items itself, learns it from `on_leave`, sent to its own
LiveView or component once the other list's server kept the items:

```heex
<.sortable_list id="someday" items={@streams.tasks} parent={@someday.id} group="tasks" on_move="move" on_leave="left" />
```

```elixir
def handle_event("left", %{"ids" => ids, "to" => _list}, socket) do
  {:noreply, Enum.reduce(ids, socket, &stream_delete_by_dom_id(&2, :tasks, "tasks-#{&1}"))}
end
```

A list in a stream that takes items puts them in with `stream_insert`
at their index (`Narabe.Live.stream_move/4`): the browser then drops the
copy it moved there.

The list also dispatches `narabe:leave` in the page, with the same
`detail`. A PubSub message, as in the [Collaboration](collaboration.md)
guide, does as well, and tells the other viewers too.

## Components and nested LiveViews

Each list sends to its own `phx-target`, so lists of a group may be in
different LiveComponents, or in LiveViews nested with `live_render`: the
move goes to the one it lands in, and `on_leave` to the one it left.

## What each list takes

A list's rules hold for the items of the others, with their kinds: a
list with `rules={[accepts: %{"root" => ["errand"]}]}` refuses a task as
people drag, as for its own items (see the [Rules](rules.md) guide).
Check the kinds on its server too.

`accept` names the lists a list takes items from; it takes from every
list of the group by default:

```heex
<.sortable_list id="archive" items={@archived} group="tasks" accept={["done"]} on_move="move" />
```

A drop on a list that does not take the items is refused: its line is
red, and the person hears why. Tab skips it.

## Refused

When the server of the list it landed in says no, the items go back to
the list they came from, where they were, and the person hears why. A
tree's item dropped in a list or a board goes with its children, unseen
there, and they come back with it.

## Collaboration

With Issho (`issho`), the people in the room of the list the items came
from see who holds them; those in the room of the list they would land
in see the line where they would drop them.

## In tests

`Narabe.Test.move/4` takes `from:`, and `Narabe.Test.leave/4` sends a
list's `on_leave`:

```elixir
move(view, "week", task.id, parent: launch.id, index: 0, from: "someday")
leave(view, "someday", task.id, "week")
```
