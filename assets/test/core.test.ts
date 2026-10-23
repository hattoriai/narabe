import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { between, betweenMany, valid } from "../src/position";
import { check, type Rules, type RuleMove } from "../src/rules";

// The same answers as Narabe.Position and Narabe.Rules, by the fixtures.
const position = JSON.parse(readFileSync("../test/fixtures/position.json", "utf8")) as {
  between: { a: string | null; b: string | null; key: string }[];
  many: { a: string | null; b: string | null; n: number; keys: string[] }[];
  invalid: string[];
};
const rules = JSON.parse(readFileSync("../test/fixtures/rules.json", "utf8")) as {
  cases: { name: string; rules: Rules; move: RuleMove; result: string }[];
};

test("position keys, as the fixture says", () => {
  for (const { a, b, key } of position.between) assert.equal(between(a, b), key, `between(${a}, ${b})`);
  for (const { a, b, n, keys } of position.many) assert.deepEqual(betweenMany(a, b, n), keys);
  for (const key of position.invalid) assert.equal(valid(key), false, key);
});

test("a key out of order is refused", () => {
  assert.throws(() => between("a1", "a0"), /is not before/);
});

test("the rules, as the fixture says", () => {
  for (const { name, rules: r, move, result } of rules.cases) assert.equal(check(r, move) ?? "ok", result, name);
});
