// The Narabe hook for a LiveSocket, and `mountNarabe` for a page without
// LiveView. The hook makes a Narabe of its element, gives it the server's
// later renders (`updated`), and passes the events of Narabe.Live
// (narabe:expand, narabe:reveal, narabe:select) to the list they name.

import { Narabe, type Transport } from "./narabe";

interface HookContext {
  el: HTMLElement;
  pushEvent(event: string, payload: object, onReply?: (reply: Record<string, unknown>, ref: number) => void): void;
  pushEventTo(target: string | HTMLElement, event: string, payload: object, onReply?: (reply: Record<string, unknown>, ref: number) => void): void;
  handleEvent(event: string, callback: (payload: Record<string, unknown>) => void): void;
}

interface NarabeHook extends HookContext {
  narabe?: Narabe;
}

const ids = (payload: Record<string, unknown>): string[] => ((payload.ids ?? (payload.item != null ? [payload.item] : [])) as unknown[]).map(String);

export const NarabeHook = {
  mounted(this: NarabeHook) {
    const hook = this;
    const target = hook.el.getAttribute("phx-target");
    const transport: Transport = {
      push(event, payload, onReply) {
        const reply = onReply ? (response: Record<string, unknown>) => onReply(response) : undefined;
        if (target) hook.pushEventTo(target, event, payload, reply);
        else hook.pushEvent(event, payload, reply);
      },
    };
    const narabe = new Narabe(hook.el, transport);
    hook.narabe = narabe;
    const mine = (payload: Record<string, unknown>) => payload.id === narabe.id;
    hook.handleEvent("narabe:expand", (p) => mine(p) && narabe.setExpanded(ids(p), p.expanded !== false));
    hook.handleEvent("narabe:reveal", (p) => mine(p) && narabe.reveal(String(p.item)));
    hook.handleEvent("narabe:select", (p) => mine(p) && narabe.setSelected(ids(p)));
  },

  updated(this: NarabeHook) {
    this.narabe?.update();
  },

  destroyed(this: NarabeHook) {
    this.narabe?.destroy();
    this.narabe = undefined;
  },
};

const mounted = new WeakMap<HTMLElement, Narabe>();

/**
 * Mounts the lists under `root` on a page without a LiveSocket (a
 * controller's template): they filter, select, expand and pick (a tree
 * picker in a form), but a move has no server to go to. Returns them; one
 * already mounted is skipped.
 */
export function mountNarabe(root: ParentNode = document): Narabe[] {
  const out: Narabe[] = [];
  for (const element of root.querySelectorAll<HTMLElement>('[phx-hook="Narabe"]')) {
    if (mounted.has(element)) continue;
    const narabe = new Narabe(element, null);
    mounted.set(element, narabe);
    out.push(narabe);
  }
  return out;
}
