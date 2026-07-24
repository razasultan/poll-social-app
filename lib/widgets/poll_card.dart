import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../core/constants/branding.dart';
import '../services/anon_vote_session_store.dart';
import '../services/poll_service.dart';
import '../services/social_service.dart';
import '../services/vote_service.dart';
import '../utils/profile_navigation.dart';
import 'app_toast.dart';
import 'auth_guard.dart';
import 'linkified_text.dart';
import 'poll_result_chart.dart' show buildPollChartEntries;
import 'shareable_poll_result_card.dart';
import 'video_preview.dart';

/// Percentage of [total] votes that [count] represents, clamped to `0` when
/// there are no votes yet. Exposed for testing.
double pollResultPercentage(int count, int total) {
  if (total <= 0) return 0;
  return (count / total) * 100;
}

/// Whether an unauthenticated visitor can vote on [poll] without logging in.
/// Only `public` polls allow this - followers-only/private polls still
/// require an account. Exposed for testing.
bool pollAllowsAnonymousVote(Map<String, dynamic> poll) {
  return poll['visibility']?.toString() == 'public';
}

/// Feed card for a poll row from Supabase (`polls` select with nested relations).
class PollCard extends StatefulWidget {
  const PollCard({
    super.key,
    required this.poll,
    this.showTrendingScore = false,
    this.onPollTap,
    this.onVoted,
  });

  final Map<String, dynamic> poll;
  final bool showTrendingScore;

  /// Opens poll detail when set; header + question area only (vote/like stay interactive).
  final VoidCallback? onPollTap;

  /// Called after a vote is successfully recorded (auth or anon). Used by
  /// [PollDetailScreen] to reload the chart without a full-screen refresh.
  final VoidCallback? onVoted;

  @override
  State<PollCard> createState() => _PollCardState();
}

class _PollCardState extends State<PollCard> {
  final VoteService _voteService = VoteService();
  final SocialService _socialService = SocialService();
  final PollService _pollService = PollService();

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
      } else if (_allowsAnonymousVote) {
        final anonSessionId = await AnonVoteSessionStore.instance.read();
        if (anonSessionId != null) {
          final vote = await _voteService.getAnonVote(
            pollId: _pollId,
            anonSessionId: anonSessionId,
          );
          if (vote is Map && vote['option_id'] != null) {
            _selectedOptionId = vote['option_id'].toString();
          }
        }
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
    if (mounted) setState(() => _optionVotes = next);
  }

  /// Visitors with no account can still vote on public polls - the
  /// vote-anonymous Edge Function handles dedup server-side since there's no
  /// RLS path for anon INSERTs into `votes`. Followers-only/private polls
  /// still require login (handled by [AuthGuard] below).
  bool get _allowsAnonymousVote => pollAllowsAnonymousVote(widget.poll);

  Future<void> _onVote(String optionId) async {
    if (_voteLoading || _hasVoted) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null && _allowsAnonymousVote) {
      await _voteAsGuest(optionId);
      return;
    }

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
          widget.onVoted?.call();
        } on PostgrestException catch (e) {
          if (!mounted) return;
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
            if (!mounted) return;
            AppToast.warning(context, 'You already voted on this poll.');
          } else {
            AppToast.error(context, _friendlyError(e.message));
          }
        } catch (_) {
          if (!mounted) return;
          AppToast.error(
            context,
            'Could not submit vote. Check your connection.',
          );
        } finally {
          if (mounted) setState(() => _voteLoading = false);
        }
      },
    );
  }

  Future<void> _voteAsGuest(String optionId) async {
    setState(() => _voteLoading = true);
    try {
      await _voteService.voteAnonymous(pollId: _pollId, optionId: optionId);
      if (!mounted) return;
      setState(() => _selectedOptionId = optionId);
      await _refreshVoteCounts();
      widget.onVoted?.call();
    } on AlreadyVotedException {
      final anonSessionId = await AnonVoteSessionStore.instance.read();
      if (!mounted) return;
      if (anonSessionId != null) {
        final vote = await _voteService.getAnonVote(
          pollId: _pollId,
          anonSessionId: anonSessionId,
        );
        if (!mounted) return;
        if (vote is Map && vote['option_id'] != null) {
          setState(() => _selectedOptionId = vote['option_id'].toString());
        }
        await _refreshVoteCounts();
      }
      if (!mounted) return;
      AppToast.warning(context, 'You already voted on this poll.');
    } catch (_) {
      if (!mounted) return;
      AppToast.error(context, 'Could not submit vote. Check your connection.');
    } finally {
      if (mounted) setState(() => _voteLoading = false);
    }
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
          // Liking succeeded silently before — comment feedback ("Comment
          // added") had no equivalent here, which felt inconsistent.
          if (nextLiked) AppToast.success(context, 'Liked!');
        } on PostgrestException catch (e) {
          if (!mounted) return;
          if (_isDuplicateVoteError(e)) {
            setState(() {
              _liked = true;
            });
            AppToast.warning(context, 'Already liked.');
          } else {
            AppToast.error(context, _friendlyError(e.message));
          }
        } catch (_) {
          if (!mounted) return;
          AppToast.error(
            context,
            'Could not update like. Check your connection.',
          );
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
      // No vote yet, so there are no per-option counts to render into an
      // image - share the poll link/question as plain text instead of
      // blocking the action entirely. A poll's shareability is a primary
      // growth lever and shouldn't be gated behind participation; this only
      // changes what gets shared, not the separate "vote to see results"
      // gate on the results display itself.
      setState(() => _sharingResults = true);
      try {
        await Share.share(_shareText());
        _pollService.recordShare(_pollId);
      } catch (_) {
        if (!mounted) return;
        AppToast.error(context, 'Could not share this poll. Try again.');
      } finally {
        if (mounted) setState(() => _sharingResults = false);
      }
      return;
    }

    setState(() => _sharingResults = true);
    try {
      // Let the off-screen ShareablePollResultCard lay out and paint first.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final boundary =
          _shareCardKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        AppToast.error(
          context,
          'Could not generate the share image. Try again.',
        );
        return;
      }

      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted) return;
      if (byteData == null) {
        AppToast.error(
          context,
          'Could not generate the share image. Try again.',
        );
        return;
      }

      final file = XFile.fromData(
        byteData.buffer.asUint8List(),
        mimeType: 'image/png',
        name: 'poll-result.png',
      );
      await Share.shareXFiles([file], text: _shareText());
      _pollService.recordShare(_pollId);
    } catch (_) {
      if (!mounted) return;
      AppToast.error(context, 'Could not share the results image. Try again.');
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
    final hasQuestion = question != null && question.isNotEmpty;
    final appName = Branding.appName;
    final base = _resultsVisible
        ? (hasQuestion
              ? '"$question" — see the results on $appName!'
              : 'Check out the results of this poll on $appName!')
        : (hasQuestion
              ? '"$question" — vote on $appName!'
              : 'Vote on this poll on $appName!');
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
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.32),
                    ),
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
                          child: _buildOptionSection(showResults),
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

  String get _mediaLayout =>
      widget.poll['media_layout']?.toString() ?? 'scrim';

  Widget _buildOptionSection(bool showResults) {
    final allHaveMedia = _options.isNotEmpty &&
        _options.every(
          (o) => (o['media_url']?.toString() ?? '').isNotEmpty,
        );

    if (!allHaveMedia) {
      if (!showResults) {
        return Column(
          key: const ValueKey<String>('poll_choices'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final o in _options)
              PollOptionButton(
                label: o['option_text']?.toString() ?? '',
                mediaUrl: o['media_url']?.toString(),
                mediaType: o['media_type']?.toString(),
                enabled: !_voteLoading,
                onPressed: () => _onVote(o['id']?.toString() ?? ''),
              ),
          ],
        );
      }
      return Column(
        key: ValueKey<String>('poll_results_$_selectedOptionId'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final o in _options)
            PollResultBar(
              label: o['option_text']?.toString() ?? '',
              optionKey: o['id']?.toString() ?? '',
              mediaUrl: o['media_url']?.toString(),
              mediaType: o['media_type']?.toString(),
              count: _optionVotes[o['id']?.toString() ?? ''] ?? 0,
              totalVotes: _totalVotes,
              selected: o['id']?.toString() == _selectedOptionId,
              percentage: pollResultPercentage(
                _optionVotes[o['id']?.toString() ?? ''] ?? 0,
                _totalVotes,
              ),
            ),
        ],
      );
    }

    // All options have media — dispatch to the chosen layout.
    if (!showResults) {
      return switch (_mediaLayout) {
        'list' => _MediaBallotVoteList(
          key: const ValueKey<String>('ballot_vote'),
          options: _options,
          enabled: !_voteLoading,
          onVote: _onVote,
        ),
        'mosaic' => _MediaMosaicVote(
          key: const ValueKey<String>('mosaic_vote'),
          options: _options,
          enabled: !_voteLoading,
          onVote: _onVote,
        ),
        _ => _MediaScrimVoteGrid(
          key: const ValueKey<String>('scrim_vote'),
          options: _options,
          enabled: !_voteLoading,
          onVote: _onVote,
        ),
      };
    }

    return switch (_mediaLayout) {
      'list' => _MediaBallotResultList(
        key: ValueKey<String>('ballot_result_$_selectedOptionId'),
        options: _options,
        optionVotes: _optionVotes,
        totalVotes: _totalVotes,
        selectedOptionId: _selectedOptionId,
      ),
      'mosaic' => _MediaMosaicResult(
        key: ValueKey<String>('mosaic_result_$_selectedOptionId'),
        options: _options,
        optionVotes: _optionVotes,
        totalVotes: _totalVotes,
        selectedOptionId: _selectedOptionId,
      ),
      _ => _MediaScrimResultGrid(
        key: ValueKey<String>('scrim_result_$_selectedOptionId'),
        options: _options,
        optionVotes: _optionVotes,
        totalVotes: _totalVotes,
        selectedOptionId: _selectedOptionId,
      ),
    };
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
            semanticLabel: 'Votes',
          ),
          const SizedBox(width: 4),
          _EngagementInk(
            icon: Icons.chat_bubble_outline_rounded,
            count: commentsCount,
            labelStyle: labelStyle,
            hoverColor: _replyColor,
            onTap: onCommentTap ?? () {},
            semanticLabel: 'Comment',
          ),
          const SizedBox(width: 4),
          _EngagementInk(
            icon: Icons.ios_share_rounded,
            count: sharesCount,
            labelStyle: labelStyle,
            hoverColor: _shareColor,
            loading: shareLoading,
            onTap: shareLoading ? null : (onShareTap ?? () {}),
            semanticLabel: 'Share',
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
            semanticLabel: liked ? 'Unlike' : 'Like',
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
    required this.semanticLabel,
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
  // This row was previously untestable via Flutter web's semantics tree
  // (InkWell alone exposes no accessible name) - wrapping in Semantics also
  // gives screen readers a label for what was otherwise four unlabeled icons.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Expanded(
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          button: true,
          label: count > 0 ? '$semanticLabel, $count' : semanticLabel,
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

/// 16:9 preview for the poll's main attached image/video.
/// Videos render as an inline playable player via [VideoPreview].
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

    if (isVideo) {
      return VideoPreview(url: url, height: 220);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Image.network(
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
      ),
    );
  }
}

// ── Shared media preview dialogs ─────────────────────────────────────────────

void _openImageLightbox(BuildContext context, String url) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    builder: (ctx) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(ctx).pop(),
      child: Stack(
        children: [
          Center(
            child: GestureDetector(
              onTap: () {},
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) =>
                        progress == null
                            ? child
                            : const SizedBox(
                                width: 40,
                                height: 40,
                                child: CircularProgressIndicator(),
                              ),
                    errorBuilder: (context, error, stack) =>
                        const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: SafeArea(
              child: Material(
                color: Colors.black.withValues(alpha: 0.60),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(ctx).pop(),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.close_rounded, color: Colors.white, size: 20),
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

void _openVideoDialog(BuildContext context, String url) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    builder: (ctx) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(ctx).pop(),
      child: Stack(
        children: [
          Center(
            child: GestureDetector(
              onTap: () {},
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: VideoPreview(url: url, height: 280),
                ),
              ),
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: SafeArea(
              child: Material(
                color: Colors.black.withValues(alpha: 0.60),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(ctx).pop(),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.close_rounded, color: Colors.white, size: 20),
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

// ── Shared media background widget ───────────────────────────────────────────

class _MediaBackground extends StatelessWidget {
  const _MediaBackground({required this.mediaUrl, required this.isVideo});

  final String mediaUrl;
  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (isVideo || mediaUrl.isEmpty) {
      return const ColoredBox(color: Colors.black);
    }
    return Image.network(
      mediaUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stack) =>
          ColoredBox(color: cs.surfaceContainerHighest),
    );
  }
}

// ── Shared helper: find option IDs tied at max votes ─────────────────────────

Set<String> _findLeaders(Map<String, int> optionVotes) {
  if (optionVotes.isEmpty) return {};
  final max = optionVotes.values.reduce((a, b) => a > b ? a : b);
  return optionVotes.entries
      .where((e) => e.value == max)
      .map((e) => e.key)
      .toSet();
}

// ═════════════════════════════════════════════════════════════════════════════
// Layout 1 — Scrim Cards
// 2-column 16:10 grid; vote controls live on a gradient scrim inside each cell.
// Last lone option spans full width at 21:9.
// ═════════════════════════════════════════════════════════════════════════════

Widget _buildScrimGrid({
  required List<Map<String, dynamic>> options,
  required Widget Function(Map<String, dynamic> option, bool isWide) cellBuilder,
}) {
  final rows = <Widget>[];
  for (int i = 0; i < options.length; i += 2) {
    final isLastAlone = i + 1 >= options.length;
    rows.add(Padding(
      padding: EdgeInsets.only(bottom: i + 2 < options.length ? 8 : 0),
      child: isLastAlone
          ? cellBuilder(options[i], true)
          : Row(children: [
              Expanded(child: cellBuilder(options[i], false)),
              const SizedBox(width: 8),
              Expanded(child: cellBuilder(options[i + 1], false)),
            ]),
    ));
  }
  return Column(children: rows);
}

class _MediaScrimVoteGrid extends StatelessWidget {
  const _MediaScrimVoteGrid({
    super.key,
    required this.options,
    required this.enabled,
    required this.onVote,
  });

  final List<Map<String, dynamic>> options;
  final bool enabled;
  final void Function(String optionId) onVote;

  @override
  Widget build(BuildContext context) {
    return _buildScrimGrid(
      options: options,
      cellBuilder: (o, isWide) => _ScrimVoteCell(
        label: o['option_text']?.toString() ?? '',
        mediaUrl: o['media_url']?.toString() ?? '',
        isVideo: o['media_type']?.toString() == 'video',
        isWide: isWide,
        enabled: enabled,
        onVote: () => onVote(o['id']?.toString() ?? ''),
      ),
    );
  }
}

class _MediaScrimResultGrid extends StatelessWidget {
  const _MediaScrimResultGrid({
    super.key,
    required this.options,
    required this.optionVotes,
    required this.totalVotes,
    required this.selectedOptionId,
  });

  final List<Map<String, dynamic>> options;
  final Map<String, int> optionVotes;
  final int totalVotes;
  final String? selectedOptionId;

  @override
  Widget build(BuildContext context) {
    final leaders = _findLeaders(optionVotes);
    return _buildScrimGrid(
      options: options,
      cellBuilder: (o, isWide) {
        final id = o['id']?.toString() ?? '';
        final count = optionVotes[id] ?? 0;
        return _ScrimResultCell(
          optionKey: id,
          label: o['option_text']?.toString() ?? '',
          mediaUrl: o['media_url']?.toString() ?? '',
          isVideo: o['media_type']?.toString() == 'video',
          isWide: isWide,
          fraction: totalVotes > 0 ? count / totalVotes : 0.0,
          percentage: pollResultPercentage(count, totalVotes),
          totalVotes: totalVotes,
          count: count,
          selected: id == selectedOptionId,
          isLeading: leaders.contains(id),
        );
      },
    );
  }
}

class _ScrimVoteCell extends StatelessWidget {
  const _ScrimVoteCell({
    required this.label,
    required this.mediaUrl,
    required this.isVideo,
    required this.isWide,
    required this.enabled,
    required this.onVote,
  });

  final String label;
  final String mediaUrl;
  final bool isVideo;
  final bool isWide;
  final bool enabled;
  final VoidCallback onVote;

  void _previewMedia(BuildContext context) {
    if (mediaUrl.isEmpty) return;
    if (isVideo) {
      _openVideoDialog(context, mediaUrl);
    } else {
      _openImageLightbox(context, mediaUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: isWide ? 21 / 9 : 16 / 10,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _MediaBackground(mediaUrl: mediaUrl, isVideo: isVideo),
            // Gradient scrim at bottom
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: _ScrimVoteOverlay(label: label),
            ),
            // Play / expand icon in upper area
            Align(
              alignment: const Alignment(0, -0.2),
              child: _ScrimPreviewIcon(isVideo: isVideo),
            ),
            // Top 65% → preview tap
            Align(
              alignment: Alignment.topCenter,
              child: FractionallySizedBox(
                heightFactor: 0.65,
                widthFactor: 1.0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _previewMedia(context),
                ),
              ),
            ),
            // Bottom 35% → vote tap (sits on the scrim)
            Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: 0.35,
                widthFactor: 1.0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: enabled ? onVote : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScrimResultCell extends StatelessWidget {
  const _ScrimResultCell({
    required this.optionKey,
    required this.label,
    required this.mediaUrl,
    required this.isVideo,
    required this.isWide,
    required this.fraction,
    required this.percentage,
    required this.totalVotes,
    required this.count,
    required this.selected,
    required this.isLeading,
  });

  final String optionKey;
  final String label;
  final String mediaUrl;
  final bool isVideo;
  final bool isWide;
  final double fraction;
  final double percentage;
  final int totalVotes;
  final int count;
  final bool selected;
  final bool isLeading;

  static const Color _blue = Color(0xFF1D9BF0);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: isWide ? 21 / 9 : 16 / 10,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _MediaBackground(mediaUrl: mediaUrl, isVideo: isVideo),
            // Gradient scrim with result content
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: _ScrimResultOverlay(
                optionKey: optionKey,
                label: label,
                fraction: fraction,
                percentage: percentage,
                totalVotes: totalVotes,
                count: count,
                selected: selected,
                isLeading: isLeading,
              ),
            ),
            // LEADING badge top-right
            if (isLeading)
              Positioned(
                top: 8, right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _blue,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'LEADING',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            // Blue border for voted cell
            if (selected)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: _blue, width: 2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScrimVoteOverlay extends StatelessWidget {
  const _ScrimVoteOverlay({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          stops: [0.0, 0.35, 0.70, 1.0],
          colors: [
            Color(0xF2000000),
            Color(0x99000000),
            Color(0x61000000),
            Colors.transparent,
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
      child: Row(
        children: [
          Container(
            width: 18, height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              color: Colors.black.withValues(alpha: 0.30),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                shadows: [
                  Shadow(color: Colors.black, blurRadius: 3, offset: Offset(0, 1)),
                  Shadow(color: Colors.black, blurRadius: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScrimResultOverlay extends StatelessWidget {
  const _ScrimResultOverlay({
    required this.optionKey,
    required this.label,
    required this.fraction,
    required this.percentage,
    required this.totalVotes,
    required this.count,
    required this.selected,
    required this.isLeading,
  });

  final String optionKey;
  final String label;
  final double fraction;
  final double percentage;
  final int totalVotes;
  final int count;
  final bool selected;
  final bool isLeading;

  static const Color _blue = Color(0xFF1D9BF0);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          stops: [0.0, 0.35, 0.70, 1.0],
          colors: [
            Color(0xF2000000),
            Color(0x99000000),
            Color(0x61000000),
            Colors.transparent,
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (selected) ...[
                Container(
                  width: 16, height: 16,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: _blue),
                  child: const Icon(Icons.check_rounded, size: 10, color: Colors.white),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    shadows: [Shadow(color: Colors.black, blurRadius: 3)],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${percentage.round()}%',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: isLeading ? _blue : Colors.white,
                  shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Animated 4px result bar
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Color(0x33FFFFFF)),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey<String>('scrim_$optionKey${totalVotes}_$count'),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOut,
                      tween: Tween<double>(begin: 0, end: fraction.clamp(0.0, 1.0)),
                      builder: (context, v, child) => FractionallySizedBox(
                        widthFactor: v,
                        heightFactor: 1,
                        child: const ColoredBox(color: _blue),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScrimPreviewIcon extends StatelessWidget {
  const _ScrimPreviewIcon({required this.isVideo});
  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    final size = isVideo ? 44.0 : 32.0;
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.60),
      ),
      child: Icon(
        isVideo ? Icons.play_arrow_rounded : Icons.zoom_out_map_rounded,
        color: Colors.white,
        size: isVideo ? 26.0 : 18.0,
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Layout 2 — Ballot List
// X-style rows: 112px thumbnail left, text block, vote pill / result right.
// Thumbnail tap = preview; entire row tap = vote.
// ═════════════════════════════════════════════════════════════════════════════

class _MediaBallotVoteList extends StatelessWidget {
  const _MediaBallotVoteList({
    super.key,
    required this.options,
    required this.enabled,
    required this.onVote,
  });

  final List<Map<String, dynamic>> options;
  final bool enabled;
  final void Function(String optionId) onVote;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _BallotVoteRow(
            label: options[i]['option_text']?.toString() ?? '',
            mediaUrl: options[i]['media_url']?.toString() ?? '',
            isVideo: options[i]['media_type']?.toString() == 'video',
            enabled: enabled,
            onVote: () => onVote(options[i]['id']?.toString() ?? ''),
          ),
        ],
      ],
    );
  }
}

class _MediaBallotResultList extends StatelessWidget {
  const _MediaBallotResultList({
    super.key,
    required this.options,
    required this.optionVotes,
    required this.totalVotes,
    required this.selectedOptionId,
  });

  final List<Map<String, dynamic>> options;
  final Map<String, int> optionVotes;
  final int totalVotes;
  final String? selectedOptionId;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Builder(builder: (context) {
            final o = options[i];
            final id = o['id']?.toString() ?? '';
            final count = optionVotes[id] ?? 0;
            return _BallotResultRow(
              optionKey: id,
              label: o['option_text']?.toString() ?? '',
              mediaUrl: o['media_url']?.toString() ?? '',
              isVideo: o['media_type']?.toString() == 'video',
              fraction: totalVotes > 0 ? count / totalVotes : 0.0,
              percentage: pollResultPercentage(count, totalVotes),
              totalVotes: totalVotes,
              count: count,
              selected: id == selectedOptionId,
            );
          }),
        ],
      ],
    );
  }
}

class _BallotVoteRow extends StatelessWidget {
  const _BallotVoteRow({
    required this.label,
    required this.mediaUrl,
    required this.isVideo,
    required this.enabled,
    required this.onVote,
  });

  final String label;
  final String mediaUrl;
  final bool isVideo;
  final bool enabled;
  final VoidCallback onVote;

  static const Color _blue = Color(0xFF1D9BF0);

  void _previewMedia(BuildContext context) {
    if (mediaUrl.isEmpty) return;
    if (isVideo) {
      _openVideoDialog(context, mediaUrl);
    } else {
      _openImageLightbox(context, mediaUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: enabled ? onVote : null,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            // Thumbnail: preview tap (stops propagation to vote GestureDetector)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _previewMedia(context),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: SizedBox(
                  width: 112,
                  child: AspectRatio(
                    aspectRatio: 16 / 10,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _MediaBackground(mediaUrl: mediaUrl, isVideo: isVideo),
                        if (isVideo)
                          Center(
                            child: Container(
                              width: 32, height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withValues(alpha: 0.65),
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          )
                        else
                          Positioned(
                            bottom: 6, right: 6,
                            child: Icon(
                              Icons.zoom_out_map_rounded,
                              color: Colors.white,
                              size: 16,
                              shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Text block
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isVideo ? 'Video' : 'Photo',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF71767B)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Vote pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: _blue),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Vote',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _blue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BallotResultRow extends StatelessWidget {
  const _BallotResultRow({
    required this.optionKey,
    required this.label,
    required this.mediaUrl,
    required this.isVideo,
    required this.fraction,
    required this.percentage,
    required this.totalVotes,
    required this.count,
    required this.selected,
  });

  final String optionKey;
  final String label;
  final String mediaUrl;
  final bool isVideo;
  final double fraction;
  final double percentage;
  final int totalVotes;
  final int count;
  final bool selected;

  static const Color _blue = Color(0xFF1D9BF0);
  static const Color _blueFill = Color(0x241D9BF0);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          // Animated blue fill overlay (left → right, 0.6s)
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              key: ValueKey<String>('ballot_$optionKey${totalVotes}_$count'),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              tween: Tween<double>(begin: 0, end: fraction.clamp(0.0, 1.0)),
              builder: (context, v, child) => Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: v,
                  heightFactor: 1,
                  child: const ColoredBox(color: _blueFill),
                ),
              ),
            ),
          ),
          // Row content
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.transparent,
              border: Border.all(color: selected ? _blue : cs.outlineVariant),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                // Thumbnail (not tappable in results state)
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: SizedBox(
                    width: 112,
                    child: AspectRatio(
                      aspectRatio: 16 / 10,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _MediaBackground(mediaUrl: mediaUrl, isVideo: isVideo),
                          if (isVideo)
                            Center(
                              child: Container(
                                width: 32, height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: 0.65),
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (selected) ...[
                  Container(
                    width: 20, height: 20,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: _blue,
                    ),
                    child: const Icon(Icons.check_rounded, size: 13, color: Colors.white),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  '${percentage.round()}%',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Layout 3 — Mosaic + Chips
// Top: preview-only media collage. Bottom: numbered pill chips for voting.
// ═════════════════════════════════════════════════════════════════════════════

class _MediaMosaicVote extends StatelessWidget {
  const _MediaMosaicVote({
    super.key,
    required this.options,
    required this.enabled,
    required this.onVote,
  });

  final List<Map<String, dynamic>> options;
  final bool enabled;
  final void Function(String optionId) onVote;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MosaicGrid(options: options),
        const SizedBox(height: 10),
        _MosaicChipsVote(options: options, enabled: enabled, onVote: onVote),
      ],
    );
  }
}

class _MediaMosaicResult extends StatelessWidget {
  const _MediaMosaicResult({
    super.key,
    required this.options,
    required this.optionVotes,
    required this.totalVotes,
    required this.selectedOptionId,
  });

  final List<Map<String, dynamic>> options;
  final Map<String, int> optionVotes;
  final int totalVotes;
  final String? selectedOptionId;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MosaicGrid(options: options),
        const SizedBox(height: 10),
        _MosaicChipsResult(
          options: options,
          optionVotes: optionVotes,
          totalVotes: totalVotes,
          selectedOptionId: selectedOptionId,
        ),
      ],
    );
  }
}

class _MosaicGrid extends StatelessWidget {
  const _MosaicGrid({required this.options});
  final List<Map<String, dynamic>> options;

  void _preview(BuildContext context, Map<String, dynamic> o) {
    final url = o['media_url']?.toString() ?? '';
    if (url.isEmpty) return;
    if (o['media_type']?.toString() == 'video') {
      _openVideoDialog(context, url);
    } else {
      _openImageLightbox(context, url);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (options.length == 2) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 170,
                child: _MosaicTile(
                  option: options[0],
                  index: 1,
                  onPreview: () => _preview(context, options[0]),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: SizedBox(
                height: 170,
                child: _MosaicTile(
                  option: options[1],
                  index: 2,
                  onPreview: () => _preview(context, options[1]),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 3–5 options: col1 (1.3fr) spans full height; col2 + optional col3 (1fr each).
    const rowH = 105.0;
    const gap = 4.0;
    const totalH = rowH * 2 + gap;

    final col2 = options.sublist(1, options.length.clamp(1, 3));
    final col3 = options.length > 3 ? options.sublist(3) : <Map<String, dynamic>>[];

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: totalH,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Col 1: option 0, full height
            Expanded(
              flex: 13,
              child: _MosaicTile(
                option: options[0],
                index: 1,
                onPreview: () => _preview(context, options[0]),
              ),
            ),
            const SizedBox(width: gap),
            // Col 2: options 1 & 2
            Expanded(
              flex: 10,
              child: Column(
                children: [
                  for (int i = 0; i < col2.length; i++) ...[
                    if (i > 0) const SizedBox(height: gap),
                    SizedBox(
                      height: rowH,
                      child: _MosaicTile(
                        option: col2[i],
                        index: i + 2,
                        onPreview: () => _preview(context, col2[i]),
                      ),
                    ),
                  ],
                  if (col2.length < 2) const Spacer(),
                ],
              ),
            ),
            if (col3.isNotEmpty) ...[
              const SizedBox(width: gap),
              // Col 3: options 3 & 4
              Expanded(
                flex: 10,
                child: Column(
                  children: [
                    for (int i = 0; i < col3.length; i++) ...[
                      if (i > 0) const SizedBox(height: gap),
                      SizedBox(
                        height: rowH,
                        child: _MosaicTile(
                          option: col3[i],
                          index: i + 4,
                          onPreview: () => _preview(context, col3[i]),
                        ),
                      ),
                    ],
                    if (col3.length < 2) const Spacer(),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MosaicTile extends StatelessWidget {
  const _MosaicTile({
    required this.option,
    required this.index,
    required this.onPreview,
  });

  final Map<String, dynamic> option;
  final int index;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final mediaUrl = option['media_url']?.toString() ?? '';
    final isVideo = option['media_type']?.toString() == 'video';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPreview,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _MediaBackground(mediaUrl: mediaUrl, isVideo: isVideo),
          // Numbered disc top-left
          Positioned(
            top: 6, left: 6,
            child: Container(
              width: 22, height: 22,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xBF000000),
              ),
              child: Center(
                child: Text(
                  '$index',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          // Play circle for video
          if (isVideo)
            Center(
              child: Container(
                width: 36, height: 36,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xBF000000),
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
              ),
            ),
        ],
      ),
    );
  }
}

class _MosaicChipsVote extends StatelessWidget {
  const _MosaicChipsVote({
    required this.options,
    required this.enabled,
    required this.onVote,
  });

  final List<Map<String, dynamic>> options;
  final bool enabled;
  final void Function(String optionId) onVote;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          _MosaicChipVote(
            index: i + 1,
            label: options[i]['option_text']?.toString() ?? '',
            enabled: enabled,
            onVote: () => onVote(options[i]['id']?.toString() ?? ''),
          ),
        ],
      ],
    );
  }
}

class _MosaicChipVote extends StatelessWidget {
  const _MosaicChipVote({
    required this.index,
    required this.label,
    required this.enabled,
    required this.onVote,
  });

  final int index;
  final String label;
  final bool enabled;
  final VoidCallback onVote;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: enabled ? onVote : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: [
            Container(
              width: 20, height: 20,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF2F3336),
              ),
              child: Center(
                child: Text(
                  '$index',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            // Radio ring
            Container(
              width: 18, height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF71767B), width: 2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MosaicChipsResult extends StatelessWidget {
  const _MosaicChipsResult({
    required this.options,
    required this.optionVotes,
    required this.totalVotes,
    required this.selectedOptionId,
  });

  final List<Map<String, dynamic>> options;
  final Map<String, int> optionVotes;
  final int totalVotes;
  final String? selectedOptionId;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          Builder(builder: (context) {
            final o = options[i];
            final id = o['id']?.toString() ?? '';
            final count = optionVotes[id] ?? 0;
            return _MosaicChipResult(
              optionKey: id,
              index: i + 1,
              label: o['option_text']?.toString() ?? '',
              fraction: totalVotes > 0 ? count / totalVotes : 0.0,
              percentage: pollResultPercentage(count, totalVotes),
              totalVotes: totalVotes,
              count: count,
              selected: id == selectedOptionId,
            );
          }),
        ],
      ],
    );
  }
}

class _MosaicChipResult extends StatelessWidget {
  const _MosaicChipResult({
    required this.optionKey,
    required this.index,
    required this.label,
    required this.fraction,
    required this.percentage,
    required this.totalVotes,
    required this.count,
    required this.selected,
  });

  final String optionKey;
  final int index;
  final String label;
  final double fraction;
  final double percentage;
  final int totalVotes;
  final int count;
  final bool selected;

  static const Color _blue = Color(0xFF1D9BF0);
  static const Color _blueFill = Color(0x241D9BF0);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Stack(
        children: [
          // Animated fill
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              key: ValueKey<String>('chip_$optionKey${totalVotes}_$count'),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              tween: Tween<double>(begin: 0, end: fraction.clamp(0.0, 1.0)),
              builder: (context, v, child) => Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: v,
                  heightFactor: 1,
                  child: const ColoredBox(color: _blueFill),
                ),
              ),
            ),
          ),
          // Chip content
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              border: Border.all(color: selected ? _blue : cs.outlineVariant),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                Container(
                  width: 20, height: 20,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF2F3336),
                  ),
                  child: Center(
                    child: Text(
                      '$index',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (selected) ...[
                  Container(
                    width: 20, height: 20,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: _blue),
                    child: const Icon(Icons.check_rounded, size: 13, color: Colors.white),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  '${percentage.round()}%',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
