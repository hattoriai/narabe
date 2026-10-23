// Helpers for the browser tests.

import { expect, type Locator, type Page } from "@playwright/test";

/** Opens a page and waits for the LiveView to connect and the pickers to mount. */
export async function openPage(page: Page, path = "/"): Promise<void> {
  await page.goto(path);
  if (!path.startsWith("/plain")) await expect(page.locator("[data-phx-main].phx-connected")).toBeVisible();
  await expect(page.locator(".narabe.narabe-ready").first()).toBeAttached();
}

/** A picker by its id. */
export function picker(page: Page, id: string): Locator {
  return page.locator(`#${id}`);
}

/** The field of a picker: the box that opens its list, or that people type in. */
export function field(page: Page, id: string): Locator {
  return picker(page, id).locator(".narabe-field");
}

/** The list of a picker, while it is open. */
export function list(page: Page, id: string): Locator {
  return picker(page, id).locator('[role="listbox"]');
}

/** The rows of a picker's list that are options, by their labels. */
export function option(page: Page, id: string, label: string): Locator {
  return list(page, id).locator('[role="option"]', { hasText: label });
}

/** The params that the form posted last (the dev page writes them as JSON). */
export async function posted(page: Page): Promise<Record<string, unknown>> {
  const json = await page.locator("#posted").getAttribute("data-json");
  return JSON.parse(json ?? "{}") as Record<string, unknown>;
}

/** Waits until the task params that the form posted have `key` with `value`. */
export async function expectPosted(page: Page, key: string, value: unknown): Promise<void> {
  await expect.poll(async () => ((await posted(page)).task as Record<string, unknown> | undefined)?.[key]).toEqual(value);
}

/** The labels of the chips of a picker. */
export async function chips(page: Page, id: string): Promise<string[]> {
  return picker(page, id).locator(".narabe-field .narabe-chip-label").allTextContents();
}
