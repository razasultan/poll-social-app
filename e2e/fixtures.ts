import { Page, expect } from '@playwright/test';

/** Seeded DEV account used by both the Flutter integration tests and these
 * Playwright E2E tests (see integration_test/app_test.dart). */
export const TEST_EMAIL = 'razasultan.gherkintest1@gmail.com';
export const TEST_PASSWORD = 'GherkinTest123!';
export const TEST_USERNAME = 'gherkintester1';

/** Logs in via the email/password form on the auth screen. */
export async function login(page: Page, email = TEST_EMAIL, password = TEST_PASSWORD) {
  await page.getByRole('textbox', { name: 'Email' }).fill(email);
  // Flutter's obscureText fields use <input type="password"> which ignores
  // fill() (value= assignment). pressSequentially dispatches real key events
  // that Flutter's input pipeline picks up correctly.
  const pwd = page.getByRole('textbox', { name: 'Password' });
  await pwd.click();
  await pwd.pressSequentially(password);
  await page.getByRole('button', { name: 'Sign in' }).click();
  // Wait for the LoginScreen to pop (confirms auth succeeded before the caller
  // tries to navigate away with goToProfileTab).
  await expect(page.getByText('Welcome back')).toBeHidden({ timeout: 15_000 });
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
}

/** Opens the "Edit profile" bottom sheet from the Profile tab's Settings page. */
export async function openEditProfile(page: Page) {
  await page.getByRole('button', { name: 'Settings' }).click();
  await page.getByRole('button', { name: /Edit profile/ }).click();
  await expect(page.getByText('Edit profile', { exact: true })).toBeVisible();
}
