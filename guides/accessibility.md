# Accessibility

Everything a pointer does, the keyboard does too: lift, move, change the
level, change the column, drop, put back, select several, open and close,
rename and pick. A screen reader hears each step.

## Roles

* A list is a `listbox`, its items `option`s. With `multiple`, the list
  has `aria-multiselectable` and each item `aria-selected`; with
  `on_select`, too.
* A tree is a `tree`, its items `treeitem`s with `aria-level`,
  `aria-posinset` and `aria-setsize` among their siblings, and
  `aria-expanded` on the items with children. An item whose children are
  loading is `aria-busy`.
* A board is a `group`. Each column is a section named by its header, and
  its cards are a `listbox` of `option`s.
* A tree picker is a tree whose items have `aria-selected`; the items that
  cannot be picked are `aria-disabled`.
* `label` names the whole list, tree or board. Each item's name for the
  announcements is its label (`item_label`).

One item takes the Tab at a time (a roving `tabindex`): the focused one,
else the first selected, else the first shown.

## Keys

| Key | |
| --- | --- |
| ↓ ↑ | the next, the previous item |
| Home, End | the first, the last item |
| → | a tree: open the item, or go to its first child; a board: the next column |
| ← | a tree: close the item, or go to its parent; a board: the previous column |
| Space | lift the item (and the others selected); in a picker, pick it |
| Enter | in a picker, pick the item |
| Shift+↓ ↑ | extend the selection (`multiple`) |
| Ctrl+A, Cmd+A | select all the items shown (`multiple`) |
| Escape | clear the selection |
| Ctrl+Shift+arrows, Cmd+Shift+arrows | move the item one step, without lifting it |
| F2 | rename (`on_rename`) |

While an item is lifted:

| Key | |
| --- | --- |
| ↓ ↑ | the next, the previous gap |
| Home, End | the first, the last gap |
| → ← | a tree: one level deeper, one level up; a board: the next, the previous column |
| Space, Enter | drop |
| Escape | put it back |
| Tab, Shift+Tab | in a `group`: to the next, the previous list of it; else put it back, and move on |

Focus that leaves the list puts a lifted item back. A list without
`on_move`, or `readonly`, does not lift: Space toggles the selection
with `multiple`.

## Announcements

A live region says what happens, in the words of the list's `locale`:

* "Roadmap lifted. Arrows move it, Space drops it, Escape puts it back.",
  and, in a `group`, "Tab takes it to another list."
* "Roadmap, in Projects, 2 of 3" as it moves, and "Roadmap dropped, 2 of
  3".
* "Roadmap is back in its place" when it is put back.
* Why a place is refused: "It can't go there: It would be nested too
  deep".
* "The move was not saved, and is undone" when the server says no, with
  its reason.
* How many items the filter shows, or "No matches"; how many are
  selected; a row opened or closed.

The words are in English, Portuguese, Spanish, French, German, Italian,
Dutch and Japanese; numbers are formatted by the browser for the locale.
A locale with a region (`pt-BR`) takes its language's words; another
language gets English. `messages` changes words by the keys of
`Narabe.Messages.keys/0`, and the config sets them for every list:

```elixir
config :narabe, messages: %{"fr" => %{"dragHandle" => "Glisser pour déplacer"}}
```

## The pointer and touch

A mouse lifts an item once it moves a few pixels, so a click stays a
click. A finger lifts it after a short hold, so a swipe still scrolls the
page; the phone vibrates briefly where it can. On a touch screen rows
are 2.75rem tall. Escape during a drag lets go and nothing moves.

## Motion and color

With `prefers-reduced-motion`, rows and arrows do not animate. A refused
drop is shown by its red line and said in words: color is never the only
sign.

## Tested

`mix test.e2e` checks the roles, levels, focus and announcements in
Chromium, Firefox and WebKit. Not tested yet: screen readers themselves
(see [Known limits](limits.md)).
