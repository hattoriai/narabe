import { expect, test } from "@playwright/test";
import { item, openPage } from "./support";

const posted = async (page: import("@playwright/test").Page) => JSON.parse((await page.locator("#posted").getAttribute("data-json")) ?? "{}");

test("a tree picker opens at the chosen item, and posts the one picked", async ({ page }) => {
  await openPage(page, "/picker");
  const engineering = page.locator("#move_parent_id [data-narabe-item][data-label='Engineering']");
  await expect(engineering).toHaveAttribute("aria-selected", "true");
  await expect(engineering).toBeVisible();

  await page.locator("#move_parent_id [data-narabe-item][data-label='Projects'] .narabe-label").click();
  await expect(page.locator("#move_parent_id input[data-narabe-value]")).toHaveValue(/\d+/);
  await expect.poll(async () => (await posted(page)).move?.parent_id).toBe(await page.locator("#move_parent_id [data-label='Projects']").getAttribute("data-id"));

  // The keyboard: Down, then Enter.
  await page.locator("#move_parent_id [data-label='Projects']").focus();
  await page.keyboard.press("ArrowDown");
  await page.keyboard.press("Enter");
  await expect(page.locator("#move_parent_id [data-label='Archive']")).toHaveAttribute("aria-selected", "true");
  void item;
});

test("a tree picker never drags", async ({ page }) => {
  await openPage(page, "/picker");
  const a = (await page.locator("#move_parent_id [data-label='Projects']").boundingBox())!;
  await page.mouse.move(a.x + 50, a.y + a.height / 2);
  await page.mouse.down();
  await page.mouse.move(a.x + 50, a.y + 80, { steps: 6 });
  await expect(page.locator(".narabe-ghost")).toHaveCount(0);
  await page.mouse.up();
});
