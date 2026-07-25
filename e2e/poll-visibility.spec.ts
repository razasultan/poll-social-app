import { test, expect, Locator, Page } from '@playwright/test';

// Same DEV Supabase project + anon key used by package.json's build:web script
// and by the app itself (see playwright.config.ts header comment). Used here
// for a direct, UI-independent call to the vote-anonymous Edge Function -
// this is a server-side enforcement check, not something the Flutter UI can
// exercise (a non-public poll's row is invisible to a guest via RLS, so the
// UI never even reaches a state where it could attempt this vote).
const SUPABASE_URL = 'https://uwomsxkvjqrvhdpnbkit.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_LgwGHGciORtyBWVRajywqA_JYzCokcF';

// Force narrow viewport so the BottomNavigationBar is rendered (not the
// NavigationRail) - see profile.spec.ts for why ExcludeSemantics on
// NavigationRailDestination makes the rail untestable via getByRole.
test.use({ viewport: { width: 430, height: 900 } });

/** click + fill('') + pressSequentially + verify-retry: bare fill()/type()
 * have repeatedly dropped leading characters on Flutter web's text fields
 * elsewhere in this suite's history; this is the reliable pattern. */
async function fillReliable(locator: Locator, value: string) {
  for (let attempt = 0; attempt < 5; attempt++) {
    await locator.click({ position: { x: 10, y: 10 } });
    await locator.fill('');
    await locator.pressSequentially(value);
    if ((await locator.inputValue()) === value) return;
  }
}

type Visibility = 'Public' | 'Followers' | 'Private';

/** Creates a poll as the currently authenticated [page] with the given
 * [visibility] (default 'Public' - the Create screen's own default, so no
 * dropdown interaction needed for that case). Returns the inserted poll's
 * `id` and `share_slug`, captured directly from the `polls` insert response
 * (poll_service.dart's createPoll() uses `.select().single()`) rather than
 * scraping the UI for them.
 */
async function createPoll(
  page: Page,
  question: string,
  optionA: string,
  optionB: string,
  visibility: Visibility = 'Public',
): Promise<{ id: string; shareSlug: string | null }> {
  const respPromise = page.waitForResponse(
    (r) => r.url().includes('/rest/v1/polls') && r.request().method() === 'POST',
  );

  await page.goto('/');
  await page.getByRole('button', { name: /Create\s+Tab \d of \d/ }).click();
  await expect(page.getByText('Create Poll')).toBeVisible();

  const textboxes = page.getByRole('textbox');
  await fillReliable(textboxes.nth(1), question); // 0 = post text, 1 = question
  await fillReliable(textboxes.nth(2), optionA);
  await fillReliable(textboxes.nth(3), optionB);

  if (visibility !== 'Public') {
    // The Visibility control renders as a button whose accessible name is
    // "Visibility <current value>" (starts as "Visibility Public"); opening
    // it shows a popup menu with one menuitem per choice.
    await page.getByRole('button', { name: /^Visibility/ }).click();
    const item = page.getByRole('menuitem', { name: visibility, exact: true });
    await item.waitFor({ state: 'visible' });
    // Locator.click() hit-tests against an overlapping Flutter semantics
    // node here and silently dismisses the whole Create Poll screen instead
    // of selecting the item (reproduced independently of this suite) - a
    // manual mouse click at the item's own bounding box avoids that.
    const box = await item.boundingBox();
    if (!box) throw new Error(`Visibility menuitem "${visibility}" has no bounding box`);
    await page.mouse.click(box.x + 5, box.y + box.height / 2);
    await expect(page.getByRole('button', { name: new RegExp(visibility) })).toBeVisible();
    // The popup menu's dismiss barrier can still intercept the very next
    // click (e.g. "Post") while its close animation is finishing - wait for
    // the menu role to fully disappear from the tree first.
    await page.getByRole('menu', { name: 'Popup menu' }).waitFor({ state: 'hidden' });
  }

  await page.getByRole('button', { name: 'Post' }).click();
  const resp = await respPromise;
  const body = JSON.parse(await resp.text());

  // The "Your poll is live - share it!" bottom sheet (with its "Done"
  // button) only appears when the created poll got a share_slug -
  // set_poll_share_slug() only auto-generates one `if new.visibility =
  // 'public'` (schema.sql), so Private/Followers polls skip straight back
  // to the feed with no such dialog.
  if (visibility === 'Public') {
    await expect(page.getByText('Your poll is live')).toBeVisible({ timeout: 10_000 });
    await page.getByRole('button', { name: 'Done' }).click();
  } else {
    await expect(page.getByText('Create Poll')).not.toBeVisible({ timeout: 10_000 });
  }

  return { id: body.id as string, shareSlug: (body.share_slug as string | null) ?? null };
}

/** Opens [question]'s poll detail from the Latest tab, then Show menu ->
 * Edit poll, changes visibility via the SegmentedButton (labels "Public" /
 * "Followers" / "Private"), and saves. Returns to the poll detail screen. */
async function editVisibility(page: Page, question: string, visibility: Visibility) {
  await page.getByRole('tab', { name: 'Latest' }).click();
  await expect(page.getByText(question)).toBeVisible({ timeout: 15_000 });
  await page.getByRole('button', { name: question, exact: true }).click();
  await expect(page.getByRole('button', { name: 'Back' })).toBeVisible();

  await page.getByRole('button', { name: 'Show menu' }).click();
  await page.getByRole('menuitem', { name: 'Edit poll' }).click();
  await expect(page.getByRole('heading', { name: 'Edit Poll' })).toBeVisible({ timeout: 10_000 });

  await page.getByRole('button', { name: visibility, exact: true }).click();
  await page.getByRole('button', { name: 'Save changes' }).click();

  // No success toast on save (edit_poll_screen.dart just pops back) - wait
  // for the Edit heading to disappear as the "it worked" signal instead.
  await expect(page.getByRole('heading', { name: 'Edit Poll' })).not.toBeVisible({
    timeout: 10_000,
  });
}

test.describe('Poll visibility enforcement', () => {
  test('VIS-01: a public poll is visible to a logged-out guest in the Latest feed', async ({
    browser,
  }) => {
    const ts = Date.now();
    const question = `Vis public ${ts}`;

    const authedContext = await browser.newContext({ storageState: 'playwright/.auth/user.json' });
    const authedPage = await authedContext.newPage();
    await createPoll(authedPage, question, `OptA ${ts}`, `OptB ${ts}`, 'Public');
    await authedContext.close();

    const guestContext = await browser.newContext();
    const page = await guestContext.newPage();
    await page.goto('/');
    // Guests land on Latest by default (no For You/Trending tabs for them).
    await expect(page.getByText(question)).toBeVisible({ timeout: 15_000 });
    await guestContext.close();
  });

  test('VIS-02: a private poll is NOT visible to a logged-out guest in the Latest feed', async ({
    browser,
  }) => {
    const ts = Date.now();
    const question = `Vis private ${ts}`;

    const authedContext = await browser.newContext({ storageState: 'playwright/.auth/user.json' });
    const authedPage = await authedContext.newPage();
    await createPoll(authedPage, question, `OptA ${ts}`, `OptB ${ts}`, 'Private');
    await authedContext.close();

    const guestContext = await browser.newContext();
    const page = await guestContext.newPage();
    await page.goto('/');
    // Give the feed a moment to fully load before asserting absence, so this
    // isn't a false pass from checking before the list finished rendering.
    await page.waitForTimeout(3_000);
    await expect(page.getByText(question)).not.toBeVisible();
    await guestContext.close();
  });

  test('VIS-03: a followers-only poll is NOT visible to a logged-out guest in the Latest feed (currently behaves like private - "followers" access is not implemented downstream)', async ({
    browser,
  }) => {
    const ts = Date.now();
    const question = `Vis followers ${ts}`;

    const authedContext = await browser.newContext({ storageState: 'playwright/.auth/user.json' });
    const authedPage = await authedContext.newPage();
    await createPoll(authedPage, question, `OptA ${ts}`, `OptB ${ts}`, 'Followers');
    await authedContext.close();

    const guestContext = await browser.newContext();
    const page = await guestContext.newPage();
    await page.goto('/');
    await page.waitForTimeout(3_000);
    await expect(page.getByText(question)).not.toBeVisible();
    await guestContext.close();
  });

  test('VIS-04: editing a poll from Public to Private removes it from the guest Latest feed', async ({
    browser,
  }) => {
    const ts = Date.now();
    const question = `Vis edit to private ${ts}`;

    const authedContext = await browser.newContext({ storageState: 'playwright/.auth/user.json' });
    const authedPage = await authedContext.newPage();
    await createPoll(authedPage, question, `OptA ${ts}`, `OptB ${ts}`, 'Public');

    // Confirm it's public first (visible to a guest) before flipping it.
    const preEditGuestContext = await browser.newContext();
    const preEditGuestPage = await preEditGuestContext.newPage();
    await preEditGuestPage.goto('/');
    await expect(preEditGuestPage.getByText(question)).toBeVisible({ timeout: 15_000 });
    await preEditGuestContext.close();

    await editVisibility(authedPage, question, 'Private');
    await authedContext.close();

    const guestContext = await browser.newContext();
    const page = await guestContext.newPage();
    await page.goto('/');
    await page.waitForTimeout(3_000);
    await expect(page.getByText(question)).not.toBeVisible();
    await guestContext.close();
  });

  test('VIS-05: a share link captured while a poll was Public fails closed (no leak) once the poll is edited to Private', async ({
    browser,
  }) => {
    const ts = Date.now();
    const question = `Vis share then private ${ts}`;

    const authedContext = await browser.newContext({ storageState: 'playwright/.auth/user.json' });
    const authedPage = await authedContext.newPage();
    const { shareSlug } = await createPoll(
      authedPage,
      question,
      `OptA ${ts}`,
      `OptB ${ts}`,
      'Public',
    );
    expect(shareSlug, 'a public poll must get a share_slug on creation').toBeTruthy();

    await editVisibility(authedPage, question, 'Private');
    await authedContext.close();

    // edit_poll_screen.dart's updatePoll() never clears share_slug, so the
    // old link still exists in the DB - this proves RLS (not app-level
    // logic) is what keeps it from resolving for a non-owner.
    const guestContext = await browser.newContext();
    const page = await guestContext.newPage();
    await page.goto(`/p/${shareSlug}`);
    await expect(
      page.getByText('This poll could not be found. It may have been deleted.'),
    ).toBeVisible({ timeout: 15_000 });
    await expect(page.getByText(question)).not.toBeVisible();
    await guestContext.close();
  });

  test('VIS-06: the vote-anonymous Edge Function rejects a direct vote on a Private poll (server-side enforcement, independent of the UI)', async ({
    browser,
    request,
  }) => {
    const ts = Date.now();
    const question = `Vis anon vote block ${ts}`;

    const authedContext = await browser.newContext({ storageState: 'playwright/.auth/user.json' });
    const authedPage = await authedContext.newPage();
    const { id: pollId } = await createPoll(
      authedPage,
      question,
      `OptA ${ts}`,
      `OptB ${ts}`,
      'Private',
    );
    await authedContext.close();

    // The function checks poll status/visibility before it ever looks at
    // optionId, so an arbitrary (invalid) optionId is fine here - a 404 for
    // "option not found" would indicate the visibility check was skipped.
    const res = await request.post(`${SUPABASE_URL}/functions/v1/vote-anonymous`, {
      headers: {
        apikey: SUPABASE_ANON_KEY,
        authorization: `Bearer ${SUPABASE_ANON_KEY}`,
        'content-type': 'application/json',
      },
      data: { pollId, optionId: '00000000-0000-0000-0000-000000000000' },
    });

    expect(res.status()).toBe(403);
    const body = await res.json();
    expect(body.error).toBe('This poll is not open to anonymous voting');
  });
});
