# Changelog

All notable changes to Narabe are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Narabe follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Narabe.Ecto.Mixed`: a tree of several tables, as folders and the
  pages in them. Each kind keeps its table, its position and its parent
  field; a folder's children of every kind are one list in one order.
  Ids in the tree say their kind (`"folder:3"`), so `<.tree>` takes the
  items as `items/2` gives them, and `move/3` writes each moved row to
  its own table, with the checks of a tree (never into itself, the
  rules, `:max_depth` counting both kinds). `insert_position/4`,
  `put_position/4` and `rebalance/3` place new rows among their siblings
  of every kind. See the Trees guide, "A tree of several tables".

- The Sumi theme follows Sumi's seven themes and their accents: a
  refused drop is rose where the accent is red's hue or near it (Ink,
  Paper, Lacquer), and rust in Silk, so that it does not look like a drop
  let through; the filter's matches are sky blue in Stone, so that they
  do not look like a selected row. `mix dev` shows every page in each
  (`?sumi=smoke`). See the Theming guide.

### Fixed

- The Sumi theme gave Sumi's dark themes other than Ink the light
  palette, and Sumi's light themes other than Paper the dark one on a
  system in dark mode. A refused drop was below 3:1 on Smoke's columns.

## [0.1.0] - Unreleased

### Added

- The components, in `Narabe.Components`: `sortable_list/1` (a list, or
  a stream), `tree/1`, `board/1` (columns of cards, and columns that
  move) and `tree_picker/1` (a field of a form that chooses an item of a
  tree).
- A drag engine of its own, on pointer events: a mouse lifts an item
  after a few pixels, a finger after a short hold (a swipe still
  scrolls); a ghost follows the pointer; the page and the list scroll
  near their edges; Escape lets go. Items drag anywhere, or by a handle.
- The keyboard: the arrows, Home and End move the focus; Space lifts the
  focused item, the arrows (and Left and Right, for a tree's depth or a
  board's column) move it, Space drops it, Escape puts it back;
  Ctrl or Cmd with Shift and an arrow moves it one step at once.
- Several items selected (Shift, Ctrl or Cmd, Ctrl+A) move together, in
  their order.
- Trees: the depth from the pointer's left and right, a drop into a
  closed row at the end of its children, a closed row that opens when a
  drag is held over it, children loaded as a row opens (`on_expand`), a
  filter that keeps the matches' ancestors, rename in place (F2, a
  double click), and on a phone one level at a time (`phone={:drill}`).
- Swipe actions on a phone (`:actions` slot).
- Moves by ids (`Narabe.Move`): `parent`, `after`, `before`, and an
  index as a last resort. The browser moves the items at once, and puts
  them back when the server's reply is an error (`Narabe.Live.reply/1`).
  A drop where the items were sends nothing.
- `Narabe.Ecto`: fractional position keys (`Narabe.Position`, the same in
  Elixir and in the browser), a move as an `Ecto.Multi` step that writes
  the moved rows only, new rows' positions, rebalancing, reading in
  order, and a tree's ancestors and descendants through recursive CTEs;
  a move into itself is refused, and depth counted. An optional lock of
  the owner row (`:serialize`). The same code on Postgres, MySQL and
  SQLite, tested on all three, with a benchmark.
- `Narabe.Migration.position/2`, with the collation each database needs.
- `use Narabe.Ordered`: the order's options on the schema, and its rules
  for the components (`rules={Page}`).
- `Narabe.Rules`: nesting, the deepest level, kinds that hold nothing,
  what a parent accepts; refused in the browser as people drag, and on
  the server.
- `Narabe.Move.apply/3`: a move applied to items in memory.
- `Narabe.Tree.rows/2`: a tree's flat rows from items with a parent id.
- `Narabe.Live`: the reply to a move, `stream_move/4` for the other
  viewers of a stream, and `expand/4`, `reveal/3` and `select/3` from the
  server.
- `Narabe.Issho`, with Issho: the item each person is on, the items
  someone drags and where they would drop them, items held by one person
  at a time, and agents that pick items up and drag them as people
  watch, stopped by a pause.
- `Narabe.Test`: `move/4`, `expand/3`, `rename/4`, `select/3`, `pick/3`,
  `items/2`, `outline/2` and `columns/2` for `Phoenix.LiveViewTest`.
- Listbox and tree roles, levels and positions, and a live region that
  says what is lifted, where it would land and where it landed, in eight
  languages (`Narabe.Messages`).
- The style sheet, with `--narabe-*` custom properties, dark mode, and
  the Sumi theme (`narabe-sumi.css`).
- `mix narabe.install`.
