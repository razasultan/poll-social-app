-- Fix: "Database error querying schema" / unexpected_failure on sign-in
--
-- Common when auth.users rows were inserted manually (SQL seed/migration) and
-- token columns are NULL. GoTrue expects empty strings, not NULL.
--
-- Run in Supabase Dashboard → SQL Editor on the SAME project your app uses
-- (e.g. poll-social-app-dev when launching with Flutter DEV).

-- 1) Inspect the user (optional)
-- select id, email, confirmation_token, recovery_token, email_change, email_change_token_new
-- from auth.users where email = 'user1@test.com';

-- 2) Fix NULL token columns for all affected users
update auth.users
set
  confirmation_token = coalesce(confirmation_token, ''),
  recovery_token = coalesce(recovery_token, ''),
  email_change_token_new = coalesce(email_change_token_new, ''),
  email_change = coalesce(email_change, '')
where
  confirmation_token is null
  or recovery_token is null
  or email_change_token_new is null
  or email_change is null;

-- 3) Prefer creating users via Dashboard → Authentication → Add user
--    or the app's Sign up screen, not raw INSERT into auth.users.
