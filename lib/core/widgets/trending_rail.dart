import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../screens/poll_detail_screen.dart';
import '../../screens/search_screen.dart';
import '../../services/feed_service.dart';
import '../../services/social_service.dart';
import '../../utils/profile_navigation.dart';
import '../../widgets/auth_guard.dart';

/// Right-hand sidebar shown on very wide (desktop web) viewports, mirroring
/// X's third column: a search box, "You might like" follow suggestions, and
/// a "Trending now" list of the top trending polls.
class TrendingRail extends StatefulWidget {
  const TrendingRail({super.key, this.reloadToken});

  /// Bump to refetch (e.g. after publishing a new poll).
  final ValueListenable<int>? reloadToken;

  static const double width = 320;

  @override
  State<TrendingRail> createState() => _TrendingRailState();
}

class _TrendingRailState extends State<TrendingRail> {
  final FeedService _feedService = FeedService();
  final SocialService _socialService = SocialService();
  late Future<List<dynamic>> _trendingFuture;
  late Future<List<Map<String, dynamic>>> _suggestedFuture;

  @override
  void initState() {
    super.initState();
    _trendingFuture = _loadTrending();
    _suggestedFuture = _loadSuggested();
    widget.reloadToken?.addListener(_reload);
  }

  @override
  void dispose() {
    widget.reloadToken?.removeListener(_reload);
    super.dispose();
  }

  void _reload() => setState(() {
    _trendingFuture = _loadTrending();
    _suggestedFuture = _loadSuggested();
  });

  Future<List<dynamic>> _loadTrending() async {
    final page = await _feedService.getTrendingFeedPage(limit: 5, offset: 0);
    return page.items;
  }

  Future<List<Map<String, dynamic>>> _loadSuggested() {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    return _socialService.getSuggestedUsers(currentUserId: currentUserId);
  }

  String _voteCountOf(dynamic poll) {
    if (poll is! Map) return '0';
    final analytics = poll['poll_analytics'];
    Map? a;
    if (analytics is Map) {
      a = analytics;
    } else if (analytics is List &&
        analytics.isNotEmpty &&
        analytics.first is Map) {
      a = analytics.first as Map;
    }
    final v = a?['votes_count'];
    final n = v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  void _openSearch(BuildContext context, {int? tabIndex}) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => SearchScreen(initialTabIndex: tabIndex),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SizedBox(
      width: TrendingRail.width,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SearchField(onTap: () => _openSearch(context)),
            const SizedBox(height: 12),
            _RailCard(
              title: 'You might like',
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _suggestedFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const _RailLoading();
                  }
                  final users = snapshot.data ?? const [];
                  if (users.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'No suggestions right now.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final user in users) _SuggestedUserTile(user: user),
                    ],
                  );
                },
              ),
              onShowMore: () => _openSearch(context, tabIndex: 1),
            ),
            const SizedBox(height: 12),
            _RailCard(
              title: 'Trending now',
              child: FutureBuilder<List<dynamic>>(
                future: _trendingFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const _RailLoading();
                  }
                  final items = snapshot.data ?? const [];
                  if (items.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Nothing trending yet — be the first to start a poll.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        _TrendingTile(
                          rank: i + 1,
                          question:
                              (items[i] as Map?)?['question']?.toString() ??
                              '',
                          votes: _voteCountOf(items[i]),
                          onTap: () {
                            final id = (items[i] as Map?)?['id']?.toString();
                            if (id == null || id.isEmpty) return;
                            Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (context) =>
                                    PollDetailScreen(pollId: id),
                              ),
                            );
                          },
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// X-style rounded search box that opens the full [SearchScreen].
class _SearchField extends StatelessWidget {
  const _SearchField({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: cs.onSurfaceVariant, size: 20),
              const SizedBox(width: 12),
              Text(
                'Search Poll Social',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rounded card shell shared by the "You might like" and "Trending now"
/// sections, mirroring X's third-column modules.
class _RailCard extends StatelessWidget {
  const _RailCard({required this.title, required this.child, this.onShowMore});

  final String title;
  final Widget child;
  final VoidCallback? onShowMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            child,
            if (onShowMore != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: InkWell(
                  onTap: onShowMore,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 8,
                    ),
                    child: Text(
                      'Show more',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RailLoading extends StatelessWidget {
  const _RailLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      ),
    );
  }
}

/// "You might like" row: avatar, name/handle, and a Follow button — mirroring
/// X's follow-suggestion tiles.
class _SuggestedUserTile extends StatefulWidget {
  const _SuggestedUserTile({required this.user});

  final Map<String, dynamic> user;

  @override
  State<_SuggestedUserTile> createState() => _SuggestedUserTileState();
}

class _SuggestedUserTileState extends State<_SuggestedUserTile> {
  final SocialService _socialService = SocialService();
  bool _following = false;
  bool _busy = false;

  Future<void> _toggleFollow() async {
    if (_busy) return;

    await AuthGuard.requireAuth(
      context,
      onAuthenticated: () async {
        final me = Supabase.instance.client.auth.currentUser?.id;
        final targetId = widget.user['id']?.toString();
        if (me == null || targetId == null || _busy) return;

        setState(() => _busy = true);
        try {
          if (_following) {
            await _socialService.unfollowUser(
              followerId: me,
              followingId: targetId,
            );
            if (!mounted) return;
            setState(() => _following = false);
          } else {
            await _socialService.followUser(
              followerId: me,
              followingId: targetId,
            );
            if (!mounted) return;
            setState(() => _following = true);
          }
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Network error. Try again.')),
          );
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final username = widget.user['username']?.toString() ?? '';
    final displayName = widget.user['display_name']?.toString();
    final name = (displayName != null && displayName.isNotEmpty)
        ? displayName
        : username;
    final avatarUrl = widget.user['avatar_url']?.toString();
    final userId = widget.user['id']?.toString() ?? '';

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openProfile(context, userId),
        hoverColor: cs.primary.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: cs.primaryContainer,
                backgroundImage:
                    avatarUrl != null && avatarUrl.isNotEmpty
                    ? NetworkImage(avatarUrl)
                    : null,
                child: avatarUrl == null || avatarUrl.isEmpty
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: TextStyle(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (username.isNotEmpty)
                      Text(
                        '@$username',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 32,
                child: OutlinedButton(
                  onPressed: _busy ? null : _toggleFollow,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    minimumSize: Size.zero,
                    shape: const StadiumBorder(),
                    foregroundColor: _following ? cs.onSurface : cs.surface,
                    backgroundColor: _following
                        ? Colors.transparent
                        : cs.onSurface,
                    side: BorderSide(
                      color: _following ? cs.outlineVariant : cs.onSurface,
                    ),
                    textStyle: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: _busy
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _following ? cs.onSurface : cs.surface,
                          ),
                        )
                      : Text(_following ? 'Following' : 'Follow'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendingTile extends StatelessWidget {
  const _TrendingTile({
    required this.rank,
    required this.question,
    required this.votes,
    required this.onTap,
  });

  final int rank;
  final String question;
  final String votes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: cs.primary.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '$rank',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      question,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$votes votes',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
