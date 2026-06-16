import { test, expect } from '@playwright/test';

/** Navigates a guest from the home screen to the login screen. */
async function goToLogin(page: import('@playwright/test').Page) {
  await page.goto('/');
  await page.getByRole('button', { name: /Profile\s+Tab \d of \d/ }).click();
  await page.getByRole('button', { name: 'Login' }).click();
  await expect(page.getByText('Welcome back')).toBeVisible();
}

test.describe('Login screen redesign', () => {
  // Below the 700px NavigationRail breakpoint (lib/screens/main_shell.dart),
  // so the bottom nav bar is used. Its destinations expose accessible names
  // like "Profile\nTab 4 of 4" — Flutter's MergeSemantics concatenates the
  // item's text label with the position Semantics using a newline separator.
  test.use({ viewport: { width: 600, height: 900 } });

  test('LOGIN-01: shows the welcome header, OAuth buttons, and form fields', async ({ page }) => {
    await goToLogin(page);

    await expect(page.getByText('Welcome back')).toBeVisible();
    await expect(page.getByText('Sign in to vote and share polls')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Continue with Google' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Continue with Apple' })).toBeVisible();
    await expect(page.getByRole('textbox', { name: 'Email' })).toBeVisible();
    await expect(page.getByRole('textbox', { name: 'Password' })).toBeVisible();
  });

  test('LOGIN-02: password show/hide toggle changes the field state', async ({ page }) => {
    await goToLogin(page);

    const showButton = page.getByRole('button', { name: 'Show password' });
    await expect(showButton).toBeVisible();

    await showButton.click();
    await expect(page.getByRole('button', { name: 'Hide password' })).toBeVisible();
  });

  test('LOGIN-03: "Create an account" navigates to the signup card', async ({ page }) => {
    await goToLogin(page);

    await page.getByRole('button', { name: 'Create an account' }).click();

    await expect(page.getByText('Create your account')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Continue with Google' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Continue with Apple' })).toBeVisible();
  });

  test('LOGIN-04: "Forgot password?" opens the reset-password dialog', async ({ page }) => {
    await goToLogin(page);

    await page.getByRole('button', { name: 'Forgot password?' }).click();

    await expect(page.getByRole('alertdialog').getByText('Reset password')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Send link' })).toBeVisible();
  });
});
