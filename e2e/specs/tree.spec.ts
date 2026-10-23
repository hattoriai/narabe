import { expect, test, type Page } from "@playwright/test";
import { drag, item, labels, lastMove, openPage, order } from "./support";

const tree = (page: Page) => page.locator("#pages");
const row = (page: Page, label: string) => item(page, "pages", label);
const toggle = (page: Page, label: string) => row(page, label).locator("[data-narabe-toggle]");

test("rows open and close, with the mouse and the keyboard", async ({ page }) => {
  await openPage(page, "/tree");
  expect(await labels(tree(page))).toEqual(["Handbook", "Projects", "Archive", "Inbox"]);
  await toggle(page, "Handbook").click();
  await expect(row(page, "Handbook")).toHaveAttribute("aria-expanded", "true");
  expect(await labels(tree(page))).toEqual(["Handbook", "Welcome", "Engineering", "Design", "Projects", "Archive", "Inbox"]);

  await row(page, "Projects").focus();
  await page.keyboard.press("ArrowRight");
  await expect(row(page, "Narabe")).toBeVisible();
  await page.keyboard.press("ArrowRight");
  await expect(row(page, "Narabe")).toBeFocused();
  await page.keyboard.press("ArrowLeft");
  await expect(row(page, "Projects")).toBeFocused();
  await page.keyboard.press("ArrowLeft");
  await expect(row(page, "Narabe")).toBeHidden();
});

test("a drag into a closed folder puts the page at its end", async ({ page }) => {
  await openPage(page, "/tree");
  await drag(page, row(page, "Inbox"), row(page, "Projects"), "inside");
  await expect(order(page)).toContainText("Projects >Narabe >>Roadmap >Erabi >Inbox Archive");
  expect(await lastMove(page)).toMatchObject({ parent: String(await row(page, "Projects").getAttribute("data-id")) });
});

test("a closed folder held under a drag opens", async ({ page }) => {
  await openPage(page, "/tree");
  const a = (await row(page, "Inbox").boundingBox())!;
  const p = (await row(page, "Projects").boundingBox())!;
  await page.mouse.move(a.x + 60, a.y + a.height / 2);
  await page.mouse.down();
  await page.mouse.move(a.x + 60, a.y + 20, { steps: 2 });
  await page.mouse.move(p.x + 60, p.y + p.height / 2, { steps: 8 });
  await expect(row(page, "Projects")).toHaveAttribute("aria-expanded", "true", { timeout: 2000 });
  await expect(row(page, "Narabe")).toBeVisible();
  // Then between Narabe and Erabi, as Projects' child.
  const n = (await row(page, "Narabe").boundingBox())!;
  await page.mouse.move(a.x + 80, n.y + n.height * 0.9, { steps: 6 });
  await page.mouse.up();
  await expect(order(page)).toContainText("Projects >Narabe >>Roadmap >Inbox >Erabi");
});

test("the pointer's left and right pick the depth", async ({ page }) => {
  await openPage(page, "/tree");
  await toggle(page, "Projects").click();
  await toggle(page, "Narabe").click();
  // Inbox under Roadmap's level (a child of Narabe), then one level out (a child of Projects).
  await drag(page, row(page, "Inbox"), row(page, "Roadmap"), "below", 40);
  await expect(order(page)).toContainText(">>Roadmap >>Inbox >Erabi");
  await drag(page, row(page, "Inbox"), row(page, "Roadmap"), "below", -20);
  await expect(order(page)).toContainText(">>Roadmap >Inbox >Erabi");
});

test("the keyboard: Space lifts, Up and Down pick the gap, Right goes deeper", async ({ page }) => {
  await openPage(page, "/tree");
  await toggle(page, "Projects").click();
  await row(page, "Inbox").focus();
  await page.keyboard.press("Space");
  await page.keyboard.press("ArrowUp"); // after Erabi, still at the top level
  await page.keyboard.press("ArrowUp"); // after Narabe: Projects' child, at the least
  await page.keyboard.press("Space");
  await expect(order(page)).toContainText("Projects >Narabe >>Roadmap >Inbox >Erabi Archive");
  await expect(row(page, "Inbox")).toBeFocused();

  await page.keyboard.press("Space"); // lifted where it is: after Narabe
  await page.keyboard.press("ArrowRight"); // into Narabe, which is closed: at its end
  await page.keyboard.press("Space");
  await expect(order(page)).toContainText("Projects >Narabe >>Roadmap >>Inbox >Erabi Archive");
  await expect(row(page, "Narabe")).toHaveAttribute("aria-expanded", "true");
});

test("a drop where the items were sends nothing", async ({ page }) => {
  await openPage(page, "/tree");
  await toggle(page, "Handbook").click();
  await toggle(page, "Engineering").click();
  // Over its own subtree: not a place to land; the gap is where it was.
  await drag(page, row(page, "Handbook"), row(page, "On call"), "below", 40);
  await expect(page.locator("#pages [aria-live]")).toContainText("back in its place");
  await expect(page.locator("#last-move")).toBeEmpty();
});

test("a file holds nothing", async ({ page }) => {
  await openPage(page, "/tree");
  await toggle(page, "Handbook").click();
  await toggle(page, "Engineering").click();
  await toggle(page, "Releases").click();
  await drag(page, row(page, "Inbox"), row(page, "Checklist"), "inside", 40);
  await expect(order(page)).not.toContainText(">>>>Inbox");
});

test("a drop too deep is refused, and shows why", async ({ page }) => {
  await openPage(page, "/tree");
  await toggle(page, "Projects").click();
  await toggle(page, "Narabe").click();
  // Handbook is four levels; under Roadmap (level 3) it would reach level 7 of 6.
  const a = (await row(page, "Handbook").boundingBox())!;
  const b = (await row(page, "Roadmap").boundingBox())!;
  await page.mouse.move(a.x + 60, a.y + a.height / 2);
  await page.mouse.down();
  await page.mouse.move(a.x + 60, a.y + 20, { steps: 2 });
  await page.mouse.move(a.x + 140, b.y + b.height * 0.9, { steps: 8 });
  await expect(page.locator(".narabe-indicator.narabe-refused")).toBeVisible();
  await page.mouse.up();
  await expect(page.locator("#pages [aria-live]")).toContainText(/deep/i);
  await expect(page.locator("#last-move")).toBeEmpty();
});

test("the filter shows the matches and their ancestors", async ({ page }) => {
  await openPage(page, "/tree");
  await page.locator("#pages .narabe-filter").fill("road");
  await expect.poll(() => labels(tree(page))).toEqual(["Projects", "Narabe", "Roadmap"]);
  await expect(row(page, "Projects")).toHaveClass(/narabe-context/);
  await page.locator("#pages .narabe-filter").fill("");
  await expect.poll(() => labels(tree(page))).toEqual(["Handbook", "Projects", "Archive", "Inbox"]);
});

test("F2 renames in place", async ({ page }) => {
  await openPage(page, "/tree");
  await row(page, "Inbox").focus();
  await page.keyboard.press("F2");
  const box = page.locator("#pages .narabe-rename");
  await expect(box).toBeFocused();
  await box.fill("Later");
  await page.keyboard.press("Enter");
  await expect(order(page)).toContainText("Later");
  await expect(row(page, "Later")).toBeVisible();
});

test("children not loaded load as their folder opens", async ({ page }) => {
  await openPage(page, "/tree");
  await toggle(page, "Archive").click();
  await expect(row(page, "Archive")).toHaveAttribute("aria-busy", "");
  await expect(row(page, "Old notes 1")).toBeVisible();
  await expect(row(page, "Archive")).not.toHaveAttribute("aria-busy", "");
  await expect(row(page, "Archive")).toHaveAttribute("aria-expanded", "true");
});

test("the tree's roles and levels", async ({ page }) => {
  await openPage(page, "/tree");
  await expect(tree(page).locator('[role="tree"]')).toHaveAttribute("aria-label", "Pages");
  await expect(row(page, "Handbook")).toHaveAttribute("role", "treeitem");
  await expect(row(page, "Handbook")).toHaveAttribute("aria-level", "1");
  await expect(row(page, "Handbook")).toHaveAttribute("aria-expanded", "false");
  await expect(row(page, "Inbox")).not.toHaveAttribute("aria-expanded", /.*/);
  await expect(row(page, "Handbook")).toHaveAttribute("tabindex", "0");
});
