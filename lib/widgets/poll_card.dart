import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../services/social_service.dart';
import '../services/vote_service.dart';
import '../utils/profile_navigation.dart';
import 'auth_guard.dart';
import 'linkified_text.dart';
import 'poll_result_chart.dart' show buildPollChartEntries;
import 'shareable_poll_result_card.dart';

/// Percentage of [total] votes that [count] represents, clamped to `0` when
/// there are no votes yet. Exposed for testing.
double pollResultPercentage(int count, int total) {
  if (total <= 0) return 0;
  return (count / total) * 100;
}

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
  bool _sharingResults = false;

  /// Boundary the off-screen [ShareablePollResultCard] is captured from.
  final GlobalKey _shareCardKey = GlobalKey();

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

  DateTime? _parseCreatedAt() => _parseTimestamp(widget.poll['created_at']);

  DateTime? _parseExpiresAt() => _parseTimestamp(widget.poll['expires_at']);

  DateTime? _parseTimestamp(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  /// Social "context" written by the author, shown above the poll question.
  String? get _postText {
    final v = widget.poll['description']?.toString().trim();
    if (v == null || v.isEmpty) return null;
    return v;
  }

  String get _username =>
      _profile?['username']?.toString() ??
      widget.poll['username']?.toString() ??
      'unknown';

  /// Falls back to the username when no display name is set.
  String get _displayName {
    final raw = _profile?['display_name']?.toString().trim();
    if (raw != null && raw.isNotEmpty) return raw;
    return _username;
  }

  bool get _isExpired {
    final at = _parseExpiresAt();
    if (at == null) return false;
    return DateTime.now().isAfter(at);
  }

  /// Short "ends in Xh" / "Poll ended" label, or null when the poll has no expiry.
  String? get _expiryStatusLabel {
    final at = _parseExpiresAt();
    if (at == null) return null;
    if (_isExpired) return 'Poll ended';
    final diff = at.difference(DateTime.now());
    if (diff.inMinutes < 60) return 'Ends in ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'Ends in ${diff.inHours}h';
    return 'Ends in ${diff.inDays}d';
  }

  /// First attached poll-level media item (image/video), if any.
  Map<String, dynamic>? get _mainMedia {
    final raw = widget.poll['poll_media'];
    if (raw is! List || raw.isEmpty) return null;
    final first = raw.first;
    if (first is Map<String, dynamic>) return first;
    if (first is Map) return Map<String, dynamic>.from(first);
    return null;
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

      if (_hasVoted || _isExpired) {
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

  /// Whether per-option vote counts are available to render into a shareable
  /// results image — mirrors the feed's reveal rule (voted, or poll ended).
  bool get _resultsVisible => _hasVoted || _isExpired;

  Future<void> _shareResults() async {
    if (_pollId.isEmpty || _sharingResults) return;
    if (!_resultsVisible) {
      _showMessage('Vote (or wait for the poll to end) to share its results.');
      return;
    }

    setState(() => _sharingResults = true);
    try {
      // Let the off-screen ShareablePollResultCard lay out and paint first.
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _shareCardKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        _showMessage('Could not generate the share image. Try again.');
        return;
      }

      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        _showMessage('Could not generate the share image. Try again.');
        return;
      }

      final file = XFile.fromData(
        byteData.buffer.asUint8List(),
        mimeType: 'image/png',
        name: 'poll-result.png',
      );
      await Share.shareXFiles([file], text: _shareText());
    } catch (_) {
      _showMessage('Could not share the results image. Try again.');
    } finally {
      if (mounted) setState(() => _sharingResults = false);
    }
  }

  /// Public share link for this poll (`$publicShareBaseUrl/p/:shareSlug`),
  /// or `null` when the poll has no `share_slug` (e.g. legacy rows).
  String? get _shareUrl {
    final slug = widget.poll['share_slug']?.toString().trim();
    if (slug == null || slug.isEmpty) return null;
    return '${AppConfig.publicShareBaseUrl}/p/$slug';
  }

  String _shareText() {
    final question = widget.poll['question']?.toString().trim();
    final base = (question == null || question.isEmpty)
        ? 'Check out the results of this poll on Poll Social!'
        : '"$question" — see the results on Poll Social!';
    final url = _shareUrl;
    return url == null ? base : '$base\n$url';
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
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(text)));
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

    final username = _username;
    final displayName = _displayName;
    final avatarUrl = _profile?['avatar_url']?.toString();
    final created = _formatRelativeTime(_parseCreatedAt());
    final showTrending =
        widget.showTrendingScore && widget.poll['trending_score'] != null;
    final showResults = _hasVoted || _isExpired;
    final expiryLabel = _expiryStatusLabel;
    final postText = _postText;
    final mainMedia = _mainMedia;

    final authorId = _pollAuthorId;

    // X-style header: avatar + "Display Name @username · time" on one line.
    final avatar = CircleAvatar(
      radius: 20,
      backgroundColor: (avatarUrl != null && avatarUrl.isNotEmpty)
          ? cs.surfaceContainerHighest
          : cs.primaryContainer,
      backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
          ? NetworkImage(avatarUrl)
          : null,
      child: avatarUrl == null || avatarUrl.isEmpty
          ? Text(
              displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
              style: TextStyle(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            )
          : null,
    );

    final metaParts = <String>['@$username', if (created.isNotEmpty) created];

    final headerRow = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: authorId != null && authorId.isNotEmpty
              ? () => openProfile(context, authorId)
              : null,
          child: avatar,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: authorId != null && authorId.isNotEmpty
                ? () => openProfile(context, authorId)
                : null,
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  displayName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  metaParts.join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showTrending) const SizedBox(width: 72),
      ],
    );

    final questionText = Text(
      widget.poll['question']?.toString() ?? '',
      style: theme.textTheme.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        height: 1.3,
        letterSpacing: -0.2,
      ),
    );

    final questionBlock = widget.onPollTap != null
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPollTap,
            child: questionText,
          )
        : questionText;

    return _PollCardChrome(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                headerRow,
                const SizedBox(height: 10),
                if (postText != null) ...[
                  LinkifiedText(
                    postText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.32,
                      color: cs.onSurface.withValues(alpha: 0.92),
                    ),
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                ],
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cs.primary.withValues(alpha: 0.32)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      questionBlock,
                      if (mainMedia != null) ...[
                        const SizedBox(height: 10),
                        PollMediaPreview(
                          mediaUrl: mainMedia['media_url']?.toString(),
                          mediaType: mainMedia['media_type']?.toString(),
                        ),
                      ],
                      const SizedBox(height: 12),
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
                          child: !showResults
                              ? Column(
                                  key: const ValueKey<String>('poll_choices'),
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    for (final o in _options)
                                      PollOptionButton(
                                        label:
                                            o['option_text']?.toString() ?? '',
                                        mediaUrl: o['media_url']?.toString(),
                                        mediaType: o['media_type']?.toString(),
                                        enabled: !_voteLoading,
                                        onPressed: () =>
                                            _onVote(o['id']?.toString() ?? ''),
                                      ),
                                  ],
                                )
                              : Column(
                                  key: ValueKey<String>(
                                    'poll_results_$_selectedOptionId',
                                  ),
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    for (final o in _options)
                                      PollResultBar(
                                        label:
                                            o['option_text']?.toString() ?? '',
                                        optionKey: o['id']?.toString() ?? '',
                                        mediaUrl: o['media_url']?.toString(),
                                        mediaType: o['media_type']?.toString(),
                                        count:
                                            _optionVotes[o['id']?.toString() ??
                                                ''] ??
                                            0,
                                        totalVotes: _totalVotes,
                                        selected:
                                            o['id']?.toString() ==
                                            _selectedOptionId,
                                        percentage: pollResultPercentage(
                                          _optionVotes[o['id']?.toString() ??
                                                  ''] ??
                                              0,
                                          _totalVotes,
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                      if (showResults || expiryLabel != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          [
                            if (showResults) '$_totalVotes votes',
                            ?expiryLabel,
                          ].join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                EngagementRow(
                  votesCount: _totalVotes,
                  likesCount: _likesCount,
                  commentsCount: _commentsCount,
                  sharesCount: _sharesCount,
                  liked: _liked,
                  likeLoading: _likeLoading,
                  shareLoading: _sharingResults,
                  onLikeTap: _toggleLike,
                  onCommentTap: _onCommentTap,
                  onShareTap: _shareResults,
                ),
              ],
            ),
            // Off-screen capture target for the "share results" action — kept
            // mounted/painted (so RepaintBoundary.toImage works) but positioned
            // far outside the visible viewport.
            if (showResults)
              Positioned(
                left: -10000,
                top: 0,
                child: RepaintBoundary(
                  key: _shareCardKey,
                  child: ShareablePollResultCard(
                    question: widget.poll['question']?.toString() ?? '',
                    postText: postText,
                    authorName: displayName,
                    shareUrl: _shareUrl,
                    totalVotes: _totalVotes,
                    entries: buildPollChartEntries(
                      options: _options,
                      voteCounts: _optionVotes,
                      totalVotes: _totalVotes,
                      selectedOptionId: _selectedOptionId,
                    ),
                  ),
                ),
              ),
            if (showTrending)
              Positioned(
                top: 0,
                right: 0,
                child: TrendingScoreBadge(
                  score: formatTrendingScore(widget.poll['trending_score']),
                ),
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
              style: TextStyle(
                fontSize:
                    Theme.of(context).textTheme.labelMedium?.fontSize ?? 13,
              ),
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
    this.mediaUrl,
    this.mediaType,
  });

  final String label;
  final VoidCallback onPressed;
  final bool enabled;
  final String? mediaUrl;
  final String? mediaType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          splashColor: cs.primary.withValues(alpha: 0.12),
          highlightColor: cs.primary.withValues(alpha: 0.06),
          hoverColor: cs.primary.withValues(alpha: 0.05),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            child: Row(
              children: [
                if (mediaUrl != null && mediaUrl!.isNotEmpty) ...[
                  OptionMediaThumbnail(
                    mediaUrl: mediaUrl,
                    mediaType: mediaType,
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static bool isLight(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light;
}

/// Slim X-style result row: the option's share of the vote fills the pill as
/// a tinted bar behind the label, with the percentage right-aligned — no
/// separate progress track, no heavy borders. A small dot marks the option
/// the viewer picked, kept subtle rather than a bordered highlight box.
class PollResultBar extends StatelessWidget {
  const PollResultBar({
    super.key,
    required this.label,
    required this.optionKey,
    required this.count,
    required this.totalVotes,
    required this.selected,
    required this.percentage,
    this.mediaUrl,
    this.mediaType,
  });

  final String label;
  final String optionKey;
  final int count;
  final int totalVotes;
  final bool selected;
  final double percentage;
  final String? mediaUrl;
  final String? mediaType;

  double get _fraction => totalVotes > 0 ? count / totalVotes : 0;

  static const double _height = 34;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final trackColor = cs.surfaceContainerHighest.withValues(
      alpha: PollOptionButton.isLight(context) ? 0.5 : 0.4,
    );
    final fillColor = selected
        ? cs.primary.withValues(alpha: 0.20)
        : cs.onSurfaceVariant.withValues(alpha: 0.16);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: _height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: trackColor),
              Align(
                alignment: Alignment.centerLeft,
                child: TweenAnimationBuilder<double>(
                  key: ValueKey<String>('bar_$optionKey${totalVotes}_$count'),
                  duration: const Duration(milliseconds: 480),
                  curve: Curves.easeOutCubic,
                  tween: Tween<double>(begin: 0, end: _fraction.clamp(0, 1)),
                  builder: (context, animValue, _) {
                    return FractionallySizedBox(
                      widthFactor: animValue,
                      heightFactor: 1,
                      child: ColoredBox(color: fillColor),
                    );
                  },
                ),
              ),
              if (selected)
                Positioned(
                  key: const ValueKey<String>('result_selected_indicator'),
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 3,
                  child: ColoredBox(color: cs.primary),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    if (mediaUrl != null && mediaUrl!.isNotEmpty) ...[
                      OptionMediaThumbnail(
                        mediaUrl: mediaUrl,
                        mediaType: mediaType,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: cs.onSurface,
                          height: 1.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${percentage.round()}%',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: selected ? cs.primary : cs.onSurfaceVariant,
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
    this.onShareTap,
    this.shareLoading = false,
  });

  final int votesCount;
  final int likesCount;
  final int commentsCount;
  final int sharesCount;
  final bool liked;
  final bool likeLoading;
  final VoidCallback onLikeTap;
  final VoidCallback? onCommentTap;
  final VoidCallback? onShareTap;
  final bool shareLoading;

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
            loading: shareLoading,
            onTap: shareLoading ? null : (onShareTap ?? () {}),
          ),
          const SizedBox(width: 4),
          _EngagementInk(
            icon: liked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
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
          hoverColor: hoverColor.withValues(alpha: 0.08),
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
                    style: labelColor != null
                        ? labelStyle?.copyWith(color: labelColor)
                        : labelStyle,
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

/// Compact (40x40) rounded thumbnail for media attached to a single poll option.
/// Videos show a play glyph over the thumbnail since the feed never autoplays.
class OptionMediaThumbnail extends StatelessWidget {
  const OptionMediaThumbnail({
    super.key,
    required this.mediaUrl,
    this.mediaType,
  });

  final String? mediaUrl;
  final String? mediaType;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = mediaUrl;
    final isVideo = mediaType == 'video';

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url != null && url.isNotEmpty)
              Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) =>
                    ColoredBox(color: cs.surfaceContainerHighest),
              )
            else
              ColoredBox(color: cs.surfaceContainerHighest),
            if (isVideo)
              ColoredBox(
                color: Colors.black.withValues(alpha: 0.28),
                child: const Center(
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Lightweight 16:9 preview for the poll's main attached image/video.
/// Deliberately avoids inline video playback to keep the feed scroll-light;
/// videos show a thumbnail with a play glyph and open full-size on tap-through.
class PollMediaPreview extends StatelessWidget {
  const PollMediaPreview({super.key, required this.mediaUrl, this.mediaType});

  final String? mediaUrl;
  final String? mediaType;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final url = mediaUrl;
    final isVideo = mediaType == 'video';

    if (url == null || url.isEmpty) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              url,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return ColoredBox(
                  color: cs.surfaceContainerHighest,
                  child: const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  ),
                );
              },
              errorBuilder: (context, error, stack) => ColoredBox(
                color: cs.surfaceContainerHighest,
                child: Icon(
                  Icons.image_not_supported_outlined,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            if (isVideo)
              ColoredBox(
                color: Colors.black.withValues(alpha: 0.32),
                child: const Center(
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    color: Colors.white,
                    size: 52,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
