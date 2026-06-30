import { test, expect, Locator, Page } from '@playwright/test';

function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/** Once a vote is recorded, PollCard's options/results collapse into a
 * single merged `group` semantics node (Flutter merges non-interactive
 * subtrees) - getByText can't see text that only exists in a group's
 * accessible name, so assert via getByRole('group', ...) instead. */
function resultGroup(page: Page, optionLabel: string) {
  return page.getByRole('group', {
    name: new RegExp(`${escapeRegex(optionLabel)} 100%`),
  });
}

// Force narrow viewport so the BottomNavigationBar is rendered (not the
// NavigationRail) - see profile.spec.ts for why ExcludeSemantics on
// NavigationRailDestination makes the rail untestable via getByRole.
test.use({ viewport: { width: 430, height: 900 } });

/** click + fill('') + pressSequentially + verify-retry: bare fill()/type()
 * have repeatedly dropped leading characters on Flutter web's text fields
 * elsewhere in this suite's history; this is the reliable pattern. */
async function fillReliable(locator: Locator, value: string) {
  for (let attempt = 0; attempt < 5; attempt++) {
    // position: avoids the click landing on an "Add video" semantics node
    // that visually overlaps the Option fields' default center-click point.
    await locator.click({ position: { x: 10, y: 10 } });
    await locator.fill('');
    await locator.pressSequentially(value);
    if ((await locator.inputValue()) === value) return;
  }
}

/** Creates a fresh public poll as the seeded authenticated user. Both the
 * question AND the option labels are unique per call (timestamp-suffixed) -
 * this dev backend accumulates leftover test polls across runs (see other
 * e2e specs/session history), and a generic "Option A"/"Option B" label
 * would match several of them at once, making locators ambiguous. */
async function createPublicPoll(
  page: Page,
  question: string,
  optionA: string,
  optionB: string,
): Promise<void> {
  await page.goto('/');
  // Authenticated 5-tab bottom nav: Home, Search, Create, Notifications, Profile.
  await page.getByRole('button', { name: /Create\s+Tab \d of \d/ }).click();
  await expect(page.getByText('Create Poll')).toBeVisible();

  const textboxes = page.getByRole('textbox');
  await fillReliable(textboxes.nth(1), question); // 0 = post text, 1 = question
  await fillReliable(textboxes.nth(2), optionA);
  await fillReliable(textboxes.nth(3), optionB);
  // Visibility already defaults to Public - no extra interaction needed.

  await page.getByRole('button', { name: 'Post' }).click();
  await expect(page.getByText('Your poll is live')).toBeVisible({ timeout: 10_000 });
  await page.getByRole('button', { name: 'Done' }).click();
}

test.describe('Anonymous voting on public polls', () => {
  test('ANON-01: guest can vote without logging in, the vote persists across reload, and re-voting is blocked', async ({ browser }) => {
    const ts = Date.now();
    const question = `Anon vote e2e ${ts}`;
    const optionA = `Option A ${ts}`;
    const optionB = `Option B ${ts}`;

    const authedContext = await browser.newContext({ storageState: 'playwright/.auth/user.json' });
    const authedPage = await authedContext.newPage();
    await createPublicPoll(authedPage, question, optionA, optionB);
    await authedContext.close();

    // Fresh guest context: no storageState, so the Flutter app boots fully
    // unauthenticated - this is the actual scenario being verified.
    const guestContext = await browser.newContext();
    const page = await guestContext.newPage();
    await page.goto('/');

    await expect(page.getByText(question)).toBeVisible({ timeout: 15_000 });

    await page.getByText(optionA, { exact: true }).click();
    // A successful vote replaces the option buttons with a results view
    // showing a percentage - this only renders once a vote is recorded.
    // Scoped to optionA's own text (unique per run) rather than a bare
    // "100%" match, since other single-vote leftover test polls on this
    // shared dev backend can also show "100%".
    await expect(resultGroup(page, optionA)).toBeVisible({ timeout: 10_000 });

    // Reload: the vote must still be reflected without voting again, proving
    // the anon session token persisted (shared_preferences/localStorage) and
    // PollCard's bootstrap looked it up via getAnonVote.
    await page.reload();
    await expect(page.getByText(question)).toBeVisible({ timeout: 15_000 });
    await expect(resultGroup(page, optionA)).toBeVisible({ timeout: 10_000 });

    // Tapping the other option must not change anything - _hasVoted already
    // guards client-side, and the Edge Function would reject it server-side
    // even if that guard were bypassed.
    await page.getByText(optionB, { exact: true }).click({ force: true }).catch(() => {});
    await page.waitForTimeout(1500);
    await expect(resultGroup(page, optionA)).toBeVisible();

    await guestContext.close();
  });

  test('ANON-02: signed-in voting still works through the original path, unaffected by the new guest branch', async ({ browser }) => {
    // _onVote() in poll_card.dart was restructured to add a guest branch
    // ahead of the existing AuthGuard-wrapped authenticated path. This
    // guards against that refactor having broken the original path it
    // wraps - votes as the poll's own creator, reusing the same
    // already-authenticated session the rest of this suite relies on.
    const ts = Date.now();
    const question = `Authed vote e2e ${ts}`;
    const optionA = `Option A ${ts}`;
    const optionB = `Option B ${ts}`;

    const context = await browser.newContext({ storageState: 'playwright/.auth/user.json' });
    const page = await context.newPage();
    await createPublicPoll(page, question, optionA, optionB);

    // Authenticated users default to "For You", which doesn't reliably
    // surface a poll the same user just created - switch to "Latest"
    // (plain reverse-chronological) like the guest test implicitly gets by
    // default with only Latest/Trending tabs available.
    await page.getByRole('tab', { name: 'Latest' }).click();
    await expect(page.getByText(question)).toBeVisible({ timeout: 15_000 });
    await page.getByText(optionA, { exact: true }).click();
    await expect(resultGroup(page, optionA)).toBeVisible({ timeout: 10_000 });

    // Reload as the same authenticated user: vote persists via the existing
    // getUserVote bootstrap path (separate from the new anonymous one).
    // Reload resets to the default "For You" tab, so switch back to Latest.
    await page.reload();
    await page.getByRole('tab', { name: 'Latest' }).click();
    await expect(page.getByText(question)).toBeVisible({ timeout: 15_000 });
    await expect(resultGroup(page, optionA)).toBeVisible({ timeout: 10_000 });

    await context.close();
  });
});
