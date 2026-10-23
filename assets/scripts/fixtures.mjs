// Makes test/fixtures/position.json from assets/src/position.ts: keys
// between pairs, chains at both ends, keys landing in one gap, and many
// keys at once. Narabe.Position (Elixir) must give the same answers.
// Run it when position.ts changes: node scripts/fixtures.mjs.

import { build } from "esbuild";
import { writeFileSync } from "node:fs";

const out = await build({ entryPoints: ["src/position.ts"], bundle: true, format: "esm", write: false, platform: "node" });
const url = "data:text/javascript;base64," + Buffer.from(out.outputFiles[0].text).toString("base64");
const { between, betweenMany } = await import(url);

const cases = [];
const add = (a, b) => cases.push({ a, b, key: between(a, b) });

// Chains: appending, prepending, and landing in the same gap again and again.
let last = null;
for (let i = 0; i < 80; i++) { const k = between(last, null); cases.push({ a: last, b: null, key: k }); last = k; }
let first = null;
for (let i = 0; i < 80; i++) { const k = between(null, first); cases.push({ a: null, b: first, key: k }); first = k; }
let lo = "a0", hi = "a1";
for (let i = 0; i < 40; i++) { const k = between(lo, hi); cases.push({ a: lo, b: hi, key: k }); hi = k; }
lo = "a0"; hi = "a1";
for (let i = 0; i < 40; i++) { const k = between(lo, hi); cases.push({ a: lo, b: hi, key: k }); lo = k; }

// A seeded walk of random inserts into a list.
let seed = 42;
const random = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
const list = [];
for (let i = 0; i < 300; i++) {
  const at = Math.floor(random() * (list.length + 1));
  const a = list[at - 1] ?? null;
  const b = list[at] ?? null;
  const key = between(a, b);
  cases.push({ a, b, key });
  list.splice(at, 0, key);
}
for (const [a, b] of [["Zz", "a0"], ["a0", "a0V"], ["z" + "z".repeat(26), null], ["b00", "b01"], ["a09", "a1"]]) add(a, b);

const many = [];
for (const [a, b, n] of [[null, null, 5], ["a0", "a1", 7], [null, "a0", 4], ["a5", null, 6], ["a0", "a0V", 10], ["Zz", "a00V", 3]]) {
  many.push({ a, b, n, keys: betweenMany(a, b, n) });
}

const invalid = ["", "a", "a00", "a0V0", "A00000000000000000000000000", "?0", "a0!", "b0"];
writeFileSync("../test/fixtures/position.json", JSON.stringify({ between: cases, many, invalid }, null, 1) + "\n");
console.log(`${cases.length} cases, ${many.length} many, ${invalid.length} invalid`);
