-- Anonymous voting for shared polls.
--
-- votes.user_id was NOT NULL with an INSERT RLS policy requiring
-- auth.uid() = user_id, so unauthenticated visitors arriving via a shared
-- poll link had no way to vote at all. This migration makes user_id
-- nullable and adds two columns identifying an anonymous voter instead:
--
--   anon_session_id - an opaque token the client persists locally (NOT a
--     client-generated value trusted blindly - it's only ever written by
--     the vote-anonymous Edge Function, which issues one on a voter's
--     first anonymous vote and the client echoes back on subsequent
--     votes). Deduped via a partial unique index, same role user_id's
--     existing (poll_id, user_id) unique constraint plays for real users.
--
--   anon_ip_hash - a salted SHA-256 hash of the voter's IP (never the raw
--     IP, to avoid storing PII at rest), used by the Edge Function as a
--     secondary dedup signal so clearing local storage alone doesn't
--     trivially defeat the session-based check. Not a hard DB constraint
--     (shared IPs/NAT would cause false rejections) - enforced as a
--     pre-INSERT check inside the Edge Function instead.
--
-- No RLS policy is added for anonymous INSERTs: anon clients still have no
-- direct path to insert into votes (the existing "Users can vote as
-- themselves" policy requires auth.uid() = user_id, which anon requests
-- can never satisfy). The only way to insert an anonymous vote is via the
-- vote-anonymous Edge Function, which uses the service role key and so
-- bypasses RLS entirely - this is intentional: it keeps all anonymous-vote
-- anti-abuse logic server-side instead of relying on RLS to express it.

ALTER TABLE "public"."votes"
  ALTER COLUMN "user_id" DROP NOT NULL;

ALTER TABLE "public"."votes"
  ADD COLUMN "anon_session_id" text,
  ADD COLUMN "anon_ip_hash" text;

ALTER TABLE "public"."votes"
  ADD CONSTRAINT "votes_identity_check" CHECK (
    ("user_id" IS NOT NULL AND "anon_session_id" IS NULL)
    OR ("user_id" IS NULL AND "anon_session_id" IS NOT NULL)
  );

CREATE UNIQUE INDEX "votes_poll_anon_session_unique"
  ON "public"."votes" ("poll_id", "anon_session_id")
  WHERE "anon_session_id" IS NOT NULL;

CREATE INDEX "idx_votes_poll_anon_ip_hash"
  ON "public"."votes" ("poll_id", "anon_ip_hash")
  WHERE "anon_ip_hash" IS NOT NULL;

COMMENT ON COLUMN "public"."votes"."anon_session_id" IS
  'Opaque per-voter token issued by the vote-anonymous Edge Function and persisted client-side; NULL for authenticated votes. Deduped via votes_poll_anon_session_unique.';

COMMENT ON COLUMN "public"."votes"."anon_ip_hash" IS
  'Salted SHA-256 hash of the anonymous voter''s IP address, set by the vote-anonymous Edge Function; NULL for authenticated votes. Secondary anti-abuse signal, not a hard uniqueness constraint.';
