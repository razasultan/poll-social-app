import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:go_router/go_router.dart';

import '../core/widgets/timeline_column.dart';
import '../services/moderation_service.dart';
import '../services/poll_service.dart';
import '../services/social_service.dart';
import '../utils/profile_navigation.dart';
import '../widgets/app_toast.dart';
import '../widgets/auth_guard.dart';
import '../widgets/poll_card.dart';
import '../widgets/poll_result_chart.dart';
import 'embed_poll_screen.dart' show embedSnippetForShareSlug;
import '../widgets/create_poll_modal.dart' show showEditPollModal;

/// Decides whether a key event on the comment composer should submit the
/// comment (a lone Enter/numpad-Enter key-down) versus letting the
/// [TextField] handle it normally, which inserts a newline (Shift+Enter, or
/// any other key). Exposed as a top-level function so the decision can be
/// unit-tested without pumping a widget tree.
bool shouldSubmitCommentOnEnter(KeyEvent event, {required bool shiftPressed}) {
  final isEnter =
      event.logicalKey == LogicalKeyboardKey.enter ||
      event.logicalKey == LogicalKeyboardKey.numpadEnter;
  return event is KeyDownEvent && isEnter && !shiftPressed;
}

/// Full poll view with comments and report action.
class PollDetailScreen extends StatefulWidget {
  const PollDetailScreen({super.key, required this.pollId});

  final String pollId;

  @override
  State<PollDetailScreen> createState() => _PollDetailScreenState();
}

class _PollDetailScreenState extends State<PollDetailScreen> {
  final PollService _pollService = PollService();
  final SocialService _socialService = SocialService();
  final ModerationService _moderationService = ModerationService();
  final TextEditingController _commentCtrl = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();

  bool _loading = true;
  bool _postingComment = false;
  String? _error;
  Map<String, dynamic>? _poll;
  // Top-level comments only. Replies are fetched lazily per-comment.
  List<Map<String, dynamic>> _comments = [];
  // comment_id → fetched replies (populated on expand).
  final Map<String, List<Map<String, dynamic>>> _replies = {};
  // Which comment threads are currently expanded.
  final Set<String> _expandedCommentIds = {};
  // Which comment threads are currently loading their replies.
  final Set<String> _loadingRepliesFor = {};
  // Comment IDs liked by the current user (used to seed tile initial state).
  Set<String> _likedCommentIds = {};
  String? _busyCommentId;
  // Incremented when the user votes via PollCard so PollResultChart reloads.
  int _chartVersion = 0;
  // Non-null when the user is composing a reply.
  String? _replyingToCommentId; // the top-level comment id (parentCommentId)
  String? _replyingToUsername;
  // For reply-to-reply: the user being @mentioned (may differ from the
  // top-level comment's author). Sent as reply_to_user_id to addComment().
  String? _replyingToUserId;

  /// Clears the persistent comment input bar at the bottom of this screen so
  /// toasts don't render underneath it.
  static const double _toastBottomClearance = 64;

  /// Guards against out-of-order responses: add/edit/delete each call
  /// [_load] right after their own mutation, so two can be in flight at
  /// once (e.g. deleting a comment, then immediately posting a new one).
  /// Without this, whichever network response arrives last wins via
  /// setState — even if it's the one from the *earlier* request, which can
  /// briefly resurrect a just-deleted comment with stale data.
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load({bool showFullLoading = true}) async {
    final generation = ++_loadGeneration;
    if (showFullLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rawPoll = await _pollService.getPollById(widget.pollId);
      final rawComments = await _socialService.getTopLevelComments(
        widget.pollId,
      );

      final poll = rawPoll is Map<String, dynamic>
          ? rawPoll
          : Map<String, dynamic>.from(rawPoll as Map);

      // Only top-level comments are loaded here. Replies are fetched lazily
      // per-thread when the user taps "View N replies".
      final comments = rawComments;

      // Batch-fetch liked comment IDs for the current user so each tile can
      // seed its optimistic like state without an individual network call.
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      Set<String> likedIds = {};
      if (currentUserId != null && comments.isNotEmpty) {
        final commentIds = comments
            .map((c) => c['id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toList();
        likedIds = await _socialService.getLikedCommentIds(
          userId: currentUserId,
          commentIds: commentIds,
        );
      }

      if (!mounted) return;
      // A newer _load() call was started while this one was in flight —
      // its (later) response should win instead, so drop this one.
      if (generation != _loadGeneration) return;
      setState(() {
        _poll = poll;
        _comments = comments;
        _likedCommentIds = likedIds;
        _loading = false;
        _error = null;
      });
      // Fire-and-forget view recording after the poll renders successfully.
      // PollService.recordView deduplicates within the session so navigating
      // away and back doesn't double-count; failures are silently ignored.
      _pollService.recordView(widget.pollId);
    } catch (e) {
      if (!mounted) return;
      if (generation != _loadGeneration) return;
      if (showFullLoading) {
        setState(() {
          _loading = false;
          _error = _pollLoadMessage(e);
        });
      } else {
        AppToast.error(
          context,
          'Could not refresh comments.',
          extraBottomOffset: _toastBottomClearance,
        );
      }
    }
  }

  String _pollLoadMessage(Object e) {
    if (e is PostgrestException) {
      final code = e.code;
      if (code == 'PGRST116' || e.message.toLowerCase().contains('0 rows')) {
        return 'Poll not found.';
      }
      return e.message.isNotEmpty ? e.message : 'Could not load poll.';
    }
    return 'Could not load poll. Check your connection.';
  }

  DateTime? _parseTime(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
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

  Map<String, dynamic>? _commentProfile(Map<String, dynamic> comment) {
    final p = comment['profiles'];
    if (p is Map<String, dynamic>) return p;
    if (p is Map) return Map<String, dynamic>.from(p);
    return null;
  }

  /// Starts composing a reply. [comment] may be a top-level comment OR a
  /// reply tile — in both cases the reply is stored under the same top-level
  /// parent (flat nesting), but `reply_to_user_id` tracks who is @mentioned.
  void _startReply(Map<String, dynamic> comment) {
    final profile = _commentProfile(comment);
    final username =
        profile?['username']?.toString() ??
        comment['username']?.toString() ??
        'user';
    final isReply = comment['parent_comment_id'] != null;
    setState(() {
      _replyingToCommentId = isReply
          ? comment['parent_comment_id'].toString()
          : comment['id']?.toString();
      _replyingToUsername = username;
      _replyingToUserId = isReply ? comment['user_id']?.toString() : null;
    });
    _commentFocusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyingToCommentId = null;
      _replyingToUsername = null;
      _replyingToUserId = null;
    });
  }

  /// Lazily fetches and shows replies for [commentId].
  Future<void> _loadReplies(String commentId) async {
    if (_loadingRepliesFor.contains(commentId)) return;
    setState(() => _loadingRepliesFor.add(commentId));
    try {
      final rows = await _socialService.getReplies(commentId);
      // Fetch liked state for replies too so their tiles start correctly.
      final userId = Supabase.instance.client.auth.currentUser?.id;
      Set<String> likedReplyIds = {};
      if (userId != null && rows.isNotEmpty) {
        final replyIds = rows
            .map((r) => r['id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toList();
        likedReplyIds = await _socialService.getLikedCommentIds(
          userId: userId,
          commentIds: replyIds,
        );
      }
      if (!mounted) return;
      setState(() {
        _replies[commentId] = rows;
        _likedCommentIds = {..._likedCommentIds, ...likedReplyIds};
        _expandedCommentIds.add(commentId);
      });
    } catch (_) {
      if (!mounted) return;
      AppToast.error(
        context,
        'Could not load replies.',
        extraBottomOffset: _toastBottomClearance,
      );
    } finally {
      if (mounted) setState(() => _loadingRepliesFor.remove(commentId));
    }
  }

  void _toggleReplies(String commentId) {
    if (_expandedCommentIds.contains(commentId)) {
      setState(() => _expandedCommentIds.remove(commentId));
    } else if (_replies.containsKey(commentId)) {
      // Already fetched — just expand without a network round-trip.
      setState(() => _expandedCommentIds.add(commentId));
    } else {
      _loadReplies(commentId);
    }
  }

  Future<void> _submitComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) {
      AppToast.warning(
        context,
        'Write a comment first.',
        extraBottomOffset: _toastBottomClearance,
      );
      return;
    }

    final parentId = _replyingToCommentId;
    final replyToUserId = _replyingToUserId;

    await AuthGuard.requireAuth(
      context,
      onAuthenticated: () async {
        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) return;

        setState(() => _postingComment = true);
        try {
          await _socialService.addComment(
            pollId: widget.pollId,
            userId: user.id,
            commentText: text,
            parentCommentId: parentId,
            replyToUserId: replyToUserId,
          );
          if (!mounted) return;
          _commentCtrl.clear();
          _cancelReply();
          if (parentId != null) {
            // Refresh just the reply list for this thread + the top-level
            // comment so replies_count updates, without re-fetching everything.
            await Future.wait([
              _socialService.getReplies(parentId).then((rows) {
                if (mounted) {
                  setState(() {
                    _replies[parentId] = rows;
                    _expandedCommentIds.add(parentId);
                  });
                }
              }),
              _load(showFullLoading: false),
            ]);
          } else {
            await _load(showFullLoading: false);
          }
          if (!mounted) return;
          if (!mounted) return;
          AppToast.success(
            context,
            'Comment added',
            extraBottomOffset: _toastBottomClearance,
          );
        } on PostgrestException catch (e) {
          AppToast.error(
            context,
            e.message.isNotEmpty ? e.message : 'Could not post comment.',
            extraBottomOffset: _toastBottomClearance,
          );
        } catch (_) {
          AppToast.error(
            context,
            'Network error. Try again.',
            extraBottomOffset: _toastBottomClearance,
          );
        } finally {
          if (mounted) setState(() => _postingComment = false);
        }
      },
    );
  }

  Future<void> _editPoll() async {
    final poll = _poll;
    if (poll == null) return;
    final result = await showEditPollModal(context, poll);
    if (!mounted) return;
    if (result == 'deleted') {
      context.pop('deleted');
    } else if (result == true) {
      _load();
    }
  }

  Future<void> _confirmDeletePoll() async {
    final cs = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.delete_forever_rounded, color: cs.error, size: 32),
        title: const Text('Delete this poll?'),
        content: const Text(
          'This permanently removes the poll and all its votes. There is no undo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    try {
      await _pollService.deletePoll(widget.pollId);
      if (!mounted) return;
      context.pop('deleted');
    } catch (_) {
      if (!mounted) return;
      AppToast.error(context, 'Could not delete poll. Try again.');
    }
  }

  Future<void> _reportPoll() async {
    await AuthGuard.requireAuth(
      context,
      onAuthenticated: () async {
        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) return;

        try {
          await _moderationService.reportContent(
            reporterId: user.id,
            targetType: 'poll',
            targetId: widget.pollId,
            reason: 'inappropriate_content',
          );
          if (!mounted) return;
          AppToast.success(
            context,
            'Report submitted',
            extraBottomOffset: _toastBottomClearance,
          );
        } on PostgrestException catch (e) {
          AppToast.error(
            context,
            e.message.isNotEmpty ? e.message : 'Could not submit report.',
            extraBottomOffset: _toastBottomClearance,
          );
        } catch (_) {
          AppToast.error(
            context,
            'Could not submit report. Try again.',
            extraBottomOffset: _toastBottomClearance,
          );
        }
      },
    );
  }

  bool get _embeddable {
    final poll = _poll;
    if (poll == null) return false;
    final slug = poll['share_slug']?.toString().trim();
    return (slug != null && slug.isNotEmpty) &&
        poll['allow_embedding'] != false;
  }

  Future<void> _copyEmbedCode() async {
    final slug = _poll?['share_slug']?.toString().trim();
    if (slug == null || slug.isEmpty) return;
    await Clipboard.setData(
      ClipboardData(text: embedSnippetForShareSlug(slug)),
    );
    if (!mounted) return;
    AppToast.success(
      context,
      'Embed code copied to clipboard.',
      extraBottomOffset: _toastBottomClearance,
    );
  }

  String? _commentOwnerId(Map<String, dynamic> comment) =>
      comment['user_id']?.toString();

  Future<void> _promptEditComment(Map<String, dynamic> comment) async {
    final user = Supabase.instance.client.auth.currentUser;
    final commentId = comment['id']?.toString();
    if (user == null || commentId == null || commentId.isEmpty) return;

    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => _EditCommentDialog(
        initialText: comment['comment_text']?.toString() ?? '',
      ),
    );

    if (!mounted || saved == null) return;
    if (saved.isEmpty) {
      AppToast.warning(
        context,
        'Comment cannot be empty.',
        extraBottomOffset: _toastBottomClearance,
      );
      return;
    }

    setState(() => _busyCommentId = commentId);
    try {
      await _socialService.updateComment(
        commentId: commentId,
        userId: user.id,
        commentText: saved,
      );
      if (!mounted) return;
      await _load(showFullLoading: false);
      if (!mounted) return;
      AppToast.success(
        context,
        'Comment updated',
        extraBottomOffset: _toastBottomClearance,
      );
    } on PostgrestException catch (e) {
      AppToast.error(
        context,
        e.message.isNotEmpty ? e.message : 'Could not update comment.',
        extraBottomOffset: _toastBottomClearance,
      );
    } catch (_) {
      AppToast.error(
        context,
        'Could not update comment. Try again.',
        extraBottomOffset: _toastBottomClearance,
      );
    } finally {
      if (mounted) setState(() => _busyCommentId = null);
    }
  }

  Future<void> _confirmDeleteComment(Map<String, dynamic> comment) async {
    final user = Supabase.instance.client.auth.currentUser;
    final commentId = comment['id']?.toString();
    if (user == null || commentId == null || commentId.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete comment?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;

    setState(() => _busyCommentId = commentId);
    try {
      await _socialService.deleteComment(commentId: commentId, userId: user.id);
      if (!mounted) return;
      await _load(showFullLoading: false);
      if (!mounted) return;
      AppToast.success(
        context,
        'Comment deleted',
        extraBottomOffset: _toastBottomClearance,
      );
    } on PostgrestException catch (e) {
      AppToast.error(
        context,
        e.message.isNotEmpty ? e.message : 'Could not delete comment.',
        extraBottomOffset: _toastBottomClearance,
      );
    } catch (_) {
      AppToast.error(
        context,
        'Could not delete comment. Try again.',
        extraBottomOffset: _toastBottomClearance,
      );
    } finally {
      if (mounted) setState(() => _busyCommentId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Poll'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') _editPoll();
              if (value == 'delete') _confirmDeletePoll();
              if (value == 'report') _reportPoll();
              if (value == 'embed') _copyEmbedCode();
            },
            itemBuilder: (context) {
              final isOwner =
                  currentUserId != null &&
                  _poll?['user_id']?.toString() == currentUserId;
              return [
                if (isOwner) ...[
                  const PopupMenuItem<String>(
                    value: 'edit',
                    child: Text('Edit poll'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'delete',
                    child: Text('Delete poll'),
                  ),
                  const PopupMenuDivider(),
                ],
                if (_embeddable)
                  const PopupMenuItem<String>(
                    value: 'embed',
                    child: Text('Copy embed code'),
                  ),
                const PopupMenuItem<String>(
                  value: 'report',
                  child: Text('Report Poll'),
                ),
              ];
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 48,
                      color: cs.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.tonal(
                      onPressed: _load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : TimelineColumn(
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 16),
                      children: [
                        PollCard(
                          poll: _poll!,
                          showTrendingScore: false,
                          onVoted: () => setState(() => _chartVersion++),
                        ),
                        PollResultChart(poll: _poll!, reloadKey: _chartVersion),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                          child: Text(
                            'Comments',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (_comments.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            child: Text(
                              'No comments yet',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          )
                        else
                          ..._comments.expand((c) {
                            final cid = c['id']?.toString() ?? '';
                            final ownerId = _commentOwnerId(c);
                            final isOwner =
                                currentUserId != null &&
                                ownerId != null &&
                                ownerId == currentUserId;
                            final repliesCount =
                                (c['replies_count'] as num?)?.toInt() ?? 0;
                            final isExpanded = _expandedCommentIds.contains(
                              cid,
                            );
                            final isLoadingReplies = _loadingRepliesFor
                                .contains(cid);
                            final loadedReplies = _replies[cid] ?? [];

                            return [
                              _CommentTile(
                                commentUserId: ownerId ?? '',
                                comment: c,
                                profile: _commentProfile(c),
                                relativeTime: _formatRelativeTime(
                                  _parseTime(c['created_at']),
                                ),
                                isOwner: isOwner,
                                busy: cid == _busyCommentId,
                                currentUserId: currentUserId,
                                initialLikesCount:
                                    (c['likes_count'] as num?)?.toInt() ?? 0,
                                initialIsLiked: _likedCommentIds.contains(cid),
                                onEdit: isOwner
                                    ? () => _promptEditComment(c)
                                    : null,
                                onDelete: isOwner
                                    ? () => _confirmDeleteComment(c)
                                    : null,
                                onReply: () => _startReply(c),
                              ),
                              // ── Reply thread ───────────────────────────
                              if (isLoadingReplies)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 60,
                                    top: 4,
                                    bottom: 8,
                                  ),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                )
                              else if (isExpanded) ...[
                                for (final r in loadedReplies)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 48),
                                    child: _CommentTile(
                                      commentUserId: _commentOwnerId(r) ?? '',
                                      comment: r,
                                      profile: _commentProfile(r),
                                      relativeTime: _formatRelativeTime(
                                        _parseTime(r['created_at']),
                                      ),
                                      isOwner:
                                          currentUserId != null &&
                                          _commentOwnerId(r) == currentUserId,
                                      busy:
                                          r['id']?.toString() == _busyCommentId,
                                      currentUserId: currentUserId,
                                      initialLikesCount:
                                          (r['likes_count'] as num?)?.toInt() ??
                                          0,
                                      initialIsLiked: _likedCommentIds.contains(
                                        r['id']?.toString() ?? '',
                                      ),
                                      onEdit:
                                          (currentUserId != null &&
                                              _commentOwnerId(r) ==
                                                  currentUserId)
                                          ? () => _promptEditComment(r)
                                          : null,
                                      onDelete:
                                          (currentUserId != null &&
                                              _commentOwnerId(r) ==
                                                  currentUserId)
                                          ? () => _confirmDeleteComment(r)
                                          : null,
                                      onReply: () => _startReply(r),
                                    ),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 60,
                                    bottom: 6,
                                  ),
                                  child: GestureDetector(
                                    onTap: () => _toggleReplies(cid),
                                    child: Text(
                                      'Hide replies',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: cs.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                ),
                              ] else if (repliesCount > 0)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: 60,
                                    bottom: 6,
                                  ),
                                  child: GestureDetector(
                                    onTap: () => _toggleReplies(cid),
                                    child: Text(
                                      'View $repliesCount '
                                      '${repliesCount == 1 ? 'reply' : 'replies'}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: cs.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                ),
                            ];
                          }),
                      ],
                    ),
                  ),
                  Material(
                    elevation: 8,
                    shadowColor: Colors.black.withValues(alpha: 0.08),
                    color: cs.surface,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_replyingToUsername != null)
                          Container(
                            width: double.infinity,
                            color: cs.surfaceContainerHighest,
                            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.reply_rounded,
                                  size: 16,
                                  color: cs.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Replying to @$_replyingToUsername',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Semantics(
                                  button: true,
                                  label: 'Cancel reply',
                                  child: GestureDetector(
                                    onTap: _cancelReply,
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            10,
                            8,
                            10 + bottomInset,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Focus(
                                  onKeyEvent: (node, event) {
                                    if (shouldSubmitCommentOnEnter(
                                      event,
                                      shiftPressed: HardwareKeyboard
                                          .instance
                                          .isShiftPressed,
                                    )) {
                                      if (!_postingComment) {
                                        _submitComment();
                                      }
                                      return KeyEventResult.handled;
                                    }
                                    return KeyEventResult.ignored;
                                  },
                                  child: TextField(
                                    controller: _commentCtrl,
                                    focusNode: _commentFocusNode,
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    textInputAction: TextInputAction.send,
                                    minLines: 1,
                                    maxLines: 5,
                                    enabled: !_postingComment,
                                    onSubmitted: (_) => _submitComment(),
                                    decoration: InputDecoration(
                                      hintText: _replyingToUsername != null
                                          ? 'Reply to @$_replyingToUsername…'
                                          : 'Add a comment…',
                                      filled: true,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: cs.outlineVariant,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: cs.primary,
                                          width: 1.5,
                                        ),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 12,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              _postingComment
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    )
                                  : IconButton.filled(
                                      onPressed: _submitComment,
                                      tooltip: 'Send comment',
                                      icon: const Icon(Icons.send_rounded),
                                    ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Edit-comment dialog. Owns its [TextEditingController] via normal State
/// lifecycle (created in [initState], disposed in [dispose]) rather than a
/// controller created by the caller around `showDialog` — disposing such a
/// controller synchronously the instant the dialog's future resolves trips
/// Flutter's `assert(_dependents.isEmpty)` in
/// `InheritedElement.debugDeactivated`, since the autofocus'd field's
/// dependents are still mid-teardown at that point.
class _EditCommentDialog extends StatefulWidget {
  const _EditCommentDialog({required this.initialText});

  final String initialText;

  @override
  State<_EditCommentDialog> createState() => _EditCommentDialogState();
}

class _EditCommentDialogState extends State<_EditCommentDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit comment'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        minLines: 2,
        maxLines: 6,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _CommentTile extends StatefulWidget {
  const _CommentTile({
    required this.commentUserId,
    required this.comment,
    required this.profile,
    required this.relativeTime,
    required this.isOwner,
    required this.busy,
    required this.currentUserId,
    required this.initialLikesCount,
    required this.initialIsLiked,
    this.onEdit,
    this.onDelete,
    this.onReply,
  });

  final String commentUserId;
  final Map<String, dynamic> comment;
  final Map<String, dynamic>? profile;
  final String relativeTime;
  final bool isOwner;
  final bool busy;
  final String? currentUserId;
  final int initialLikesCount;
  final bool initialIsLiked;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onReply;

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  final SocialService _socialService = SocialService();
  late bool _liked;
  late int _likesCount;
  bool _liking = false;

  @override
  void initState() {
    super.initState();
    _liked = widget.initialIsLiked;
    _likesCount = widget.initialLikesCount;
  }

  @override
  void didUpdateWidget(_CommentTile old) {
    super.didUpdateWidget(old);
    // Sync if the parent reloads data (e.g. after a refresh).
    if (old.initialIsLiked != widget.initialIsLiked) {
      _liked = widget.initialIsLiked;
    }
    if (old.initialLikesCount != widget.initialLikesCount) {
      _likesCount = widget.initialLikesCount;
    }
  }

  Future<void> _toggleLike() async {
    final commentId = widget.comment['id']?.toString() ?? '';
    if (commentId.isEmpty) return;

    await AuthGuard.requireAuth(
      context,
      onAuthenticated: () async {
        final userId = widget.currentUserId;
        if (userId == null) return;

        // Optimistic flip
        setState(() {
          final next = toggleCommentLikeState(
            currentlyLiked: _liked,
            currentLikesCount: _likesCount,
          );
          _liked = next.liked;
          _likesCount = next.likesCount;
          _liking = true;
        });

        try {
          if (_liked) {
            await _socialService.likeComment(
              commentId: commentId,
              userId: userId,
            );
          } else {
            await _socialService.unlikeComment(
              commentId: commentId,
              userId: userId,
            );
          }
        } on PostgrestException catch (e) {
          if (!mounted) return;
          setState(() {
            final rollback = toggleCommentLikeState(
              currentlyLiked: _liked,
              currentLikesCount: _likesCount,
            );
            _liked = rollback.liked;
            _likesCount = rollback.likesCount;
          });
          AppToast.error(
            context,
            e.message.isNotEmpty ? e.message : 'Could not update like.',
            extraBottomOffset: 64,
          );
        } catch (_) {
          if (!mounted) return;
          setState(() {
            final rollback = toggleCommentLikeState(
              currentlyLiked: _liked,
              currentLikesCount: _likesCount,
            );
            _liked = rollback.liked;
            _likesCount = rollback.likesCount;
          });
          AppToast.error(
            context,
            'Network error. Try again.',
            extraBottomOffset: 64,
          );
        } finally {
          if (mounted) setState(() => _liking = false);
        }
      },
    );
  }

  Widget _wrapProfileTap(BuildContext context, String uid, Widget child) {
    if (uid.isEmpty) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openProfile(context, uid),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final username =
        widget.profile?['username']?.toString() ??
        widget.comment['username']?.toString() ??
        'Unknown';
    final avatarUrl = widget.profile?['avatar_url']?.toString();
    final replyToUsername =
        (widget.comment['reply_to_profile'] as Map?)?['username']?.toString();
    final rawText = widget.comment['comment_text']?.toString() ?? '';
    final text = replyToUsername != null
        ? '@$replyToUsername $rawText'
        : rawText;
    final uid = widget.commentUserId.trim();

    final avatar = CircleAvatar(
      radius: 18,
      backgroundColor: (avatarUrl != null && avatarUrl.isNotEmpty)
          ? cs.surfaceContainerHighest
          : cs.primaryContainer,
      backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
          ? NetworkImage(avatarUrl)
          : null,
      child: avatarUrl == null || avatarUrl.isEmpty
          ? Text(
              username.isNotEmpty ? username[0].toUpperCase() : '?',
              style: TextStyle(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            )
          : null,
    );

    final usernameText = Text(
      username,
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _wrapProfileTap(context, uid, avatar),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _wrapProfileTap(
                        context,
                        uid,
                        Align(
                          alignment: Alignment.centerLeft,
                          child: usernameText,
                        ),
                      ),
                    ),
                    if (widget.relativeTime.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          widget.relativeTime,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (widget.busy)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: Padding(
                          padding: EdgeInsets.all(2),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if (widget.isOwner &&
                        widget.onEdit != null &&
                        widget.onDelete != null)
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert_rounded,
                          size: 20,
                          color: cs.onSurfaceVariant,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                        onSelected: (value) {
                          if (value == 'edit') widget.onEdit!();
                          if (value == 'delete') widget.onDelete!();
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (widget.onReply != null)
                      GestureDetector(
                        onTap: widget.onReply,
                        child: Text(
                          'Reply',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    const Spacer(),
                    // Like button — heart icon + count
                    Semantics(
                      button: true,
                      label: _liked ? 'Unlike comment' : 'Like comment',
                      child: GestureDetector(
                        onTap: _liking ? null : _toggleLike,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_liking)
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: cs.onSurfaceVariant,
                                ),
                              )
                            else
                              Icon(
                                _liked
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                size: 16,
                                color: _liked ? cs.error : cs.onSurfaceVariant,
                              ),
                            if (_likesCount > 0) ...[
                              const SizedBox(width: 4),
                              Text(
                                '$_likesCount',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: _liked
                                      ? cs.error
                                      : cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
