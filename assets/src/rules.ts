// What may go where, as Narabe.Rules says it on the server: a drop that
// breaks the rules is not offered. The same answers, held by
// test/fixtures/rules.json.

export interface Rules {
  nest?: boolean;
  maxDepth?: number;
  leaves?: string[];
  accepts?: Record<string, string[]>;
}

/** A move as the rules see it (see Narabe.Rules' move type). */
export interface RuleMove {
  kinds: string[];
  parentKind: string | null;
  /** 0: the top level, or a board's column. */
  parentDepth: number;
  /** The height of the tallest item's subtree: 1 for an item with no children. */
  height: number;
  intoItself: boolean;
}

export type Refusal = "into_itself" | "not_accepted" | "too_deep";

/** Checks a move: null when it may happen, else why not. */
export function check(rules: Rules, move: RuleMove): Refusal | null {
  const nested = move.parentDepth > 0;
  if (move.intoItself) return "into_itself";
  if (nested && !rules.nest) return "not_accepted";
  if (nested && move.parentKind !== null && (rules.leaves ?? []).includes(move.parentKind)) return "not_accepted";
  const kinds = rules.accepts?.[move.parentKind ?? "root"];
  if (kinds && !move.kinds.every((kind) => kinds.includes(kind))) return "not_accepted";
  if (rules.maxDepth !== undefined && move.parentDepth + move.height > rules.maxDepth) return "too_deep";
  return null;
}
