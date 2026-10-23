# Theming

Every color, space, radius and font of the lists, trees and boards comes
from a `--narabe-*` custom property. The defaults have no specificity, so
a value set on `:root`, on an ancestor or on `.narabe` itself wins:

```css
:root {
  --narabe-accent: #0f766e;
  --narabe-radius: 4px;
  --narabe-row-height: 2.5rem;
}
```

The defaults are Erabi's, so that a page with both looks like one thing.

## The properties

| | |
| --- | --- |
| Type | `--narabe-font`, `--narabe-font-size`, `--narabe-small`, `--narabe-line-height` |
| Colors | `--narabe-text`, `--narabe-muted`, `--narabe-background`, `--narabe-surface`, `--narabe-border`, `--narabe-accent`, `--narabe-accent-text`, `--narabe-refused`, `--narabe-hover`, `--narabe-selected`, `--narabe-match` |
| Shape | `--narabe-radius`, `--narabe-inner-radius`, `--narabe-row-height`, `--narabe-space`, `--narabe-indent` |
| Boards | `--narabe-column-width`, `--narabe-card-gap`, `--narabe-card-shadow` |
| Depth and motion | `--narabe-shadow`, `--narabe-transition` |

* `--narabe-accent` is the focus outline, the drop line and the swipe
  actions; `--narabe-refused` is the line of a drop that the rules
  refuse.
* `--narabe-hover` and `--narabe-selected` are the backgrounds of a row
  under the pointer and of a selected row; by default they mix the text
  or the accent into the background.
* `--narabe-match` marks the letters the filter matched (a CSS custom
  highlight, `::highlight(narabe-match)`).
* `--narabe-indent` is a tree's indent per level. A drag reads it too: a
  pointer that moves one indent sideways changes the level by one.
* `--narabe-shadow` is the shadow of the dragged copy; `--narabe-card-shadow`
  that of a board's cards.

Narabe sets `--narabe-level` on each row (its level in a tree) and
`--narabe-peer` on rows that other people are on (their color); use them
in your own rules, do not set them.

## Dark

The defaults are light, and dark under `data-theme="dark"` (the attribute
of Phoenix's themes) or the class `dark` on an ancestor. `narabe.css`
does not follow `prefers-color-scheme` by itself.

## Sumi

`narabe-sumi.css`, after `narabe.css`, maps every property to the Sumi
tokens of the page: its daisyUI theme colors, or the short `--sumi-*`
names (`--sumi-ink`, `--sumi-paper`, `--sumi-accent`, ...), or Sumi's own
palette when the page has none. Its palette is dark under
`data-theme="dark"`, and under a dark preference unless the page says
`data-theme="light"`.

## Touch

On a coarse pointer, rows are taller (`--narabe-row-height` is 2.75rem),
handles are larger, and a board's columns snap into place as it scrolls
sideways, each at most 85% of the screen wide. Swipe actions show on a
coarse pointer only.

## Reduced motion

With `prefers-reduced-motion`, the rows, the tree's arrows and the lines
of other people do not animate.

## Classes

| | |
| --- | --- |
| The whole | `.narabe`, with `.narabe-list`, `.narabe-tree`, `.narabe-board` or `.narabe-picker`; `.narabe-ready` once the hook mounts; `.narabe-moving` while an item is lifted; `.narabe-drilling` while a tree shows one level at a time |
| Rows | `.narabe-item`, `.narabe-content`, `.narabe-label`, `.narabe-handle`, `.narabe-toggle`, `.narabe-actions` |
| Row states | `.narabe-selected`, `.narabe-lifted`, `.narabe-locked`, `.narabe-context` (an ancestor shown by the filter), `.narabe-peer`, `.narabe-held` |
| Boards | `.narabe-columns`, `.narabe-column`, `.narabe-column-header`, `.narabe-column-title`, `.narabe-column-count`, `.narabe-column-body`, `.narabe-column-footer`, `.narabe-column-handle` |
| Drawn by the hook | `.narabe-indicator` (the drop line; `.narabe-indicator-inside`, `.narabe-indicator-vertical`, `.narabe-refused`), `.narabe-ghost` (the dragged copy) and `.narabe-count` (how many it carries), `.narabe-filter`, `.narabe-drill`, `.narabe-back`, `.narabe-drill-title`, `.narabe-rename`, `.narabe-peer-line`, `.narabe-peer-name` |

While a drag is on, the page's `<html>` has `.narabe-dragging`.
