import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../screens/auth/login_screen.dart';
import '../../screens/auth/signup_screen.dart';
import '../../screens/backend_test_screen.dart';
import '../../screens/embed_poll_screen.dart';
import '../../screens/feed_screen.dart';
import '../../screens/main_shell.dart';
import '../../screens/notifications_screen.dart';
import '../../screens/poll_detail_screen.dart';
import '../../screens/profile_screen.dart';
import '../../screens/public_poll_screen.dart';
import '../../screens/public_profile_screen.dart';
import '../../screens/search_screen.dart';
import '../../screens/settings_screen.dart';
import '../media/video_pause_observer.dart';

/// Sub-routes shared by every shell branch: poll detail, other-user profile,
/// and settings (so the nav rail stays visible while in Settings).
/// Paths are relative (no leading `/`) so they nest under each branch root.
List<RouteBase> _branchSubRoutes() => [
  GoRoute(
    path: 'poll/:id',
    builder: (ctx, s) => PollDetailScreen(pollId: s.pathParameters['id']!),
  ),
  GoRoute(
    path: 'user/:userId',
    builder: (ctx, s) => ProfileScreen(userId: s.pathParameters['userId']!),
  ),
  GoRoute(
    path: 'settings',
    builder: (ctx, s) => const SettingsScreen(),
    routes: [
      GoRoute(path: 'blocked', builder: (ctx, s) => const BlockedUsersScreen()),
    ],
  ),
];

/// Application-wide [GoRouter]. Replaces Navigator 1.0 push/pop so every
/// screen has a stable browser URL (fixes Bug #7).
final GoRouter appRouter = GoRouter(
  initialLocation: '/home',
  routes: [
    GoRoute(path: '/', redirect: (ctx, state) => '/home'),

    // ── Shell with 4 StatefulShellBranches ─────────────────────────────
    StatefulShellRoute.indexedStack(
      builder: (ctx, state, shell) => MainShell(navigationShell: shell),
      branches: [
        // Branch 0 — Home / Feed
        StatefulShellBranch(
          observers: [VideoPauseObserver()],
          routes: [
            GoRoute(
              path: '/home',
              builder: (ctx, s) => const FeedScreen(),
              routes: _branchSubRoutes(),
            ),
          ],
        ),
        // Branch 1 — Search
        StatefulShellBranch(
          observers: [VideoPauseObserver()],
          routes: [
            GoRoute(
              path: '/search',
              builder: (ctx, s) => SearchScreen(
                initialQuery: s.uri.queryParameters['q'],
                initialTabIndex: int.tryParse(
                  s.uri.queryParameters['tab'] ?? '',
                ),
              ),
              routes: _branchSubRoutes(),
            ),
          ],
        ),
        // Branch 2 — Notifications
        StatefulShellBranch(
          observers: [VideoPauseObserver()],
          routes: [
            GoRoute(
              path: '/notifications',
              builder: (ctx, s) => const NotificationsScreen(),
              routes: _branchSubRoutes(),
            ),
          ],
        ),
        // Branch 3 — Profile (own user or login-required view)
        StatefulShellBranch(
          observers: [VideoPauseObserver()],
          routes: [
            GoRoute(
              path: '/profile',
              builder: (ctx, s) {
                final user = Supabase.instance.client.auth.currentUser;
                if (user == null) return const _LoginRequiredView();
                return ProfileScreen(userId: user.id);
              },
              routes: _branchSubRoutes(),
            ),
          ],
        ),
      ],
    ),

    // ── Public share links ────────────────────────────────────────────────
    GoRoute(
      path: '/p/:slug',
      builder: (ctx, s) =>
          PublicPollScreen(shareSlug: s.pathParameters['slug']!),
    ),
    GoRoute(
      path: '/embed/poll/:slug',
      builder: (ctx, s) =>
          EmbedPollScreen(shareSlug: s.pathParameters['slug']!),
    ),
    // Legacy /poll/:slug → /p/:slug redirect.
    GoRoute(
      path: '/poll/:slug',
      redirect: (ctx, s) => '/p/${s.pathParameters['slug']}',
    ),

    // ── Public profile page ───────────────────────────────────────────────
    GoRoute(
      path: '/u/:username',
      builder: (ctx, s) =>
          PublicProfileScreen(username: s.pathParameters['username']!),
    ),

    // ── Auth screens ──────────────────────────────────────────────────────
    GoRoute(path: '/login', builder: (ctx, s) => const LoginScreen()),
    GoRoute(path: '/signup', builder: (ctx, s) => const SignupScreen()),

    // ── Debug ─────────────────────────────────────────────────────────────
    GoRoute(path: '/debug', builder: (ctx, s) => const BackendTestScreen()),
  ],
);

/// Shown in the Profile branch when the user is not signed in.
class _LoginRequiredView extends StatelessWidget {
  const _LoginRequiredView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_outline_rounded,
                size: 48,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'Log in to view your profile',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: () => context.push('/login'),
                    child: const Text('Log in'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () => context.push('/signup'),
                    child: const Text('Sign up'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
