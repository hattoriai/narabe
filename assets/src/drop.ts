// Where dragged items would land: a gap between two rows (and, in a tree,
// a depth), or inside a row. The pointer and the keyboard both find a gap
// here, so they land the same way.
//
// A tree's rows are flat, each with its level. In the gap between row A
// (above) and row B (below), the depth may be from B's level (it cannot go
// under B's parent's level) to A's level + 1 (A's first child), and the
// pointer's x (or Left and Right) picks it. The rows being dragged, and
// their subtrees, are not among the rows here: nothing lands in itself.

import type { Row } from "./model";

/** A place to land. */
export interface Gap {
  /** The new parent (a tree row, or a board's column), or null at the top. */
  parent: string | null;
  after: string | null;
  before: string | null;
  /** The depth it lands at (1 at the top). */
  level: number;
  /** Its place among its new siblings (0 first), and how many there are with it. */
  index: number;
  count: number;
  /** The row above the gap, to draw the line under; or the row it goes into. */
  anchor: Row | null;
  /** "line" between rows, or "inside" a row (its end, children hidden). */
  shape: "line" | "inside";
}

/** The depths a gap allows: [min, max]. */
export function depths(rows: Row[], gap: number, nest: boolean): [number, number] {
  const a = rows[gap];
  const b = rows[gap + 1];
  const min = b ? b.level : 1;
  const max = a ? (nest ? a.level + 1 : a.level) : 1;
  return [Math.min(min, max), max];
}

/**
 * The place for a gap after `rows[gap]` (-1: before the first) at a depth,
 * clamped to what the gap allows. `group` is a board column's id.
 */
export function gapAt(rows: Row[], gap: number, depth: number, nest: boolean, group: string | null = null): Gap {
  const [min, max] = depths(rows, gap, nest);
  const level = Math.max(min, Math.min(max, depth));
  let parent: string | null = group;
  let after: string | null = null;
  let index = 0;

  // Up from the row above: the previous sibling, siblings before it, the parent.
  for (let i = gap; i >= 0; i--) {
    const row = rows[i]!;
    if (row.level < level) {
      if (level > 1) parent = row.id;
      break;
    }
    if (row.level === level) {
      if (after === null) after = row.id;
      index++;
    }
  }
  if (level === 1 && group === null) parent = null;

  // Down from the row below: the next sibling and those after it.
  let following = 0;
  let before: string | null = null;
  for (let i = gap + 1; i < rows.length; i++) {
    const row = rows[i]!;
    if (row.level < level) break;
    if (row.level === level) {
      if (before === null) before = row.id;
      following++;
    }
  }

  return { parent, after, before, level, index, count: index + following + 1, anchor: rows[gap] ?? null, shape: "line" };
}

/** Inside a row whose children are not shown: at the end of them. */
export function inside(row: Row): Gap {
  return { parent: row.id, after: null, before: null, level: row.level + 1, index: 0, count: 1, anchor: row, shape: "inside" };
}

/** The rows of a board's column, a list, or a tree, without the dragged ones and their subtrees. */
export function without(all: Row[], dragged: Set<string>): Row[] {
  const out: Row[] = [];
  let skipBelow = Infinity;
  for (const row of all) {
    if (row.level > skipBelow) continue;
    skipBelow = Infinity;
    if (dragged.has(row.id)) {
      skipBelow = row.level;
      continue;
    }
    out.push(row);
  }
  return out;
}

/** The gap a pointer at y is in: after the last row whose middle is above it. */
export function gapAtY(rows: Row[], rects: DOMRect[], y: number): number {
  for (let i = 0; i < rows.length; i++) {
    const r = rects[i]!;
    if (y < r.top + r.height / 2) return i - 1;
  }
  return rows.length - 1;
}

/**
 * In a tree: the row under the pointer and where in it. The top quarter is
 * the gap before it, the bottom quarter the gap after it, the middle is
 * inside it (when it may hold children); a row that may not hold children
 * splits at its middle.
 */
export function zoneAtY(rows: Row[], rects: DOMRect[], y: number, canHold: (row: Row) => boolean): { gap: number; into: Row | null } {
  for (let i = 0; i < rows.length; i++) {
    const r = rects[i]!;
    if (y > r.bottom) continue;
    const t = (y - r.top) / Math.max(1, r.height);
    if (!canHold(rows[i]!)) return { gap: t < 0.5 ? i - 1 : i, into: null };
    if (t < 0.25) return { gap: i - 1, into: null };
    if (t > 0.75) return { gap: i, into: null };
    return { gap: i, into: rows[i]! };
  }
  return { gap: rows.length - 1, into: null };
}
