-- v1.8.0: Add is_public flag to profiles
--
-- Controls whether a profile is accessible at /u/:username without auth.
-- Defaults to FALSE (private) — users opt-in to a public profile in Settings.
-- Poll visibility is independent: public polls remain discoverable in feeds
-- regardless of profile privacy.

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS is_public BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN profiles.is_public IS
  'When true the profile is accessible at the public /u/:username URL. '
  'Defaults to false (private). Does not affect poll visibility.';
