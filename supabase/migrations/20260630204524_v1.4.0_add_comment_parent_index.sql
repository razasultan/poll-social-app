-- Index supporting client-side grouping of comments into parent + replies.
-- Partial (WHERE parent_comment_id IS NOT NULL) so only reply rows are
-- indexed - top-level comments have null there and are found by poll_id
-- via the existing idx_comments_poll_id index, so this avoids indexing
-- rows that would never be looked up through this column.
CREATE INDEX IF NOT EXISTS idx_comments_parent_comment_id
  ON public.comments (parent_comment_id)
  WHERE parent_comment_id IS NOT NULL;
