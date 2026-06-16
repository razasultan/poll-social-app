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
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  webServer: process.env.CI
    ? {
        // CI: compile fresh and serve via flutter run
        command:
          'flutter run -d web-server --web-port=8765 --web-hostname=127.0.0.1 ' +
          '--dart-define=APP_ENV=dev ' +
          '--dart-define=SUPABASE_URL=https://uwomsxkvjqrvhdpnbkit.supabase.co ' +
          '--dart-define=SUPABASE_ANON_KEY=sb_publishable_LgwGHGciORtyBWVRajywqA_JYzCokcF',
        url: 'http://127.0.0.1:8765',
        reuseExistingServer: false,
        timeout: 300_000,
      }
    : {
        // Local dev: serve the pre-built release from build/web (fast, no recompile).
        // Run `flutter build web --dart-define=APP_ENV=dev ...` before testing.
        command: 'npx serve build/web --listen 8765 --no-clipboard',
        url: 'http://127.0.0.1:8765',
        reuseExistingServer: true,
        timeout: 30_000,
      },
});
