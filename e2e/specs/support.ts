// Helpers for the browser tests.

import { expect, type Locator, type Page } from "@playwright/test";

/** Resets the database, opens a page, and waits for the LiveView and the lists. */
export async function openPage(page: Page, path = "/"): Promise<void> {
  const reset = await page.request.get("/reset");
  expect(reset.ok()).toBe(true);
  await page.goto(path);
  await expect(page.locator("[data-phx-main].phx-connected")).toBeVisible();
  await expect(page.locator(".narabe.narabe-ready").first()).toBeAttached();
}

/** An item of a list, by its label. */
export function item(page: Page, list: string, label: string): Locator {
  return page.locator(`#${list} [data-narabe-item][data-label="${label}"]`);
}

/** The labels of the items shown, in order. */
export async function labels(scope: Locator): Promise<string[]> {
  return scope.locator("[data-narabe-item]:visible").evaluateAll((els) => els.map((el) => (el as HTMLElement).dataset.label ?? ""));
}

/** The order the server has (the dev page writes it). */
export function order(page: Page): Locator {
  return page.locator("#order");
}

/** The last move the server took. */
export async function lastMove(page: Page): Promise<Record<string, unknown>> {
  return JSON.parse((await page.locator("#last-move").textContent()) || "{}") as Record<string, unknown>;
}

type Where = "above" | "below" | "inside";

/**
 * Drags `from` with a mouse to a place on `to`: just above it, just below
 * it, or onto its middle (into it, in a tree). `dx` moves the pointer
 * sideways at the end (a tree's depth), from where it started.
 */
export async function drag(page: Page, from: Locator, to: Locator, where: Where, dx = 0): Promise<void> {
  const a = (await from.boundingBox())!;
  const b = (await to.boundingBox())!;
  const x = a.x + Math.min(60, a.width / 2);
  const y = a.y + a.height / 2;
  const ty = where === "above" ? b.y + b.height * 0.12 : where === "below" ? b.y + b.height * 0.88 : b.y + b.height / 2;
  const tx = b.x + Math.min(60, b.width / 2) + dx;
  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.mouse.move(x, y + 8, { steps: 2 });
  await page.mouse.move(tx, ty, { steps: 12 });
  await page.mouse.move(tx, ty + 1, { steps: 1 });
  await page.mouse.up();
}
