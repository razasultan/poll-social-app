-- RPCs for recording poll views and share actions.
-- poll_analytics rows are always created by the create_poll_analytics trigger
-- on poll INSERT, but the UPSERT guards against any edge-case gaps.
-- Both functions are SECURITY DEFINER and granted to anon + authenticated so
-- anonymous visitors (PublicPollScreen / embedded polls) can call them too.

CREATE OR REPLACE FUNCTION public.increment_poll_views(p_poll_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  INSERT INTO poll_analytics (poll_id, views_count)
  VALUES (p_poll_id, 1)
  ON CONFLICT (poll_id)
  DO UPDATE SET
    views_count = poll_analytics.views_count + 1,
    updated_at  = now();
$$;

CREATE OR REPLACE FUNCTION public.increment_poll_shares(p_poll_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  INSERT INTO poll_analytics (poll_id, shares_count)
  VALUES (p_poll_id, 1)
  ON CONFLICT (poll_id)
  DO UPDATE SET
    shares_count = poll_analytics.shares_count + 1,
    updated_at   = now();
$$;

GRANT EXECUTE ON FUNCTION public.increment_poll_views(uuid)  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.increment_poll_shares(uuid) TO anon, authenticated;

COMMENT ON FUNCTION public.increment_poll_views(uuid)  IS
  'Increments views_count for a poll. Client-side per-session dedup is expected '
  'at the call site (PollDetailScreen) - this function itself is idempotent-safe '
  'but not deduplicated at the DB level.';

COMMENT ON FUNCTION public.increment_poll_shares(uuid) IS
  'Increments shares_count for a poll. Called after a successful Share.share / '
  'Share.shareXFiles invocation in poll_card.dart.';
