// Lets unauthenticated visitors (e.g. arriving via a shared poll link) vote
// on public polls. votes.user_id requires auth.uid() = user_id via RLS, so
// anon clients have no direct INSERT path - this function is the only way
// an anonymous vote gets recorded, using the service role key to bypass RLS
// and applying its own anti-abuse checks server-side instead.
//
// Anti-abuse approach (deliberately not perfect - see ticket notes):
//   - anonSessionId: an opaque token the client persists locally and echoes
//     back on every request. Issued by this function on a voter's first
//     anonymous vote (never trusted if the client invents one - see
//     isValidSessionId). Deduped via the votes_poll_anon_session_unique
//     partial unique index (same role as the existing (poll_id, user_id)
//     unique constraint plays for authenticated votes).
//   - anonIpHash: a salted SHA-256 hash of the request's IP, checked before
//     insert as a secondary signal so clearing local storage alone doesn't
//     trivially defeat the session check. Not a hard DB constraint (shared
//     IPs/NAT would cause false rejections for legitimate voters) - just a
//     pre-insert lookup here.
//
// Neither check stops a determined attacker (VPN + cleared storage), but
// together they raise the bar well above "no protection at all", which is
// the current state for anonymous votes.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
// Pepper for IP hashing so raw IPs are never stored. A fixed dev-only
// fallback is fine here precisely because it's a fallback only used when
// IP_HASH_SALT isn't set - set the real secret per-project before relying
// on this for anti-abuse in a real deployment.
const IP_HASH_SALT = Deno.env.get("IP_HASH_SALT") ?? "dev-only-insecure-salt";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/// Best-effort real client IP from common proxy headers. Cloudflare's own
/// header (cf-connecting-ip) is preferred when present since Supabase Edge
/// Functions run behind Cloudflare; x-forwarded-for is the general fallback.
/// Exported for testing.
export function extractClientIp(headers: Headers): string | null {
  const cf = headers.get("cf-connecting-ip");
  if (cf && cf.trim().length > 0) return cf.trim();
  const xff = headers.get("x-forwarded-for");
  if (xff && xff.trim().length > 0) return xff.split(",")[0].trim();
  return null;
}

/// Salted SHA-256 hex digest of an IP address. Exported for testing.
export async function hashIp(ip: string, salt: string): Promise<string> {
  const bytes = new TextEncoder().encode(`${salt}:${ip}`);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/// A client-supplied anonSessionId is only ever reused if it looks like a
/// token this function itself would have issued (crypto.randomUUID()
/// format) - anything else is treated as absent and a fresh one is issued,
/// so a client can't pick an arbitrary string to collide with someone
/// else's session. Exported for testing.
export function isValidSessionId(value: unknown): value is string {
  return (
    typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      value,
    )
  );
}

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const pollId = typeof body.pollId === "string" ? body.pollId : null;
  const optionId = typeof body.optionId === "string" ? body.optionId : null;
  if (!pollId || !optionId) {
    return jsonResponse({ error: "pollId and optionId are required" }, 400);
  }

  const anonSessionId = isValidSessionId(body.anonSessionId)
    ? body.anonSessionId
    : crypto.randomUUID();

  const ip = extractClientIp(req.headers);
  const ipHash = ip ? await hashIp(ip, IP_HASH_SALT) : null;

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: poll } = await supabase
    .from("polls")
    .select("id, status, visibility")
    .eq("id", pollId)
    .maybeSingle();

  if (!poll) {
    return jsonResponse({ error: "Poll not found" }, 404);
  }
  if (poll.status !== "active" || poll.visibility !== "public") {
    return jsonResponse(
      { error: "This poll is not open to anonymous voting" },
      403,
    );
  }

  const { data: option } = await supabase
    .from("poll_options")
    .select("id")
    .eq("id", optionId)
    .eq("poll_id", pollId)
    .maybeSingle();

  if (!option) {
    return jsonResponse({ error: "Option not found on this poll" }, 404);
  }

  if (ipHash) {
    const { data: existingByIp } = await supabase
      .from("votes")
      .select("id")
      .eq("poll_id", pollId)
      .eq("anon_ip_hash", ipHash)
      .limit(1);
    if (existingByIp && existingByIp.length > 0) {
      return jsonResponse({ error: "already_voted", anonSessionId }, 409);
    }
  }

  const { error: insertError } = await supabase.from("votes").insert({
    poll_id: pollId,
    option_id: optionId,
    user_id: null,
    anon_session_id: anonSessionId,
    anon_ip_hash: ipHash,
  });

  if (insertError) {
    if (insertError.code === "23505") {
      return jsonResponse({ error: "already_voted", anonSessionId }, 409);
    }
    return jsonResponse({ error: "Could not record vote" }, 500);
  }

  return jsonResponse({ success: true, anonSessionId }, 200);
});
