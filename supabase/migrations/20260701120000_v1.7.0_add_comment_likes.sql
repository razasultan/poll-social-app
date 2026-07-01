-- v1.7.0: Instagram-style comment likes
-- Adds comment_likes junction table, likes_count denorm column on comments,
-- and AFTER INSERT/DELETE triggers to keep the count in sync.

-- ─── Table ───────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.comment_likes (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  comment_id  uuid        NOT NULL REFERENCES public.comments(id) ON DELETE CASCADE,
  user_id     uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (comment_id, user_id)
);

-- ─── Denorm column ───────────────────────────────────────────────────────────

ALTER TABLE public.comments
  ADD COLUMN IF NOT EXISTS likes_count integer NOT NULL DEFAULT 0;

-- ─── Triggers ────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.increment_comment_likes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.comments
  SET likes_count = likes_count + 1
  WHERE id = NEW.comment_id;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.decrement_comment_likes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.comments
  SET likes_count = GREATEST(likes_count - 1, 0)
  WHERE id = OLD.comment_id;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_increment_comment_likes ON public.comment_likes;
CREATE TRIGGER trg_increment_comment_likes
  AFTER INSERT ON public.comment_likes
  FOR EACH ROW EXECUTE FUNCTION public.increment_comment_likes();

DROP TRIGGER IF EXISTS trg_decrement_comment_likes ON public.comment_likes;
CREATE TRIGGER trg_decrement_comment_likes
  AFTER DELETE ON public.comment_likes
  FOR EACH ROW EXECUTE FUNCTION public.decrement_comment_likes();

-- ─── RLS ─────────────────────────────────────────────────────────────────────

ALTER TABLE public.comment_likes ENABLE ROW LEVEL SECURITY;

-- Everyone can read likes (needed to show counts and resolve own-like state)
CREATE POLICY "comment_likes_select"
  ON public.comment_likes FOR SELECT
  USING (true);

-- Authenticated users can like
CREATE POLICY "comment_likes_insert"
  ON public.comment_likes FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Only the liker can unlike
CREATE POLICY "comment_likes_delete"
  ON public.comment_likes FOR DELETE
  USING (auth.uid() = user_id);
