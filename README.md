# Narabe

![Narabe — Lists, trees and boards for Phoenix](https://raw.githubusercontent.com/hattoriai/narabe/main/media/banner.png)

<p>
  <a href="https://hex.pm/packages/narabe">
    <img alt="Hex Version" src="https://img.shields.io/hexpm/v/narabe.svg">
  </a>
  <a href="https://hexdocs.pm/narabe">
    <img src="https://img.shields.io/badge/docs-hexdocs-blue" alt="HexDocs">
  </a>
  <a href="https://github.com/hattoriai/narabe/actions">
    <img alt="CI Status" src="https://github.com/hattoriai/narabe/actions/workflows/ci.yml/badge.svg">
  </a>
</p>

並べ (*narabe*): to line up, to put in order.

Lists, trees and boards that people reorder, for Phoenix LiveView, with
the order kept in your database through Ecto.

```heex
<.sortable_list id="tasks" items={@streams.tasks} on_move="move" multiple>
  <:item :let={task}>{task.title}</:item>
</.sortable_list>

<.tree id="pages" items={@pages} rules={Page} on_move="move" on_rename="rename" filter />

<.board id="sprint" columns={@columns} cards={@cards} on_move="move_card" move_columns>
  <:card :let={card}>{card.title}</:card>
</.board>
```

```elixir
def handle_event("move", params, socket) do
  result = Narabe.Ecto.move(Repo, where(Page, space_id: ^socket.assigns.space.id), Narabe.Move.parse!(params, Page))
  {:reply, Narabe.Live.reply(result), load_pages(socket)}
end
```

## What it does

- **A mouse, a finger, the keyboard.** A drag starts after a few pixels
  with a mouse, after a short hold with a finger (a swipe still scrolls),
  and with Space on the focused item (the arrows move it, Space drops it,
  Escape puts it back). The page scrolls near its edges. Several selected
  items move together. Its own drag engine on pointer events: no
  SortableJS, no HTML drag and drop.
- **Lists, trees and boards.** A tree nests as deep as you like, picks
  the depth from where the pointer is (or Left and Right), opens a
  closed folder under the pointer, loads children as it opens, filters,
  and renames in place. Its items may be rows of several tables, as
  folders and pages (`Narabe.Ecto.Mixed`). On a phone it can show one level at a time. A
  board moves cards within and across columns, and the columns too.
  Lists, trees and boards of a `group` take each other's items: a task
  to another project's list, a page into a folder of the sidebar.
- **Moves by ids.** A move says "after 12, in 7", not "to index 3", so a
  screen a moment out of date still means what the person meant. The
  browser moves the items at once, and puts them back if the server says
  no.
- **The order in the database.** `Narabe.Ecto` keeps fractional position
  keys: a move writes the moved rows only, in one transaction (an
  `Ecto.Multi`), whatever the size of the list. Trees use recursive CTEs
  to refuse a move into itself and to count depth. The same code on
  Postgres, MySQL and SQLite: a move in a list of 100,000 rows takes
  about a millisecond.
- **The same rules on both sides.** Depth, kinds that hold nothing, what
  a parent accepts: refused as people drag, and refused by the server.
- **Accessible.** Listbox and tree roles, levels and positions, a live
  region that says what was lifted, where it would go, and where it
  landed, in eight languages.
- **Collaboration.** With [Issho](https://hex.pm/packages/issho), people
  see who is dragging what and where it would land, an item is moved by
  one person at a time, and an agent picks a card up and drags it as
  people watch.

The bundle is 13 KB gzipped, the style sheet 4 KB.

## Install

Narabe needs Elixir 1.18 or later, Phoenix 1.7.14 or 1.8, Phoenix
LiveView 1.1 or later, and Ecto 3.13 or later (`ecto_sql` for the
database helpers).

```elixir
def deps do
  [
    {:narabe, "~> 0.2"}
  ]
end
```

```sh
mix deps.get
mix narabe.install
```

The installer adds the hook to `assets/js/app.js` and the style sheet to
`assets/css/app.css`, and prints what it changed (`--dry-run` shows it
first). By hand:

```js
import { Narabe } from "narabe"

const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, Narabe},
})
```

```css
@import "../../deps/narabe/priv/static/narabe.css";
/* @import "../../deps/narabe/priv/static/narabe-sumi.css"; */
```

`import { Narabe } from "narabe"` resolves through the `NODE_PATH` of your
esbuild profile, which must have `deps/` (the Phoenix generators set it).

## Use

A position column, and the order on the schema:

```elixir
# In a migration
import Narabe.Migration

create table(:pages) do
  add :title, :string
  add :parent_id, references(:pages)
  position()
end

create index(:pages, [:parent_id, :position])
```

```elixir
schema "pages" do
  field :title, :string
  field :position, :string
  belongs_to :parent, Page
end

use Narabe.Ordered, group: :parent_id, tree: true, rules: [max_depth: 6]
```

New rows get a position with `Narabe.Ecto.insert_position/4` (or
`put_position/4` in a changeset); `Narabe.Ecto.ordered/2` reads them in
order. See the [Database](guides/database.md) guide.

## Guides

* [Quickstart](guides/quickstart.md) - a first sortable list, step by step.
* [Lists](guides/lists.md) - `sortable_list`, streams, selection, swipe actions.
* [Trees](guides/trees.md) - nesting, depth, lazy children, filter, rename, phones, `tree_picker`.
* [Boards](guides/boards.md) - columns and cards, kanban.
* [Groups](guides/groups.md) - drags between lists, trees and boards.
* [Database](guides/database.md) - `Narabe.Ecto`: keys, moves, trees, Postgres, MySQL and SQLite, benchmarks.
* [Rules](guides/rules.md) - what may go where, in the browser and on the server.
* [Collaboration](guides/collaboration.md) - who is moving what, with Issho; agents.
* [Testing](guides/testing.md) - `Narabe.Test` in `Phoenix.LiveViewTest`.
* [Theming](guides/theming.md) - the custom properties, dark mode, Sumi.
* [Accessibility](guides/accessibility.md) - the keyboard and screen readers.
* [Known limits](guides/limits.md) - what Narabe does not do yet.

## Development

```sh
mix deps.get
mix narabe.build   # the bundle and the style sheets, into priv/static
mix dev            # a list, a tree, a board and a picker at http://localhost:4097
```

Every page of `mix dev` takes `theme=sumi` (and `dark=1`), or one of
Sumi's seven themes, `sumi=smoke` (the links under the menu).

### Tests

```sh
mix test                   # Elixir, on Postgres, MySQL and SQLite
NARABE_DBS=sqlite mix test # some of the databases (none: "none")
mix test --include build   # the build and the package
mix test.js                # the browser's keys, rules and drop places
mix test.e2e               # in Chromium, Firefox and WebKit
MIX_ENV=test mix run bench/ecto.exs  # the database benchmark
```

The tests expect Postgres at `postgres:postgres@localhost` and MySQL at
`narabe:narabe@127.0.0.1` (or `NARABE_POSTGRES_URL` and
`NARABE_MYSQL_URL`). The position keys and the rules that both the
server and the browser apply are tested on both sides with one fixture
each: `test/fixtures/position.json` and `test/fixtures/rules.json`.

### Release

`mix release` builds the bundle, checks `priv/static` and the version of
`package.json`, publishes to Hex and tags the version.

## Contributing

See [CONTRIBUTING.md](https://github.com/hattoriai/narabe/blob/main/CONTRIBUTING.md). Security problems:
[SECURITY.md](https://github.com/hattoriai/narabe/blob/main/SECURITY.md).

## License

MIT. See [LICENSE](https://github.com/hattoriai/narabe/blob/main/LICENSE) and [NOTICE](https://github.com/hattoriai/narabe/blob/main/NOTICE).
