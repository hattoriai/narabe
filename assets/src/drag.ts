// A drag with a pointer: a mouse or a pen lifts an item once it moves a
// few pixels (a click stays a click); a finger lifts it after a short hold
// (a swipe still scrolls the page). The lifted items follow the pointer as
// a ghost; the page scrolls near its edges; Escape lets go.
//
// Pointer events, not the browser's drag and drop: the same on every
// device, a ghost we draw, and no fight with the page's scrolling.

export interface DragCallbacks {
  /** The drag starts: the ghost to show (a copy of the item, sized). */
  lift(start: PointerEvent): HTMLElement | null;
  /** The pointer moved (after the page scrolled too, if it did). */
  move(x: number, y: number): void;
  /** The pointer let go: drop where it is. */
  drop(): void;
  /** Escape, a lost pointer, or a press that never became a drag. */
  cancel(): void;
}

const MOUSE_SLOP = 4;
const TOUCH_SLOP = 8;
const HOLD = 280;
const EDGE = 48;
const SPEED = 18;

/** Elements that keep their own pointer: a drag does not start on them. */
const INTERACTIVE = "a[href], button, input, select, textarea, label, [contenteditable=''], [contenteditable='true'], [data-narabe-nodrag]";

export function startsDrag(target: Element, handleOnly: boolean): boolean {
  const handle = target.closest("[data-narabe-handle], [data-narabe-group-handle]");
  if (handle) return true;
  if (handleOnly) return false;
  return !target.closest(INTERACTIVE);
}

export class DragSession {
  private start: PointerEvent;
  private x: number;
  private y: number;
  private lifted = false;
  private ghost: HTMLElement | null = null;
  private offsetX = 0;
  private offsetY = 0;
  private timer: ReturnType<typeof setTimeout> | null = null;
  private frame = 0;
  private scroller: HTMLElement | null;
  private cleanups: (() => void)[] = [];
  private done = false;

  constructor(
    start: PointerEvent,
    private source: HTMLElement,
    private callbacks: DragCallbacks,
  ) {
    this.start = start;
    this.x = start.clientX;
    this.y = start.clientY;
    this.scroller = scrollParent(source);
    const touch = start.pointerType === "touch";

    const on = <K extends keyof DocumentEventMap>(type: K, fn: (e: DocumentEventMap[K]) => void, opts?: AddEventListenerOptions) => {
      document.addEventListener(type, fn as EventListener, opts);
      this.cleanups.push(() => document.removeEventListener(type, fn as EventListener, opts));
    };
    on("pointermove", (e) => this.onMove(e));
    on("pointerup", () => (this.lifted ? this.finish(true) : this.finish(false)));
    on("pointercancel", () => this.finish(false));
    on("keydown", (e) => {
      if (e.key === "Escape" && this.lifted) {
        e.preventDefault();
        e.stopPropagation();
        this.finish(false);
      }
    }, { capture: true });
    // Once lifted, a finger's moves are the drag's, not the page's scroll.
    on("touchmove", (e) => {
      if (this.lifted) e.preventDefault();
    }, { passive: false });
    on("contextmenu", (e) => {
      if (this.lifted || touch) e.preventDefault();
    });

    if (touch) this.timer = setTimeout(() => this.lift(), HOLD);
  }

  get active(): boolean {
    return this.lifted;
  }

  private onMove(e: PointerEvent): void {
    if (e.pointerId !== this.start.pointerId) return;
    this.x = e.clientX;
    this.y = e.clientY;
    const distance = Math.hypot(this.x - this.start.clientX, this.y - this.start.clientY);
    if (!this.lifted) {
      if (this.start.pointerType === "touch") {
        // Moved before the hold: a scroll or a swipe, not a drag.
        if (distance > TOUCH_SLOP) this.finish(false);
      } else if (distance > MOUSE_SLOP) {
        this.lift();
      }
      return;
    }
    e.preventDefault();
    this.place();
  }

  private lift(): void {
    if (this.done || this.lifted) return;
    const ghost = this.callbacks.lift(this.start);
    if (!ghost) return this.finish(false);
    this.lifted = true;
    navigator.vibrate?.(8);
    try {
      this.source.setPointerCapture(this.start.pointerId);
    } catch {
      // The pointer is gone already: the next move or up ends the drag.
    }
    const box = this.source.getBoundingClientRect();
    this.offsetX = this.start.clientX - box.left;
    this.offsetY = this.start.clientY - box.top;
    this.ghost = ghost;
    document.body.append(ghost);
    document.documentElement.classList.add("narabe-dragging");
    this.place();
    this.frame = requestAnimationFrame(() => this.tick());
  }

  /** Where the dragged items' top left corner is: for a tree's depth. */
  get left(): number {
    return this.x - this.offsetX;
  }

  private place(): void {
    if (!this.ghost) return;
    this.ghost.style.translate = `${this.x - this.offsetX}px ${this.y - this.offsetY}px`;
    this.callbacks.move(this.x, this.y);
  }

  // Scrolls the list (or the page) while the pointer is near an edge.
  private tick(): void {
    if (!this.lifted) return;
    const scrolled = edgeScroll(this.scroller, this.x, this.y);
    if (scrolled) this.callbacks.move(this.x, this.y);
    this.frame = requestAnimationFrame(() => this.tick());
  }

  private finish(drop: boolean): void {
    if (this.done) return;
    this.done = true;
    if (this.timer) clearTimeout(this.timer);
    cancelAnimationFrame(this.frame);
    for (const cleanup of this.cleanups) cleanup();
    this.ghost?.remove();
    document.documentElement.classList.remove("narabe-dragging");
    if (this.lifted && drop) this.callbacks.drop();
    else this.callbacks.cancel();
  }

  /** Ends the drag from outside (the list is gone, or patched away). */
  abort(): void {
    this.finish(false);
  }
}

function scrollParent(el: HTMLElement): HTMLElement | null {
  for (let node = el.parentElement; node; node = node.parentElement) {
    const style = getComputedStyle(node);
    if (/(auto|scroll)/.test(style.overflowY + style.overflowX) && (node.scrollHeight > node.clientHeight || node.scrollWidth > node.clientWidth)) return node;
  }
  return null;
}

// Scrolls a box, and the page, toward the pointer when it is near their
// edges, faster the nearer: whether anything scrolled.
function edgeScroll(box: HTMLElement | null, x: number, y: number): boolean {
  let moved = false;
  const step = (distance: number) => (distance < EDGE ? Math.ceil(SPEED * (1 - Math.max(0, distance) / EDGE)) : 0);
  if (box) {
    const r = box.getBoundingClientRect();
    const dy = step(y - r.top) ? -step(y - r.top) : step(r.bottom - y);
    const dx = step(x - r.left) ? -step(x - r.left) : step(r.right - x);
    if ((dy && box.scrollHeight > box.clientHeight) || (dx && box.scrollWidth > box.clientWidth)) {
      const before = [box.scrollTop, box.scrollLeft];
      box.scrollBy(dx, dy);
      moved = before[0] !== box.scrollTop || before[1] !== box.scrollLeft;
    }
  }
  const dy = step(y) ? -step(y) : step(window.innerHeight - y);
  if (dy) {
    const before = window.scrollY;
    window.scrollBy(0, dy);
    moved = moved || before !== window.scrollY;
  }
  return moved;
}
