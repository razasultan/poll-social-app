// Serves Open Graph previews for shared poll links and redirects everyone
// else into the Flutter web app.
//
// Flutter web is a client-rendered SPA, so a route like /p/:shareSlug can't
// carry per-poll <meta property="og:..."> tags in its initial HTML — link
// crawlers (Twitter/Discord/iMessage/Slack/etc.) don't run JavaScript, so
// they'd only ever see the app's generic index.html.
//
// This function is the fix: point your hosting's rewrite/proxy rule for
// `/p/*` (and `/poll/*`) at this function. It then:
//   - Bot/crawler request  -> returns a small static HTML page with the
//     poll's question, description, and (when available) an image, as OG/
//     Twitter Card meta tags.
//   - Real browser request -> 302 redirects to the Flutter app's own
//     /p/:shareSlug route, which resolves the poll and opens it live.
//
// APP_WEB_BASE_URL is sourced from the APP_WEB_BASE_URL project secret (set
// via `supabase secrets set APP_WEB_BASE_URL=https://your-domain.example`),
// matching AppConfig.publicShareBaseUrl's own --dart-define=PUBLIC_SHARE_BASE_URL
// on the Flutter side - keep both in sync. Falls back to the local dev-server
// URL when the secret isn't set, which only resolves on the machine running
// the Flutter dev server - not something real visitors can open.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const APP_WEB_BASE_URL = Deno.env.get("APP_WEB_BASE_URL") ??
  "http://localhost:9555";

// Branded fallback used as og:image/twitter:image for polls with no image of
// their own. Social platforms (Facebook in particular) flag previews with no
// og:image at all as incomplete, and most clients render a plain text-only
// card without one. Hosted in the public poll-media bucket rather than the
// app's own web build, since it needs a real URL independent of
// APP_WEB_BASE_URL/hosting status.
const DEFAULT_OG_IMAGE_URL =
  "https://uwomsxkvjqrvhdpnbkit.supabase.co/storage/v1/object/public/poll-media/2ab016e9-0adb-4e7f-8f56-cc89950f0bea/app-default-share-image.png";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

// Substrings of User-Agent headers used by link-preview crawlers. Matched
// case-insensitively; covers the platforms polls are most likely shared on.
const BOT_USER_AGENT_HINTS = [
  "facebookexternalhit",
  "Facebot",
  "Twitterbot",
  "Slackbot",
  "Discordbot",
  "TelegramBot",
  "WhatsApp",
  "LinkedInBot",
  "Pinterest",
  "redditbot",
  "SkypeUriPreview",
  "Googlebot",
  "Bingbot",
  "embedly",
  "vkShare",
  "Iframely",
];

function isBotUserAgent(userAgent: string | null): boolean {
  if (!userAgent) return false;
  const lower = userAgent.toLowerCase();
  return BOT_USER_AGENT_HINTS.some((hint) => lower.includes(hint.toLowerCase()));
}

/// Pulls the share slug out of a request path like
/// `/share-poll/abc123`, `/p/abc123`, or `/poll/abc123`. Returns `null` when
/// no slug segment is present. Exported for testing.
export function extractShareSlug(pathname: string): string | null {
  const segments = pathname.split("/").filter((s) => s.length > 0);
  if (segments.length === 0) return null;
  const last = segments[segments.length - 1];
  if (last === "share-poll" || last === "p" || last === "poll") return null;
  return last;
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/// Builds the OG/Twitter-card preview HTML for a resolved poll. Exported for
/// testing.
export function buildPreviewHtml(options: {
  shareSlug: string;
  question: string;
  description: string | null;
  authorName: string | null;
  imageUrl: string | null;
  appUrl: string;
}): string {
  const { question, description, authorName, imageUrl, appUrl } = options;
  const title = question.trim().length > 0 ? question.trim() : "Poll Social";
  const summary = (description?.trim().length ?? 0) > 0
    ? description!.trim()
    : authorName
    ? `See the results and vote on @${authorName}'s poll on Poll Social.`
    : "See the results and vote on Poll Social.";

  const imageTags = imageUrl
    ? `
    <meta property="og:image" content="${escapeHtml(imageUrl)}">
    <meta name="twitter:image" content="${escapeHtml(imageUrl)}">
    <meta name="twitter:card" content="summary_large_image">`
    : `
    <meta name="twitter:card" content="summary">`;

  // No <meta http-equiv="refresh"> here on purpose: this HTML is only ever
  // served to bot/crawler User-Agents (see isBotUserAgent below), which read
  // the og:/twitter: meta tags directly and don't need to navigate anywhere.
  // Facebook's crawler in particular follows a meta-refresh as if it were a
  // redirect, discarding the OG tags it just read and re-fetching the
  // refresh target instead - which broke previews entirely while appUrl
  // still pointed at an unreachable localhost address. Real browsers never
  // see this page; they get a real 302 redirect further down.
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>${escapeHtml(title)} · Poll Social</title>
  <meta name="description" content="${escapeHtml(summary)}">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="Poll Social">
  <meta property="og:title" content="${escapeHtml(title)}">
  <meta property="og:description" content="${escapeHtml(summary)}">
  <meta property="og:url" content="${escapeHtml(appUrl)}">${imageTags}
</head>
<body>
  <p>Open <a href="${escapeHtml(appUrl)}">this poll on Poll Social</a>.</p>
</body>
</html>`;
}

function notFoundHtml(appUrl: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Poll not found · Poll Social</title>
  <meta name="description" content="This poll could not be found. It may have been deleted.">
  <meta property="og:title" content="Poll not found">
  <meta property="og:description" content="This poll could not be found. It may have been deleted.">
</head>
<body>
  <p>This poll could not be found. <a href="${escapeHtml(appUrl)}">Open Poll Social</a>.</p>
</body>
</html>`;
}

Deno.serve(async (req: Request) => {
  const url = new URL(req.url);
  const shareSlug = extractShareSlug(url.pathname);
  const appUrl = shareSlug
    ? `${APP_WEB_BASE_URL}/p/${encodeURIComponent(shareSlug)}`
    : APP_WEB_BASE_URL;

  if (!shareSlug) {
    return Response.redirect(appUrl, 302);
  }

  const userAgent = req.headers.get("user-agent");
  if (!isBotUserAgent(userAgent)) {
    return Response.redirect(appUrl, 302);
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  const { data: poll } = await supabase
    .from("polls")
    .select(
      "question, description, profiles(username, display_name), poll_media(media_url, media_type)",
    )
    .eq("share_slug", shareSlug)
    .maybeSingle();

  if (!poll) {
    return new Response(notFoundHtml(appUrl), {
      status: 404,
      headers: { "Content-Type": "text/html; charset=utf-8" },
    });
  }

  const profile = Array.isArray(poll.profiles) ? poll.profiles[0] : poll.profiles;
  const media = Array.isArray(poll.poll_media) ? poll.poll_media : [];
  const image = media.find((m: { media_type?: string; media_url?: string }) =>
    m?.media_type === "image" && typeof m.media_url === "string" && m.media_url.length > 0
  );

  const html = buildPreviewHtml({
    shareSlug,
    question: poll.question ?? "",
    description: poll.description ?? null,
    authorName: profile?.username ?? null,
    imageUrl: image?.media_url ?? DEFAULT_OG_IMAGE_URL,
    appUrl,
  });

  return new Response(html, {
    status: 200,
    headers: { "Content-Type": "text/html; charset=utf-8" },
  });
});
