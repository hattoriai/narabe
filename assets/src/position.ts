// Position keys: a string per item that sorts between its neighbours, so
// that a move writes one row. Fractional indexing, as rocicorp's
// fractional-indexing (CC0, see NOTICE): base 62 (0-9A-Za-z), compared
// byte by byte. Narabe.Position is the same, held to the same answers by
// test/fixtures/position.json.
//
// A key is an integer part (a head letter that says its length, then
// digits) and a fraction (digits, never ending in 0). "a0" is the first
// key; keys after it count up ("a1", "a2", … "b00"), keys before it count
// down ("Zz", …); a key between two close ones grows a fraction ("a0V").

export const DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
const ZERO = DIGITS[0]!;
const SMALLEST_INTEGER = "A" + ZERO.repeat(26);

function midpoint(a: string, b: string | null): string {
  if (b !== null && a >= b) throw new Error(`Narabe: ${a} is not before ${b}`);
  if (a.slice(-1) === ZERO || (b && b.slice(-1) === ZERO)) throw new Error("Narabe: a fraction ends in 0");
  if (b) {
    // The common prefix, then the midpoint of what follows.
    let n = 0;
    while ((a[n] ?? ZERO) === b[n]) n++;
    if (n > 0) return b.slice(0, n) + midpoint(a.slice(n), b.slice(n));
  }
  const digitA = a ? DIGITS.indexOf(a[0]!) : 0;
  const digitB = b !== null ? DIGITS.indexOf(b[0]!) : DIGITS.length;
  if (digitB - digitA > 1) return DIGITS[Math.round(0.5 * (digitA + digitB))]!;
  if (b && b.length > 1) return b.slice(0, 1);
  return DIGITS[digitA]! + midpoint(a.slice(1), null);
}

function integerLength(head: string): number {
  if (head >= "a" && head <= "z") return head.charCodeAt(0) - 97 + 2;
  if (head >= "A" && head <= "Z") return 90 - head.charCodeAt(0) + 2;
  throw new Error(`Narabe: not a position key head: ${head}`);
}

function integerPart(key: string): string {
  const length = integerLength(key[0]!);
  if (length > key.length) throw new Error(`Narabe: not a position key: ${key}`);
  return key.slice(0, length);
}

/** Whether a text is a position key. */
export function valid(key: string): boolean {
  try {
    check(key);
    return true;
  } catch {
    return false;
  }
}

function check(key: string): void {
  if (key === "" || key === SMALLEST_INTEGER) throw new Error(`Narabe: not a position key: ${key}`);
  for (const char of key) if (!DIGITS.includes(char)) throw new Error(`Narabe: not a position key: ${key}`);
  const integer = integerPart(key);
  if (key.slice(integer.length).slice(-1) === ZERO) throw new Error(`Narabe: not a position key: ${key}`);
}

function increment(x: string): string | null {
  const [head, ...digits] = x.split("") as [string, ...string[]];
  let carry = true;
  for (let i = digits.length - 1; carry && i >= 0; i--) {
    const d = DIGITS.indexOf(digits[i]!) + 1;
    if (d === DIGITS.length) digits[i] = ZERO;
    else {
      digits[i] = DIGITS[d]!;
      carry = false;
    }
  }
  if (!carry) return head + digits.join("");
  if (head === "Z") return "a" + ZERO;
  if (head === "z") return null;
  const next = String.fromCharCode(head.charCodeAt(0) + 1);
  if (next > "a") digits.push(ZERO);
  else digits.pop();
  return next + digits.join("");
}

function decrement(x: string): string | null {
  const [head, ...digits] = x.split("") as [string, ...string[]];
  const last = DIGITS[DIGITS.length - 1]!;
  let borrow = true;
  for (let i = digits.length - 1; borrow && i >= 0; i--) {
    const d = DIGITS.indexOf(digits[i]!) - 1;
    if (d === -1) digits[i] = last;
    else {
      digits[i] = DIGITS[d]!;
      borrow = false;
    }
  }
  if (!borrow) return head + digits.join("");
  if (head === "a") return "Z" + last;
  if (head === "A") return null;
  const previous = String.fromCharCode(head.charCodeAt(0) - 1);
  if (previous < "Z") digits.push(last);
  else digits.pop();
  return previous + digits.join("");
}

/** A key between `a` and `b` (null: the start or the end). */
export function between(a: string | null, b: string | null): string {
  if (a !== null) check(a);
  if (b !== null) check(b);
  if (a !== null && b !== null && a >= b) throw new Error(`Narabe: ${a} is not before ${b}`);
  if (a === null) {
    if (b === null) return "a" + ZERO;
    const ib = integerPart(b);
    const fb = b.slice(ib.length);
    if (ib === SMALLEST_INTEGER) return ib + midpoint("", fb);
    if (ib < b) return ib;
    const key = decrement(ib);
    if (key === null) throw new Error("Narabe: no key before the smallest");
    return key;
  }
  if (b === null) {
    const ia = integerPart(a);
    const key = increment(ia);
    return key === null ? ia + midpoint(a.slice(ia.length), null) : key;
  }
  const ia = integerPart(a);
  const fa = a.slice(ia.length);
  const ib = integerPart(b);
  const fb = b.slice(ib.length);
  if (ia === ib) return ia + midpoint(fa, fb);
  const key = increment(ia);
  if (key === null) throw new Error("Narabe: no key after the largest");
  return key < b ? key : ia + midpoint(fa, null);
}

/** `n` keys between `a` and `b`, in order, spread so that none is long. */
export function betweenMany(a: string | null, b: string | null, n: number): string[] {
  if (n <= 0) return [];
  if (n === 1) return [between(a, b)];
  if (b === null) {
    let c = between(a, b);
    const keys = [c];
    for (let i = 0; i < n - 1; i++) keys.push((c = between(c, b)));
    return keys;
  }
  if (a === null) {
    let c = between(a, b);
    const keys = [c];
    for (let i = 0; i < n - 1; i++) keys.push((c = between(a, c)));
    return keys.reverse();
  }
  const middle = Math.floor(n / 2);
  const c = between(a, b);
  return [...betweenMany(a, c, middle), c, ...betweenMany(c, b, n - middle - 1)];
}
