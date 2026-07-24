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

/** Creates a public poll and navigates to its detail screen. */
async function createAndOpenPoll(page: Page, question: string): Promise<void> {
  const ts = question.match(/\d+$/)?.[0] ?? Date.now().toString();
  await page.goto('/');
  await page.getByRole('button', { name: /Create\s+Tab \d of \d/ }).click();
  await expect(page.getByText('Create Poll')).toBeVisible();

  const textboxes = page.getByRole('textbox');
  await fillReliable(textboxes.nth(1), question);
  await fillReliable(textboxes.nth(2), `Opt A ${ts}`);
  await fillReliable(textboxes.nth(3), `Opt B ${ts}`);

  await page.getByRole('button', { name: 'Post' }).click();
  await expect(page.getByText('Your poll is live')).toBeVisible({ timeout: 10_000 });
  await page.getByRole('button', { name: 'Done' }).click();

  await page.getByRole('tab', { name: 'Latest' }).click();
  await expect(page.getByText(question)).toBeVisible({ timeout: 15_000 });
  await page.getByRole('button', { name: question, exact: true }).click();
  await expect(page.getByRole('button', { name: 'Back' })).toBeVisible();
}

/**
 * In PollDetailScreen Flutter exposes comments as `group` semantics nodes
 * whose accessible name is the combined "Xs ago <text>" string. This helper
 * locates the group that contains `commentText` and returns it, so tests can
 * assert on the structure and children of a specific comment.
 */
function commentGroup(page: Page, commentText: string) {
  return page.getByRole('group', { name: new RegExp(commentText) });
}

async function postTopLevelComment(page: Page, text: string) {
  const composer = page.getByRole('textbox', { name: 'Add a comment…' });
  await composer.click();
  await composer.pressSequentially(text);
  await page.getByRole('button', { name: 'Send comment' }).click();
  await expect(page.getByText('Comment added')).toBeVisible({ timeout: 10_000 });
}

test.describe('Comment likes', () => {
  test('LIKES-01: liking a comment fills the heart and shows a count of 1; unliking reverts both', async ({
    page,
  }) => {
    const ts = Date.now();
    await createAndOpenPoll(page, `Comment likes test ${ts}`);
    await postTopLevelComment(page, 'Like me please');

    const group = commentGroup(page, 'Like me please');
    await expect(group).toBeVisible({ timeout: 15_000 });

    // Initially unliked - no count shown (count is hidden when 0).
    const likeButton = group.getByRole('button', { name: 'Like comment' });
    await expect(likeButton).toBeVisible();

    // Like it.
    await likeButton.click();
    const unlikeButton = group.getByRole('button', { name: 'Unlike comment' });
    await expect(unlikeButton).toBeVisible({ timeout: 5_000 });
    await expect(group.getByText('1', { exact: true })).toBeVisible();

    // Unlike it - reverts to the original state.
    await unlikeButton.click();
    await expect(group.getByRole('button', { name: 'Like comment' })).toBeVisible({
      timeout: 5_000,
    });
    await expect(group.getByText('1', { exact: true })).not.toBeVisible();
  });

  test('LIKES-02: the like count persists across a page reload', async ({ page }) => {
    const ts = Date.now();
    await createAndOpenPoll(page, `Comment likes persist test ${ts}`);
    await postTopLevelComment(page, 'Persisted like target');

    const group = commentGroup(page, 'Persisted like target');
    await expect(group).toBeVisible({ timeout: 15_000 });
    await group.getByRole('button', { name: 'Like comment' }).click();
    await expect(group.getByRole('button', { name: 'Unlike comment' })).toBeVisible({
      timeout: 5_000,
    });

    await page.reload();
    const reloadedGroup = commentGroup(page, 'Persisted like target');
    await expect(reloadedGroup).toBeVisible({ timeout: 15_000 });
    await expect(reloadedGroup.getByRole('button', { name: 'Unlike comment' })).toBeVisible();
    await expect(reloadedGroup.getByText('1', { exact: true })).toBeVisible();
  });
});

test.describe('Comment composer: Enter to submit', () => {
  test('COMPOSER-01: pressing Enter with no modifier submits the comment', async ({ page }) => {
    const ts = Date.now();
    await createAndOpenPoll(page, `Enter submit test ${ts}`);

    const composer = page.getByRole('textbox', { name: 'Add a comment…' });
    await composer.click();
    await composer.pressSequentially(`Submitted via Enter ${ts}`);
    await composer.press('Enter');

    await expect(page.getByText('Comment added')).toBeVisible({ timeout: 10_000 });
    await expect(commentGroup(page, `Submitted via Enter ${ts}`)).toBeVisible({
      timeout: 10_000,
    });
  });

  test('COMPOSER-02: Shift+Enter inserts a newline instead of submitting', async ({ page }) => {
    const ts = Date.now();
    await createAndOpenPoll(page, `Shift enter test ${ts}`);

    const composer = page.getByRole('textbox', { name: 'Add a comment…' });
    await composer.click();
    await composer.pressSequentially('First line');
    await composer.press('Shift+Enter');
    await composer.pressSequentially('Second line');

    // Still in the composer (not submitted) - the newline was inserted.
    await expect(composer).toHaveValue('First line\nSecond line');
    await expect(page.getByText('Comment added')).not.toBeVisible();

    // Now actually submit with a bare Enter.
    await composer.press('Enter');
    await expect(page.getByText('Comment added')).toBeVisible({ timeout: 10_000 });
  });
});
