# poll-social-app

A social polling platform where users create polls (text, image, video), follow others, vote instantly, and discover regional/global opinion trends.

## Stack

- **Flutter** (mobile, web, desktop)
- **Supabase** (auth, Postgres, realtime)

## Guest browsing

The app is **guest-first**: it never forces a login at startup. Anyone can open
the app and browse without an account.

**Without an account you can:**
- Browse the **Latest** and **Trending** feeds
- Search polls, users, hashtags, and topics
- Open a poll's detail screen and read its comments
- View user profiles

**Logging in is required to interact:**
- Voting, liking, and commenting on polls
- Creating polls
- Following / unfollowing users
- Viewing the **For You** feed, notifications, and settings

When a guest taps a gated action (vote, like, comment, follow, create a poll,
or open notifications), a bottom sheet prompts **"Log in to interact with
polls and follow creators."** with **Log in** / **Create account** / **Not
now** options — see `AuthGuard.requireAuth` in `lib/widgets/auth_guard.dart`.
Your own Profile tab shows a dedicated login prompt instead when opened while
signed out.

## Environments (DEV / PROD)

Supabase URL and anon key are **not** hardcoded. They are supplied at build/run time with `--dart-define`:

| Define | Purpose |
|--------|---------|
| `APP_ENV` | `dev` (default) or `prod` |
| `SUPABASE_URL` | Project API URL |
| `SUPABASE_ANON_KEY` | Publishable anon key |

Config lives in `lib/core/config/app_config.dart`. Supabase startup is in `lib/core/config/supabase_config.dart`.

### Run DEV (Cursor / VS Code)

1. Open **Run and Debug**.
2. Choose **Flutter DEV** (`.vscode/launch.json`).
3. Start debugging.

That configuration sets `APP_ENV=dev` and the **poll-social-app-dev** Supabase project. It runs in **debug** mode (hot reload, breakpoints).

Use **Flutter DEV (Release)** for the same DEV backend in **release** mode (no hot reload; closer to store performance). **Flutter PROD (Release)** is the same for production defines.

### Run DEV (command line)

```bash
flutter run \
  --dart-define=APP_ENV=dev \
  --dart-define=SUPABASE_URL=https://uwomsxkvjqrvhdpnbkit.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=sb_publishable_LgwGHGciORtyBWVRajywqA_JYzCokcF
```

### Run DEV / PROD via shortcuts

To avoid retyping the `--dart-define` flags, use the wrapper scripts in `scripts/`
(PowerShell) or the `Makefile` targets (bash / WSL / Git Bash / `make`):

```powershell
# PowerShell
.\scripts\run_dev.ps1                        # debug, default device
.\scripts\run_dev.ps1 -Release -Device windows
.\scripts\run_prod.ps1
.\scripts\run_prod.ps1 -Release -Device windows
```

```bash
# Makefile (pass extra flutter args via FLUTTER_ARGS)
make run-dev
make run-dev FLUTTER_ARGS="-d windows"
make run-dev-release
make run-prod
make run-prod-release
```

Both scripts and the `Makefile` already have the PROD URL and publishable anon
key filled in (Supabase dashboard → **poll-social-app** project → Settings →
API → Publishable key, if it ever needs rotating).

### Run PROD

Use the **Flutter PROD** launch config, the shortcuts above, or the CLI directly:

```bash
flutter run \
  --dart-define=APP_ENV=prod \
  --dart-define=SUPABASE_URL=https://ioweogjlumrzcbejwbeb.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=sb_publishable_eBRj_ukaVQGpeAfcjwKvjQ_8sIu7PIP
```

### Debug DEV indicator

In **debug** builds, when `APP_ENV=dev`, a small orange **DEV** badge appears at the top-right so you can see you are not on production.

If `SUPABASE_URL` or `SUPABASE_ANON_KEY` is missing, the app shows a startup error screen and prints a clear message to the console (no silent failure).

### Test account (manual testing, DEV only)

A seeded, confirmed account on the **DEV** Supabase project — copy/paste straight into the login screen:

| Field | Value |
|-------|-------|
| Username | `gherkintester1` |
| Email | `razasultan.gherkintest1@gmail.com` |
| Password | `GherkinTest123!` |

This is the same account used by `integration_test/app_test.dart`. Don't use it against PROD.

### Test account (manual testing, PROD only)

A seeded, confirmed account on the **PROD** Supabase project (`poll-social-app`) — copy/paste straight into the login screen:

| Field | Value |
|-------|-------|
| Username | `prodtester1` |
| Email | `razasultan.prodtest1@gmail.com` |
| Password | `ProdTest123!` |

Verified working end-to-end (loads the live Poll Feed). Don't use it against DEV — the two projects don't share users.

### Login error: `Database error querying schema`

This comes from **Supabase Auth** (HTTP 500), not from Flutter. It often happens when a user in `auth.users` was created with **SQL** and token columns (`confirmation_token`, `recovery_token`, etc.) are **NULL** instead of `''`.

**Fix (DEV project — poll-social-app-dev):**

1. Confirm the app shows the **DEV** badge (you are on the dev Supabase project).
2. Open [Supabase SQL Editor](https://supabase.com/dashboard) for that project.
3. Run `supabase/troubleshooting-auth-login.sql`.
4. Try signing in again.

**Also check:**

- `user1@test.com` must exist in **this** project (Authentication → Users). Users from the old prod project are not shared with dev.
- Prefer **Sign up** in the app or **Add user** in the dashboard instead of manual `INSERT` into `auth.users`.
- If it still fails, open **Logs → Postgres** right after a failed login for the underlying SQL error.

## Creating a poll

1. Sign in with a valid account (use your auth flow or the temporary **Backend test** screen from the debug route).
2. On the **Poll Feed**, tap the **floating action button (+)**.
3. Fill in **Create Poll**:
   - **Question** (required)
   - **Description** (optional)
   - **Answer choices**: at least 2, up to 5 (use **Add option** / remove on each row)
   - **Expiration**: none, presets (1 hour / 24 hours / 7 days), or **Custom date & time**
   - **Visibility**: `Public`, `Followers`, or `Private` (stored as sent to `PollService.createPoll`)
   - **Country** / **City** (optional)
4. Tap **Publish Poll**. While publishing, the button is disabled and a progress indicator appears.
5. On success the screen closes with `Navigator.pop(context, true)`, the feed shows **Poll published**, and **Latest** / **Trending** lists refresh.

Validation errors (not signed in, missing question, too few options, duplicate option text, invalid expiration, etc.) are shown via **SnackBar**.

### Debug route

Long-press the poll icon in the feed app bar title, or navigate to `Navigator.pushNamed(context, '/debug')`, to open the developer backend test screen.

## Project layout (high level)

- `lib/main.dart` — app entry, theme, routes
- `lib/core/config/app_config.dart` — `APP_ENV`, Supabase dart-defines
- `lib/core/config/supabase_config.dart` — Supabase initialization
- `lib/core/widgets/dev_environment_banner.dart` — debug DEV badge
- `.vscode/launch.json` — **Flutter DEV** / **PROD** (debug and release) launch configs
- `lib/screens/create_poll_screen.dart` — create poll UI
- `lib/widgets/poll_card.dart` — feed poll card
- `lib/services/poll_service.dart` — `createPoll`, `getPollById`, …
- `lib/services/auth_service.dart` — sign-in / current user helpers
