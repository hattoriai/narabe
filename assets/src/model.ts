// The items as the page has them: rows read from the DOM (the server
// renders them, flat, a tree's rows with their level and parent), and the
// shape of a tree among them.

/** An item of a list, a tree or a board. */
export interface Row {
  el: HTMLElement;
  id: string;
  kind: string;
  /** 1 at the top level; a list's and a board's items are all 1. */
  level: number;
  /** A tree item's parent id; a board card's column id; else null. */
  parent: string | null;
  /** Whether it has children, loaded or not (a tree). */
  children: boolean;
  label: string;
  locked: string | null;
}

/** A board's column. */
export interface Group {
  el: HTMLElement;
  /** The element that holds its items. */
  body: HTMLElement;
  id: string;
  kind: string;
  label: string;
}

export function readRow(el: HTMLElement): Row {
  const d = el.dataset;
  return {
    el,
    id: d.id ?? "",
    kind: d.kind || "item",
    level: Number(d.level ?? 1) || 1,
    parent: d.parent || null,
    children: d.children === "true",
    label: d.label || el.textContent?.trim() || d.id || "",
    locked: d.locked || null,
  };
}

/** The items of a container, in the page's order. */
export function rows(root: HTMLElement): Row[] {
  return Array.from(root.querySelectorAll<HTMLElement>("[data-narabe-item]")).map(readRow);
}

export function groups(root: HTMLElement): Group[] {
  return Array.from(root.querySelectorAll<HTMLElement>("[data-narabe-group]")).map((el) => ({
    el,
    body: el.querySelector<HTMLElement>("[data-narabe-group-body]") ?? el,
    id: el.dataset.id ?? "",
    kind: el.dataset.kind || "column",
    label: el.dataset.label || el.dataset.id || "",
  }));
}

/** The rows of a row's subtree, the row first (a tree's rows are flat, by level). */
export function subtree(all: Row[], index: number): Row[] {
  const level = all[index]!.level;
  let end = index + 1;
  while (end < all.length && all[end]!.level > level) end++;
  return all.slice(index, end);
}

/** How many levels a row's loaded subtree spans: 1 for a row with no children shown. */
export function height(all: Row[], index: number): number {
  const tree = subtree(all, index);
  return Math.max(...tree.map((r) => r.level)) - tree[0]!.level + 1;
}

/** The row's ancestors, its parent first. */
export function ancestors(all: Row[], index: number): Row[] {
  const out: Row[] = [];
  let level = all[index]!.level;
  for (let i = index - 1; i >= 0 && level > 1; i--) {
    if (all[i]!.level < level) {
      out.push(all[i]!);
      level = all[i]!.level;
    }
  }
  return out;
}
