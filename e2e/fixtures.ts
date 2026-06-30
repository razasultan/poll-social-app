import { Page, expect } from '@playwright/test';

/** Seeded DEV account used by both the Flutter integration tests and these
 * Playwright E2E tests (see integration_test/app_test.dart). */
export const TEST_EMAIL = 'razasultan.gherkintest1@gmail.com';
export const TEST_PASSWORD = 'GherkinTest123!';
export const TEST_USERNAME = 'gherkintester1';

/** Logs in via the email/password form on the auth screen. */
export async function login(page: Page, email = TEST_EMAIL, password = TEST_PASSWORD) {
  // Bare fill() has intermittently left Flutter web's Email field seeing a
  // stale/empty value (same class of issue documented for the Password
  // field below) - click()+fill('')+pressSequentially is the reliable
  // pattern used elsewhere in this suite (see e2e/profile.spec.ts PROF-08/09).
  const emailField = page.getByRole('textbox', { name: 'Email' });
  await emailField.click();
  await emailField.fill('');
  await emailField.pressSequentially(email);
  // Flutter's obscureText fields use <input type="password"> which ignores
  // fill() (value= assignment). pressSequentially dispatches real key events
  // that Flutter's input pipeline picks up correctly.
  const pwd = page.getByRole('textbox', { name: 'Password' });
  await pwd.click();
  await pwd.pressSequentially(password);
  await page.getByRole('button', { name: 'Sign in' }).click();
  // Wait for the LoginScreen to pop (confirms auth succeeded).
  await expect(page.getByText('Welcome back')).toBeHidden({ timeout: 15_000 });
  // Wait for the shell to finish re-rendering with the auth nav (5 tabs).
  // Without this the BottomNavBar may still show 4 (guest) tabs and a
  // subsequent click on /Profile\s+Tab \d of \d/ lands on the wrong item.
  await expect(
    page.getByRole('button', { name: /Notifications\s+Tab \d of \d/ }),
  ).toBeVisible({ timeout: 10_000 });
}

/** Navigates to the Profile tab via the bottom/side nav. */
export async function goToProfileTab(page: Page) {
  await page.getByRole('button', { name: /Profile\s+Tab \d of \d/ }).click();
  await expect(page.getByRole('heading', { name: 'Profile' })).toBeVisible();
}

/** Logs in (if needed) and lands on the signed-in user's Profile tab. */
export async function loginAndGoToProfile(page: Page) {
  await page.goto('/');

  const profileTab = page.getByRole('button', { name: /Profile\s+Tab \d of \d/ });
  await profileTab.click();

  const loginButton = page.getByRole('button', { name: 'Login' });
  if (await loginButton.isVisible().catch(() => false)) {
    await loginButton.click();
    await login(page);
    await goToProfileTab(page);
  } else {
    await expect(page.getByRole('heading', { name: 'Profile' })).toBeVisible();
  }
  // Ensure profile data has fully loaded before returning so each test in a
  // beforeEach block starts with a completely rendered profile, not a spinner.
  await expect(page.getByText(`@${TEST_USERNAME}`)).toBeVisible();
}

/** Opens the "Edit profile" bottom sheet from the Profile tab's Settings page. */
export async function openEditProfile(page: Page) {
  await page.getByRole('button', { name: 'Settings' }).click();
  await page.getByRole('button', { name: /Edit profile/ }).click();
  await expect(page.getByText('Edit profile', { exact: true })).toBeVisible();
}
