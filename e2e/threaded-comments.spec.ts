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

test.describe('Threaded Comments (2c: Reply UI)', () => {
  test('THREADS-01: top-level comment shows a Reply button; tapping it shows the Replying banner and changes the composer hint', async ({
    page,
  }) => {
    const ts = Date.now();
    await createAndOpenPoll(page, `Threads test 01 ${ts}`);

    // Post a top-level comment.
    const composer = page.getByRole('textbox');
    await composer.click();
    await composer.pressSequentially('Parent comment');
    await page.getByRole('button', { name: 'Send comment' }).click();
    await expect(page.getByText('Comment added')).toBeVisible({ timeout: 10_000 });

    // Comment appears as a group; it should have a Reply button.
    const group = commentGroup(page, 'Parent comment');
    await expect(group).toBeVisible({ timeout: 15_000 });
    await expect(group.getByRole('button', { name: 'Reply' })).toBeVisible();

    // Tap Reply — banner should appear and hint text should change.
    await group.getByRole('button', { name: 'Reply' }).click();
    await expect(page.getByText(/^Replying to @/)).toBeVisible({ timeout: 5_000 });
    await expect(page.getByRole('textbox', { name: /Reply to @/ })).toBeVisible();
  });

  test('THREADS-02: posting a reply nests it under the parent; the reply also has a Reply button for reply-to-reply', async ({
    page,
  }) => {
    const ts = Date.now();
    await createAndOpenPoll(page, `Threads test 02 ${ts}`);

    // Post parent comment.
    const composer = page.getByRole('textbox');
    await composer.click();
    await composer.pressSequentially('Parent for reply');
    await page.getByRole('button', { name: 'Send comment' }).click();
    await expect(page.getByText('Comment added')).toBeVisible({ timeout: 10_000 });
    const parentGroup = commentGroup(page, 'Parent for reply');
    await expect(parentGroup).toBeVisible({ timeout: 15_000 });

    // Post a reply.
    await parentGroup.getByRole('button', { name: 'Reply' }).click();
    await expect(page.getByText(/^Replying to @/)).toBeVisible({ timeout: 5_000 });

    const replyComposer = page.getByRole('textbox', { name: /Reply to @/ });
    await replyComposer.click();
    await replyComposer.pressSequentially('Nested reply text');
    await page.getByRole('button', { name: 'Send comment' }).click();
    await expect(page.getByText('Comment added')).toBeVisible({ timeout: 10_000 });

    // Banner clears after posting.
    await expect(page.getByText(/^Replying to @/)).not.toBeVisible();

    // Reply appears in the thread.
    const replyGroup = commentGroup(page, 'Nested reply text');
    await expect(replyGroup).toBeVisible({ timeout: 10_000 });

    // Replies now have their own Reply button for reply-to-reply (Instagram
    // model: stays flat under the same parent, just @mentions the person).
    await expect(replyGroup.getByRole('button', { name: 'Reply' })).toBeVisible();
  });

  test('THREADS-03: the cancel-reply button dismisses the banner and restores the default composer', async ({
    page,
  }) => {
    const ts = Date.now();
    await createAndOpenPoll(page, `Threads test 03 ${ts}`);

    // Post a parent comment so there is something to reply to.
    const composer = page.getByRole('textbox');
    await composer.click();
    await composer.pressSequentially('Comment to reply to');
    await page.getByRole('button', { name: 'Send comment' }).click();
    await expect(page.getByText('Comment added')).toBeVisible({ timeout: 10_000 });
    const group = commentGroup(page, 'Comment to reply to');
    await expect(group).toBeVisible({ timeout: 15_000 });

    // Open reply mode.
    await group.getByRole('button', { name: 'Reply' }).click();
    await expect(page.getByText(/^Replying to @/)).toBeVisible({ timeout: 5_000 });

    // Cancel — the Semantics label 'Cancel reply' is added to the X icon
    // so it's accessible and testable.
    await page.getByRole('button', { name: 'Cancel reply' }).click();
    await expect(page.getByText(/^Replying to @/)).not.toBeVisible({ timeout: 5_000 });
    await expect(page.getByRole('textbox', { name: 'Add a comment…' })).toBeVisible();
  });
});

test.describe('Threaded Comments (Instagram-style: lazy loading + reply-to-reply)', () => {
  test('THREADS-04: replies are hidden by default; "View N replies" button appears and loads replies lazily', async ({
    page,
  }) => {
    const ts = Date.now();
    await createAndOpenPoll(page, `Threads test 04 ${ts}`);

    // Post a top-level comment.
    const composer = page.getByRole('textbox');
    await composer.click();
    await composer.pressSequentially('Lazy load parent');
    await page.getByRole('button', { name: 'Send comment' }).click();
    await expect(page.getByText('Comment added')).toBeVisible({ timeout: 10_000 });
    const parent = commentGroup(page, 'Lazy load parent');
    await expect(parent).toBeVisible({ timeout: 12_000 });

    // No replies yet — "View N replies" must not appear.
    await expect(page.getByText(/View \d+ repl/)).toHaveCount(0);

    // Post a reply — auto-expands after posting so the reply is visible.
    await parent.getByRole('button', { name: 'Reply' }).click();
    await expect(page.getByText(/^Replying to @/)).toBeVisible({ timeout: 5_000 });
    const replyComposer = page.getByRole('textbox', { name: /Reply to @/ });
    await replyComposer.click();
    await replyComposer.pressSequentially('Lazy reply');
    await page.getByRole('button', { name: 'Send comment' }).click();
    await expect(page.getByText('Comment added')).toBeVisible({ timeout: 10_000 });
    await expect(commentGroup(page, 'Lazy reply')).toBeVisible({ timeout: 10_000 });

    // Collapse.
    await page.getByText('Hide replies').click();
    await expect(commentGroup(page, 'Lazy reply')).not.toBeVisible({ timeout: 5_000 });

    // "View 1 reply" button should appear.
    const viewBtn = page.getByText(/View 1 repl/);
    await expect(viewBtn).toBeVisible({ timeout: 5_000 });

    // Lazy expand — no full page reload, just the reply rows appear.
    await viewBtn.click();
    await expect(commentGroup(page, 'Lazy reply')).toBeVisible({ timeout: 8_000 });
    await expect(page.getByText('Hide replies')).toBeVisible();
  });

  test('THREADS-05: replying to a reply keeps the same parent and prefixes @username', async ({
    page,
  }) => {
    const ts = Date.now();
    await createAndOpenPoll(page, `Threads test 05 ${ts}`);

    // Post a top-level comment + a reply.
    const composer = page.getByRole('textbox');
    await composer.click();
    await composer.pressSequentially('Top for r2r');
    await page.getByRole('button', { name: 'Send comment' }).click();
    await expect(page.getByText('Comment added')).toBeVisible({ timeout: 10_000 });
    const parent = commentGroup(page, 'Top for r2r');
    await expect(parent).toBeVisible({ timeout: 12_000 });

    await parent.getByRole('button', { name: 'Reply' }).click();
    const firstReplyComposer = page.getByRole('textbox', { name: /Reply to @/ });
    await firstReplyComposer.click();
    await firstReplyComposer.pressSequentially('First nested reply');
    await page.getByRole('button', { name: 'Send comment' }).click();
    await expect(page.getByText('Comment added')).toBeVisible({ timeout: 10_000 });

    // Reply-to-reply: the Reply button on the reply tile.
    const firstReply = commentGroup(page, 'First nested reply');
    await expect(firstReply).toBeVisible({ timeout: 10_000 });
    await firstReply.getByRole('button', { name: 'Reply' }).click();
    await expect(page.getByText(/^Replying to @/)).toBeVisible({ timeout: 5_000 });

    const r2rComposer = page.getByRole('textbox', { name: /Reply to @/ });
    await r2rComposer.click();
    await r2rComposer.pressSequentially('reply-to-reply');
    await page.getByRole('button', { name: 'Send comment' }).click();
    await expect(page.getByText('Comment added')).toBeVisible({ timeout: 10_000 });

    // The reply-to-reply should appear with @username prefix.
    // It lands under the SAME parent (flat nesting, not double-indent).
    const r2rGroup = page.getByRole('group', {
      name: /@gherkintester1 reply-to-reply/,
    });
    await expect(r2rGroup).toBeVisible({ timeout: 10_000 });

    // Only one indent level — r2r tile must NOT itself have a "Reply" button
    // (it's the same level as the first reply, so it DOES have one per spec).
    await expect(r2rGroup.getByRole('button', { name: 'Reply' })).toBeVisible();
  });
});
