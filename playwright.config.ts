import { defineConfig, devices } from '@playwright/test';

/**
 * E2E config for the Flutter web app. The app is driven through its
 * accessibility (semantics) tree — see `_semanticsHandle` in `lib/main.dart`,
 * which keeps ARIA roles/labels in the DOM so Playwright can use
 * `getByRole`/`getByText` instead of reading the CanvasKit/Skwasm canvas.
 *
 * Tests run against the DEV Supabase backend (poll-social-app-dev) using the
 * seeded `gherkintester1` account (see e2e/fixtures.ts).
 */
export default defineConfig({
  testDir: './e2e',
  fullyParallel: false,
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  reporter: [['html', { open: 'never' }]],
  timeout: 60_000,
  expect: { timeout: 10_000 },
  use: {
    baseURL: 'http://127.0.0.1:8765',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    actionTimeout: 15_000,
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  // Both CI and local dev serve the pre-built output with npx serve.
  // CI: the e2e-web job runs `flutter build web` before `npx playwright test`.
  // Local: run `flutter build web --dart-define=APP_ENV=dev ...` once, then
  //        keep the server alive across test runs with reuseExistingServer.
  webServer: {
    command: 'npx serve build/web --listen 8765 --no-clipboard',
    url: 'http://127.0.0.1:8765',
    reuseExistingServer: !process.env.CI,
    timeout: 30_000,
  },
});
