import { test as setup, expect } from '@playwright/test';
import { login, TEST_USERNAME } from './fixtures';

const authFile = 'playwright/.auth/user.json';

/**
 * Signs in once and persists the Supabase session (stored in localStorage)
 * so the authenticated describe blocks in profile.spec.ts can restore it
 * via storageState without calling signInWithPassword again.
 *
 * Supabase's free tier rate-limits repeated sign-ins per email (~5/min).
 * Without this setup, each test's beforeEach would call login(), exhausting
 * that limit before the suite finishes.
 */
setup('sign in and save session', async ({ page }) => {
  // Use narrow viewport so BottomNavigationBar is rendered — NavigationRail
  // destinations are wrapped in ExcludeSemantics and never appear as buttons.
  await page.setViewportSize({ width: 600, height: 900 });
  await page.goto('/');

  await page.getByRole('button', { name: /Profile\s+Tab \d of \d/ }).click();
  await page.getByRole('button', { name: 'Login' }).click();
  await login(page);

  // login() waits for the Notifications tab, confirming the 5-item auth nav
  // is rendered. Now navigate to Profile (5-of-5) to verify auth.
  await page.getByRole('button', { name: /Profile\s+Tab \d of \d/ }).click();
  // .first(): the profile header's own @username renders before the user's
  // poll list, but each poll card below also shows "@username" as its
  // author byline - with enough accumulated test polls on this shared dev
  // account, a bare getByText match becomes ambiguous (strict-mode
  // violation). The header instance is reliably first in DOM order.
  await expect(page.getByText(`@${TEST_USERNAME}`).first()).toBeVisible({
    timeout: 15_000,
  });

  await page.context().storageState({ path: authFile });
});
