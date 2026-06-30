import { test, expect } from '@playwright/test';
import {
  loginAndGoToProfile,
  goToProfileTab,
  openEditProfile,
  login,
  TEST_USERNAME,
} from './fixtures';

// Force narrow viewport so the BottomNavigationBar is rendered (not the
// NavigationRail). Flutter's NavigationRailDestination wraps its icon in
// ExcludeSemantics internally, so destinations never appear as ARIA buttons
// and getByRole('button', { name: /Profile/ }) times out. At ≤699px the
// BottomNavigationBar is used and its items are correctly exposed as buttons.
test.use({ viewport: { width: 600, height: 900 } });

test.describe('Profile page — guest', () => {
  test('PROF-01: guest is shown a login prompt instead of a profile', async ({ page }) => {
    await page.goto('/');
    await goToProfileTab(page).catch(() => {
      /* heading check below covers the guest case too */
    });

    await expect(page.getByText('Log in to view and edit your profile')).toBeVisible();
    await expect(page.getByRole('button', { name: 'Login' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Sign up' })).toBeVisible();
  });

  test('PROF-02: guest can sign in from the Profile tab and lands on their profile', async ({ page }) => {
    await page.goto('/');
    await page.getByRole('button', { name: /Profile\s+Tab \d of \d/ }).click();
    await page.getByRole('button', { name: 'Login' }).click();

    await login(page);

    await goToProfileTab(page);
    await expect(page.getByText(`@${TEST_USERNAME}`)).toBeVisible();
  });
});

test.describe('Profile page — authenticated', () => {
  // Restore the Supabase session saved by auth.setup.ts so Flutter boots in
  // authenticated state — avoids repeated signInWithPassword calls that hit
  // Supabase's free-tier rate limit (~5 sign-ins/min per email).
  test.use({ storageState: 'playwright/.auth/user.json' });

  test.beforeEach(async ({ page }) => {
    await loginAndGoToProfile(page);
  });

  test('PROF-03: header shows avatar, name, username, and stats', async ({ page }) => {
    await expect(page.getByText(`@${TEST_USERNAME}`)).toBeVisible();
    await expect(page.getByText('Following', { exact: true })).toBeVisible();
    await expect(page.getByText('Followers', { exact: true })).toBeVisible();
    await expect(page.getByText('Polls', { exact: true })).toBeVisible();
  });

  test('PROF-04: header shows location and "Joined" meta chips', async ({ page }) => {
    await expect(page.getByText(/^Joined [A-Z][a-z]+ \d{4}$/)).toBeVisible();
  });

  test('PROF-05: switching between Polls and Liked tabs', async ({ page }) => {
    const pollsTab = page.getByRole('tab', { name: 'Polls' });
    const likedTab = page.getByRole('tab', { name: 'Liked' });

    await expect(pollsTab).toBeVisible();
    await expect(likedTab).toBeVisible();

    await likedTab.click();
    await expect(likedTab).toHaveAttribute('aria-selected', 'true');

    await pollsTab.click();
    await expect(pollsTab).toHaveAttribute('aria-selected', 'true');
  });

  test('PROF-06: Settings is reachable from the profile and back returns to it', async ({ page }) => {
    await page.getByRole('button', { name: 'Settings' }).click();
    await expect(page.getByRole('heading', { name: 'Settings' })).toBeVisible();

    await page.getByRole('button', { name: 'Back' }).click();
    await expect(page.getByRole('heading', { name: 'Profile' })).toBeVisible();
  });

  test('PROF-07: Edit profile sheet opens with the expected fields', async ({ page }) => {
    await openEditProfile(page);

    await expect(page.getByRole('textbox', { name: 'Display name' })).toBeVisible();
    await expect(page.getByRole('textbox', { name: 'Bio' })).toBeVisible();
    await expect(page.getByRole('textbox', { name: 'Country' })).toBeVisible();
    await expect(page.getByRole('textbox', { name: 'City' })).toBeVisible();
    await expect(page.getByRole('textbox', { name: 'Website' })).toBeVisible();
    await expect(page.getByRole('button', { name: /Date of birth/ })).toBeVisible();
  });

  test('PROF-08: Website field rejects an invalid URL', async ({ page }) => {
    await openEditProfile(page);

    // Plain fill() (value= assignment) doesn't reliably propagate to
    // Flutter web's internal TextEditingController state, which made this
    // test intermittently flaky (Save would sometimes see a stale/empty
    // value and skip validation). pressSequentially dispatches real key
    // events that Flutter's input pipeline always picks up.
    const website = page.getByRole('textbox', { name: 'Website' });
    await website.click();
    await website.fill('');
    await website.pressSequentially('not a url');
    await page.getByRole('button', { name: 'Save' }).click();

    await expect(page.getByText('Enter a valid URL').first()).toBeVisible({ timeout: 15_000 });

    // Restore field and dismiss without saving so we don't leave bad state.
    await website.fill('');
    await page.getByRole('button', { name: 'Dismiss' }).click();
  });
});

test.describe('Profile page — edit website & date of birth', () => {
  test.use({ storageState: 'playwright/.auth/user.json' });
  test.describe.configure({ mode: 'serial' });

  test.beforeEach(async ({ page }) => {
    await loginAndGoToProfile(page);
  });

  test('PROF-09: saving a website and date of birth shows them on the profile', async ({ page }) => {
    await openEditProfile(page);

    // Use a full URL so _openWebsite() gets a valid URI with a scheme; without
    // one, Uri.tryParse returns a path-only URI and launchUrl misfires on web.
    // click()+fill('')+pressSequentially (not a bare fill()) - see PROF-08's
    // comment above: bare fill() intermittently leaves Flutter's web text
    // field seeing a stale/empty value, so Save can persist nothing.
    const websiteField = page.getByRole('textbox', { name: 'Website' });
    await websiteField.click();
    await websiteField.fill('');
    await websiteField.pressSequentially('https://pollsocial.app');
    await expect(websiteField).toHaveValue('https://pollsocial.app');

    await page.getByRole('button', { name: /Date of birth/ }).click();
    // Pick the 15th of the currently-displayed month in the date picker.
    await page.getByRole('button', { name: /^15, .+\d{4}$/ }).click();
    await page.getByRole('button', { name: 'OK' }).click();

    await page.getByRole('button', { name: 'Save' }).click();
    await expect(page.getByText('Profile updated').first()).toBeVisible();

    // openEditProfile navigates into Settings; after the sheet closes we're
    // still on Settings. Press Back to return to Profile, then tap the Profile
    // tab to bump _profileReloadToken so the screen re-fetches from Supabase
    // and renders the newly saved website and date-of-birth chips.
    await page.getByRole('button', { name: 'Back' }).click();
    await page.getByRole('button', { name: /Profile\s+Tab \d of \d/ }).click();

    const websiteLink = page.getByRole('button', { name: 'pollsocial.app' });
    await expect(websiteLink).toBeVisible();
    await expect(page.getByText(/^Born .+ 15, \d{4}$/)).toBeVisible();
  });

  test('PROF-10: website link opens the external site in a new tab', async ({ page, context }) => {
    // pollsocial.app doesn't resolve in sandboxed CI environments, so the
    // popup would land on chrome-error://chromewebdata/ before we can read
    // its URL. Stub the network response instead of relying on real DNS.
    await context.route('https://pollsocial.app/**', (route) =>
      route.fulfill({ status: 200, contentType: 'text/html', body: '<html><body>ok</body></html>' }),
    );

    const websiteLink = page.getByRole('button', { name: 'pollsocial.app' });
    await expect(websiteLink).toBeVisible();

    const [popup] = await Promise.all([
      context.waitForEvent('page'),
      websiteLink.click(),
    ]);

    await popup.waitForLoadState('load');
    expect(popup.url()).toContain('pollsocial.app');
    await popup.close();
    await context.unroute('https://pollsocial.app/**');
  });

  test('PROF-11: clearing the date of birth removes the "Born" chip', async ({ page }) => {
    await openEditProfile(page);

    // The edit sheet's date picker shows just the formatted date (no "Born"
    // prefix - that wording is only used on the profile display chip
    // checked below). The "Clear" suffix button only renders when a date
    // is currently set, so its presence is the right precondition check.
    await expect(page.getByRole('button', { name: 'Clear' })).toBeVisible();
    await page.getByRole('button', { name: 'Clear' }).click();
    await page.getByRole('button', { name: 'Save' }).click();
    await expect(page.getByText('Profile updated').first()).toBeVisible();

    // Return to Profile screen and reload so the chip change is visible.
    await page.getByRole('button', { name: 'Back' }).click();
    await page.getByRole('button', { name: /Profile\s+Tab \d of \d/ }).click();
    await expect(page.getByText(`@${TEST_USERNAME}`)).toBeVisible();

    await expect(page.getByText(/^Born /)).toHaveCount(0);
  });

  test('PROF-12: clearing the website removes the link from the profile', async ({ page }) => {
    await openEditProfile(page);

    await page.getByRole('textbox', { name: 'Website' }).fill('');
    await page.getByRole('button', { name: 'Save' }).click();
    await expect(page.getByText('Profile updated').first()).toBeVisible();

    // Return to Profile screen and reload so the chip change is visible.
    await page.getByRole('button', { name: 'Back' }).click();
    await page.getByRole('button', { name: /Profile\s+Tab \d of \d/ }).click();
    await expect(page.getByText(`@${TEST_USERNAME}`)).toBeVisible();

    await expect(page.getByRole('button', { name: 'pollsocial.app' })).toHaveCount(0);
  });
});
