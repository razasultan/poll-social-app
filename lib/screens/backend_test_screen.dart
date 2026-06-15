// TEMP: Developer-only Supabase backend verification screen. Safe to delete.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/feed_service.dart';
import '../services/moderation_service.dart';
import '../services/notification_service.dart';
import '../services/poll_service.dart';
import '../services/profile_service.dart';
import '../services/search_service.dart';
import '../services/social_service.dart';
import '../services/vote_service.dart';

/// Temporary screen to exercise all Supabase-backed services via buttons + logs.
class BackendTestScreen extends StatefulWidget {
  const BackendTestScreen({super.key});

  @override
  State<BackendTestScreen> createState() => _BackendTestScreenState();
}

class _BackendTestScreenState extends State<BackendTestScreen> {
  final ScrollController _logScroll = ScrollController();

  final AuthService _authService = AuthService();
  final ProfileService _profileService = ProfileService();
  final PollService _pollService = PollService();
  final VoteService _voteService = VoteService();
  final FeedService _feedService = FeedService();
  final SocialService _socialService = SocialService();
  final SearchService _searchService = SearchService();
  final ModerationService _moderationService = ModerationService();
  final NotificationService _notificationService = NotificationService();

  final StringBuffer _logBuffer = StringBuffer();

  /// Last poll used for vote / like / comment / report (from latest feed or create flow).
  dynamic _latestPoll;

  User? get _user => Supabase.instance.client.auth.currentUser;

  @override
  void dispose() {
    _logScroll.dispose();
    super.dispose();
  }

  void _appendLog(String line) {
    setState(() {
      _logBuffer.writeln(line);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
      }
    });
  }

  void _logSuccess(String action, Object? data) {
    _appendLog('[OK] $action\n$data');
  }

  void _logError(String action, Object e, StackTrace st) {
    _appendLog('[ERR] $action\n$e\n$st');
  }

  String? _guardSignedIn() {
    final user = _user;
    if (user == null) {
      _appendLog('Please sign in first.');
      return null;
    }
    return user.id;
  }

  Future<void> _signInTestUser() async {
    try {
      final res = await _authService.signIn(
        email: 'testuser@example.com',
        password: 'Test123456!',
      );
      final u = res.session?.user ?? res.user;
      _logSuccess('Sign in test user', {'id': u?.id, 'email': u?.email});
    } catch (e, st) {
      _logError('Sign in test user', e, st);
    }
  }

  Future<void> _fetchProfile() async {
    final userId = _guardSignedIn();
    if (userId == null) return;
    try {
      final profile = await _profileService.getProfile(userId);
      _logSuccess('Fetch current profile', profile);
    } catch (e, st) {
      _logError('Fetch current profile', e, st);
    }
  }

  Future<void> _createTestPoll() async {
    final userId = _guardSignedIn();
    if (userId == null) return;
    try {
      final poll = await _pollService.createPoll(
        userId: userId,
        question: 'Backend test poll?',
        options: const ['Yes', 'No'],
      );
      final full = await _pollService.getPollById(poll['id'].toString());
      setState(() => _latestPoll = full);
      _logSuccess('Create test poll', full);
    } catch (e, st) {
      if (e is PostgrestException && e.message.contains('poll_analytics')) {
        _appendLog(
          '[ERR] Create test poll\n'
          '$e\n'
          'Note: Inserts are only to polls/poll_options from the app. If the DB '
          'creates poll_analytics via a trigger, allow that row under RLS for the '
          'poll owner or run that insert as SECURITY DEFINER in Postgres.',
        );
      } else {
        _logError('Create test poll', e, st);
      }
    }
  }

  Future<void> _fetchLatestFeed() async {
    try {
      final list = await _feedService.getLatestFeed();
      if (list.isNotEmpty) {
        setState(() => _latestPoll = list.first);
      }
      _logSuccess('Fetch latest feed (count=${list.length})', list);
    } catch (e, st) {
      _logError('Fetch latest feed', e, st);
    }
  }

  Future<void> _fetchTrendingFeed() async {
    try {
      final list = await _feedService.getTrendingFeed();
      _logSuccess('Fetch trending feed (count=${list.length})', list);
    } catch (e, st) {
      _logError('Fetch trending feed', e, st);
    }
  }

  Future<void> _voteLatestOption() async {
    final userId = _guardSignedIn();
    if (userId == null) return;
    final poll = _latestPoll;
    if (poll == null) {
      _appendLog(
        '[SKIP] No latest poll cached. Fetch latest feed or create a poll first.',
      );
      return;
    }
    try {
      final pollId = poll['id']?.toString();
      final options = poll['poll_options'] as List<dynamic>?;
      if (pollId == null || options == null || options.isEmpty) {
        _appendLog(
          '[SKIP] Latest poll has no options. Fetch latest feed or create a poll.',
        );
        return;
      }
      final optionId = options.first['id']?.toString();
      if (optionId == null) {
        _appendLog('[SKIP] Could not read option id.');
        return;
      }
      final existingVote = await _voteService.getUserVote(
        pollId: pollId,
        userId: userId,
      );
      if (existingVote != null) {
        _appendLog(
          '[SKIP] Already voted on this poll. Existing vote: $existingVote',
        );
        return;
      }
      await _voteService.vote(
        pollId: pollId,
        optionId: optionId,
        userId: userId,
      );
      _logSuccess('Vote on latest poll option', {
        'poll_id': pollId,
        'option_id': optionId,
      });
    } catch (e, st) {
      if (e is PostgrestException && e.code == '23505') {
        _appendLog('[SKIP] Duplicate vote (already voted on this poll).');
      } else {
        _logError('Vote on latest poll option', e, st);
      }
    }
  }

  Future<void> _likeLatestPoll() async {
    final userId = _guardSignedIn();
    if (userId == null) return;
    final poll = _latestPoll;
    if (poll == null) {
      _appendLog('[SKIP] No latest poll cached.');
      return;
    }
    try {
      final pollId = poll['id']?.toString();
      if (pollId == null) {
        _appendLog('[SKIP] Missing poll id.');
        return;
      }
      await _socialService.likePoll(pollId: pollId, userId: userId);
      _logSuccess('Like latest poll', pollId);
    } catch (e, st) {
      _logError('Like latest poll', e, st);
    }
  }

  Future<void> _unlikeLatestPoll() async {
    final userId = _guardSignedIn();
    if (userId == null) return;
    final poll = _latestPoll;
    if (poll == null) {
      _appendLog('[SKIP] No latest poll cached.');
      return;
    }
    try {
      final pollId = poll['id']?.toString();
      if (pollId == null) {
        _appendLog('[SKIP] Missing poll id.');
        return;
      }
      await _socialService.unlikePoll(pollId: pollId, userId: userId);
      _logSuccess('Unlike latest poll', pollId);
    } catch (e, st) {
      _logError('Unlike latest poll', e, st);
    }
  }

  Future<void> _addCommentLatest() async {
    final userId = _guardSignedIn();
    if (userId == null) return;
    final poll = _latestPoll;
    if (poll == null) {
      _appendLog('[SKIP] No latest poll cached.');
      return;
    }
    try {
      final pollId = poll['id']?.toString();
      if (pollId == null) {
        _appendLog('[SKIP] Missing poll id.');
        return;
      }
      await _socialService.addComment(
        pollId: pollId,
        userId: userId,
        commentText: 'Backend test comment',
      );
      _logSuccess('Add comment to latest poll', pollId);
    } catch (e, st) {
      _logError('Add comment to latest poll', e, st);
    }
  }

  Future<void> _fetchComments() async {
    final poll = _latestPoll;
    if (poll == null) {
      _appendLog('[SKIP] No latest poll cached.');
      return;
    }
    try {
      final pollId = poll['id']?.toString();
      if (pollId == null) {
        _appendLog('[SKIP] Missing poll id.');
        return;
      }
      final comments = await _socialService.getComments(pollId);
      _logSuccess('Fetch comments', comments);
    } catch (e, st) {
      _logError('Fetch comments', e, st);
    }
  }

  Future<void> _searchPolls() async {
    try {
      final rows = await _searchService.searchPolls('test');
      _logSuccess('Search polls', rows);
    } catch (e, st) {
      _logError('Search polls', e, st);
    }
  }

  Future<void> _searchUsers() async {
    try {
      final rows = await _searchService.searchUsers('test');
      _logSuccess('Search users', rows);
    } catch (e, st) {
      _logError('Search users', e, st);
    }
  }

  Future<void> _reportLatestPoll() async {
    final userId = _guardSignedIn();
    if (userId == null) return;
    final poll = _latestPoll;
    if (poll == null) {
      _appendLog('[SKIP] No latest poll cached.');
      return;
    }
    try {
      final pollId = poll['id']?.toString();
      if (pollId == null) {
        _appendLog('[SKIP] Missing poll id.');
        return;
      }
      await _moderationService.reportContent(
        reporterId: userId,
        targetType: 'poll',
        targetId: pollId,
        reason: 'backend_test',
        details: 'Automated backend test report',
      );
      _logSuccess('Report latest poll', pollId);
    } catch (e, st) {
      _logError('Report latest poll', e, st);
    }
  }

  Future<void> _blockTestUser() async {
    final userId = _guardSignedIn();
    if (userId == null) return;
    try {
      final rows = await _searchService.searchUsers('test');
      String? blockedId;
      for (final row in rows) {
        if (row is! Map) continue;
        final map = Map<String, dynamic>.from(row);
        final id = map['id']?.toString();
        if (id != null && id != userId) {
          blockedId = id;
          break;
        }
      }
      if (blockedId == null) {
        _appendLog('[SKIP] No other user found via search "test" to block.');
        return;
      }
      await _moderationService.blockUser(
        blockerId: userId,
        blockedId: blockedId,
      );
      _logSuccess('Block test user', {'blocked_id': blockedId});
    } catch (e, st) {
      _logError('Block test user', e, st);
    }
  }

  Future<void> _fetchNotifications() async {
    final userId = _guardSignedIn();
    if (userId == null) return;
    try {
      final list = await _notificationService.getNotifications(userId);
      _logSuccess('Fetch notifications', list);
    } catch (e, st) {
      _logError('Fetch notifications', e, st);
    }
  }

  Widget _actionButton(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: ElevatedButton(onPressed: onTap, child: Text(label)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backend test (temp)')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                children: [
                  _actionButton('Sign in test user', _signInTestUser),
                  _actionButton('Fetch current profile', _fetchProfile),
                  _actionButton('Create test poll', _createTestPoll),
                  _actionButton('Fetch latest feed', _fetchLatestFeed),
                  _actionButton('Fetch trending feed', _fetchTrendingFeed),
                  _actionButton(
                    'Vote on latest poll option',
                    _voteLatestOption,
                  ),
                  _actionButton('Like latest poll', _likeLatestPoll),
                  _actionButton('Unlike latest poll', _unlikeLatestPoll),
                  _actionButton(
                    'Add comment to latest poll',
                    _addCommentLatest,
                  ),
                  _actionButton('Fetch comments', _fetchComments),
                  _actionButton('Search polls', _searchPolls),
                  _actionButton('Search users', _searchUsers),
                  _actionButton('Report latest poll', _reportLatestPoll),
                  _actionButton('Block test user', _blockTestUser),
                  _actionButton('Fetch notifications', _fetchNotifications),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              padding: const EdgeInsets.all(8),
              alignment: Alignment.topLeft,
              child: SingleChildScrollView(
                controller: _logScroll,
                child: SelectableText(
                  _logBuffer.isEmpty
                      ? 'Logs appear here…'
                      : _logBuffer.toString(),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
