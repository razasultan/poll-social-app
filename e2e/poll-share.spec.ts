import { test, expect, Locator, Page } from '@playwright/test';

function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

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

/** The engagement-row icons (votes/comment/share/like) are unlabeled
 * InkWells with no accessible name of their own; poll_card.dart now wraps
 * each in Semantics(label: ...) so they're reachable here. The question
 * button itself is a leaf node, so the engagement row (a sibling) is found
 * by going up to its parent container first. */
function engagementRow(page: Page, question: string): Locator {
  const questionButton = page.getByRole('button', { name: question, exact: true });
  return questionButton.locator('xpath=..');
}

test.describe('Poll sharing is not gated behind voting', () => {
  test('SHARE-01: an unvoted poll can still be shared (no "vote first" warning, no accidental vote)', async ({
    page,
  }) => {
    // Stub the Web Share API so the click resolves instead of hitting a
    // real OS share sheet Playwright can't see, and so we can assert on
    // what text would have been shared.
    await page.addInitScript(() => {
      (window as unknown as { __sharedCalls: unknown[] }).__sharedCalls = [];
      (navigator as unknown as { share: (data: unknown) => Promise<void> }).share = async (
        data,
      ) => {
        (window as unknown as { __sharedCalls: unknown[] }).__sharedCalls.push(data);
      };
    });

    const ts = Date.now();
    const question = `Vote-gate share e2e ${ts}`;
    const optionA = `Option A ${ts}`;
    const optionB = `Option B ${ts}`;
    await createPublicPoll(page, question, optionA, optionB);

    const shareButton = engagementRow(page, question).getByRole('button', { name: 'Share', exact: true });
    await expect(shareButton).toBeVisible();
    await shareButton.click();

    // The old vote-gate showed this warning and refused to share at all -
    // it must not appear now that sharing works pre-vote.
    await expect(
      page.getByText('Vote (or wait for the poll to end) to share its results.'),
    ).not.toBeVisible();
    await expect(page.getByText('Could not share this poll. Try again.')).not.toBeVisible();

    // Tapping Share must not register a vote as a side effect.
    await expect(page.getByText(question)).toBeVisible();
    await expect(
      page.getByRole('group', { name: new RegExp(`${escapeRegex(optionA)} 100%`) }),
    ).toHaveCount(0);
  });

  test('SHARE-02: the existing post-vote results-image share path still works unaffected', async ({
    page,
  }) => {
    const ts = Date.now();
    const question = `Vote-gate share voted e2e ${ts}`;
    const optionA = `Option A ${ts}`;
    const optionB = `Option B ${ts}`;
    await createPublicPoll(page, question, optionA, optionB);

    await page.getByRole('button', { name: optionA, exact: true }).click();
    const resultGroup = page.getByRole('group', {
      name: new RegExp(`${escapeRegex(optionA)} 100%`),
    });
    await expect(resultGroup).toBeVisible({ timeout: 10_000 });

    const shareButton = resultGroup.getByRole('button', { name: 'Share', exact: true });
    await shareButton.click();

    await expect(
      page.getByText('Could not share the results image. Try again.'),
    ).not.toBeVisible();
  });
});
