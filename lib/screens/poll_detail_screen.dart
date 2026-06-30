import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  bool _loading = true;
  bool _postingComment = false;
  String? _error;
  Map<String, dynamic>? _poll;
  List<Map<String, dynamic>> _comments = [];
  String? _busyCommentId;

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
      final rawComments = await _socialService.getCommentThread(widget.pollId);

      final poll = rawPoll is Map<String, dynamic>
          ? rawPoll
          : Map<String, dynamic>.from(rawPoll as Map);

      // getCommentThread returns List<Map<String, dynamic>> already sorted
      // chronologically (ascending: true in the query) and grouped into a
      // two-level tree (top-level comments carry a 'replies' key).
      final comments = rawComments;

      if (!mounted) return;
      // A newer _load() call was started while this one was in flight —
      // its (later) response should win instead, so drop this one.
      if (generation != _loadGeneration) return;
      setState(() {
        _poll = poll;
        _comments = comments;
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
          );
          if (!mounted) return;
          _commentCtrl.clear();
          await _load(showFullLoading: false);
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
              if (value == 'report') _reportPoll();
              if (value == 'embed') _copyEmbedCode();
            },
            itemBuilder: (context) => [
              if (_embeddable)
                const PopupMenuItem<String>(
                  value: 'embed',
                  child: Text('Copy embed code'),
                ),
              const PopupMenuItem<String>(
                value: 'report',
                child: Text('Report Poll'),
              ),
            ],
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
                        PollCard(poll: _poll!, showTrendingScore: false),
                        PollResultChart(poll: _poll!),
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
                          ..._comments.map((c) {
                            final cid = c['id']?.toString();
                            final ownerId = _commentOwnerId(c);
                            final isOwner =
                                currentUserId != null &&
                                ownerId != null &&
                                ownerId == currentUserId;
                            return _CommentTile(
                              commentUserId: ownerId ?? '',
                              comment: c,
                              profile: _commentProfile(c),
                              relativeTime: _formatRelativeTime(
                                _parseTime(c['created_at']),
                              ),
                              isOwner: isOwner,
                              busy: cid != null && cid == _busyCommentId,
                              onEdit: isOwner
                                  ? () => _promptEditComment(c)
                                  : null,
                              onDelete: isOwner
                                  ? () => _confirmDeleteComment(c)
                                  : null,
                            );
                          }),
                      ],
                    ),
                  ),
                  Material(
                    elevation: 8,
                    shadowColor: Colors.black.withValues(alpha: 0.08),
                    color: cs.surface,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 10, 8, 10 + bottomInset),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _commentCtrl,
                              textCapitalization: TextCapitalization.sentences,
                              minLines: 1,
                              maxLines: 5,
                              enabled: !_postingComment,
                              decoration: InputDecoration(
                                hintText: 'Add a comment…',
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
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
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

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.commentUserId,
    required this.comment,
    required this.profile,
    required this.relativeTime,
    required this.isOwner,
    required this.busy,
    this.onEdit,
    this.onDelete,
  });

  final String commentUserId;
  final Map<String, dynamic> comment;
  final Map<String, dynamic>? profile;
  final String relativeTime;
  final bool isOwner;
  final bool busy;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

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
        profile?['username']?.toString() ??
        comment['username']?.toString() ??
        'Unknown';
    final avatarUrl = profile?['avatar_url']?.toString();
    final text = comment['comment_text']?.toString() ?? '';
    final uid = commentUserId.trim();

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
                    if (relativeTime.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          relativeTime,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (busy)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: Padding(
                          padding: EdgeInsets.all(2),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if (isOwner && onEdit != null && onDelete != null)
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
                          if (value == 'edit') onEdit!();
                          if (value == 'delete') onDelete!();
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
