// What the server tells a list, tree or board (Narabe.Components), in
// `data-config`, and the words it says.

import type { Rules } from "./rules";

export type Kind = "list" | "tree" | "board" | "picker";

export interface Config {
  v: 1;
  id: string;
  kind: Kind;
  rules: Rules;
  messages: Record<string, string>;
  locale: string;
  /** The accessible name of the whole. */
  label?: string;
  /** Events to the LiveView (or the component of phx-target). */
  onMove?: string;
  onSelect?: string;
  onExpand?: string;
  onRename?: string;
  /** Whether items drag only by their handle. */
  handle?: boolean;
  /** Whether several items may be selected and moved together. */
  multiple?: boolean;
  /** No dragging: a picker, or a list shown read-only. */
  readonly?: boolean;
  /** Whether a board's columns move too. */
  moveColumns?: boolean;
  /** How a tree shows on a phone: as a tree, or one level at a time. */
  phone?: "tree" | "drill";
  /** A tree picker: the name and value of the field it posts. */
  name?: string;
  value?: string;
  /** Ids that a tree picker does not offer. */
  disabled?: string[];
  /** With Issho (Narabe.Issho): the element of its room. */
  issho?: { target: string };
}

export function readConfig(el: HTMLElement): Config {
  return JSON.parse(el.dataset.config ?? "{}") as Config;
}

/** The words of a list, with placeholders and plural forms. */
export class Words {
  private plurals: Intl.PluralRules;

  constructor(
    private messages: Record<string, string>,
    readonly locale: string,
  ) {
    this.plurals = new Intl.PluralRules(locale);
  }

  t(key: string, vars: Record<string, string | number> = {}): string {
    const text = this.messages[key] ?? key;
    return text.replace(/\{(\w+)\}/g, (match, name: string) => (name in vars ? String(vars[name]) : match));
  }

  /** The plural form of `base` for `n` (`itemsOne`, `itemsOther`), with `{n}` filled. */
  count(base: string, n: number, vars: Record<string, string | number> = {}): string {
    const form = this.plurals.select(n) === "one" ? "One" : "Other";
    return this.t(base + form, { n: this.number(n), ...vars });
  }

  number(n: number): string {
    return new Intl.NumberFormat(this.locale).format(n);
  }
}
