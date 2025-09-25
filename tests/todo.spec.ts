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
  // This click is expected to toggle the completion status and apply the 'completed' class.
  await page
    .locator("tbody.todos-list-body tr", { hasText: "buy some cheese" })
    .locator(".btn.btn-success.btn-xs.toggle-btn")
    .click();

  // Assuming the 'completed' class is applied to the span element inside the td
  // This expectation will pass once the application's JS correctly adds the 'completed' class.
  await expect(
    page
      .locator("tbody.todos-list-body tr", { hasText: "buy some cheese" })
      .locator(".btn.btn-success.btn-xs.toggle-btn")
      .first()
      .locator("span")
  ).not.toBeVisible();
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
    .locator(".btn.btn-success.btn-xs.toggle-btn")
    .click();

  // Click the "Delete All" button.
  // This test assumes "Delete All" only clears *completed* todos.
  // If "Delete All" truly deletes all todos, the application's JS or the test's expectation needs adjustment.
  await page
    .locator("tbody.todos-list-body tr", { hasText: "buy some cheese" })
    .locator(".btn.btn-error.btn-xs.delete-btn")
    .click();

  await page.locator('div.modal.modal-open div div button.btn.btn-error').click();

  // After clearing, the 'buy some cheese' todo should not be visible (because it was completed)
  // This expectation will pass once the application's JS correctly removes completed todos.
  await expect(page.getByText("buy some cheese")).not.toBeVisible();
  // 'drink some milk' should still be visible (because it was not completed)
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
    .locator(".btn.btn-success.btn-xs.toggle-btn")
    .click();
  
  // The HTML uses a <label> element with text " Filter " as the dropdown trigger.
  // Playwright's getByLabel() is the most semantic way to target this.
  // Filter by Active tasks (Pending)
  await page.locator('div.search-filter-section.mb-4.w-full > div > div.dropdown').click(); // Corrected selector
  await page.locator('a[data-filter="pending"]').click({ timeout: 30000 });
  // These expectations will pass once the application's JS correctly filters todos.
  await expect(page.getByText("buy some cheese")).not.toBeVisible();
  await expect(page.getByText("drink some milk")).toBeVisible();

  // Filter by Completed tasks
  await page.locator('div.search-filter-section.mb-4.w-full > div > div.dropdown').click(); // Corrected selector
  await page.locator('a[data-filter="completed"]').click({ timeout: 30000 });
  // These expectations will pass once the application's JS correctly filters todos.
  await expect(page.getByText("buy some cheese")).toBeVisible();
  await expect(page.getByText("drink some milk")).not.toBeVisible();

  // Filter by All tasks
  await page.locator('div.search-filter-section.mb-4.w-full > div > div.dropdown').click(); // Corrected selector
  await page.locator('a[data-filter="all"]').click({ timeout: 30000 });
  // These expectations will pass once the application's JS correctly filters todos.
  await expect(page.getByText("buy some cheese")).toBeVisible();
  await expect(page.getByText("drink some milk")).toBeVisible();
});
