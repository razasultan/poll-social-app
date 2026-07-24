-- v1.9.0: per-poll media layout selector
-- Stores which visual layout the poll creator chose for rendering options
-- that all carry media attachments. Three options: scrim (default), list, mosaic.

ALTER TABLE polls
  ADD COLUMN IF NOT EXISTS media_layout TEXT
    CHECK (media_layout IN ('scrim', 'list', 'mosaic'))
    DEFAULT 'scrim';
