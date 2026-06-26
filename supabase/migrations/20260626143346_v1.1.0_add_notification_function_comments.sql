-- Pipeline test migration: documents the notification trigger functions
-- with COMMENT ON (metadata only, no behavior change). Used to verify the
-- deploy-dev / deploy-prod CI workflow end-to-end before relying on it for
-- real changes.

COMMENT ON FUNCTION public.create_vote_notification() IS
  'Inserts a notification for the poll owner when someone else votes on their poll. Skips self-votes.';

COMMENT ON FUNCTION public.create_like_notification() IS
  'Inserts a notification for the poll owner when someone else likes their poll. Skips self-likes.';

COMMENT ON FUNCTION public.create_comment_notification() IS
  'Inserts a notification for the poll owner when someone else comments on their poll (active comments only). Skips self-comments.';

COMMENT ON FUNCTION public.create_follow_notification() IS
  'Inserts a notification for the followed user when someone follows them.';
