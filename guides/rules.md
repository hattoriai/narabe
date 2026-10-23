# Rules

Rules say what may go where. They hold in the browser, as people drag (a
drop that breaks them is not offered), and on the server, as
`Narabe.Ecto` applies a move (one that breaks them is refused). Give both
the same rules by declaring them on the schema:

```elixir
use Narabe.Ordered,
  group: :parent_id,
  tree: true,
  kind: :kind,
  rules: [nest: true, max_depth: 6, leaves: ["file"]]
```

```heex
<.tree id="pages" items={@pages} item_kind={:kind} rules={Page} on_move="move" />
```

`rules={Page}` takes the rules from `use Narabe.Ordered`, so that the
browser and `Narabe.Ecto.move/4` agree. `rules` also takes a
`Narabe.Rules`, or its options.

| Rule | |
| --- | --- |
| `nest` | whether an item may hold others: a tree. A list's and a board's items do not nest |
| `max_depth` | the deepest level an item may be at, the top level being 1. A moved item's own children count: a page with two levels under it cannot go to the deepest level |
| `leaves` | the kinds of items that hold nothing (`["file"]`) |
| `accepts` | which kinds of items a kind of parent takes: `%{"section" => ["page"], "root" => ["section"]}`. `"root"` is the top level. A kind with no entry takes anything |

A tree's rules nest unless they say `nest: false`, in the component and
in `Narabe.Ecto` (`tree: true`); a list's and a board's do not.

## Kinds

An item's kind comes from `item_kind` in the component, and from the
`:kind` field on the server. An item without one is `"item"`. A board's
columns are parents of the kind `"column"` in the browser (or their
`column_kind`); see the [Boards](boards.md) guide for the server's
`:group_kind`.

```elixir
rules: [
  nest: true,
  accepts: %{"root" => ["folder"], "folder" => ["folder", "page"], "page" => ["page"]},
  leaves: ["file"]
]
```

## In the browser

While a person drags, a drop that breaks the rules shows its line in red
(`--narabe-refused`) and is not made: the items go back, and the person
hears why ("It would be nested too deep", "Folder can't hold it"). A
tree's rows that may not hold children have no middle zone to drop into.

## On the server

`Narabe.Ecto.move/4` checks the rules in the transaction, with the
database as it is, and refuses with `{:error, reason}`:

| Reason | |
| --- | --- |
| `:into_itself` | a tree item into itself or under itself |
| `:not_accepted` | a parent that holds nothing, or not this kind |
| `:too_deep` | past `max_depth` |
| `:not_found` | an item, or the new parent, is not in the queryable |

`Narabe.Live.reply/1` turns the reason into `%{error: "too_deep"}`. The
browser puts the items back and says "The move was not saved, and is
undone", with the reason for `too_deep` and `into_itself`.

The browser is a convenience: the server checks again, since an event
can come from anything. It also sees what the browser may not: children
that are not loaded, and the moves of other people.

## Rules of your own

Refuse a move for a reason of your app with a text. The person hears it:

```elixir
def handle_event("move", params, socket) do
  result =
    if socket.assigns.board.archived do
      {:error, "Archived boards don't change"}
    else
      Narabe.Ecto.move(Repo, Card, Narabe.Move.parse!(params, Card))
    end

  {:reply, Narabe.Live.reply(result), socket}
end
```

`Narabe.Rules.check/2` checks a move as the rules see it, for a check of
your own:

```elixir
rules = Narabe.Rules.new(nest: true, max_depth: 2)

Narabe.Rules.check(rules, %{
  kinds: ["page"],
  parent_kind: "page",
  parent_depth: 1,
  height: 2,
  into_itself: false
})
#=> {:error, :too_deep}
```

To keep one item in place, give it a reason with `item_locked` (see the
[Lists](lists.md) guide).

## The same answers

`assets/src/rules.ts` and `Narabe.Rules` answer every case of
`test/fixtures/rules.json` the same way.
