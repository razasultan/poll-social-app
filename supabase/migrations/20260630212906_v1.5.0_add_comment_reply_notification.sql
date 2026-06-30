-- Adds 'comment_reply' notification type and a trigger that fires when a reply
-- is posted, notifying the parent comment's author. Also patches
-- create_comment_notification so it no longer fires for replies (poll-owner
-- notifications are for top-level comments only, matching Instagram/X patterns
-- where replies are contextual to the comment thread, not a fresh top-level
-- signal on the poll itself).

-- 1. Extend the type CHECK constraint.
ALTER TABLE public.notifications
  DROP CONSTRAINT notifications_type_check;

ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_check
  CHECK (type = ANY (ARRAY[
    'vote', 'like', 'comment', 'follow', 'system', 'comment_reply'
  ]));

-- 2. Patch create_comment_notification to skip replies.
CREATE OR REPLACE FUNCTION public.create_comment_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    poll_owner uuid;
    commenter_name text;
    poll_question text;
BEGIN
    -- Skip status-inactive comments and replies — replies get their own
    -- notification via create_reply_notification().
    IF new.status <> 'active' OR new.parent_comment_id IS NOT NULL THEN
        RETURN new;
    END IF;

    SELECT user_id, question INTO poll_owner, poll_question
    FROM polls WHERE id = new.poll_id;

    -- Skip if the commenter is the poll owner (self-comment).
    IF poll_owner IS NULL OR poll_owner = new.user_id THEN
        RETURN new;
    END IF;

    SELECT coalesce(display_name, username) INTO commenter_name
    FROM profiles WHERE id = new.user_id;

    INSERT INTO notifications (user_id, type, title, message, related_poll_id, related_user_id)
    VALUES (
        poll_owner,
        'comment',
        'New comment',
        coalesce(commenter_name, 'Someone')
            || ' commented on "'
            || left(coalesce(poll_question, 'your poll'), 80)
            || '"',
        new.poll_id,
        new.user_id
    );

    RETURN new;
END;
$$;

-- 3. New function: notify the parent comment's author when a reply lands.
CREATE OR REPLACE FUNCTION public.create_reply_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    parent_author uuid;
    replier_name  text;
    reply_preview text;
BEGIN
    -- Only act on active replies (top-level comments have null parent_comment_id).
    IF new.status <> 'active' OR new.parent_comment_id IS NULL THEN
        RETURN new;
    END IF;

    -- Who wrote the comment being replied to?
    SELECT user_id INTO parent_author
    FROM comments WHERE id = new.parent_comment_id;

    -- Orphan reply (parent deleted) or self-reply: nothing to notify.
    IF parent_author IS NULL OR parent_author = new.user_id THEN
        RETURN new;
    END IF;

    SELECT coalesce(display_name, username) INTO replier_name
    FROM profiles WHERE id = new.user_id;

    -- Truncate the reply text for the preview so the message stays readable.
    reply_preview := left(new.comment_text, 100);

    INSERT INTO notifications (user_id, type, title, message, related_poll_id, related_user_id)
    VALUES (
        parent_author,
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

-- 4. Trigger on comments INSERT.
CREATE OR REPLACE TRIGGER trg_create_reply_notification
    AFTER INSERT ON public.comments
    FOR EACH ROW EXECUTE FUNCTION public.create_reply_notification();

COMMENT ON FUNCTION public.create_reply_notification() IS
    'Inserts a comment_reply notification for the parent comment author when '
    'a reply is posted. Skips orphan replies and self-replies.';
