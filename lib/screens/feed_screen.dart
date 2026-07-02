import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/media/video_manager.dart';
import '../core/navigation/branch_utils.dart';
import '../core/state/feed_notifier.dart';
import '../core/widgets/timeline_column.dart';
import '../services/feed_service.dart';
import '../services/notification_service.dart';
import '../services/seen_polls_store.dart';
import '../widgets/app_toast.dart';
import '../widgets/auth_guard.dart';
import '../widgets/create_poll_modal.dart';
import '../widgets/paged_poll_feed.dart';

/// Home poll feed with For You / Latest / Trending tabs (paged).
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  static void openDebugRoute(BuildContext context) {
    context.push('/debug');
  }

  static const int _pageSize = 12;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  late final FeedService _feedService;
  late final NotificationService _notificationService;
  late bool _isGuest;

  int _unreadNotificationCount = 0;
  RealtimeChannel? _notificationBadgeChannel;
  StreamSubscription<AuthState>? _authSubscription;

  int get _tabCount => _isGuest ? 2 : 3;

  @override
  void initState() {
    super.initState();
    _feedService = FeedService();
    _notificationService = NotificationService();
    _isGuest = Supabase.instance.client.auth.currentUser == null;
    _tabController = TabController(length: _tabCount, vsync: this);
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) {
      final user = data.session?.user;
      _syncNotificationBadge(user);
      final isGuestNow = user == null;
      if (isGuestNow != _isGuest && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final oldController = _tabController;
          setState(() {
            _isGuest = isGuestNow;
            _tabController = TabController(length: _tabCount, vsync: this);
          });
          oldController.dispose();
        });
      }
      feedReloadNotifier.value++;
    });
    _syncNotificationBadge(Supabase.instance.client.auth.currentUser);
    unawaited(SeenPollsStore.instance.seenIds());
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _notificationBadgeChannel?.unsubscribe();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshUnreadBadge(String userId) async {
    final count = await _notificationService.countUnreadNotifications(userId);
    if (mounted) setState(() => _unreadNotificationCount = count);
  }

  void _syncNotificationBadge(User? user) {
    _notificationBadgeChannel?.unsubscribe();
    _notificationBadgeChannel = null;

    if (user == null) {
      if (mounted) setState(() => _unreadNotificationCount = 0);
      return;
    }

    unawaited(_refreshUnreadBadge(user.id));

    final filter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'user_id',
      value: user.id,
    );

    final channel = Supabase.instance.client.channel(
      'feed-notifications-${user.id}',
    );
    channel
        .onPostgresChanges(
          schema: 'public',
          table: 'notifications',
          event: PostgresChangeEvent.all,
          filter: filter,
          callback: (_) {
            unawaited(_refreshUnreadBadge(user.id));
          },
        )
        .subscribe();
    _notificationBadgeChannel = channel;
  }

  Widget _buildForYouTab() {
    final user = Supabase.instance.client.auth.currentUser;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (user == null) {
      return RefreshIndicator(
        onRefresh: () async => feedReloadNotifier.value++,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Login to see personalized feed',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return PagedPollFeed(
      pageStorageKey: 'feed_for_you',
      reloadListenable: feedReloadNotifier,
      emptyMessage: 'No polls yet',
      trendingScoreWhenPresent: true,
      fetch: (cursor) async {
        final seen = await SeenPollsStore.instance.seenIds();
        final exclude = {...seen, ...cursor.loadedPollIds};
        return _feedService.getForYouFeedPage(
          user.id,
          limit: FeedScreen._pageSize,
          excludePollIds: exclude,
        );
      },
      onPollIdsBecameVisible: (ids) =>
          SeenPollsStore.instance.markPollsSeen(ids),
    );
  }

  Widget _buildLatestTab() {
    return PagedPollFeed(
      pageStorageKey: 'feed_latest',
      reloadListenable: feedReloadNotifier,
      emptyMessage: 'No polls yet',
      fetch: (cursor) => _feedService.getLatestFeedPage(
        limit: FeedScreen._pageSize,
        offset: cursor.offset,
      ),
    );
  }

  Widget _buildTrendingTab() {
    return PagedPollFeed(
      pageStorageKey: 'feed_trending',
      reloadListenable: feedReloadNotifier,
      emptyMessage: 'No polls yet',
      isTrendingTab: true,
      fetch: (cursor) => _feedService.getTrendingFeedPage(
        limit: FeedScreen._pageSize,
        offset: cursor.offset,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await AuthGuard.requireAuth(
            context,
            onAuthenticated: () async {
              final created = await showCreatePollModal(context);
              if (!context.mounted) return;
              if (created == true) {
                AppToast.success(context, 'Poll published');
                feedReloadNotifier.value++;
              }
            },
          );
        },
        child: const Icon(Icons.add),
      ),
      appBar: AppBar(
        actions: [
          Badge(
            isLabelVisible: _unreadNotificationCount > 0,
            label: Text(
              _unreadNotificationCount > 99
                  ? '99+'
                  : '$_unreadNotificationCount',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
            ),
            child: IconButton(
              tooltip: 'Notifications',
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () async {
                await AuthGuard.requireAuth(
                  context,
                  onAuthenticated: () async {
                    context.go('/notifications');
                    final u = Supabase.instance.client.auth.currentUser;
                    if (u != null && context.mounted) {
                      await _refreshUnreadBadge(u.id);
                    }
                  },
                );
              },
            ),
          ),
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => context.go('/search'),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () =>
                context.push('${branchPrefixFor(context)}/settings'),
          ),
        ],
        title: Row(
          children: [
            GestureDetector(
              onLongPress: () => FeedScreen.openDebugRoute(context),
              child: const Padding(
                padding: EdgeInsets.only(right: 10),
                child: Icon(Icons.how_to_vote_outlined),
              ),
            ),
            const Text('Poll Feed'),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          onTap: (_) => VideoManager.pauseAll(),
          tabs: _isGuest
              ? const [Tab(text: 'Latest'), Tab(text: 'Trending')]
              : const [
                  Tab(text: 'For You'),
                  Tab(text: 'Latest'),
                  Tab(text: 'Trending'),
                ],
        ),
      ),
      body: TimelineColumn(
        child: TabBarView(
          controller: _tabController,
          children: _isGuest
              ? [_buildLatestTab(), _buildTrendingTab()]
              : [_buildForYouTab(), _buildLatestTab(), _buildTrendingTab()],
        ),
      ),
    );
  }
}
