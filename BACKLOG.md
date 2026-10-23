# Backlog

Known gaps in Narabe, each to become an issue.

## Rebalance a window

A key longer than `:rebalance_at` rewrites every key of its scope. A
window of the keys around it would be enough, and cost a few rows instead
of thousands (10,000 rows take 0.5 to 3 seconds today).

## Deep trees on Postgres

A move under the 900th level takes 62 ms on Postgres, against 5 to 13 ms
on SQLite and MySQL: the recursive CTE's plan, to look at.

## Virtual lists

Every row is in the page. Past a few thousand rows, a list should draw
only those on the screen, as Masu does, and drop between rows it has not
drawn.

## Undo

A person's own last moves, undone with Ctrl+Z, as the moves they were:
the app applies them as any other.

## Masu's rows

Masu reorders its rows itself, tuned for its size; it might share
Narabe's drag engine and keyboard, not its rendering.

## Canvas

Lists, trees and boards drawn on the family's canvas, with the same
moves and the same database helpers.

## Outlines

Editing in a tree: Enter makes a sibling, Tab indents, as an outliner
does (Kotoba's ground).

## Drags between lists

An item dragged from one list to another (a task to another project's
list), as one move with the other list as its parent.
