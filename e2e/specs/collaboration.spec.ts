import { expect, test } from "@playwright/test";
import { item, openPage, order } from "./support";

test("another person sees a drag, where it would land, and cannot lift the card", async ({ page, browser }) => {
  await openPage(page, "/board?user=ada");
  const ken = await browser.newPage();
  await ken.goto("/board?user=ken");
  await expect(ken.locator("[data-phx-main].phx-connected")).toBeVisible();

  const a = (await item(page, "board", "Search in the docs").boundingBox())!;
  const b = (await item(page, "board", "Lazy children").boundingBox())!;
  await page.mouse.move(a.x + 60, a.y + 20);
  await page.mouse.down();
  await page.mouse.move(a.x + 60, a.y + 30, { steps: 2 });
  await page.mouse.move(b.x + 60, b.y + 8, { steps: 10 });

  const card = item(ken, "board", "Search in the docs");
  await expect(card).toHaveClass(/narabe-held/);
  await expect(card).toHaveAttribute("data-narabe-peer", "Ada");
  await expect(ken.locator(".narabe-peer-line .narabe-peer-name")).toHaveText("Ada");

  await card.focus();
  await ken.keyboard.press("Space");
  await expect(ken.locator("#board [aria-live]")).toContainText("Ada is moving this");
  await expect(card).not.toHaveClass(/narabe-lifted/);

  await page.mouse.up();
  await expect(order(ken)).toContainText("Doing: Keyboard moves on boards,Search in the docs,Lazy children");
  await expect(card).not.toHaveClass(/narabe-held/);
  await expect(ken.locator(".narabe-peer-line")).toHaveCount(0);
  await ken.close();
});

test("an agent's move: the card held, its drop line, then the move", async ({ page }) => {
  await openPage(page, "/board?user=ken");
  await page.locator("#agent").click();
  await expect(item(page, "board", "Search in the docs")).toHaveAttribute("data-narabe-peer", "Claude");
  await expect(page.locator(".narabe-peer-line .narabe-peer-name")).toHaveText("Claude");
  await expect(order(page)).toContainText("Done: Search in the docs,Position keys");
  await expect(page.locator(".narabe-peer-line")).toHaveCount(0);
});
