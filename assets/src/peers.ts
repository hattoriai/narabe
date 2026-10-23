// Others moving things (Narabe.Issho): the item each person is on, the
// items someone drags, marked in their color with their name, and the
// line where they would drop them; and the items they hold, which this
// person cannot lift meanwhile. The server says who is where
// ("narabe:people"); this draws it, and tells the server where this
// person is ("narabe:place").

import { rows, type Row } from "./model";

/** A place in a list, as Narabe.Issho has it. */
export interface Place {
  item?: string;
  count?: number;
  drag?: { parent: string | null; after: string | null; before: string | null; level: number | null };
  /** The dragged items' ids, for their lock (not shared as the place). */
  items?: string[];
}

export interface Person {
  key: string;
  name: string;
  color: string;
  kind: "human" | "agent";
  at: Place;
}

export type Held = Record<string, { key: string; name: string; color: string; kind?: string }>;

export class Peers {
  private people: Person[] = [];
  private held: Held = {};
  private marks: HTMLElement[] = [];
  private last = "";
  private timer: ReturnType<typeof setTimeout> | null = null;

  constructor(
    private el: HTMLElement,
    private chrome: HTMLElement,
    private send: ((at: Place | null) => void) | null,
    private indent: () => number,
    private tree: () => boolean,
  ) {}

  /** Who else is in the list, and who holds what. */
  set(people: Person[], held: Held): void {
    this.people = people;
    this.held = held;
    this.draw();
  }

  /** The person who holds one of these items, if someone else does. */
  holder(ids: string[]): string | null {
    for (const id of ids) if (this.held[id]) return this.held[id]!.name;
    return null;
  }

  /** Where this person is: told at most every 80 ms, and only when it changes. */
  tell(at: Place | null): void {
    if (!this.send) return;
    const json = JSON.stringify(at);
    if (json === this.last) return;
    this.last = json;
    if (this.timer) clearTimeout(this.timer);
    this.timer = setTimeout(() => this.send?.(at), 80);
  }

  /** Draws the others again: after the server's render, the rows moved. */
  draw(): void {
    for (const mark of this.marks) mark.remove();
    this.marks = [];
    const all = rows(this.el);
    const byId = new Map(all.map((r) => [r.id, r]));
    for (const row of all) {
      row.el.classList.remove("narabe-peer", "narabe-held");
      row.el.style.removeProperty("--narabe-peer");
      row.el.removeAttribute("data-narabe-peer");
    }
    for (const [id, who] of Object.entries(this.held)) {
      const row = byId.get(id);
      if (!row) continue;
      row.el.classList.add("narabe-held");
      row.el.style.setProperty("--narabe-peer", who.color);
      row.el.setAttribute("data-narabe-peer", who.name);
    }
    for (const person of this.people) {
      const row = person.at.item ? byId.get(person.at.item) : undefined;
      if (row && !row.el.hidden) {
        row.el.classList.add("narabe-peer");
        row.el.style.setProperty("--narabe-peer", person.color);
        row.el.setAttribute("data-narabe-peer", person.name);
      }
      if (person.at.drag) this.line(person, byId, all);
    }
  }

  // A person's drop line, in their color, with their name.
  private line(person: Person, byId: Map<string, Row>, all: Row[]): void {
    const box = this.el.getBoundingClientRect();
    const rect = this.gapRect(person.at.drag!, byId, all);
    if (!rect) return;
    const line = document.createElement("div");
    line.className = `narabe-peer-line${rect.inside ? " narabe-peer-inside" : ""}`;
    line.style.setProperty("--narabe-peer", person.color);
    Object.assign(line.style, {
      left: `${rect.left - box.left}px`,
      top: `${rect.top - box.top}px`,
      width: `${rect.width}px`,
      height: rect.inside ? `${rect.height}px` : "",
    });
    const name = document.createElement("span");
    name.className = "narabe-peer-name";
    name.textContent = person.at.count && person.at.count > 1 ? `${person.name} · ${person.at.count}` : person.name;
    line.append(name);
    line.setAttribute("aria-hidden", "true");
    this.chrome.append(line);
    this.marks.push(line);
  }

  private gapRect(drag: NonNullable<Place["drag"]>, byId: Map<string, Row>, all: Row[]): { left: number; top: number; width: number; height: number; inside: boolean } | null {
    const visible = (id: string | null) => {
      const row = id ? byId.get(id) : undefined;
      return row && !row.el.hidden ? row : undefined;
    };
    const after = visible(drag.after);
    const before = visible(drag.before);
    const parent = drag.parent ? byId.get(drag.parent) : undefined;
    const column = drag.parent ? this.el.querySelector<HTMLElement>(`[data-narabe-group][data-id="${CSS.escape(drag.parent)}"] [data-narabe-group-body]`) : null;
    const body = (column ?? this.el.querySelector<HTMLElement>("[data-narabe-body]") ?? this.el).getBoundingClientRect();
    const level = drag.level ?? (parent ? parent.level + 1 : after?.level ?? before?.level ?? 1);
    const indent = this.tree() ? (level - 1) * this.indent() : 0;
    let y: number;
    if (after) {
      // Below the row and the rows shown under it.
      const index = all.indexOf(after);
      let last = after;
      for (let i = index + 1; i < all.length && all[i]!.level > after.level; i++) if (!all[i]!.el.hidden) last = all[i]!;
      y = last.el.getBoundingClientRect().bottom;
    } else if (before) {
      y = before.el.getBoundingClientRect().top;
    } else if (parent && !parent.el.hidden) {
      const r = parent.el.getBoundingClientRect();
      return { left: r.left, top: r.top, width: r.width, height: r.height, inside: true };
    } else {
      y = body.top + 4;
    }
    // Within what shows of the list (a board scrolls sideways).
    const shown = (this.el.querySelector<HTMLElement>("[data-narabe-body]") ?? this.el).getBoundingClientRect();
    const left = Math.max(body.left + indent, shown.left);
    const right = Math.min(body.right, shown.right);
    return { left, top: y - 1, width: Math.max(24, right - left), height: 0, inside: false };
  }

  /**
   * Issho's pointers, through the symbols it reads (no import of it): a
   * place is where its item, or its drop line, is on this screen; a
   * person's pointer over an item is that item.
   */
  share(): () => void {
    const element = this.el as unknown as Record<symbol, unknown>;
    const locator = (at: unknown) => this.locate((typeof at === "object" && at !== null ? at : {}) as Place);
    const pointer = (x: number, y: number) => {
      const row = document.elementFromPoint(x, y)?.closest<HTMLElement>("[data-narabe-item]");
      return row && this.el.contains(row) ? { item: row.dataset.id } : null;
    };
    element[Symbol.for("issho.locator")] = locator;
    element[Symbol.for("issho.point")] = pointer;
    return () => {
      if (element[Symbol.for("issho.locator")] === locator) delete element[Symbol.for("issho.locator")];
      if (element[Symbol.for("issho.point")] === pointer) delete element[Symbol.for("issho.point")];
    };
  }

  private locate(at: Place): DOMRect | null {
    const all = rows(this.el);
    const byId = new Map(all.map((r) => [r.id, r]));
    if (at.drag) {
      const r = this.gapRect(at.drag, byId, all);
      if (r) return new DOMRect(r.left, r.top, r.width, Math.max(2, r.height));
    }
    const row = at.item ? byId.get(at.item) : undefined;
    return (row && !row.el.hidden ? row.el : this.el).getBoundingClientRect();
  }

  destroy(): void {
    if (this.timer) clearTimeout(this.timer);
    for (const mark of this.marks) mark.remove();
  }
}
