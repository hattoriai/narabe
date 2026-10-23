# Changelog

All notable changes to Narabe are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Narabe follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
