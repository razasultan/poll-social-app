import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/notification_service.dart';
import '../widgets/auth_guard.dart';
import 'auth/login_screen.dart';
import 'auth/signup_screen.dart';
import 'create_poll_screen.dart';
import 'feed_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

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

  final ValueNotifier<int> _feedReloadToken = ValueNotifier<int>(0);
  final ValueNotifier<int> _profileReloadToken = ValueNotifier<int>(0);

  late final NotificationService _notificationService;
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
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) {
        final user = data.session?.user;
        _syncShellNotificationBadge(user);
        final itemCount = user == null ? 4 : 5;
        if (_selectedIndex >= itemCount && mounted) {
          setState(() => _selectedIndex = 0);
        }
      },
    );
    _syncShellNotificationBadge(Supabase.instance.client.auth.currentUser);
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

    final channel = Supabase.instance.client.channel('shell-nav-notifications-${user.id}');
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
        final created = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (context) => const CreatePollScreen(),
          ),
        );
        if (!mounted) return;
        if (created == true) {
          setState(() => _selectedIndex = 0);
          _feedReloadToken.value++;
          _profileReloadToken.value++;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Poll published')),
          );
          final u = Supabase.instance.client.auth.currentUser;
          if (u != null) await _refreshShellUnreadBadge(u.id);
        }
      },
    );
  }

  void _onBottomNavTap(int index) {
    if (index == MainShell.createNavIndex) {
      unawaited(_openCreate());
      return;
    }
    setState(() => _selectedIndex = index);
    final u = Supabase.instance.client.auth.currentUser;
    if (index == 3 && u != null) {
      unawaited(_refreshShellUnreadBadge(u.id));
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
      child: Icon(active ? Icons.notifications_rounded : Icons.notifications_outlined),
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
            Icon(Icons.lock_outline_rounded, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              message,
              style: theme.textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
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

    final stackChildren = <Widget>[
      FeedScreen(feedReloadToken: _feedReloadToken),
      const SearchScreen(),
      if (!isGuest) const NotificationsScreen(),
      _buildProfileTab(user),
    ];

    final entries = _navEntries(context, isGuest);
    final selectedIndex = _selectedIndex < entries.length ? _selectedIndex : 0;

    final body = IndexedStack(
      index: _stackIndex,
      sizing: StackFit.expand,
      children: stackChildren,
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
                    for (final entry in entries)
                      NavigationRailDestination(
                        icon: entry.icon,
                        selectedIcon: entry.activeIcon,
                        label: Text(entry.label),
                      ),
                  ],
                ),
                VerticalDivider(width: 1, color: cs.outlineVariant),
                Expanded(child: body),
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
              for (final entry in entries)
                BottomNavigationBarItem(
                  icon: entry.icon,
                  activeIcon: entry.activeIcon,
                  label: entry.label,
                ),
            ],
          ),
        );
      },
    );
  }
}
