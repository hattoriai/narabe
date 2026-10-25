import { expect, test, type CDPSession, type Page } from "@playwright/test";
import { drag, item, labels, lastMove, openPage, order } from "./support";

// Lists of a group (dev.exs: /group and /folders): the board "week" in the
// LiveView, the list "someday" in a component, the list "errands" in a
// LiveView of its own; the tree "folders" beside the list "handbook".

const card = (page: Page, label: string) => item(page, "week", label);
const column = (page: Page, name: string) => page.locator("#week [data-narabe-group]", { has: page.locator(".narabe-column-title", { hasText: name }) });
const START = "Launch: Write the launch post,Record the demo | Website: New pricing page,Fix the footer | Someday: Learn the cello,Pick up the dry cleaning | Errands: Buy stamps,Return the library books";

test("a task moves from a list to a board's column, and the list hears it left", async ({ page }) => {
  await openPage(page, "/group");
  await drag(page, item(page, "someday", "Learn the cello"), card(page, "Record the demo"), "below");
  await expect(order(page)).toContainText("Launch: Write the launch post,Record the demo,Learn the cello | Website");
  await expect(order(page)).toContainText("Someday: Pick up the dry cleaning |");
  const move = await lastMove(page);
  expect(move).toMatchObject({ ids: [await item(page, "week", "Learn the cello").getAttribute("data-id")], from: "someday", after: await card(page, "Record the demo").getAttribute("data-id") });
  expect(move.parent).toBe(await column(page, "Launch").getAttribute("data-id"));
  await expect(page.locator("#last-leave")).toContainText('"to":"week"');
  expect(await labels(page.locator("#someday"))).toEqual(["Pick up the dry cleaning"]);
});

test("a card moves from the board to a list in another LiveView", async ({ page }) => {
  await openPage(page, "/group");
  await drag(page, item(page, "someday", "Pick up the dry cleaning"), item(page, "errands", "Return the library books"), "above");
  await expect(order(page)).toContainText("Errands: Buy stamps,Pick up the dry cleaning,Return the library books");
  await drag(page, card(page, "Fix the footer"), item(page, "someday", "Learn the cello"), "above");
  await expect(order(page)).toContainText("Website: New pricing page | Someday: Fix the footer,Learn the cello |");
  expect((await lastMove(page)).from).toBe("week");
  expect(await labels(page.locator("#week"))).toEqual(["Write the launch post", "Record the demo", "New pricing page"]);
});

test("a list's rules hold for items of the others: the errands take errands only", async ({ page }) => {
  await openPage(page, "/group");
  await drag(page, card(page, "Fix the footer"), item(page, "errands", "Buy stamps"), "below");
  await expect(page.locator("#week [aria-live]")).toContainText("can't hold it");
  await expect(page.locator("#last-move")).toBeEmpty();
  await expect(order(page)).toHaveText(START);
  expect(await labels(column(page, "Website"))).toEqual(["New pricing page", "Fix the footer"]);
});

test("a move the other list's server refuses goes back to both lists", async ({ page }) => {
  await openPage(page, "/group?refuse=1");
  await drag(page, item(page, "someday", "Learn the cello"), card(page, "Write the launch post"), "below");
  await expect(page.locator("#week [aria-live]")).toContainText("not saved");
  expect(await labels(page.locator("#someday"))).toEqual(["Learn the cello", "Pick up the dry cleaning"]);
  expect(await labels(column(page, "Launch"))).toEqual(["Write the launch post", "Record the demo"]);

  // To the list of another LiveView, which refuses too.
  await drag(page, item(page, "someday", "Pick up the dry cleaning"), item(page, "errands", "Buy stamps"), "below");
  await expect(page.locator("#errands [aria-live]")).toContainText("not saved");
  expect(await labels(page.locator("#someday"))).toEqual(["Learn the cello", "Pick up the dry cleaning"]);
  expect(await labels(page.locator("#errands"))).toEqual(["Buy stamps", "Return the library books"]);
  await expect(order(page)).toHaveText(START);
  await expect(page.locator("#last-leave")).toBeEmpty();
});

test("the keyboard: Tab takes a lifted task to the next list of the group", async ({ page }) => {
  await openPage(page, "/group");
  await item(page, "someday", "Learn the cello").focus();
  await page.keyboard.press("Space");
  await expect(page.locator("#someday [aria-live]")).toContainText("Tab takes it to another list");
  // The errands, which refuse a task; then, round, the board.
  await page.keyboard.press("Tab");
  await expect(page.locator("#someday [aria-live]")).toContainText("can't hold it");
  await expect(page.locator("#errands")).toHaveClass(/narabe-receiving/);
  await page.keyboard.press("Tab");
  await expect(page.locator("#errands")).not.toHaveClass(/narabe-receiving/);
  await expect(page.locator("#week")).toHaveClass(/narabe-receiving/);
  await expect(item(page, "someday", "Learn the cello")).toBeFocused();
  await page.keyboard.press("ArrowRight");
  await page.keyboard.press("ArrowDown");
  await expect(page.locator("#someday [aria-live]")).toContainText("in Website, 2 of 3");
  await page.keyboard.press("Space");
  await expect(order(page)).toContainText("Website: New pricing page,Learn the cello,Fix the footer |");
  await expect(card(page, "Learn the cello")).toBeFocused();
});

test("the keyboard: Shift+Tab goes back, and Escape puts the task back", async ({ page }) => {
  await openPage(page, "/group");
  await item(page, "someday", "Learn the cello").focus();
  await page.keyboard.press("Space");
  await page.keyboard.press("Shift+Tab");
  await expect(page.locator("#week")).toHaveClass(/narabe-receiving/);
  await page.keyboard.press("Escape");
  await expect(page.locator("#week")).not.toHaveClass(/narabe-receiving/);
  await expect(page.locator(".narabe-indicator:visible")).toHaveCount(0);
  await expect(page.locator("#last-move")).toBeEmpty();
  await expect(item(page, "someday", "Learn the cello")).toBeFocused();
});

test("a page of the list goes into a folder of the tree, and a folder into the list", async ({ page }) => {
  await openPage(page, "/folders");
  await drag(page, item(page, "handbook", "Welcome"), item(page, "folders", "Projects"), "inside");
  await expect(order(page)).toContainText("Projects >Welcome >Narabe");
  const move = await lastMove(page);
  expect(move).toMatchObject({ from: "handbook", parent: await item(page, "folders", "Projects").getAttribute("data-id") });
  expect(await labels(page.locator("#handbook"))).toEqual(["Engineering", "Design"]);

  await drag(page, item(page, "folders", "Archive"), item(page, "handbook", "Design"), "below");
  await expect(order(page)).toContainText(">Design >>Brand >>Logo.svg >Archive >>Old notes 1");
  expect((await lastMove(page)).from).toBe("folders");
  expect(await labels(page.locator("#handbook"))).toEqual(["Engineering", "Design", "Archive"]);
});

test.describe("on a phone", () => {
  test.use({ viewport: { width: 390, height: 760 }, hasTouch: true, isMobile: true });
  test.skip(({ browserName }) => browserName !== "chromium", "touch through CDP: Chromium only");

  async function touch(cdp: CDPSession, type: "touchStart" | "touchMove" | "touchEnd", x: number, y: number): Promise<void> {
    await cdp.send("Input.dispatchTouchEvent", { type, touchPoints: type === "touchEnd" ? [] : [{ x, y }] });
  }

  test("a held finger drags a page from the list into a folder of the tree", async ({ page }) => {
    await openPage(page, "/folders");
    const cdp = await page.context().newCDPSession(page);
    const a = (await item(page, "handbook", "Welcome").boundingBox())!;
    const b = (await item(page, "folders", "Archive").boundingBox())!;
    const from = { x: a.x + 80, y: a.y + a.height / 2 };
    const to = { x: b.x + 80, y: b.y + b.height / 2 };
    await touch(cdp, "touchStart", from.x, from.y);
    await page.waitForTimeout(400);
    await expect(page.locator(".narabe-ghost")).toBeVisible();
    for (let i = 1; i <= 12; i++) await touch(cdp, "touchMove", from.x + ((to.x - from.x) * i) / 12, from.y + ((to.y - from.y) * i) / 12);
    await touch(cdp, "touchEnd", to.x, to.y);
    await expect(order(page)).toContainText("Archive >Welcome");
  });
});
