-- Instagram-style comment enhancements.
-- Adds: replies_count (denormalized, trigger-maintained), reply_to_user_id
-- (for reply-to-reply @mention tracking), and extends create_reply_notification
-- to notify the directly-mentioned user when reply_to_user_id is set.

-- ── 1. New columns ─────────────────────────────────────────────────────────

ALTER TABLE public.comments
    ADD COLUMN IF NOT EXISTS replies_count integer NOT NULL DEFAULT 0;

-- Who is being directly replied to in a reply-to-reply scenario.
-- NULL for top-level comments and for replies that target the top-level
-- comment directly. Referencing profiles so the name is fetchable without
-- an extra join; SET NULL on delete so the comment survives profile deletion.
ALTER TABLE public.comments
    ADD COLUMN IF NOT EXISTS reply_to_user_id uuid
    REFERENCES public.profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_comments_reply_to_user_id
    ON public.comments (reply_to_user_id)
    WHERE reply_to_user_id IS NOT NULL;

-- ── 2. Backfill replies_count from existing data ────────────────────────────

UPDATE public.comments c
SET replies_count = (
    SELECT count(*)
    FROM public.comments r
    WHERE r.parent_comment_id = c.id
      AND r.status = 'active'
)
WHERE c.parent_comment_id IS NULL;  -- only top-level rows can be parents

-- ── 3. Trigger to keep replies_count accurate ───────────────────────────────

CREATE OR REPLACE FUNCTION public.update_comment_replies_count()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.parent_comment_id IS NOT NULL AND NEW.status = 'active' THEN
            UPDATE comments
            SET replies_count = replies_count + 1
            WHERE id = NEW.parent_comment_id;
        END IF;
        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN
        IF OLD.parent_comment_id IS NOT NULL AND OLD.status = 'active' THEN
            UPDATE comments
            SET replies_count = GREATEST(0, replies_count - 1)
            WHERE id = OLD.parent_comment_id;
        END IF;
        RETURN OLD;
    END IF;
END;
$$;

CREATE OR REPLACE TRIGGER trg_update_comment_replies_count
    AFTER INSERT OR DELETE ON public.comments
    FOR EACH ROW EXECUTE FUNCTION public.update_comment_replies_count();

-- ── 4. Update create_reply_notification to handle reply-to-reply ────────────
-- When reply_to_user_id IS NULL  → direct reply to a top-level comment
--   → notify the top-level comment's author (existing behaviour)
-- When reply_to_user_id IS NOT NULL → reply aimed at a specific previous reply
--   → notify reply_to_user_id (the person being @mentioned), not the
--     top-level comment author (they were already notified when the first
--     reply arrived)

CREATE OR REPLACE FUNCTION public.create_reply_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    notify_user   uuid;
    replier_name  text;
    reply_preview text;
BEGIN
    IF new.status <> 'active' OR new.parent_comment_id IS NULL THEN
        RETURN new;
    END IF;

    IF new.reply_to_user_id IS NOT NULL THEN
        -- Reply-to-reply: notify the person being directly addressed.
        notify_user := new.reply_to_user_id;
    ELSE
        -- Direct reply to a top-level comment: notify that comment's author.
        SELECT user_id INTO notify_user
        FROM comments WHERE id = new.parent_comment_id;
    END IF;

    -- Orphan or self-reply: skip.
    IF notify_user IS NULL OR notify_user = new.user_id THEN
        RETURN new;
    END IF;

    SELECT coalesce(display_name, username) INTO replier_name
    FROM profiles WHERE id = new.user_id;

    reply_preview := left(new.comment_text, 100);

    INSERT INTO notifications (user_id, type, title, message, related_poll_id, related_user_id)
    VALUES (
        notify_user,
        'comment_reply',
        'New reply',
        coalesce(replier_name, 'Someone')
            || ' replied: "'
            || reply_preview
            || '"',
        new.poll_id,
        new.user_id
    );

    RETURN new;
END;
$$;

COMMENT ON COLUMN public.comments.replies_count IS
    'Denormalized count of active direct replies. Maintained by trg_update_comment_replies_count.';
COMMENT ON COLUMN public.comments.reply_to_user_id IS
    'For reply-to-reply: the user being directly addressed. NULL for top-level comments and for direct replies to a top-level comment. Display as "@username" prefix in the UI.';
COMMENT ON FUNCTION public.update_comment_replies_count() IS
    'Keeps comments.replies_count in sync with actual reply rows.';
COMMENT ON FUNCTION public.create_reply_notification() IS
    'Notifies reply_to_user_id when set (reply-to-reply), otherwise notifies the top-level comment author. Skips self-replies and orphans.';
