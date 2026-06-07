# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Added
- Guest browsing: the app now opens directly into `MainShell` without requiring
  login. Guests can browse Latest/Trending feeds, search, view poll details,
  and view public profiles (avatar, display name, username, bio, follower/
  following counts, public polls) without being redirected to the login screen.
- `AuthGuard.requireAuth` (`lib/widgets/auth_guard.dart`): a callback-based,
  action-level auth gate. When a signed-in user calls a gated action it runs
  immediately; when a guest does, a bottom sheet prompts
  "Log in to interact with polls and follow creators." with **Log in**,
  **Create account**, and **Not now** options.

### Changed
- Replaced screen-level login redirects with action-level auth gating. Voting,
  liking, commenting, reporting, following/unfollowing, creating a poll, and
  opening notifications now show the `AuthGuard` prompt at the moment a guest
  taps them, instead of blocking access to whole screens.
- Adapted navigation chrome for guests: `FeedScreen` shows Latest/Trending tabs
  (no For You) and `MainShell` hides the Notifications tab when signed out.
- Updated `README.md` with a "Guest browsing" section describing the new
  behavior.

### Removed
- `lib/widgets/auth_required_dialog.dart` and its `showAuthRequiredDialog`
  helper, superseded by `AuthGuard.requireAuth`.
