import { expect, test, type CDPSession, type Page } from "@playwright/test";
import { item, labels, openPage, order } from "./support";

// A phone: a finger, a narrow screen. Chromium's touch, through CDP (the
// held finger and its moves are what a drag on a phone is).
test.use({ viewport: { width: 390, height: 760 }, hasTouch: true, isMobile: true });
test.skip(({ browserName }) => browserName !== "chromium", "touch through CDP: Chromium only");

async function finger(page: Page): Promise<CDPSession> {
  return page.context().newCDPSession(page);
}

async function touch(cdp: CDPSession, type: "touchStart" | "touchMove" | "touchEnd", x: number, y: number): Promise<void> {
  await cdp.send("Input.dispatchTouchEvent", { type, touchPoints: type === "touchEnd" ? [] : [{ x, y }] });
}

test("a held finger drags a task", async ({ page }) => {
  await openPage(page);
  const cdp = await finger(page);
  const a = (await item(page, "tasks", "Write the brief").boundingBox())!;
  const b = (await item(page, "tasks", "Order the badges").boundingBox())!;
  const x = a.x + 60;
  await touch(cdp, "touchStart", x, a.y + a.height / 2);
  await page.waitForTimeout(400);
  await expect(page.locator(".narabe-ghost")).toBeVisible();
  for (let i = 1; i <= 10; i++) await touch(cdp, "touchMove", x, a.y + a.height / 2 + ((b.y + b.height * 0.8 - a.y - a.height / 2) * i) / 10);
  await touch(cdp, "touchEnd", x, b.y + b.height * 0.8);
  await expect(order(page)).toHaveText("2,3,1,4,5,6,7,8");
});

test("a quick swipe scrolls, and drags nothing", async ({ page }) => {
  await openPage(page);
  const cdp = await finger(page);
  const a = (await item(page, "tasks", "Print the schedule").boundingBox())!;
  await touch(cdp, "touchStart", a.x + 60, a.y + 10);
  for (let i = 1; i <= 6; i++) await touch(cdp, "touchMove", a.x + 60, a.y + 10 - i * 20);
  await touch(cdp, "touchEnd", a.x + 60, a.y - 110);
  await page.waitForTimeout(400);
  await expect(page.locator(".narabe-ghost")).toHaveCount(0);
  await expect(page.locator("#last-move")).toBeEmpty();
});

test("a tree one level at a time", async ({ page }) => {
  await openPage(page, "/tree");
  await expect(page.locator("#pages")).toHaveClass(/narabe-drilling/);
  expect(await labels(page.locator("#pages"))).toEqual(["Handbook", "Projects", "Archive", "Inbox"]);
  await item(page, "pages", "Handbook").tap();
  await expect.poll(() => labels(page.locator("#pages"))).toEqual(["Welcome", "Engineering", "Design"]);
  await expect(page.locator("#pages .narabe-drill-title")).toHaveText("Handbook");
  await item(page, "pages", "Engineering").tap();
  await expect.poll(() => labels(page.locator("#pages"))).toEqual(["Code review", "On call", "Releases"]);
  await page.locator("#pages .narabe-back").tap();
  await expect.poll(() => labels(page.locator("#pages"))).toEqual(["Welcome", "Engineering", "Design"]);
  await page.locator("#pages .narabe-back").tap();
  await expect.poll(() => labels(page.locator("#pages"))).toEqual(["Handbook", "Projects", "Archive", "Inbox"]);
});

test("a held finger reorders within a level, one level at a time", async ({ page }) => {
  await openPage(page, "/tree");
  await item(page, "pages", "Handbook").tap();
  const cdp = await finger(page);
  const a = (await item(page, "pages", "Welcome").boundingBox())!;
  const b = (await item(page, "pages", "Design").boundingBox())!;
  await touch(cdp, "touchStart", a.x + 80, a.y + a.height / 2);
  await page.waitForTimeout(400);
  for (let i = 1; i <= 8; i++) await touch(cdp, "touchMove", a.x + 80, a.y + a.height / 2 + ((b.y + b.height * 0.85 - a.y - a.height / 2) * i) / 8);
  await touch(cdp, "touchEnd", a.x + 80, b.y + b.height * 0.85);
  await expect(order(page)).toContainText("Handbook >Engineering");
  await expect(order(page)).toContainText(">Design >>Brand >>Logo.svg >Welcome Projects");
});
