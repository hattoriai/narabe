# Known limits

What Narabe does not do yet, stated plainly. Each is a good first issue
to open.

* **No virtualization.** Every row of a list, a tree or a board is in the
  page, all the time. That is fine to a few thousand items; past that,
  show a page of them, or, in a tree, load children as rows open
  (`item_children`).
* **Trees are flat rows from the server.** The server renders a tree's
  loaded items as one flat run of rows, each with its level, and sends
  them again on a change. A big tree is a big render.
* **The filter is the browser's.** It finds the loaded items whose label
  has the text, as a plain substring; it does not ask the server, and it
  does not match words out of order or typos.
* **Rebalancing writes the whole scope.** When a key grows too long, or
  on `Narabe.Ecto.rebalance/3`, every key of the list, column or parent
  is written anew, not a window around the move: 10,000 rows take about
  a second on Postgres (see the [Database](database.md) guide).
* **Deep trees on MySQL.** MySQL stops a recursive query at 1,000 levels
  (`cte_max_recursion_depth`), so a tree deeper than that cannot be
  moved there.
* **Columns move by pointer only.** A board's columns move by the handle
  in their header; the keyboard moves cards, not columns.
* **Kinds per column, on the server.** `Narabe.Ecto` takes one kind for
  all of a board's columns (`:group_kind`); rules for columns of
  different kinds are checked in the browser only.
* **Boards take lists.** A board's columns and cards are lists, not
  streams: it renders again after a move.
* **Browsers.** The browser tests run in Chromium, Firefox and WebKit in
  CI. Touch is tested in Chromium's emulation only, not on phones
  themselves.
* **Screen readers.** The roles and announcements are tested in three
  browsers; not yet with VoiceOver, NVDA and JAWS themselves.
* **Forced colors.** There are no styles of their own for Windows' forced
  colors yet.
