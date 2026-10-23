import { expect, test, type Page } from "@playwright/test";
import { drag, item, lastMove, openPage, order } from "./support";

const card = (page: Page, label: string) => item(page, "board", label);
const column = (page: Page, name: string) => page.locator("#board [data-narabe-group]", { has: page.locator(".narabe-column-title", { hasText: name }) });

test("a card moves within its column", async ({ page }) => {
  await openPage(page, "/board");
  await drag(page, card(page, "Search in the docs"), card(page, "Flaky upload test"), "below");
  await expect(order(page)).toContainText("To do: Dark mode for charts,Flaky upload test,Search in the docs |");
});

test("a card moves to another column, between two cards", async ({ page }) => {
  await openPage(page, "/board");
  await drag(page, card(page, "Flaky upload test"), card(page, "Lazy children"), "above");
  await expect(order(page)).toContainText("Doing: Keyboard moves on boards,Flaky upload test,Lazy children");
  await expect(order(page)).toContainText("To do: Search in the docs,Dark mode for charts |");
  const move = await lastMove(page);
  expect(move.parent).toBe(await column(page, "Doing").getAttribute("data-id"));
  await expect(column(page, "Doing").locator(".narabe-column-count")).toHaveText("3");
});

test("a card moves into an empty column", async ({ page }) => {
  await openPage(page, "/board");
  await drag(page, card(page, "Rebalance a window"), card(page, "Lazy children"), "below");
  await expect(order(page)).toContainText("Review: |");
  const body = column(page, "Review").locator("[data-narabe-group-body]");
  await drag(page, card(page, "Search in the docs"), body, "inside");
  await expect(order(page)).toContainText("Review: Search in the docs |");
});

test("a column moves by its handle", async ({ page }) => {
  await openPage(page, "/board");
  const handle = column(page, "Done").locator("[data-narabe-group-handle]");
  const target = column(page, "To do");
  const a = (await handle.boundingBox())!;
  const b = (await target.boundingBox())!;
  await page.mouse.move(a.x + a.width / 2, a.y + a.height / 2);
  await page.mouse.down();
  await page.mouse.move(a.x - 10, a.y + 5, { steps: 3 });
  await page.mouse.move(b.x + 10, b.y + 20, { steps: 12 });
  await page.mouse.up();
  await expect(order(page)).toHaveText(/^Done: .* \| To do: /);
  expect((await lastMove(page)).columns).toBe(true);
});

test("the keyboard: Left and Right change the column", async ({ page }) => {
  await openPage(page, "/board");
  await card(page, "Search in the docs").focus();
  await page.keyboard.press("ArrowRight");
  await expect(card(page, "Keyboard moves on boards")).toBeFocused();
  await page.keyboard.press("ArrowLeft");
  await expect(card(page, "Search in the docs")).toBeFocused();

  await page.keyboard.press("Space");
  await page.keyboard.press("ArrowRight");
  await page.keyboard.press("ArrowRight");
  await page.keyboard.press("Space");
  await expect(order(page)).toContainText("Review: Search in the docs,Rebalance a window |");
  await expect(card(page, "Search in the docs")).toBeFocused();
});

test("a card added at the end moves like the others", async ({ page }) => {
  await openPage(page, "/board");
  await column(page, "Review").getByRole("button", { name: "+ Add a card" }).click();
  await expect(card(page, "New card")).toBeVisible();
  await drag(page, card(page, "New card"), card(page, "Position keys"), "above");
  await expect(order(page)).toContainText("Done: New card,Position keys,MySQL nodelay");
});
