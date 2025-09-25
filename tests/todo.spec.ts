import { test, expect } from "@playwright/test";

test.beforeEach(async ({ page }) => {
  await page.goto("/"); // Explicitly navigate to the base URL
  await page.waitForLoadState("networkidle"); // Wait for the network to be idle
});

test("should allow me to add todo items", async ({ page }) => {
  const newTodo = page.getByPlaceholder("Add a todo . . .");
  await newTodo.fill("buy some cheese");
  await newTodo.press("Enter");
  await expect(page.getByText("buy some cheese")).toBeVisible();
});

test("should allow me to complete a todo item", async ({ page }) => {
  const newTodo = page.getByPlaceholder("Add a todo . . .");
  await newTodo.fill("buy some cheese");
  await newTodo.press("Enter");

  // Locate the table row (tr) that contains the text "buy some cheese" and click on the text itself
  await page
    .locator("tbody.todos-list-body tr", { hasText: "buy some cheese" })
    .locator("td")
    .first()
    .click();

  // Assuming the 'completed' class is applied to the span element inside the td
  await expect(
    page
      .locator("tbody.todos-list-body tr", { hasText: "buy some cheese" })
      .locator("td")
      .first()
      .locator("span")
  ).toHaveClass(/completed/);
});

test("should allow me to clear completed todos", async ({ page }) => {
  const newTodo = page.getByPlaceholder("Add a todo . . .");
  await newTodo.fill("buy some cheese");
  await newTodo.press("Enter");
  await newTodo.fill("drink some milk");
  await newTodo.press("Enter");

  // Locate and click the first todo to mark it as complete
  await page
    .locator("tbody.todos-list-body tr", { hasText: "buy some cheese" })
    .locator("td")
    .first()
    .click();

  await page.getByRole("button", { name: "Delete All" }).click();

  // After clearing, the 'buy some cheese' todo should not be visible
  await expect(page.getByText("buy some cheese")).not.toBeVisible();
  // 'drink some milk' should still be visible
  await expect(page.getByText("drink some milk")).toBeVisible();
});

test("should allow me to filter todos", async ({ page }) => {
  const newTodo = page.getByPlaceholder("Add a todo . . .");
  await newTodo.fill("buy some cheese");
  await newTodo.press("Enter");
  await newTodo.fill("drink some milk");
  await newTodo.press("Enter");

  // Mark 'buy some cheese' as completed
  await page
    .locator("tbody.todos-list-body tr", { hasText: "buy some cheese" })
    .locator("td")
    .first()
    .click();

  // Filter by Active tasks (Pending)
  await page.getByRole("button", { name: "Filter" }).click();
  await page.getByRole("link", { name: "Pending" }).click();
  await expect(page.getByText("buy some cheese")).not.toBeVisible();
  await expect(page.getByText("drink some milk")).toBeVisible();

  // Filter by Completed tasks
  await page.getByRole("button", { name: "Filter" }).click();
  await page.getByRole("link", { name: "Completed" }).click();
  await expect(page.getByText("buy some cheese")).toBeVisible();
  await expect(page.getByText("drink some milk")).not.toBeVisible();

  // Filter by All tasks
  await page.getByRole("button", { name: "Filter" }).click();
  await page.getByRole("link", { name: "All Tasks" }).click();
  await expect(page.getByText("buy some cheese")).toBeVisible();
  await expect(page.getByText("drink some milk")).toBeVisible();
});
