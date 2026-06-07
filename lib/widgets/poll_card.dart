import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/social_service.dart';
import '../services/vote_service.dart';
import '../utils/profile_navigation.dart';
import 'auth_guard.dart';

/// Feed card for a poll row from Supabase (`polls` select with nested relations).
class PollCard extends StatefulWidget {
  const PollCard({
    super.key,
    required this.poll,
    this.showTrendingScore = false,
    this.onPollTap,
  });

  final Map<String, dynamic> poll;
  final bool showTrendingScore;

  /// Opens poll detail when set; header + question area only (vote/like stay interactive).
  final VoidCallback? onPollTap;

  @override
  State<PollCard> createState() => _PollCardState();
}

class _PollCardState extends State<PollCard> {
  final VoteService _voteService = VoteService();
  final SocialService _socialService = SocialService();

  bool _bootstrapDone = false;
  bool _voteLoading = false;
  bool _likeLoading = false;

  String? _selectedOptionId;
  Map<String, int> _optionVotes = {};
  int _likesCount = 0;
  int _commentsCount = 0;
  int _sharesCount = 0;
  bool _liked = false;

  String get _pollId => widget.poll['id']?.toString() ?? '';

  String? get _pollAuthorId {
    final id = widget.poll['user_id']?.toString();
    if (id == null || id.isEmpty) return null;
    return id;
  }

  Map<String, dynamic>? _analyticsMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is List && raw.isNotEmpty) {
      final first = raw.first;
      if (first is Map<String, dynamic>) return first;
      if (first is Map) return Map<String, dynamic>.from(first);
    }
    return null;
  }

  Map<String, dynamic>? get _profile {
    final p = widget.poll['profiles'];
    if (p is Map<String, dynamic>) return p;
    if (p is Map) return Map<String, dynamic>.from(p);
    return null;
  }

  Map<String, dynamic>? get _analytics {
    final nested = _analyticsMap(widget.poll['poll_analytics']);
    if (nested != null) return nested;
    return null;
  }

  List<Map<String, dynamic>> get _options {
    final raw = widget.poll['poll_options'];
    if (raw is! List) return [];
    final list = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        list.add(item);
      } else if (item is Map) {
        list.add(Map<String, dynamic>.from(item));
      }
    }
    list.sort((a, b) {
      final ao = a['option_order'];
      final bo = b['option_order'];
      final ai = ao is int ? ao : int.tryParse('$ao') ?? 0;
      final bi = bo is int ? bo : int.tryParse('$bo') ?? 0;
      return ai.compareTo(bi);
    });
    return list;
  }

  bool get _hasVoted => _selectedOptionId != null;

  int get _totalVotes {
    final sum = _optionVotes.values.fold<int>(0, (a, b) => a + b);
    if (sum > 0) return sum;
    final a = _analytics;
    final vc = a?['votes_count'];
    if (vc is int) return vc;
    if (vc is num) return vc.toInt();
    return 0;
  }

  static double _percentage(int count, int total) {
    if (total <= 0) return 0;
    return (count / total) * 100;
  }

  static String _formatRelativeTime(DateTime? at) {
    if (at == null) return '';
    final now = DateTime.now();
    final diff = now.difference(at);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
  }

  DateTime? _parseCreatedAt() {
    final v = widget.poll['created_at'];
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  @override
  void initState() {
    super.initState();
    _hydrateCountsFromAnalytics();
    _bootstrap();
  }

  void _hydrateCountsFromAnalytics() {
    final a = _analytics;
    _likesCount = _readInt(a?['likes_count']);
    _commentsCount = _readInt(a?['comments_count']);
    _sharesCount = _readInt(a?['shares_count']);
  }

  int _readInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  Future<void> _bootstrap() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (_pollId.isEmpty) {
      setState(() => _bootstrapDone = true);
      return;
    }

    try {
      if (user != null) {
        final vote = await _voteService.getUserVote(
          pollId: _pollId,
          userId: user.id,
        );
        if (vote is Map && vote['option_id'] != null) {
          _selectedOptionId = vote['option_id'].toString();
        }

        final like = await _socialService.getUserLike(
          pollId: _pollId,
          userId: user.id,
        );
        _liked = like != null;
      }

      if (_hasVoted) {
        await _refreshVoteCounts();
      }
    } catch (_) {
      // Non-fatal; card still renders from analytics.
    }

    if (mounted) {
      setState(() => _bootstrapDone = true);
    }
  }

  Future<void> _refreshVoteCounts() async {
    final rows = await _voteService.getPollVotes(_pollId);
    final next = <String, int>{};
    for (final r in rows) {
      if (r is! Map) continue;
      final oid = r['option_id']?.toString();
      if (oid == null) continue;
      next[oid] = (next[oid] ?? 0) + 1;
    }
    for (final o in _options) {
      final id = o['id']?.toString();
      if (id != null) next.putIfAbsent(id, () => 0);
    }
    _optionVotes = next;
  }

  Future<void> _onVote(String optionId) async {
    if (_voteLoading || _hasVoted) return;

    await AuthGuard.requireAuth(
      context,
      onAuthenticated: () async {
        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) return;

        setState(() => _voteLoading = true);
        try {
          await _voteService.vote(
            pollId: _pollId,
            optionId: optionId,
            userId: user.id,
          );
          if (!mounted) return;
          setState(() => _selectedOptionId = optionId);
          await _refreshVoteCounts();
        } on PostgrestException catch (e) {
          final user = Supabase.instance.client.auth.currentUser;
          if (_isDuplicateVoteError(e) && user != null) {
            final vote = await _voteService.getUserVote(
              pollId: _pollId,
              userId: user.id,
            );
            if (!mounted) return;
            if (vote is Map && vote['option_id'] != null) {
              setState(() => _selectedOptionId = vote['option_id'].toString());
            }
            await _refreshVoteCounts();
            _showMessage('You already voted on this poll.');
          } else {
            _showMessage(_friendlyError(e.message));
          }
        } catch (_) {
          _showMessage('Could not submit vote. Check your connection.');
        } finally {
          if (mounted) setState(() => _voteLoading = false);
        }
      },
    );
  }

  bool _isDuplicateVoteError(PostgrestException e) {
    final code = e.code;
    final msg = e.message.toLowerCase();
    return code == '23505' ||
        msg.contains('duplicate') ||
        msg.contains('unique') ||
        msg.contains('already');
  }

  Future<void> _toggleLike() async {
    if (_likeLoading) return;

    await AuthGuard.requireAuth(
      context,
      onAuthenticated: () async {
        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) return;

        setState(() => _likeLoading = true);
        final nextLiked = !_liked;
        try {
          if (nextLiked) {
            await _socialService.likePoll(pollId: _pollId, userId: user.id);
          } else {
            await _socialService.unlikePoll(pollId: _pollId, userId: user.id);
          }
          if (!mounted) return;
          setState(() {
            _liked = nextLiked;
            _likesCount += nextLiked ? 1 : -1;
            if (_likesCount < 0) _likesCount = 0;
          });
        } on PostgrestException catch (e) {
          if (_isDuplicateVoteError(e)) {
            if (!mounted) return;
            setState(() {
              _liked = true;
            });
            _showMessage('Already liked.');
          } else {
            _showMessage(_friendlyError(e.message));
          }
        } catch (_) {
          _showMessage('Could not update like. Check your connection.');
        } finally {
          if (mounted) setState(() => _likeLoading = false);
        }
      },
    );
  }

  Future<void> _onCommentTap() async {
    await AuthGuard.requireAuth(
      context,
      onAuthenticated: () async {
        widget.onPollTap?.call();
      },
    );
  }

  String _friendlyError(String message) {
    final m = message.toLowerCase();
    if (m.contains('jwt') || m.contains('session')) {
      return 'Session expired. Sign in again.';
    }
    return 'Something went wrong. Try again.';
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  /// Normalizes negative backend scores; shows "Trending" when zero/invalid after clamp.
  static String formatTrendingScore(dynamic v) {
    num? n;
    if (v is num) {
      n = v;
    } else {
      n = num.tryParse(v?.toString() ?? '');
    }
    if (n == null) return 'Trending';
    final normalized = n.toDouble() < 0 ? 0.0 : n.toDouble();
    if (normalized == 0) return 'Trending';
    return normalized == normalized.roundToDouble()
        ? normalized.round().toString()
        : normalized.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (!_bootstrapDone) {
      return _PollCardChrome(
        child: const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final username =
        _profile?['username']?.toString() ?? widget.poll['username']?.toString() ?? 'Unknown';
    final avatarUrl = _profile?['avatar_url']?.toString();
    final created = _formatRelativeTime(_parseCreatedAt());
    final showTrending =
        widget.showTrendingScore && widget.poll['trending_score'] != null;

    final authorId = _pollAuthorId;
    final pollAuthorHeader = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: (avatarUrl != null && avatarUrl.isNotEmpty)
              ? cs.surfaceContainerHighest
              : cs.primaryContainer,
          backgroundImage:
              avatarUrl != null && avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
          child: avatarUrl == null || avatarUrl.isEmpty
              ? Text(
                  username.isNotEmpty ? username[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                username,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (created.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  created,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );

    final tappableAuthorHeader = authorId != null && authorId.isNotEmpty
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => openProfile(context, authorId),
            child: pollAuthorHeader,
          )
        : pollAuthorHeader;

    final questionText = Text(
      widget.poll['question']?.toString() ?? '',
      style: theme.textTheme.titleLarge?.copyWith(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        height: 1.28,
        letterSpacing: -0.3,
      ),
    );

    final questionBlock = widget.onPollTap != null
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPollTap,
            child: questionText,
          )
        : questionText;

    final pollIntro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: tappableAuthorHeader),
            if (showTrending) const SizedBox(width: 72),
          ],
        ),
        const SizedBox(height: 16),
        questionBlock,
        const SizedBox(height: 14),
      ],
    );

    return _PollCardChrome(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                pollIntro,
                if (_voteLoading) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      backgroundColor: cs.surfaceContainerHighest,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_options.isEmpty)
                  Text(
                    'No options available.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  )
                else
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 380),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.04),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: !_hasVoted
                        ? Column(
                            key: const ValueKey<String>('poll_choices'),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final o in _options)
                                PollOptionButton(
                                  label: o['option_text']?.toString() ?? '',
                                  enabled: !_voteLoading,
                                  onPressed: () => _onVote(o['id']?.toString() ?? ''),
                                ),
                            ],
                          )
                        : Column(
                            key: ValueKey<String>('poll_results_$_selectedOptionId'),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final o in _options)
                                PollResultBar(
                                  label: o['option_text']?.toString() ?? '',
                                  optionKey: o['id']?.toString() ?? '',
                                  count: _optionVotes[o['id']?.toString() ?? ''] ?? 0,
                                  totalVotes: _totalVotes,
                                  selected: o['id']?.toString() == _selectedOptionId,
                                  percentage: _percentage(
                                    _optionVotes[o['id']?.toString() ?? ''] ?? 0,
                                    _totalVotes,
                                  ),
                                ),
                            ],
                          ),
                  ),
                const SizedBox(height: 16),
                EngagementRow(
                  votesCount: _totalVotes,
                  likesCount: _likesCount,
                  commentsCount: _commentsCount,
                  sharesCount: _sharesCount,
                  liked: _liked,
                  likeLoading: _likeLoading,
                  onLikeTap: _toggleLike,
                  onCommentTap: _onCommentTap,
                ),
              ],
            ),
            if (showTrending)
              Positioned(
                top: 0,
                right: 0,
                child: TrendingScoreBadge(score: formatTrendingScore(widget.poll['trending_score'])),
              ),
          ],
        ),
      ),
    );
  }
}

/// Card chrome shared by loading and loaded states (elevation, radius, contrast).
class _PollCardChrome extends StatelessWidget {
  const _PollCardChrome({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // X-style timeline row: borderless, full-bleed, separated by a hairline.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: child,
    );
  }
}

/// Small pill badge for trending score (top-right).
class TrendingScoreBadge extends StatelessWidget {
  const TrendingScoreBadge({super.key, required this.score});

  final String score;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '🔥',
              style: TextStyle(fontSize: Theme.of(context).textTheme.labelMedium?.fontSize ?? 13),
            ),
            const SizedBox(width: 4),
            Text(
              score,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-width choice row before voting with ink feedback.
class PollOptionButton extends StatelessWidget {
  const PollOptionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: isLight(context) ? 0.65 : 0.55),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          splashColor: cs.primary.withValues(alpha: 0.14),
          highlightColor: cs.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                  height: 1.25,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static bool isLight(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light;
}

/// Result row with animated bar, selection tint, and checkmark.
class PollResultBar extends StatelessWidget {
  const PollResultBar({
    super.key,
    required this.label,
    required this.optionKey,
    required this.count,
    required this.totalVotes,
    required this.selected,
    required this.percentage,
  });

  final String label;
  final String optionKey;
  final int count;
  final int totalVotes;
  final bool selected;
  final double percentage;

  double get _fraction => totalVotes > 0 ? count / totalVotes : 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: 0.10)
              : cs.surfaceContainerHighest.withValues(alpha: PollOptionButton.isLight(context) ? 0.45 : 0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? cs.primary.withValues(alpha: 0.65) : cs.outlineVariant.withValues(alpha: 0.35),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (selected) ...[
                  Icon(Icons.check_circle_rounded, color: cs.primary, size: 22),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? cs.primary : cs.onSurface.withValues(alpha: 0.85),
                      height: 1.25,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${percentage.round()}%',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: selected ? cs.primary : cs.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TweenAnimationBuilder<double>(
              key: ValueKey<String>('bar_$optionKey${totalVotes}_$count'),
              duration: const Duration(milliseconds: 520),
              curve: Curves.easeOutCubic,
              tween: Tween<double>(begin: 0, end: _fraction),
              builder: (context, animValue, _) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: animValue,
                    minHeight: 7,
                    backgroundColor: cs.surfaceContainerHighest,
                    color: selected ? cs.primary : cs.outline.withValues(alpha: 0.55),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Icons + counts with ink wells; like uses filled vs outlined heart.
class EngagementRow extends StatelessWidget {
  const EngagementRow({
    super.key,
    required this.votesCount,
    required this.likesCount,
    required this.commentsCount,
    required this.sharesCount,
    required this.liked,
    required this.likeLoading,
    required this.onLikeTap,
    this.onCommentTap,
  });

  final int votesCount;
  final int likesCount;
  final int commentsCount;
  final int sharesCount;
  final bool liked;
  final bool likeLoading;
  final VoidCallback onLikeTap;
  final VoidCallback? onCommentTap;

  static const double _iconSize = 20;

  /// X-style action accents: reply=blue, like=pink, share/repost=green.
  static const Color _replyColor = Color(0xFF1D9BF0);
  static const Color _likeColor = Color(0xFFF91880);
  static const Color _shareColor = Color(0xFF00BA7C);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Material(
      color: Colors.transparent,
      child: Row(
        children: [
          _EngagementInk(
            icon: Icons.how_to_vote_outlined,
            count: votesCount,
            labelStyle: labelStyle,
            hoverColor: _replyColor,
            onTap: () {},
          ),
          const SizedBox(width: 4),
          _EngagementInk(
            icon: Icons.chat_bubble_outline_rounded,
            count: commentsCount,
            labelStyle: labelStyle,
            hoverColor: _replyColor,
            onTap: onCommentTap ?? () {},
          ),
          const SizedBox(width: 4),
          _EngagementInk(
            icon: Icons.ios_share_rounded,
            count: sharesCount,
            labelStyle: labelStyle,
            hoverColor: _shareColor,
            onTap: () {},
          ),
          const SizedBox(width: 4),
          _EngagementInk(
            icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            iconColor: liked ? _likeColor : cs.onSurfaceVariant,
            labelColor: liked ? _likeColor : null,
            count: likesCount,
            labelStyle: labelStyle,
            hoverColor: _likeColor,
            loading: likeLoading,
            onTap: likeLoading ? null : onLikeTap,
          ),
        ],
      ),
    );
  }
}

class _EngagementInk extends StatelessWidget {
  const _EngagementInk({
    required this.icon,
    required this.count,
    required this.labelStyle,
    required this.onTap,
    required this.hoverColor,
    this.iconColor,
    this.labelColor,
    this.loading = false,
  });

  final IconData icon;
  final int count;
  final TextStyle? labelStyle;
  final VoidCallback? onTap;
  final Color hoverColor;
  final Color? iconColor;
  final Color? labelColor;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Expanded(
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          splashColor: hoverColor.withValues(alpha: 0.14),
          highlightColor: hoverColor.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  SizedBox(
                    width: EngagementRow._iconSize,
                    height: EngagementRow._iconSize,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: hoverColor,
                    ),
                  )
                else
                  Icon(
                    icon,
                    size: EngagementRow._iconSize,
                    color: iconColor ?? cs.onSurfaceVariant,
                  ),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    '$count',
                    style: labelColor != null ? labelStyle?.copyWith(color: labelColor) : labelStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
