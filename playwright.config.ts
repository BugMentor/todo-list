// playwright.config.ts
import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  // Directory where tests are located
  testDir: "./tests",
  // Maximum time one test can run for
  timeout: 30000,
  // Run tests in files in parallel
  fullyParallel: true,
  // Fail the build on CI if you accidentally left test.only in the source code
  forbidOnly: !!process.env.CI,
  // Retry on CI only
  retries: process.env.CI ? 2 : 0,
  // Limit parallel workers on CI, use default locally
  workers: process.env.CI ? 1 : undefined,
  // Reporter to use - includes HTML, JUnit for CI integration, and JSON for data processing
  reporter: [
    ["html", { outputFolder: "playwright-report" }],
    ["junit", { outputFile: "playwright-report/junit.xml" }],
    ["json", { outputFile: "playwright-report/test-results.json" }],
  ],
  // Shared settings for all the projects below
  use: {
    // Base URL to use in actions like `await page.goto('/')`
    baseURL: "http://localhost:3000",
    // Collect trace when retrying the failed test
    trace: "on-first-retry",
    // Record video for failed tests
    video: "on-first-retry",
    // Take screenshot on failure
    screenshot: "only-on-failure",
    // Enable coverage collection
    launchOptions: {
      args: ["--enable-precise-memory-info"],
    },
  },
  // Configure projects for major browsers
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
    // Uncomment these for multi-browser testing
    // {
    //   name: 'firefox',
    //   use: { ...devices['Desktop Firefox'] },
    // },
    // {
    //   name: 'webkit',
    //   use: { ...devices['Desktop Safari'] },
    // },
  ],

  // Run local dev server before starting the tests
  webServer: {
    command: "npm start",
    url: "http://localhost:3000",
    reuseExistingServer: !process.env.CI,
    timeout: 60000,
  },

  // Output directory for test artifacts
  outputDir: "test-results/",
});
