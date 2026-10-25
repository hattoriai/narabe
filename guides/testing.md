# Testing

`Narabe.Test` moves, opens, renames, selects and picks in
`Phoenix.LiveViewTest`, with no browser. It reads the page with
LazyHTML, which a Phoenix 1.8 app has in its test deps; else add
`{:lazy_html, ">= 0.1.0", only: :test}`.

```elixir
import Narabe.Test

test "a card moves to Done", %{conn: conn} do
  {:ok, view, _html} = live(conn, ~p"/boards/#{board.id}")

  move(view, "sprint", card.id, parent: done.id, index: 0)
  assert_reply(view, %{ok: true})
  assert {"Done", ["Write the docs", "Ship"]} in columns(view, "sprint")
end
```

## Sending events

Each sends the list's own event, with the params the browser sends, to
the LiveView or the component of the list's `phx-target`, and gives the
rendered LiveView. The list's id may have a `#` in front.

* `move/4` sends `on_move`: the ids (one or a list) and `:after`,
  `:before`, `:parent` and `:index`, as in `Narabe.Move`. `columns: true`
  moves a board's columns; `:from`, the id of another list of the
  group, is a drop from it.
* `leave/4` sends `on_leave`: items that landed in another list of the
  group.
* `expand/3` sends `on_expand` for a tree item whose children are not
  loaded.
* `rename/4` sends `on_rename`.
* `select/3` sends `on_select`.
* `pick/3` picks an item of a tree picker: the form's `phx-change`, with
  the item's id. The form needs an `id`.

Each raises when the page has no list with that id, or the list has no
such event.

```elixir
move(view, "pages", blog.id, parent: docs.id, after: intro.id)
move(view, "pages", docs.id, parent: intro.id)
assert_reply(view, %{error: "into_itself"})

expand(view, "pages", archive.id)
rename(view, "pages", post.id, "Hello")
pick(view, "move_parent_id", folder.id)
```

`assert_reply/2` is LiveViewTest's: it checks the reply to the last
event.

## Reading the page

* `items/2` gives the labels of a list's items in order (a board's cards,
  a tree's loaded items).
* `outline/2` gives a tree's loaded items as `{label, level}`, the top
  level being 1.
* `columns/2` gives a board's columns as `{label, card labels}`.

```elixir
assert items(view, "tasks") == ["Task 2", "Task 3", "Task 1", "Task 4"]
assert outline(view, "pages") == [{"Docs", 1}, {"Intro", 2}, {"Blog", 2}]
```

A browser moves the items before the server answers; a test does not.
The page shows what the server renders next. A list in a stream is not
rendered again for the person who moved, so check the database instead:

```elixir
move(view, "todos", b.id, before: a.id)
assert Todo |> Narabe.Ecto.ordered() |> Repo.all() |> Enum.map(& &1.id) == [b.id, a.id]
```

## Without a LiveView

`Narabe.Move.apply/3` applies a move in memory, and
`Narabe.Move.to_params/1` gives the params of a move as the browser sends
them, for an event handler or an agent's tool:

```elixir
params = Narabe.Move.to_params(%Narabe.Move{ids: [42], after: 12})
{:ok, move} = Narabe.Move.parse(params, :id)
{:ok, moved} = Narabe.Move.apply(items, move)
```

`Narabe.Ecto` runs in the Ecto sandbox as any query does.

## In a browser

Narabe's own browser tests (`mix test.e2e`) run in Chromium, Firefox and
WebKit against the development pages (`mix dev`): drags, the keyboard,
refused moves, trees, the picker, a second viewer, and Issho. The phone
tests (a held finger, a swipe, one level at a time) run in Chromium only,
whose touch events they drive.
