# Trees

`tree/1` is a tree that people reorder and nest: pages, folders and
files, an outline. `tree_picker/1` chooses a place in a tree, in a form.

```heex
<.tree id="pages" items={@pages} item_label={:title} item_kind={:kind} rules={Page} on_move="move" filter label="Pages" />
```

## The items

`items` is flat, as the database has it: each item with its parent's id
(`item_parent`, `:parent_id` by default), in their order. Read them with
`Narabe.Ecto.ordered/2` and the tree shows each under its parent
(`Narabe.Tree.rows/2`). An item whose parent is not among the items is at
the top, so a tree may show one branch, or the levels loaded so far.

The schema says that its group is its parent:

```elixir
defmodule MyApp.Docs.Page do
  use Ecto.Schema

  schema "pages" do
    field :title, :string
    field :kind, :string
    field :position, :string
    belongs_to :parent, __MODULE__
  end

  use Narabe.Ordered,
    group: :parent_id,
    tree: true,
    kind: :kind,
    rules: [nest: true, max_depth: 6, leaves: ["file"]]
end
```

`rules={Page}` gives the tree the same rules as `Narabe.Ecto` (see the
[Rules](rules.md) guide). A tree's rules nest when none are given.

## The move

A move's `"parent"` is the new parent's id, or nil at the top level. The
item's subtree moves with it. The LiveView applies it as a list's:

```elixir
def handle_event("move", params, socket) do
  result = Narabe.Ecto.move(Repo, Page, Narabe.Move.parse!(params, Page))
  {:reply, Narabe.Live.reply(result), load_pages(socket)}
end
```

`Narabe.Ecto` refuses a move into the item itself or under it
(`:into_itself`), and checks the rules. In memory,
`Narabe.Move.apply(pages, move, group: :parent_id, tree: true)` does the
same.

## Where a drop lands

With a pointer, the top quarter of a row is the gap before it, the bottom
quarter the gap after it, and the middle is inside it, when it may hold
children. A drop inside a closed row puts the items at the end of its
children. In a gap, moving the pointer left and right picks the depth,
one indent (`--narabe-indent`) per level, between what the rows above
and below allow.

With the keyboard, Space lifts, Up and Down pick the gap, Right goes one
level deeper and Left one level up, Space drops.

## Opening and closing

Rows open and close with a click on their arrow, or Right and Left.
`expanded` gives the ids open at first. From the server,
`Narabe.Live.expand/4` opens or closes rows, and `Narabe.Live.reveal/3`
opens a row's ancestors, scrolls to it and focuses it.

## Children loaded as they open

`item_children` says which items have children that are not loaded yet
(a key or a function). Such an item shows an arrow; as it opens, the
tree sends `on_expand` with `%{"v" => 1, "id" => id}` and shows a
spinner until its children are in `items`:

```heex
<.tree id="pages" items={@pages} item_children={:has_children} on_expand="expand" on_move="move" />
```

```elixir
def handle_event("expand", %{"id" => id}, socket) do
  children = Page |> where(parent_id: ^id) |> Narabe.Ecto.ordered() |> Repo.all()
  {:noreply, update(socket, :pages, &(&1 ++ children))}
end
```

Order matters only among siblings: the children may come after the rest.

## Filter

With `filter`, a box above the tree shows the items whose label has the
text (case and accents do not count), with their ancestors dimmed for
context. The matched letters are marked. Nothing moves while the box has
text. Only the loaded items are searched.

## Rename

With `on_rename`, F2 or a double click on a label opens a box in place.
Enter or leaving the box saves, Escape cancels. The tree shows the new
name at once and sends `%{"v" => 1, "id" => id, "name" => name}`:

```elixir
def handle_event("rename", %{"id" => id, "name" => name}, socket) do
  page = Repo.get!(Page, id)
  {:ok, _} = page |> Ecto.Changeset.change(title: name) |> Repo.update()
  {:noreply, load_pages(socket)}
end
```

With an `item` slot of your own, mark the element of the label with
`data-narabe-label`, so the rename box and the filter's marks find it:

```heex
<:item :let={page}>
  <.icon name={icon(page)} />
  <span data-narabe-label>{page.title}</span>
</:item>
```

## On a phone

A tree shows as a tree on a phone. With `phone={:drill}`, on a touch
screen 640 px wide or less, it shows one level at a time: a tap on a row
with children opens its level, and a bar at the top goes back. A held
finger reorders the items within the level shown.

## The tree picker

`tree_picker/1` is a field of a form that chooses an item of a tree: a
folder, a parent page, a category. It posts the item's id, as a
`<select>` would:

```heex
<.form for={@form} id="move-form" phx-change="validate" phx-submit="save">
  <.tree_picker field={@form[:parent_id]} items={@folders} item_label={:title} disabled={[@page.id]} label="Folder" />
</.form>
```

A click, Space or Enter picks an item. `disabled` ids, and the items
under them, show and cannot be picked (the page being moved, so it does
not go into itself). The chosen item's ancestors are open at first,
unless `expanded` says otherwise. The picker filters by default
(`filter={false}` turns it off) and drills on a phone by default
(`phone={:tree}` shows the tree). Nothing drags in a picker. It
dispatches `narabe:pick` in the page, with the id in its `detail`.

## The tree in the database

`Narabe.Ecto.ancestors/4` gives an item's ancestors' ids, parent first;
`Narabe.Ecto.descendants/4` its descendants' ids. Each is one recursive
query. See the [Database](database.md) guide.

## A tree of several tables

Folders and the pages in them, sections and their lessons: often each
kind of item has its own table. `Narabe.Ecto.Mixed` makes one tree of
them, in which a folder's children, folders and pages alike, are one
list in one order:

```elixir
tree =
  Narabe.Ecto.Mixed.new(
    [
      folder: [from: where(Folder, space_id: ^space.id), parent: :parent_id],
      page: [from: where(Page, space_id: ^space.id), parent: :folder_id]
    ],
    parents: :folder,
    rules: [max_depth: 3]
  )
```

Each table has its position column (`Narabe.Migration.position/2`) and
its parent field; the folders' parent is a folder, and the pages' too.
The kinds other than `parents:` hold nothing. An item's id in the tree
is its kind and its key, `"folder:3"` or `"page:9"`, so the tree takes
the items as `Narabe.Ecto.Mixed.items/2` gives them, with their kind:

```heex
<.tree
  id="pages"
  items={@items}
  item_kind={:kind}
  item_label={&(&1.record.title || &1.record.name)}
  rules={@tree.rules}
  on_move="move"
>
  <:item :let={item}>{item.record.title || item.record.name}</:item>
</.tree>
```

and a move comes back to `Narabe.Ecto.Mixed.move/3`, which writes each
moved row to its own table:

```elixir
def handle_event("move", params, socket) do
  tree = socket.assigns.tree
  result = Narabe.Ecto.Mixed.move(Repo, tree, Narabe.Move.parse!(params))
  {:reply, Narabe.Live.reply(result), assign(socket, items: Narabe.Ecto.Mixed.items(Repo, tree))}
end
```

A new row gets its place among its siblings of every kind with
`Narabe.Ecto.Mixed.put_position/4` (or `insert_position/4`).
