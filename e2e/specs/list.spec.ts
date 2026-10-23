import { expect, test } from "@playwright/test";
import { drag, item, labels, lastMove, openPage, order } from "./support";

const list = (page: import("@playwright/test").Page) => page.locator("#tasks");

test("a drag moves a task, and the database has it", async ({ page }) => {
  await openPage(page);
  await drag(page, item(page, "tasks", "Write the brief"), item(page, "tasks", "Order the badges"), "below");
  await expect(order(page)).toHaveText("2,3,1,4,5,6,7,8");
  expect(await lastMove(page)).toMatchObject({ v: 1, ids: ["1"], after: "3", before: "4", index: 2, parent: null });
  expect((await labels(list(page))).slice(0, 3)).toEqual(["Book the venue", "Order the badges", "Write the brief"]);

  await page.reload();
  await expect(page.locator("[data-phx-main].phx-connected")).toBeVisible();
  expect((await labels(list(page))).slice(0, 3)).toEqual(["Book the venue", "Order the badges", "Write the brief"]);
});

test("a drag to the top, and to the end", async ({ page }) => {
  await openPage(page);
  await drag(page, item(page, "tasks", "Buy coffee"), item(page, "tasks", "Write the brief"), "above");
  await expect(order(page)).toHaveText("7,1,2,3,4,5,6,8");
  await drag(page, item(page, "tasks", "Book the venue"), item(page, "tasks", "Set up the stream"), "below");
  await expect(order(page)).toHaveText("7,1,3,4,5,6,8,2");
});

test("a click is not a drag", async ({ page }) => {
  await openPage(page);
  await item(page, "tasks", "Book the venue").click();
  await expect(item(page, "tasks", "Book the venue")).toHaveAttribute("aria-selected", "true");
  await expect(item(page, "tasks", "Book the venue")).toBeFocused();
  await expect(page.locator("#last-move")).toBeEmpty();
});

test("the keyboard: Space lifts, the arrows move, Space drops", async ({ page }) => {
  await openPage(page);
  await item(page, "tasks", "Write the brief").focus();
  await page.keyboard.press("Space");
  await expect(item(page, "tasks", "Write the brief")).toHaveClass(/narabe-lifted/);
  await expect(page.locator("#tasks [aria-live]")).toContainText("Write the brief");
  await page.keyboard.press("ArrowDown");
  await page.keyboard.press("ArrowDown");
  await page.keyboard.press("Space");
  await expect(order(page)).toHaveText("2,3,1,4,5,6,7,8");
  await expect(item(page, "tasks", "Write the brief")).toBeFocused();
  await expect(page.locator("#tasks [aria-live]")).toContainText("3");
});

test("Escape puts a lifted task back", async ({ page }) => {
  await openPage(page);
  await item(page, "tasks", "Write the brief").focus();
  await page.keyboard.press("Space");
  await page.keyboard.press("ArrowDown");
  await page.keyboard.press("Escape");
  await expect(item(page, "tasks", "Write the brief")).not.toHaveClass(/narabe-lifted/);
  await expect(page.locator(".narabe-indicator")).toBeHidden();
  await expect(page.locator("#last-move")).toBeEmpty();
  expect((await labels(list(page)))[0]).toBe("Write the brief");
});

test("Ctrl+Shift+Down moves a task one step at once", async ({ page }) => {
  await openPage(page);
  await item(page, "tasks", "Write the brief").focus();
  await page.keyboard.press("Control+Shift+ArrowDown");
  await expect(order(page)).toHaveText("2,1,3,4,5,6,7,8");
});

test("several selected tasks move together, in their order", async ({ page }) => {
  await openPage(page);
  await item(page, "tasks", "Write the brief").click();
  await item(page, "tasks", "Order the badges").click({ modifiers: ["ControlOrMeta"] });
  await drag(page, item(page, "tasks", "Order the badges"), item(page, "tasks", "Set up the stream"), "below");
  await expect(order(page)).toHaveText("2,4,5,6,7,8,1,3");
  expect((await lastMove(page)).ids).toEqual(["1", "3"]);
});

test("a move the server refuses goes back", async ({ page }) => {
  await openPage(page, "/?refuse=1");
  await drag(page, item(page, "tasks", "Write the brief"), item(page, "tasks", "Print the schedule"), "below");
  await expect(page.locator("#tasks [aria-live]")).toContainText("not saved");
  expect((await labels(list(page)))[0]).toBe("Write the brief");
  await expect(order(page)).toHaveText("1,2,3,4,5,6,7,8");
});

test("Escape during a drag lets go, and nothing moves", async ({ page }) => {
  await openPage(page);
  const a = (await item(page, "tasks", "Write the brief").boundingBox())!;
  await page.mouse.move(a.x + 40, a.y + a.height / 2);
  await page.mouse.down();
  await page.mouse.move(a.x + 40, a.y + 150, { steps: 8 });
  await expect(page.locator(".narabe-ghost")).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(page.locator(".narabe-ghost")).toHaveCount(0);
  await page.mouse.up();
  await expect(page.locator("#last-move")).toBeEmpty();
});

test("another viewer sees the move", async ({ page, browser }) => {
  await openPage(page);
  const other = await browser.newPage();
  await other.goto("/");
  await expect(other.locator("[data-phx-main].phx-connected")).toBeVisible();
  await drag(page, item(page, "tasks", "Write the brief"), item(page, "tasks", "Order the badges"), "below");
  await expect.poll(async () => (await labels(other.locator("#tasks"))).slice(0, 3)).toEqual(["Book the venue", "Order the badges", "Write the brief"]);
  await other.close();
});
