import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/media/video_manager.dart';
import '../core/state/feed_notifier.dart';
import '../core/state/profile_notifier.dart';
import '../core/widgets/trending_rail.dart';
import '../services/notification_service.dart';
import '../services/profile_service.dart';
import '../widgets/app_toast.dart';
import '../widgets/auth_guard.dart';
import '../widgets/create_poll_modal.dart';

/// Root shell: renders the navigation rail (wide) or bottom nav bar (narrow)
/// alongside the go_router [StatefulNavigationShell] which maintains one
/// navigator stack per tab.
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// Nav-item index of the Create action (opens a modal, not a branch).
  static const int createNavIndex = 2;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late final NotificationService _notificationService;
  final ProfileService _profileService = ProfileService();
  int _shellUnreadCount = 0;
  RealtimeChannel? _shellNotificationChannel;
  StreamSubscription<AuthState>? _authSubscription;

  // ── Branch index → nav-item index mapping ────────────────────────────
  // Branches: 0=Home, 1=Search, 2=Notifications, 3=Profile
  // Nav items: 0=Home, 1=Search, 2=Create(modal), 3=Notifications, 4=Profile
  int get _selectedNavIndex {
    final b = widget.navigationShell.currentIndex;
    return b < 2 ? b : b + 1; // skip Create slot (index 2)
  }

  static int _navTobranchIndex(int navIndex) {
    if (navIndex < 2) return navIndex;
    return navIndex - 1; // 3→2(Notifications), 4→3(Profile)
  }

  @override
  void initState() {
    super.initState();
    _notificationService = NotificationService();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) {
      if (data.event == AuthChangeEvent.signedOut) {
        VideoManager.pauseAll();
        // Push LoginScreen on top of the shell (keep shell alive underneath
        // so that after login, pop() lands back here naturally).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) context.push('/login');
          });
        });
        return;
      }
      final user = data.session?.user;
      _syncShellNotificationBadge(user);
      if (user != null) _ensureProfileExists(user);
    });
    final currentUser = Supabase.instance.client.auth.currentUser;
    _syncShellNotificationBadge(currentUser);
    if (currentUser != null) _ensureProfileExists(currentUser);
  }

  Future<void> _ensureProfileExists(User user) async {
    try {
      await _profileService.ensureProfileExists(user);
    } catch (_) {}
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _shellNotificationChannel?.unsubscribe();
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
          // Switch to Feed tab so the new poll is visible, then reload.
          context.go('/home');
          feedReloadNotifier.value++;
          profileReloadNotifier.value++;
          AppToast.success(context, 'Poll published');
          final u = Supabase.instance.client.auth.currentUser;
          if (u != null) await _refreshShellUnreadBadge(u.id);
        }
      },
    );
  }

  void _onBottomNavTap(int navIndex) {
    if (navIndex == MainShell.createNavIndex) {
      unawaited(_openCreate());
      return;
    }
    VideoManager.pauseAll();
    final branchIndex = _navTobranchIndex(navIndex);

    // Navigating to the same branch taps its root (pop-to-top behaviour).
    // Navigating to a different branch preserves that branch's stack.
    if (branchIndex == widget.navigationShell.currentIndex) {
      widget.navigationShell.goBranch(branchIndex, initialLocation: true);
    } else {
      widget.navigationShell.goBranch(branchIndex);
    }

    // When navigating to the Profile tab, trigger a profile reload so newly
    // published polls appear without requiring a manual pull-to-refresh.
    if (branchIndex == 3) {
      final u = Supabase.instance.client.auth.currentUser;
      if (u != null) profileReloadNotifier.value++;
    }
    // When navigating to Notifications, refresh the unread badge.
    if (branchIndex == 2) {
      final u = Supabase.instance.client.auth.currentUser;
      if (u != null) unawaited(_refreshShellUnreadBadge(u.id));
    }
  }

  /// Circular compose badge used for the Create nav item.
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

  static const double _wideLayoutBreakpoint = 700;
  static const double _trendingRailBreakpoint = 1100;

  /// Shared icon/label data for the 5 nav items (Home, Search, Create,
  /// Notifications, Profile). Fed into both [BottomNavigationBar] and
  /// [NavigationRail] so the two layouts stay in sync.
  List<({Widget icon, Widget activeIcon, String label})> _navEntries(
    BuildContext context,
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
    final entries = _navEntries(context);
    final selectedIndex = _selectedNavIndex;

    // The StatefulNavigationShell IS the IndexedStack of branch navigators.
    final body = widget.navigationShell;

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
                  const TrendingRail(),
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
