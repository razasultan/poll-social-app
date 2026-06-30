import { test, expect, Locator, Page } from '@playwright/test';

test.use({ viewport: { width: 430, height: 900 }, storageState: 'playwright/.auth/user.json' });

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

async function createPublicPoll(
  page: Page,
  question: string,
  optionA: string,
  optionB: string,
): Promise<void> {
  await page.goto('/');
  await page.getByRole('button', { name: /Create\s+Tab \d of \d/ }).click();
  await expect(page.getByText('Create Poll')).toBeVisible();

  const textboxes = page.getByRole('textbox');
  await fillReliable(textboxes.nth(1), question);
  await fillReliable(textboxes.nth(2), optionA);
  await fillReliable(textboxes.nth(3), optionB);

  await page.getByRole('button', { name: 'Post' }).click();
  await expect(page.getByText('Your poll is live')).toBeVisible({ timeout: 10_000 });
  await page.getByRole('button', { name: 'Done' }).click();

  await page.getByRole('tab', { name: 'Latest' }).click();
  await expect(page.getByText(question)).toBeVisible({ timeout: 15_000 });
}

test.describe('Poll view and share analytics', () => {
  test('ANALYTICS-01: viewing a poll detail twice in one session records exactly one view, and sharing records a share', async ({
    page,
  }) => {
    const ts = Date.now();
    const question = `Poll analytics e2e ${ts}`;
    const optionA = `Option A ${ts}`;
    const optionB = `Option B ${ts}`;
    await createPublicPoll(page, question, optionA, optionB);

    // Open the poll detail screen (records a view via PollService.recordView).
    await page.getByRole('button', { name: question, exact: true }).click();
    await expect(page.getByRole('button', { name: 'Back' })).toBeVisible();

    // Go back and open it again - PollService's in-memory per-session dedup
    // (PollService._viewedThisSession) must keep the count at one view, not two.
    await page.getByRole('button', { name: 'Back' }).click();
    await page.getByRole('tab', { name: 'Latest' }).click();
    await expect(page.getByText(question)).toBeVisible({ timeout: 15_000 });
    await page.getByRole('button', { name: question, exact: true }).click();
    await expect(page.getByRole('button', { name: 'Back' })).toBeVisible();

    // Share from the detail screen. PollDetailScreen wraps the poll card in
    // a `group` whose accessible name IS the question text directly (unlike
    // the feed list, where the question is its own separate leaf button).
    const card = page.getByRole('group', { name: question });
    await card.getByRole('button', { name: 'Share', exact: true }).click();

    const pollId = await pollIdForQuestion(page, question);

    // Give both RPC calls (view, then share) time to land before asserting
    // on the database directly - there's no UI-visible counter to check
    // against (views_count/shares_count aren't rendered anywhere yet).
    await expect
      .poll(
        async () => {
          const res = await page.request.get(
            `https://uwomsxkvjqrvhdpnbkit.supabase.co/rest/v1/poll_analytics?select=views_count,shares_count&poll_id=eq.${pollId}`,
            { headers: { apikey: SUPABASE_PUBLISHABLE_KEY } },
          );
          const body = await res.json();
          return body[0] ?? null;
        },
        { timeout: 15_000 },
      )
      .toMatchObject({ views_count: 1, shares_count: 1 });
  });
});

const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_LgwGHGciORtyBWVRajywqA_JYzCokcF';

/** Looks up a poll's id by its (unique, timestamp-suffixed) question text via
 * the public REST API - simpler than threading the id through the UI flow
 * above, and this table is publicly readable. */
async function pollIdForQuestion(page: Page, question: string): Promise<string> {
  const res = await page.request.get(
    `https://uwomsxkvjqrvhdpnbkit.supabase.co/rest/v1/polls?select=id&question=eq.${encodeURIComponent(question)}`,
    { headers: { apikey: SUPABASE_PUBLISHABLE_KEY } },
  );
  const body = await res.json();
  return body[0].id;
}
