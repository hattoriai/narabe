import assert from "node:assert/strict";
import { test } from "node:test";
import { depths, gapAt, without } from "../src/drop";
import type { Row } from "../src/model";

// A tree, flat, as the page has it:
// a
//   a1
//   a2
//     a2x
// b
const row = (id: string, level: number, parent: string | null = null): Row => ({
  el: null as unknown as HTMLElement,
  id,
  kind: "item",
  level,
  parent,
  children: false,
  label: id,
  locked: null,
});
const tree = [row("a", 1), row("a1", 2, "a"), row("a2", 2, "a"), row("a2x", 3, "a2"), row("b", 1)];

test("a gap allows from the level below it to one under the row above", () => {
  assert.deepEqual(depths(tree, 3, true), [1, 4]); // between a2x and b
  assert.deepEqual(depths(tree, 0, true), [2, 2]); // between a and a1: a's first child only
  assert.deepEqual(depths(tree, -1, true), [1, 1]); // before a
  assert.deepEqual(depths(tree, 4, true), [1, 2]); // after b, the last
});

test("the depth picks the parent and the neighbours", () => {
  assert.deepEqual(pick(gapAt(tree, 3, 1, true)), { parent: null, after: "a", before: "b", level: 1, index: 1, count: 3 });
  assert.deepEqual(pick(gapAt(tree, 3, 2, true)), { parent: "a", after: "a2", before: null, level: 2, index: 2, count: 3 });
  assert.deepEqual(pick(gapAt(tree, 3, 3, true)), { parent: "a2", after: "a2x", before: null, level: 3, index: 1, count: 2 });
  assert.deepEqual(pick(gapAt(tree, 3, 4, true)), { parent: "a2x", after: null, before: null, level: 4, index: 0, count: 1 });
  assert.deepEqual(pick(gapAt(tree, 0, 1, true)), { parent: "a", after: null, before: "a1", level: 2, index: 0, count: 3 });
  assert.deepEqual(pick(gapAt(tree, -1, 5, true)), { parent: null, after: null, before: "a", level: 1, index: 0, count: 3 });
});

test("a list is one level; a board's column is the parent", () => {
  const list = [row("x", 1), row("y", 1), row("z", 1)];
  assert.deepEqual(pick(gapAt(list, 0, 3, false)), { parent: null, after: "x", before: "y", level: 1, index: 1, count: 4 });
  assert.deepEqual(pick(gapAt(list, 2, 1, false, "done")), { parent: "done", after: "z", before: null, level: 1, index: 3, count: 4 });
  assert.deepEqual(pick(gapAt([], -1, 1, false, "empty")), { parent: "empty", after: null, before: null, level: 1, index: 0, count: 1 });
});

test("the dragged rows and their subtrees are not places to land", () => {
  assert.deepEqual(
    without(tree, new Set(["a2"])).map((r) => r.id),
    ["a", "a1", "b"],
  );
  assert.deepEqual(
    without(tree, new Set(["a"])).map((r) => r.id),
    ["b"],
  );
});

function pick(g: ReturnType<typeof gapAt>) {
  return { parent: g.parent, after: g.after, before: g.before, level: g.level, index: g.index, count: g.count };
}
