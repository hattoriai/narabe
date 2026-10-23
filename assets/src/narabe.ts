// A list, a tree, a board or a tree picker: the items the server rendered,
// and what people do with them. Focus moves with the arrows; Space lifts
// the focused item (and the others selected), the arrows move it, Space
// drops it, Escape puts it back; a pointer drags it; a drop moves the
// items in the page at once and tells the server, which may say no, and
// then they go back. A tree expands and collapses, loads its children as
// it opens, filters, and renames in place; on a phone it may show one
// level at a time.

import { readConfig, Words, type Config } from "./config";
import { DragSession, startsDrag } from "./drag";
import { gapAt, gapAtY, inside, without, zoneAtY, type Gap } from "./drop";
import { ancestors, groups, height, readRow, rows, subtree, type Group, type Row } from "./model";
import { Peers, type Held, type Person, type Place } from "./peers";
import { check, type Refusal } from "./rules";

export interface Transport {
  push(event: string, payload: object, onReply?: (reply: Record<string, unknown>) => void): void;
  /** To another element's component (Narabe.Issho's room). */
  pushTo?(target: string, event: string, payload: object): void;
}

/** A drop, worked out: where, and whether the rules allow it. */
interface Target {
  gap: Gap;
  rows: Row[];
  group: Group | null;
  refusal: Refusal | null;
}

/** Where moved elements were, to put them back. */
interface Snapshot {
  el: HTMLElement;
  parent: Node;
  next: Node | null;
  level: string | undefined;
  parentId: string | undefined;
}

const PHONE = "(pointer: coarse) and (max-width: 640px)";
const SR = "position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap";

export class Narabe {
  readonly id: string;
  private el: HTMLElement;
  private transport: Transport | null;
  private config: Config;
  private words: Words;
  private chrome: HTMLElement;
  private live: HTMLElement;
  private line: HTMLElement;
  private expanded = new Set<string>();
  private selected = new Set<string>();
  private anchor: string | null = null;
  private focusId: string | null = null;
  private session: DragSession | null = null;
  private dragging: string[] = [];
  private target: Target | null = null;
  private lifted: { ids: string[]; gap: number; level: number; group: number; snapshot: Snapshot[] } | null = null;
  private query = "";
  private drillAt: string | null = null;
  private renaming: HTMLInputElement | null = null;
  /** The item to keep focused through the server's render after a keyboard move. */
  private refocus: string | null = null;
  private cleanups: (() => void)[] = [];
  private peers: Peers;

  constructor(el: HTMLElement, transport: Transport | null) {
    this.el = el;
    this.transport = transport;
    this.config = readConfig(el);
    this.id = this.config.id ?? el.id;
    this.words = new Words(this.config.messages ?? {}, this.config.locale ?? "en");
    this.chrome = el.querySelector<HTMLElement>("[data-narabe-chrome]") ?? el;
    this.live = document.createElement("div");
    this.live.setAttribute("aria-live", "assertive");
    this.live.setAttribute("style", SR);
    this.line = document.createElement("div");
    this.line.className = "narabe-indicator";
    this.line.hidden = true;
    this.chrome.append(this.live, this.line);
    for (const row of rows(el)) if (row.el.dataset.expanded === "true") this.expanded.add(row.id);
    if (this.config.value) this.selected.add(this.config.value);
    const room = this.config.issho?.target;
    this.peers = new Peers(
      el,
      this.chrome,
      room && transport?.pushTo ? (at) => transport.pushTo!(room, "narabe:place", { at }) : null,
      () => this.indent(),
      () => this.tree && !this.drilling,
    );
    if (room) this.cleanups.push(this.peers.share());
    this.buildChrome();
    this.listen();
    this.update();
    el.classList.add("narabe-ready");
  }

  private get tree(): boolean {
    return this.config.kind === "tree" || this.config.kind === "picker";
  }

  private get board(): boolean {
    return this.config.kind === "board";
  }

  private get canMove(): boolean {
    return !!this.config.onMove && !this.config.readonly && this.config.kind !== "picker" && this.query === "";
  }

  private get drilling(): boolean {
    return this.tree && this.config.phone === "drill" && typeof matchMedia === "function" && matchMedia(PHONE).matches;
  }

  // -- The page's state, applied after every render of the server ----------

  /** The server rendered again: the rows' state, as this list keeps it. */
  update(): void {
    this.config = readConfig(this.el);
    const all = rows(this.el);
    // An item moved with the keyboard keeps the focus, even when the server's
    // render made it anew (a card in another column).
    if (this.refocus) {
      const row = all.find((r) => r.id === this.refocus);
      const lost = !document.activeElement || document.activeElement === document.body || !document.activeElement.isConnected;
      if (row && lost) {
        this.focusId = row.id;
        queueMicrotask(() => row.el.focus({ preventScroll: true }));
      }
    }
    const ids = new Set(all.map((r) => r.id));
    for (const id of this.selected) if (!ids.has(id) && id !== this.config.value) this.selected.delete(id);
    this.applyVisibility(all);
    this.applySelection(all);
    this.applyFocus(all);
    this.renderDrill(all);
    this.peers.draw();
  }

  /** The others in the list, and who holds what (Narabe.Issho's "narabe:people"). */
  setPeers(people: Person[], held: Held): void {
    this.peers.set(people, held);
  }

  // Where this person is, for the others: the items they drag and where to, or the item they are on.
  private tellPlace(): void {
    if (this.dragging.length && this.target && !this.target.refusal) {
      const gap = this.target.gap;
      const place: Place = {
        item: this.dragging[0],
        count: this.dragging.length,
        items: this.dragging,
        drag: { parent: gap.parent, after: gap.shape === "inside" ? null : gap.after, before: gap.shape === "inside" ? null : gap.before, level: this.tree ? gap.level : null },
      };
      this.peers.tell(place);
    } else if (this.dragging.length) {
      this.peers.tell({ item: this.dragging[0], count: this.dragging.length, items: this.dragging });
    } else {
      const focused = (document.activeElement as HTMLElement | null)?.closest?.<HTMLElement>("[data-narabe-item]");
      this.peers.tell(focused && this.el.contains(focused) ? { item: focused.dataset.id! } : null);
    }
  }

  private applyVisibility(all: Row[]): void {
    const filtering = this.query !== "";
    const keep = filtering ? this.matches(all) : null;
    // A row shows when its ancestors are expanded (and, filtering, it or a descendant matches).
    const open: boolean[] = [];
    for (let i = 0; i < all.length; i++) {
      const row = all[i]!;
      open.length = row.level - 1;
      let shown = open.every(Boolean);
      if (filtering) shown = keep!.has(row.id);
      if (this.drilling && !this.query) shown = row.parent === this.drillAt;
      row.el.hidden = !shown;
      row.el.classList.toggle("narabe-context", filtering && shown && !keep!.get(row.id));
      if (this.tree) {
        const expanded = filtering || this.expanded.has(row.id);
        open[row.level - 1] = expanded;
        row.el.style.setProperty("--narabe-level", String(this.drilling ? 1 : row.level));
        if (row.children) row.el.setAttribute("aria-expanded", String(expanded && !this.drilling));
        else row.el.removeAttribute("aria-expanded");
        const loaded = all[i + 1] !== undefined && all[i + 1]!.level > row.level;
        row.el.toggleAttribute("aria-busy", this.expanded.has(row.id) && row.children && !loaded && !!this.config.onExpand);
      }
    }
  }

  /** The rows that match the filter (true) or are an ancestor of one (false). */
  private matches(all: Row[]): Map<string, boolean> {
    const needle = fold(this.query);
    const keep = new Map<string, boolean>();
    all.forEach((row, i) => {
      if (!fold(row.label).includes(needle)) return;
      keep.set(row.id, true);
      for (const a of ancestors(all, i)) if (!keep.has(a.id)) keep.set(a.id, false);
    });
    this.highlight(all, needle, keep);
    return keep;
  }

  // The matched letters, marked without touching the server's markup.
  private highlight(all: Row[], needle: string, keep: Map<string, boolean>): void {
    const registry = (globalThis as unknown as { CSS?: { highlights?: Map<string, unknown> } }).CSS?.highlights;
    const HighlightCtor = (globalThis as unknown as { Highlight?: new (...r: Range[]) => unknown }).Highlight;
    if (!registry || !HighlightCtor) return;
    const ranges: Range[] = [];
    if (needle) {
      for (const row of all) {
        if (!keep.get(row.id)) continue;
        const label = row.el.querySelector("[data-narabe-label]") ?? row.el;
        const walker = document.createTreeWalker(label, NodeFilter.SHOW_TEXT);
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
          const at = fold(node.textContent ?? "").indexOf(needle);
          if (at < 0) continue;
          const range = document.createRange();
          range.setStart(node, at);
          range.setEnd(node, at + needle.length);
          ranges.push(range);
          break;
        }
      }
    }
    registry.set(`narabe-match`, new HighlightCtor(...ranges));
  }

  private applySelection(all: Row[]): void {
    for (const row of all) {
      const on = this.selected.has(row.id);
      if (this.config.multiple || this.config.kind === "picker" || this.config.onSelect) row.el.setAttribute("aria-selected", String(on));
      row.el.classList.toggle("narabe-selected", on);
    }
  }

  // One row takes the Tab (roving focus): the focused one, else the first shown.
  private applyFocus(all: Row[]): void {
    const shown = all.filter((r) => !r.el.hidden);
    const focus = shown.find((r) => r.id === this.focusId) ?? shown.find((r) => this.selected.has(r.id)) ?? shown[0];
    for (const row of all) row.el.tabIndex = row === focus ? 0 : -1;
  }

  // -- Chrome: the parts this list draws itself -------------------------------

  private filterInput: HTMLInputElement | null = null;
  private drillBar: HTMLElement | null = null;

  private buildChrome(): void {
    if (this.el.dataset.filter === "true") {
      this.filterInput = document.createElement("input");
      this.filterInput.type = "search";
      this.filterInput.className = "narabe-filter";
      this.filterInput.placeholder = this.words.t("filter");
      this.filterInput.setAttribute("aria-label", this.words.t("filter"));
      this.filterInput.addEventListener("input", () => {
        this.query = this.filterInput!.value.trim();
        this.update();
        const shown = rows(this.el).filter((r) => !r.el.hidden).length;
        this.say(shown ? this.words.count("items", shown) : this.words.t("noMatches"));
      });
      this.chrome.prepend(this.filterInput);
    }
    if (this.tree && this.config.phone === "drill") {
      this.drillBar = document.createElement("div");
      this.drillBar.className = "narabe-drill";
      this.chrome.prepend(this.drillBar);
    }
  }

  private renderDrill(all: Row[]): void {
    if (!this.drillBar) return;
    this.drillBar.hidden = !this.drilling;
    this.el.classList.toggle("narabe-drilling", this.drilling);
    if (!this.drilling) return;
    const at = all.find((r) => r.id === this.drillAt);
    this.drillBar.replaceChildren();
    if (at) {
      const back = document.createElement("button");
      back.type = "button";
      back.className = "narabe-back";
      const parent = all.find((r) => r.id === at.parent);
      back.textContent = `‹ ${parent ? parent.label : this.words.t("topLevel")}`;
      back.setAttribute("aria-label", `${this.words.t("back")}: ${parent ? parent.label : this.words.t("topLevel")}`);
      back.addEventListener("click", () => this.drill(at.parent));
      const title = document.createElement("div");
      title.className = "narabe-drill-title";
      title.textContent = at.label;
      this.drillBar.append(back, title);
    }
  }

  private drill(id: string | null): void {
    this.drillAt = id;
    if (id) this.expand(id, true);
    this.update();
    rows(this.el).find((r) => !r.el.hidden)?.el.focus();
  }

  // -- Events -------------------------------------------------------------------

  private listen(): void {
    const on = <K extends keyof HTMLElementEventMap>(type: K, fn: (e: HTMLElementEventMap[K]) => void) => {
      this.el.addEventListener(type, fn as EventListener);
      this.cleanups.push(() => this.el.removeEventListener(type, fn as EventListener));
    };
    on("pointerdown", (e) => this.pointerDown(e));
    on("click", (e) => this.click(e));
    on("dblclick", (e) => {
      const label = (e.target as Element).closest<HTMLElement>("[data-narabe-label]");
      const row = label?.closest<HTMLElement>("[data-narabe-item]");
      if (row && this.config.onRename) this.rename(readRow(row));
    });
    on("keydown", (e) => this.key(e));
    on("focusin", (e) => {
      const row = (e.target as Element).closest<HTMLElement>("[data-narabe-item]");
      if (row && row.parentElement && this.el.contains(row)) this.focusId = row.dataset.id ?? null;
      if (row?.dataset.id !== this.refocus) this.refocus = null;
      if (!this.dragging.length) this.tellPlace();
    });
    on("focusout", (e) => {
      if (this.lifted && !this.el.contains(e.relatedTarget as Node | null)) this.cancelLift();
      if (!this.el.contains(e.relatedTarget as Node | null) && !this.dragging.length) this.peers.tell(null);
    });
    this.swipes();
  }

  private rowOf(target: EventTarget | null): Row | null {
    const el = (target as Element | null)?.closest?.<HTMLElement>("[data-narabe-item]");
    return el && this.el.contains(el) ? readRow(el) : null;
  }

  private click(e: MouseEvent): void {
    const target = e.target as Element;
    const toggle = target.closest("[data-narabe-toggle]");
    const row = this.rowOf(target);
    if (!row) return;
    if (toggle) {
      e.preventDefault();
      if (this.drilling && row.children) this.drill(row.id);
      else this.toggle(row);
      return;
    }
    if (target.closest("a[href], button, input, select, textarea, label, [data-narabe-nodrag]")) return;
    if (this.config.kind === "picker") return this.pick(row);
    // One level at a time: a tap on a row with children opens it.
    if (this.drilling && row.children && !e.shiftKey && !e.metaKey && !e.ctrlKey) return this.drill(row.id);
    if (!this.config.multiple && !this.config.onSelect) return;
    if (e.shiftKey && this.anchor) this.selectRange(row.id);
    else if (e.metaKey || e.ctrlKey) this.selectToggle(row.id);
    else this.selectOnly(row.id);
    row.el.focus();
  }

  // -- Selection ----------------------------------------------------------------

  private selectOnly(id: string): void {
    this.selected = new Set([id]);
    this.anchor = id;
    this.selectionChanged();
  }

  private selectToggle(id: string): void {
    if (!this.config.multiple) return this.selectOnly(id);
    if (this.selected.has(id)) this.selected.delete(id);
    else this.selected.add(id);
    this.anchor = id;
    this.selectionChanged();
  }

  private selectRange(id: string): void {
    if (!this.config.multiple) return this.selectOnly(id);
    const shown = rows(this.el).filter((r) => !r.el.hidden);
    const a = shown.findIndex((r) => r.id === this.anchor);
    const b = shown.findIndex((r) => r.id === id);
    if (a < 0 || b < 0) return this.selectOnly(id);
    this.selected = new Set(shown.slice(Math.min(a, b), Math.max(a, b) + 1).map((r) => r.id));
    this.selectionChanged();
  }

  private selectionChanged(): void {
    this.applySelection(rows(this.el));
    if (this.selected.size > 1) this.say(this.words.count("selected", this.selected.size));
    if (this.config.onSelect) this.transport?.push(this.config.onSelect, { v: 1, ids: Array.from(this.selected) });
  }

  // A tree picker: one item, posted by its form.
  private pick(row: Row): void {
    if ((this.config.disabled ?? []).includes(row.id)) return;
    this.selected = new Set([row.id]);
    this.applySelection(rows(this.el));
    const input = this.el.querySelector<HTMLInputElement>("[data-narabe-value]");
    if (input) {
      input.value = row.id;
      input.dispatchEvent(new Event("input", { bubbles: true }));
      input.dispatchEvent(new Event("change", { bubbles: true }));
    }
    this.el.dispatchEvent(new CustomEvent("narabe:pick", { bubbles: true, detail: { id: row.id } }));
    this.say(row.label);
  }

  // -- Expand and collapse ------------------------------------------------------

  private toggle(row: Row): void {
    this.expand(row.id, !this.expanded.has(row.id));
  }

  private expand(id: string, open: boolean): void {
    const all = rows(this.el);
    const index = all.findIndex((r) => r.id === id);
    const row = all[index];
    if (!row || !row.children) return;
    if (open) this.expanded.add(id);
    else this.expanded.delete(id);
    // Children not loaded yet: the server loads them.
    const loaded = all[index + 1] !== undefined && all[index + 1]!.level > row.level;
    if (open && !loaded && this.config.onExpand) this.transport?.push(this.config.onExpand, { v: 1, id });
    this.update();
    this.say(`${row.label}, ${this.words.t(open ? "expand" : "collapse")}`);
  }

  // -- Keys ---------------------------------------------------------------------

  private key(e: KeyboardEvent): void {
    if (this.renaming || e.target === this.filterInput) return;
    const row = this.rowOf(e.target);
    if (!row || e.target !== row.el) return;
    if (this.lifted) return this.liftedKey(e);

    const shown = rows(this.el).filter((r) => !r.el.hidden);
    const i = shown.findIndex((r) => r.id === row.id);
    const go = (to: Row | undefined) => {
      if (!to) return;
      e.preventDefault();
      to.el.focus();
      if (e.shiftKey && this.config.multiple) this.selectRange(to.id);
    };
    const mod = e.metaKey || e.ctrlKey;

    // Ctrl/Cmd+Shift+arrows: move the item one step, without lifting it.
    if (mod && e.shiftKey && e.key.startsWith("Arrow") && this.canMove) {
      e.preventDefault();
      this.lift(row);
      this.liftedKey(new KeyboardEvent("keydown", { key: e.key }));
      return this.dropLifted();
    }

    switch (e.key) {
      case "ArrowDown":
        return go(shown[i + 1]);
      case "ArrowUp":
        return go(shown[i - 1]);
      case "Home":
        return go(shown[0]);
      case "End":
        return go(shown[shown.length - 1]);
      case "ArrowRight":
        if (this.board) return go(this.neighbourColumn(row, 1));
        if (!this.tree || !row.children) return;
        e.preventDefault();
        if (this.drilling) return this.drill(row.id);
        if (!this.expanded.has(row.id)) return this.expand(row.id, true);
        return go(shown[i + 1]?.level === row.level + 1 ? shown[i + 1] : undefined);
      case "ArrowLeft": {
        if (this.board) return go(this.neighbourColumn(row, -1));
        if (!this.tree) return;
        e.preventDefault();
        if (this.drilling && this.drillAt) return this.drill(rows(this.el).find((r) => r.id === this.drillAt)?.parent ?? null);
        if (row.children && this.expanded.has(row.id)) return this.expand(row.id, false);
        return go(shown.slice(0, i).reverse().find((r) => r.level < row.level));
      }
      case " ":
        if (this.config.kind === "picker") {
          e.preventDefault();
          return this.pick(row);
        }
        if (!this.canMove) {
          if (this.config.multiple) {
            e.preventDefault();
            this.selectToggle(row.id);
          }
          return;
        }
        e.preventDefault();
        return this.lift(row);
      case "Enter":
        if (this.config.kind === "picker") {
          e.preventDefault();
          return this.pick(row);
        }
        return;
      case "F2":
        if (this.config.onRename) {
          e.preventDefault();
          this.rename(row);
        }
        return;
      case "a":
        if (mod && this.config.multiple) {
          e.preventDefault();
          this.selected = new Set(shown.map((r) => r.id));
          this.selectionChanged();
        }
        return;
      case "Escape":
        if (this.selected.size && this.config.kind !== "picker") {
          this.selected.clear();
          this.selectionChanged();
        }
        return;
    }
  }

  private neighbourColumn(row: Row, step: number): Row | undefined {
    const cols = groups(this.el);
    const at = cols.findIndex((g) => g.id === row.parent);
    const col = cols[at + step];
    if (!col) return undefined;
    const mine = rows(col.body);
    const index = rows(cols[at]!.body).findIndex((r) => r.id === row.id);
    return mine[Math.min(index, mine.length - 1)];
  }

  // -- Moving with the keyboard ---------------------------------------------------

  private moving(row: Row): string[] {
    if (!this.selected.has(row.id)) return [row.id];
    // The selected rows, in the page's order, not those inside another selected one.
    const all = rows(this.el);
    return without(all, new Set()).filter((r) => this.selected.has(r.id)).filter((r, _i, list) => {
      const index = all.findIndex((x) => x.id === r.id);
      return !ancestors(all, index).some((a) => list.some((s) => s.id === a.id));
    }).map((r) => r.id);
  }

  private lift(row: Row): void {
    if (row.locked) return this.say(this.words.t("locked", { name: row.locked }));
    const ids = this.moving(row);
    const holder = this.peers.holder(ids);
    if (holder) return this.say(this.words.t("locked", { name: holder }));
    const all = rows(this.el);
    const others = without(all, new Set(ids)).filter((r) => !r.el.hidden || this.board);
    const first = all.findIndex((r) => r.id === ids[0]);
    // The gap where it is now: after the last row shown above it.
    let gap = -1;
    for (let i = first - 1; i >= 0; i--) {
      const index = others.findIndex((r) => r.id === all[i]!.id);
      if (index >= 0) {
        gap = index;
        break;
      }
    }
    if (this.board) {
      const cols = groups(this.el);
      const group = cols.findIndex((g) => g.id === row.parent);
      const inColumn = without(rows(cols[group]!.body), new Set(ids));
      gap = inColumn.findIndex((r) => r.id === all[first - 1]?.id);
      this.lifted = { ids, gap, level: 1, group, snapshot: [] };
    } else {
      this.lifted = { ids, gap, level: row.level, group: -1, snapshot: [] };
    }
    this.dragging = ids;
    for (const id of ids) all.find((r) => r.id === id)?.el.classList.add("narabe-lifted");
    this.el.classList.add("narabe-moving");
    this.say(this.words.t("lifted", { label: this.labelOf(ids) }));
    this.showKeyboardTarget();
  }

  private liftedKey(e: KeyboardEvent): void {
    const lifted = this.lifted!;
    const step: Record<string, () => void> = {
      ArrowUp: () => (lifted.gap = Math.max(-1, lifted.gap - 1)),
      ArrowDown: () => (lifted.gap = Math.min(this.candidates().length - 1, lifted.gap + 1)),
      ArrowRight: () => (this.board ? this.moveColumn(1) : (lifted.level += 1)),
      ArrowLeft: () => (this.board ? this.moveColumn(-1) : (lifted.level = Math.max(1, lifted.level - 1))),
      Home: () => (lifted.gap = -1),
      End: () => (lifted.gap = this.candidates().length - 1),
    };
    if (e.key in step) {
      e.preventDefault?.();
      step[e.key]!();
      this.showKeyboardTarget();
    } else if (e.key === " " || e.key === "Enter") {
      e.preventDefault();
      this.dropLifted();
    } else if (e.key === "Escape") {
      e.preventDefault();
      e.stopPropagation();
      this.cancelLift();
    } else if (e.key === "Tab") {
      this.cancelLift();
    }
  }

  private moveColumn(step: number): void {
    const lifted = this.lifted!;
    const count = groups(this.el).length;
    lifted.group = Math.max(0, Math.min(count - 1, lifted.group + step));
    lifted.gap = Math.min(lifted.gap, this.candidates().length - 1);
  }

  /** The rows a dragged item may land among: of its column on a board. */
  private candidates(group?: Group | null): Row[] {
    const scope = this.board ? (group ?? groups(this.el)[this.lifted?.group ?? 0])?.body : this.el;
    if (!scope) return [];
    return without(rows(scope), new Set(this.dragging)).filter((r) => !r.el.hidden || this.board);
  }

  private showKeyboardTarget(): void {
    const lifted = this.lifted!;
    const group = this.board ? groups(this.el)[lifted.group] ?? null : null;
    const others = this.candidates(group);
    let gap = this.drilling
      ? gapAt(others, lifted.gap, this.drillLevel(), false, this.drillAt)
      : gapAt(others, lifted.gap, lifted.level, !!this.config.rules?.nest, group?.id ?? null);
    lifted.level = gap.level;
    // Under a closed row with children: at the end of them, unseen.
    if (this.tree && gap.anchor && gap.parent === gap.anchor.id && gap.anchor.children && !this.expanded.has(gap.anchor.id)) gap = inside(gap.anchor);
    this.target = { gap, rows: others, group, refusal: this.refusal(gap, group) };
    this.drawTarget();
    this.tellPlace();
    (gap.anchor?.el ?? others[0]?.el)?.scrollIntoView({ block: "nearest" });
    this.say(this.describe(this.target));
  }

  private dropLifted(): void {
    const target = this.target;
    const ids = this.lifted?.ids ?? [];
    this.endLift();
    if (!target || target.refusal) {
      this.say(target?.refusal ? `${this.words.t("refused")}: ${this.refusalText(target.refusal)}` : this.words.t("cancelled", { label: this.labelOf(ids) }));
      return;
    }
    this.apply(ids, target);
    this.refocus = ids[0] ?? null;
    rows(this.el).find((r) => r.id === ids[0])?.el.focus();
  }

  private cancelLift(): void {
    const ids = this.lifted?.ids ?? [];
    this.endLift();
    this.say(this.words.t("cancelled", { label: this.labelOf(ids) }));
  }

  private endLift(): void {
    for (const row of rows(this.el)) row.el.classList.remove("narabe-lifted");
    this.el.classList.remove("narabe-moving");
    this.lifted = null;
    this.dragging = [];
    this.target = null;
    this.line.hidden = true;
    this.tellPlace();
  }

  // -- Moving with a pointer --------------------------------------------------------

  private pointerDown(e: PointerEvent): void {
    this.refocus = null;
    if (e.button !== 0 || !this.canMove || this.session || this.lifted) return;
    const target = e.target as Element;
    const columnHandle = target.closest<HTMLElement>("[data-narabe-group-handle]");
    if (columnHandle && this.board && this.config.moveColumns) return this.columnDrag(e, columnHandle);
    const row = this.rowOf(target);
    if (!row || !startsDrag(target, !!this.config.handle)) return;
    if (row.locked) return;
    const ids = this.moving(row);
    if (this.peers.holder(ids)) return;
    this.session = new DragSession(e, row.el, {
      lift: () => {
        this.dragging = ids;
        for (const r of rows(this.el)) if (ids.includes(r.id)) r.el.classList.add("narabe-lifted");
        this.el.classList.add("narabe-moving");
        this.say(this.words.t("lifted", { label: this.labelOf(ids) }));
        return this.ghost(row, ids.length);
      },
      move: (x, y) => this.pointerTarget(x, y),
      drop: () => {
        const target = this.target;
        this.endDrag();
        if (target && !target.refusal) this.apply(ids, target);
        else if (target?.refusal) this.say(`${this.words.t("refused")}: ${this.refusalText(target.refusal)}`);
      },
      cancel: () => {
        const was = this.dragging.length > 0;
        this.endDrag();
        if (was) this.say(this.words.t("cancelled", { label: this.labelOf(ids) }));
      },
    });
  }

  private endDrag(): void {
    this.session = null;
    for (const row of rows(this.el)) row.el.classList.remove("narabe-lifted");
    this.el.classList.remove("narabe-moving");
    this.dragging = [];
    this.target = null;
    this.line.hidden = true;
    this.tellPlace();
  }

  private ghost(row: Row, count: number): HTMLElement {
    const box = row.el.getBoundingClientRect();
    const ghost = row.el.cloneNode(true) as HTMLElement;
    ghost.removeAttribute("id");
    for (const el of ghost.querySelectorAll("[id]")) el.removeAttribute("id");
    ghost.removeAttribute("phx-hook");
    ghost.className = `${row.el.className} narabe-ghost`;
    ghost.setAttribute("aria-hidden", "true");
    ghost.style.width = `${box.width}px`;
    ghost.style.height = `${box.height}px`;
    if (count > 1) {
      const badge = document.createElement("span");
      badge.className = "narabe-count";
      badge.textContent = this.words.number(count);
      ghost.append(badge);
    }
    return ghost;
  }

  private pointerTarget(x: number, y: number): void {
    const nest = !!this.config.rules?.nest;
    let group: Group | null = null;
    if (this.board) {
      const cols = groups(this.el);
      group = cols.find((g) => {
        const r = g.el.getBoundingClientRect();
        return x >= r.left && x <= r.right;
      }) ?? nearest(cols, x);
      if (!group) return;
    }
    const others = this.candidates(group);
    const rects = others.map((r) => r.el.getBoundingClientRect());
    let gap: Gap;
    if (this.tree && nest && !this.drilling) {
      const zone = zoneAtY(others, rects, y, (r) => this.mayHold(r));
      if (zone.into && !this.expanded.has(zone.into.id) && zone.into.children) {
        gap = inside(zone.into);
      } else if (zone.into) {
        gap = gapAt(others, zone.gap, zone.into.level + 1, true);
      } else {
        const indent = this.indent();
        const left = (this.el.querySelector<HTMLElement>("[data-narabe-body]") ?? this.el).getBoundingClientRect().left;
        // The dragged row's own level, and a level for each indent the pointer moved sideways.
        const base = rows(this.el).find((r) => r.id === this.dragging[0])?.level ?? 1;
        const depth = base + Math.round(((this.session ? this.session.left : x) - left) / indent);
        gap = gapAt(others, zone.gap, depth, true);
      }
    } else {
      const parent = this.drilling ? this.drillAt : group?.id ?? null;
      gap = gapAt(others, gapAtY(others, rects, y), this.drilling ? this.drillLevel() : 1, false, parent);
    }
    this.target = { gap, rows: others, group, refusal: this.refusal(gap, group) };
    this.drawTarget();
    this.tellPlace();
  }

  /** The level shown, one level at a time. */
  private drillLevel(): number {
    return (rows(this.el).find((r) => r.id === this.drillAt)?.level ?? 0) + 1;
  }

  private mayHold(row: Row): boolean {
    const rules = this.config.rules ?? {};
    return !!rules.nest && !(rules.leaves ?? []).includes(row.kind);
  }

  private indent(): number {
    const value = parseFloat(getComputedStyle(this.el).getPropertyValue("--narabe-indent"));
    return value > 0 ? value : 20;
  }

  // -- A board's columns, dragged by their heads ------------------------------------

  private columnDrag(e: PointerEvent, handle: HTMLElement): void {
    const column = handle.closest<HTMLElement>("[data-narabe-group]");
    if (!column) return;
    const id = column.dataset.id ?? "";
    let target: { after: string | null; before: string | null; index: number } | null = null;
    this.session = new DragSession(e, column, {
      lift: () => {
        column.classList.add("narabe-lifted");
        const ghost = column.cloneNode(true) as HTMLElement;
        ghost.removeAttribute("id");
        ghost.className = `${column.className} narabe-ghost`;
        const box = column.getBoundingClientRect();
        ghost.style.width = `${box.width}px`;
        ghost.style.height = `${Math.min(box.height, 320)}px`;
        return ghost;
      },
      move: (x) => {
        const cols = groups(this.el).filter((g) => g.id !== id);
        let index = cols.length;
        for (let i = 0; i < cols.length; i++) {
          const r = cols[i]!.el.getBoundingClientRect();
          if (x < r.left + r.width / 2) {
            index = i;
            break;
          }
        }
        target = { after: cols[index - 1]?.id ?? null, before: cols[index]?.id ?? null, index };
        const anchor = cols[index - 1]?.el ?? cols[index]?.el;
        if (anchor) this.drawColumnLine(anchor, !!cols[index - 1]);
      },
      drop: () => {
        column.classList.remove("narabe-lifted");
        this.session = null;
        this.line.hidden = true;
        if (!target) return;
        const cols = groups(this.el);
        const snapshot = [{ el: column, parent: column.parentNode!, next: column.nextSibling }];
        const before = cols.find((g) => g.id === target!.before)?.el ?? null;
        const after = cols.find((g) => g.id === target!.after)?.el ?? null;
        if (after) after.after(column);
        else if (before) before.before(column);
        this.push({ v: 1, ids: [id], parent: null, after: target.after, before: target.before, index: target.index, columns: true }, () => {
          const s = snapshot[0]!;
          s.parent.insertBefore(s.el, s.next);
        });
      },
      cancel: () => {
        column.classList.remove("narabe-lifted");
        this.session = null;
        this.line.hidden = true;
      },
    });
  }

  private drawColumnLine(anchor: HTMLElement, after: boolean): void {
    const box = this.el.getBoundingClientRect();
    const r = anchor.getBoundingClientRect();
    const s = this.line.style;
    this.line.hidden = false;
    this.line.className = "narabe-indicator narabe-indicator-vertical";
    s.left = `${(after ? r.right : r.left) - box.left - 2}px`;
    s.top = `${r.top - box.top}px`;
    s.width = "";
    s.height = `${r.height}px`;
  }

  // -- The target: rules, drawing, words ------------------------------------------------

  private refusal(gap: Gap, group: Group | null): Refusal | null {
    const all = rows(this.el);
    const moved = this.dragging.map((id) => all.findIndex((r) => r.id === id)).filter((i) => i >= 0);
    const parentRow = this.tree && gap.parent ? all.find((r) => r.id === gap.parent) : null;
    return check(this.config.rules ?? {}, {
      kinds: moved.map((i) => all[i]!.kind),
      parentKind: parentRow ? parentRow.kind : group ? group.kind : null,
      parentDepth: parentRow ? parentRow.level : 0,
      height: Math.max(1, ...moved.map((i) => height(all, i))),
      intoItself: false,
    });
  }

  private drawTarget(): void {
    const target = this.target;
    if (!target) return;
    const { gap, rows: others, group } = target;
    const box = this.el.getBoundingClientRect();
    const s = this.line.style;
    this.line.hidden = false;
    this.line.className = `narabe-indicator${target.refusal ? " narabe-refused" : ""}${gap.shape === "inside" ? " narabe-indicator-inside" : ""}`;
    if (gap.shape === "inside" && gap.anchor) {
      const r = gap.anchor.el.getBoundingClientRect();
      Object.assign(s, { left: `${r.left - box.left}px`, top: `${r.top - box.top}px`, width: `${r.width}px`, height: `${r.height}px` });
      return;
    }
    const above = gap.anchor ? gap.anchor.el.getBoundingClientRect() : null;
    const belowRow = others[others.indexOf(gap.anchor as Row) + 1] ?? (gap.anchor ? null : others[0]);
    const below = belowRow ? belowRow.el.getBoundingClientRect() : null;
    const body = (group?.body ?? this.el.querySelector<HTMLElement>("[data-narabe-body]") ?? this.el).getBoundingClientRect();
    const y = above && below ? (above.bottom + below.top) / 2 : above ? above.bottom + 2 : below ? below.top - 2 : body.top + 8;
    const indent = this.tree && !this.drilling ? (gap.level - 1) * this.indent() : 0;
    // Within what shows of the list (a board scrolls sideways).
    const shown = (this.el.querySelector<HTMLElement>("[data-narabe-body]") ?? this.el).getBoundingClientRect();
    const left = Math.max(body.left + indent, shown.left);
    const right = Math.min(body.right, shown.right);
    Object.assign(s, { left: `${left - box.left}px`, top: `${y - box.top - 1}px`, width: `${Math.max(24, right - left)}px`, height: "" });
  }

  private describe(target: Target): string {
    if (target.refusal) return `${this.words.t("refused")}: ${this.refusalText(target.refusal)}`;
    const label = this.labelOf(this.dragging);
    const position = this.words.number(target.gap.index + 1);
    const count = this.words.number(target.gap.count);
    const parent = target.gap.parent ? (this.tree ? rows(this.el).find((r) => r.id === target.gap.parent)?.label : target.group?.label) : null;
    return parent ? this.words.t("movedIn", { label, parent, position, count }) : this.words.t("moved", { label, position, count });
  }

  private refusalText(refusal: Refusal): string {
    const parent = this.target?.gap.parent ? rows(this.el).find((r) => r.id === this.target!.gap.parent)?.label ?? this.target?.group?.label ?? "" : "";
    return refusal === "too_deep" ? this.words.t("tooDeep") : refusal === "into_itself" ? this.words.t("intoItself") : this.words.t("notAccepted", { parent });
  }

  private labelOf(ids: string[]): string {
    if (ids.length > 1) return this.words.count("items", ids.length);
    return rows(this.el).find((r) => r.id === ids[0])?.label ?? "";
  }

  // -- Applying a move: the page first, then the server -----------------------------------

  private apply(ids: string[], target: Target): void {
    const all = rows(this.el);
    const { gap, group } = target;
    const shape = (list: Row[]) => list.map((r) => `${r.id}/${r.el.dataset.level}/${r.el.dataset.parent ?? ""}/${r.el.parentElement === null ? "" : (r.el.closest("[data-narabe-group]") as HTMLElement | null)?.dataset.id ?? ""}`).join(" ");
    const was = shape(all);
    const snapshot: Snapshot[] = [];
    const blocks = ids.map((id) => {
      const index = all.findIndex((r) => r.id === id);
      return this.tree ? subtree(all, index) : [all[index]!];
    });
    for (const block of blocks) for (const row of block) snapshot.push({ el: row.el, parent: row.el.parentNode!, next: row.el.nextSibling, level: row.el.dataset.level, parentId: row.el.dataset.parent });

    // Where the moved rows go: after the gap's row (and all of its subtree, to land as its next sibling).
    let after: HTMLElement | null = null;
    let container: HTMLElement | null = null;
    if (gap.shape === "inside" && gap.anchor) {
      const index = all.findIndex((r) => r.id === gap.anchor!.id);
      const tree = subtree(all, index);
      after = tree[tree.length - 1]!.el;
    } else if (gap.anchor) {
      const index = all.findIndex((r) => r.id === gap.anchor!.id);
      const tree = this.tree ? subtree(all, index).filter((r) => !ids.includes(r.id)) : [gap.anchor];
      // Below the anchor's subtree only when landing at the anchor's level or above.
      after = gap.level <= gap.anchor.level ? tree[tree.length - 1]!.el : gap.anchor.el;
    } else {
      container = group?.body ?? (this.el.querySelector<HTMLElement>("[data-narabe-body]") ?? this.el);
    }

    const moved: HTMLElement[] = [];
    for (const block of blocks) {
      const delta = gap.level - block[0]!.level;
      for (const row of block) {
        row.el.dataset.level = String(row.level + delta);
        moved.push(row.el);
      }
      block[0]!.el.dataset.parent = gap.parent ?? "";
    }
    if (after) after.after(...moved);
    else if (container) container.prepend(...moved);
    if (gap.shape === "inside" && gap.parent) this.expanded.add(gap.parent);
    this.update();
    // Dropped where they were: nothing to tell the server.
    if (shape(rows(this.el)) === was) return this.say(this.words.t("cancelled", { label: this.labelOf(ids) }));

    const payload = { v: 1, ids, parent: gap.parent, after: gap.shape === "inside" ? null : gap.after, before: gap.shape === "inside" ? null : gap.before, index: gap.shape === "inside" ? null : gap.index };
    this.say(this.words.t("dropped", { label: this.labelOf(ids), position: this.words.number(gap.index + 1), count: this.words.number(gap.count) }));
    this.el.dispatchEvent(new CustomEvent("narabe:move", { bubbles: true, detail: payload }));
    this.push(payload, () => {
      for (const s of snapshot.reverse()) {
        s.parent.insertBefore(s.el, s.next);
        if (s.level !== undefined) s.el.dataset.level = s.level;
        if (s.parentId !== undefined) s.el.dataset.parent = s.parentId;
      }
      this.update();
    });
  }

  // Tells the server; on its error, the page goes back.
  private push(payload: object, revert: () => void): void {
    if (!this.config.onMove || !this.transport) return;
    this.transport.push(this.config.onMove, payload, (reply) => {
      if (reply && reply.error) {
        revert();
        const reason = String(reply.error);
        const known = { too_deep: "tooDeep", into_itself: "intoItself" } as Record<string, string>;
        const why = typeof reply.message === "string" ? reply.message : known[reason] ? this.words.t(known[reason]!) : "";
        this.say(why ? `${this.words.t("failed")}: ${why}` : this.words.t("failed"));
        this.el.dispatchEvent(new CustomEvent("narabe:refused", { bubbles: true, detail: reply }));
      }
    });
  }

  // -- Rename in place ------------------------------------------------------------

  private rename(row: Row): void {
    const label = row.el.querySelector<HTMLElement>("[data-narabe-label]");
    if (!label || this.renaming) return;
    const box = label.getBoundingClientRect();
    const own = this.el.getBoundingClientRect();
    const input = document.createElement("input");
    input.className = "narabe-rename";
    input.value = label.textContent?.trim() ?? "";
    input.setAttribute("aria-label", this.words.t("rename"));
    Object.assign(input.style, { left: `${box.left - own.left - 4}px`, top: `${box.top - own.top - 3}px`, width: `${Math.max(box.width + 24, 140)}px` });
    this.chrome.append(input);
    this.renaming = input;
    input.focus();
    input.select();
    const finish = (save: boolean) => {
      if (!this.renaming) return;
      this.renaming = null;
      const name = input.value.trim();
      input.remove();
      row.el.focus();
      if (save && name && name !== label.textContent?.trim() && this.config.onRename) {
        label.textContent = name;
        this.transport?.push(this.config.onRename, { v: 1, id: row.id, name });
      }
    };
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter") finish(true);
      if (e.key === "Escape") {
        e.stopPropagation();
        finish(false);
      }
    });
    input.addEventListener("blur", () => finish(true));
  }

  // -- Swipe actions on a phone -------------------------------------------------------

  private swipes(): void {
    let start: { x: number; y: number; row: HTMLElement; content: HTMLElement; width: number } | null = null;
    let open: HTMLElement | null = null;
    const close = () => {
      if (open) open.style.translate = "";
      open = null;
    };
    this.el.addEventListener("touchstart", (e) => {
      const row = (e.target as Element).closest<HTMLElement>("[data-narabe-item]");
      const content = row?.querySelector<HTMLElement>(":scope > [data-narabe-content]");
      const actions = row?.querySelector<HTMLElement>(":scope > [data-narabe-actions]");
      if (open && open !== content) close();
      if (!row || !content || !actions || !actions.children.length) return;
      start = { x: e.touches[0]!.clientX, y: e.touches[0]!.clientY, row, content, width: actions.offsetWidth };
    }, { passive: true });
    this.el.addEventListener("touchmove", (e) => {
      if (!start || this.session?.active) return;
      const dx = e.touches[0]!.clientX - start.x;
      const dy = e.touches[0]!.clientY - start.y;
      if (Math.abs(dx) < Math.abs(dy) || Math.abs(dx) < 10) return;
      this.session?.abort();
      start.content.style.transition = "none";
      start.content.style.translate = `${Math.max(-start.width, Math.min(0, dx))}px 0`;
    }, { passive: true });
    this.el.addEventListener("touchend", () => {
      if (!start) return;
      const shift = parseFloat(start.content.style.translate) || 0;
      start.content.style.transition = "";
      if (shift < -start.width / 2) {
        start.content.style.translate = `${-start.width}px 0`;
        open = start.content;
      } else start.content.style.translate = "";
      start = null;
    });
  }

  // -- Words for screen readers ---------------------------------------------------------

  private say(text: string): void {
    this.live.textContent = "";
    requestAnimationFrame(() => (this.live.textContent = text));
  }

  // -- What the server asks (Narabe.Live) ----------------------------------------

  /** Expands (or collapses) rows; a row whose children are not here asks for them. */
  setExpanded(ids: string[], open: boolean): void {
    for (const id of ids) this.expand(id, open);
  }

  /** Expands the ancestors of a row, scrolls to it, and focuses it. */
  reveal(id: string): void {
    const all = rows(this.el);
    const index = all.findIndex((r) => r.id === id);
    const row = all[index];
    if (!row) return;
    for (const a of ancestors(all, index)) this.expanded.add(a.id);
    if (this.drilling) this.drillAt = row.parent;
    this.focusId = id;
    this.update();
    row.el.scrollIntoView({ block: "nearest" });
    row.el.focus({ preventScroll: true });
  }

  /** The selected rows, as the server says (no event back). */
  setSelected(ids: string[]): void {
    this.selected = new Set(ids);
    this.applySelection(rows(this.el));
  }

  destroy(): void {
    this.session?.abort();
    this.peers.destroy();
    for (const cleanup of this.cleanups) cleanup();
    this.cleanups = [];
  }
}

function nearest(cols: Group[], x: number): Group | null {
  let best: Group | null = null;
  let distance = Infinity;
  for (const g of cols) {
    const r = g.el.getBoundingClientRect();
    const d = Math.min(Math.abs(x - r.left), Math.abs(x - r.right));
    if (d < distance) {
      distance = d;
      best = g;
    }
  }
  return best;
}

function fold(text: string): string {
  return text.normalize("NFKD").replace(/\p{M}/gu, "").toLowerCase();
}
