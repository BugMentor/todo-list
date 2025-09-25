// playwright.config.ts
import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./tests", // This tells Playwright to look for tests in a 'tests' directory
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: "html",
  use: {
    baseURL: "http://localhost:3000", // Your app will be served here
    trace: "on-first-retry",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
  // This is the crucial part that was likely missing or incorrect
  webServer: {
    command: "npm start", // Command to start your web server (which now uses http-server)
    url: "http://localhost:3000", // URL to check if the server is ready
    reuseExistingServer: !process.env.CI, // Reuse server if not in CI
  },
});
