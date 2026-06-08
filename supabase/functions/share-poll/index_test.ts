import { assertEquals, assertStringIncludes } from "jsr:@std/assert";
import { buildPreviewHtml, extractShareSlug } from "./index.ts";

Deno.test("extractShareSlug pulls the last path segment", () => {
  assertEquals(extractShareSlug("/p/abc123"), "abc123");
  assertEquals(extractShareSlug("/poll/abc123"), "abc123");
  assertEquals(extractShareSlug("/share-poll/abc123"), "abc123");
});

Deno.test("extractShareSlug returns null when no slug segment is present", () => {
  assertEquals(extractShareSlug("/"), null);
  assertEquals(extractShareSlug("/p"), null);
  assertEquals(extractShareSlug("/poll"), null);
  assertEquals(extractShareSlug("/share-poll"), null);
});

Deno.test("buildPreviewHtml uses the question as title and og:title", () => {
  const html = buildPreviewHtml({
    shareSlug: "abc123",
    question: "Coffee or tea?",
    description: null,
    authorName: "razasultan",
    imageUrl: null,
    appUrl: "https://example.com/p/abc123",
  });
  assertStringIncludes(html, "<title>Coffee or tea? · Poll Social</title>");
  assertStringIncludes(html, '<meta property="og:title" content="Coffee or tea?">');
});

Deno.test("buildPreviewHtml falls back to an author-based summary without a description", () => {
  const html = buildPreviewHtml({
    shareSlug: "abc123",
    question: "Coffee or tea?",
    description: null,
    authorName: "razasultan",
    imageUrl: null,
    appUrl: "https://example.com/p/abc123",
  });
  assertStringIncludes(
    html,
    "See the results and vote on @razasultan&#39;s poll on Poll Social.",
  );
});

Deno.test("buildPreviewHtml uses the description when present", () => {
  const html = buildPreviewHtml({
    shareSlug: "abc123",
    question: "Coffee or tea?",
    description: "A classic debate.",
    authorName: "razasultan",
    imageUrl: null,
    appUrl: "https://example.com/p/abc123",
  });
  assertStringIncludes(html, '<meta property="og:description" content="A classic debate.">');
});

Deno.test("buildPreviewHtml includes image meta tags only when an image URL is given", () => {
  const withImage = buildPreviewHtml({
    shareSlug: "abc123",
    question: "Coffee or tea?",
    description: null,
    authorName: null,
    imageUrl: "https://example.com/poll.png",
    appUrl: "https://example.com/p/abc123",
  });
  assertStringIncludes(withImage, '<meta property="og:image" content="https://example.com/poll.png">');
  assertStringIncludes(withImage, '<meta name="twitter:card" content="summary_large_image">');

  const withoutImage = buildPreviewHtml({
    shareSlug: "abc123",
    question: "Coffee or tea?",
    description: null,
    authorName: null,
    imageUrl: null,
    appUrl: "https://example.com/p/abc123",
  });
  assertEquals(withoutImage.includes("og:image"), false);
  assertStringIncludes(withoutImage, '<meta name="twitter:card" content="summary">');
});

Deno.test("buildPreviewHtml escapes HTML-significant characters in poll content", () => {
  const html = buildPreviewHtml({
    shareSlug: "abc123",
    question: 'Cats <3 vs "Dogs" & Co?',
    description: null,
    authorName: null,
    imageUrl: null,
    appUrl: "https://example.com/p/abc123",
  });
  assertStringIncludes(html, "Cats &lt;3 vs &quot;Dogs&quot; &amp; Co?");
  assertEquals(html.includes('Cats <3'), false);
});
