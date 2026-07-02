import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/media/video_manager.dart';
import '../core/widgets/trending_rail.dart';
import '../services/notification_service.dart';
import '../services/profile_service.dart';
import '../widgets/app_toast.dart';
import '../widgets/auth_guard.dart';
import '../widgets/create_poll_modal.dart';
import 'auth/login_screen.dart';
import 'auth/signup_screen.dart';
import 'feed_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

/// Pauses all [VideoPreview] instances whenever the shell's nested navigator
/// pushes a new route (e.g. feed → poll detail, feed → profile).
class _VideoPauseObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    VideoManager.pauseAll();
  }
}

/// Root shell with bottom navigation across primary destinations.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  /// Bottom nav index for the Create action (opens [CreatePollScreen], not a stack page).
  static const int createNavIndex = 2;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  /// Nested navigator for the body area, so pushed screens (poll detail,
  /// other profiles, settings, etc.) render inside the body while the side
  /// nav and [TrendingRail] stay fixed.
  final GlobalKey<NavigatorState> _shellNavigatorKey =
      GlobalKey<NavigatorState>();

  final ValueNotifier<int> _feedReloadToken = ValueNotifier<int>(0);
  final ValueNotifier<int> _profileReloadToken = ValueNotifier<int>(0);

  late final NotificationService _notificationService;
  final ProfileService _profileService = ProfileService();
  int _shellUnreadCount = 0;
  RealtimeChannel? _shellNotificationChannel;
  StreamSubscription<AuthState>? _authSubscription;

  int get _stackIndex {
    assert(_selectedIndex != MainShell.createNavIndex);
    if (_selectedIndex < MainShell.createNavIndex) return _selectedIndex;
    return _selectedIndex - 1;
  }

  @override
  void initState() {
    super.initState();
    _notificationService = NotificationService();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) {
      // On sign-out: skip all setState work (widget tree is being replaced)
      // and navigate to LoginScreen after the current frame settles.
      if (data.event == AuthChangeEvent.signedOut) {
        VideoManager.pauseAll();
        // Push LoginScreen on top of MainShell (don't remove it).
        // MainShell stays alive in guest mode underneath so that when
        // sign-in succeeds, LoginScreen.pop() lands back here naturally —
        // no "can't pop" dead-end, and no OverlayPortal layout assertion
        // from destroying FeedScreen mid-frame.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
              );
            }
          });
        });
        return;
      }
      final user = data.session?.user;
      _syncShellNotificationBadge(user);
      if (user != null) _ensureProfileExists(user);
      final itemCount = user == null ? 4 : 5;
      if (_selectedIndex >= itemCount && mounted) {
        setState(() => _selectedIndex = 0);
      }
    });
    final currentUser = Supabase.instance.client.auth.currentUser;
    _syncShellNotificationBadge(currentUser);
    if (currentUser != null) _ensureProfileExists(currentUser);
  }

  /// Fallback profile creation for users whose `profiles` row wasn't created
  /// at signup time (e.g. email confirmation deferred the session, or
  /// sign-in happened via OAuth). Failures are non-fatal — the user can
  /// still create their profile from Settings.
  Future<void> _ensureProfileExists(User user) async {
    try {
      await _profileService.ensureProfileExists(user);
    } catch (_) {
      // Best-effort; profile can still be completed from Settings.
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _shellNotificationChannel?.unsubscribe();
    _feedReloadToken.dispose();
    _profileReloadToken.dispose();
    super.dispose();
  }

  Future<void> _refreshShellUnreadBadge(String userId) async {
    final count = await _notificationService.countUnreadNotifications(userId);
    if (mounted) setState(() => _shellUnreadCount = count);
  }

  void _syncShellNotificationBadge(User? user) {
    _shellNotificationChannel?.unsubscribe();
    _shellNotificationChannel = null;

    if (user == null) {
      if (mounted) setState(() => _shellUnreadCount = 0);
      return;
    }

    unawaited(_refreshShellUnreadBadge(user.id));

    final filter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'user_id',
      value: user.id,
    );

    final channel = Supabase.instance.client.channel(
      'shell-nav-notifications-${user.id}',
    );
    channel
        .onPostgresChanges(
          schema: 'public',
          table: 'notifications',
          event: PostgresChangeEvent.all,
          filter: filter,
          callback: (_) {
            unawaited(_refreshShellUnreadBadge(user.id));
          },
        )
        .subscribe();
    _shellNotificationChannel = channel;
  }

  Future<void> _openCreate() async {
    await AuthGuard.requireAuth(
      context,
      onAuthenticated: () async {
        final created = await showCreatePollModal(context);
        if (!mounted) return;
        if (created == true) {
          setState(() => _selectedIndex = 0);
          _feedReloadToken.value++;
          _profileReloadToken.value++;
          AppToast.success(context, 'Poll published');
          final u = Supabase.instance.client.auth.currentUser;
          if (u != null) await _refreshShellUnreadBadge(u.id);
        }
      },
    );
  }

  /// Nav index of the Profile destination for an authenticated user (5 items:
  /// Home=0, Search=1, Create=2, Notifications=3, Profile=4).
  static const int _profileNavIndex = 4;

  void _onBottomNavTap(int index) {
    if (index == MainShell.createNavIndex) {
      unawaited(_openCreate());
      return;
    }
    // Pause any playing video when the user switches tabs — IndexedStack
    // hides the old tab without pushing a new route, so RouteAware.didPushNext
    // is never called and we need an explicit pause here.
    VideoManager.pauseAll();
    _shellNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    setState(() => _selectedIndex = index);
    final u = Supabase.instance.client.auth.currentUser;
    if (index == 3 && u != null) {
      unawaited(_refreshShellUnreadBadge(u.id));
    }
    // Reload profile data whenever the user navigates to the Profile tab so
    // newly published polls appear without requiring a manual pull-to-refresh.
    if (u != null && index == _profileNavIndex) {
      _profileReloadToken.value++;
    }
  }

  /// X-style circular blue compose badge, set apart from the plain nav icons.
  Widget _composeNavIcon(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
      child: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
    );
  }

  Widget _notificationsNavIcon({required bool active}) {
    return Badge(
      isLabelVisible: _shellUnreadCount > 0,
      label: Text(
        _shellUnreadCount > 99 ? '99+' : '$_shellUnreadCount',
        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
      ),
      child: Icon(
        active ? Icons.notifications_rounded : Icons.notifications_outlined,
      ),
    );
  }

  Widget _buildProfileTab(User? user) {
    if (user == null) {
      return _buildLoginRequiredView(
        message: 'Log in to view and edit your profile',
      );
    }
    return ProfileScreen(userId: user.id, reloadToken: _profileReloadToken);
  }

  Widget _buildLoginRequiredView({required String message}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 48,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              message,
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
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                  child: const Text('Login'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SignupScreen()),
                  ),
                  child: const Text('Sign up'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Width above which the shell switches from a bottom nav bar (mobile/narrow
  /// web) to a side [NavigationRail] (desktop/wide web), mirroring how X swaps
  /// its mobile tab bar for a left-hand nav column on wider viewports.
  static const double _wideLayoutBreakpoint = 700;

  /// Width above which a "Trending now" rail appears on the right, mirroring
  /// X's third column on large desktop viewports.
  static const double _trendingRailBreakpoint = 1100;

  /// Shared icon/label data for each destination, fed into both the
  /// [BottomNavigationBar] (narrow) and [NavigationRail] (wide) so the two
  /// layouts always stay in sync.
  List<({Widget icon, Widget activeIcon, String label})> _navEntries(
    BuildContext context,
    bool isGuest,
  ) {
    return [
      const (
        icon: Icon(Icons.home_outlined),
        activeIcon: Icon(Icons.home_rounded),
        label: 'Home',
      ),
      const (
        icon: Icon(Icons.search_rounded),
        activeIcon: Icon(Icons.search_rounded),
        label: 'Search',
      ),
      (
        icon: _composeNavIcon(context),
        activeIcon: _composeNavIcon(context),
        label: 'Create',
      ),
      if (!isGuest)
        (
          icon: _notificationsNavIcon(active: false),
          activeIcon: _notificationsNavIcon(active: true),
          label: 'Notifications',
        ),
      const (
        icon: Icon(Icons.person_outline_rounded),
        activeIcon: Icon(Icons.person_rounded),
        label: 'Profile',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final isGuest = user == null;

    final entries = _navEntries(context, isGuest);
    final selectedIndex = _selectedIndex < entries.length ? _selectedIndex : 0;

    // The route builder must NOT capture stackChildren from the local build()
    // scope. That list would become stale after a sign-in/out event because
    // Flutter reuses the existing MaterialPageRoute and never re-calls
    // onGenerateRoute for the initial route. Reading auth state fresh inside
    // the builder ensures the IndexedStack children are always current.
    final body = Navigator(
      key: _shellNavigatorKey,
      observers: [_VideoPauseObserver()],
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) {
          final u = Supabase.instance.client.auth.currentUser;
          return IndexedStack(
            index: _stackIndex,
            sizing: StackFit.expand,
            children: [
              FeedScreen(feedReloadToken: _feedReloadToken),
              const SearchScreen(),
              if (u != null) const NotificationsScreen(),
              _buildProfileTab(u),
            ],
          );
        },
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _wideLayoutBreakpoint) {
          final cs = Theme.of(context).colorScheme;
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: _onBottomNavTap,
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: cs.surface,
                  destinations: [
                    for (int i = 0; i < entries.length; i++)
                      NavigationRailDestination(
                        icon: Semantics(
                          button: true,
                          label:
                              '${entries[i].label} Tab ${i + 1} of ${entries.length}',
                          onTap: () => _onBottomNavTap(i),
                          child: entries[i].icon,
                        ),
                        selectedIcon: Semantics(
                          button: true,
                          label:
                              '${entries[i].label} Tab ${i + 1} of ${entries.length}',
                          onTap: () => _onBottomNavTap(i),
                          child: entries[i].activeIcon,
                        ),
                        label: Text(entries[i].label),
                      ),
                  ],
                ),
                VerticalDivider(width: 1, color: cs.outlineVariant),
                Expanded(child: body),
                if (constraints.maxWidth >= _trendingRailBreakpoint) ...[
                  VerticalDivider(width: 1, color: cs.outlineVariant),
                  TrendingRail(reloadToken: _feedReloadToken),
                ],
              ],
            ),
          );
        }

        return Scaffold(
          body: body,
          bottomNavigationBar: BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            currentIndex: selectedIndex,
            onTap: _onBottomNavTap,
            items: [
              for (int i = 0; i < entries.length; i++)
                BottomNavigationBarItem(
                  icon: Semantics(
                    button: true,
                    label: 'Tab ${i + 1} of ${entries.length}',
                    onTap: () => _onBottomNavTap(i),
                    child: entries[i].icon,
                  ),
                  activeIcon: Semantics(
                    button: true,
                    label: 'Tab ${i + 1} of ${entries.length}',
                    onTap: () => _onBottomNavTap(i),
                    child: entries[i].activeIcon,
                  ),
                  label: entries[i].label,
                ),
            ],
          ),
        );
      },
    );
  }
}
