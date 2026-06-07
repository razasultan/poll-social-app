import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/notification_service.dart';
import 'poll_detail_screen.dart';

/// Lists notifications for the signed-in user.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationService _notificationService = NotificationService();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _notifications = [];

  RealtimeChannel? _notificationsChannel;

  User? get _user => Supabase.instance.client.auth.currentUser;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _unsubscribeRealtime();
    super.dispose();
  }

  PostgresChangeFilter _userNotificationsFilter(String userId) {
    return PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'user_id',
      value: userId,
    );
  }

  void _unsubscribeRealtime() {
    _notificationsChannel?.unsubscribe();
    _notificationsChannel = null;
  }

  void _subscribeRealtime(String userId) {
    _unsubscribeRealtime();
    final filter = _userNotificationsFilter(userId);

    final channel =
        Supabase.instance.client.channel('notifications-screen-$userId');

    channel
        .onPostgresChanges(
          schema: 'public',
          table: 'notifications',
          event: PostgresChangeEvent.insert,
          filter: filter,
          callback: _onRealtimeInsert,
        )
        .onPostgresChanges(
          schema: 'public',
          table: 'notifications',
          event: PostgresChangeEvent.update,
          filter: filter,
          callback: _onRealtimeUpdate,
        );

    channel.subscribe();
    _notificationsChannel = channel;
  }

  void _onRealtimeInsert(PostgresChangePayload payload) {
    if (!mounted) return;
    final row = _asMap(payload.newRecord);
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() {
      if (!_notifications.any((n) => n['id']?.toString() == id)) {
        _notifications = [row, ..._notifications];
      }
    });
  }

  void _onRealtimeUpdate(PostgresChangePayload payload) {
    if (!mounted) return;
    final row = _asMap(payload.newRecord);
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() {
      final idx = _notifications.indexWhere((n) => n['id']?.toString() == id);
      if (idx >= 0) {
        _notifications[idx] = {..._notifications[idx], ...row};
      }
    });
  }

  Map<String, dynamic> _asMap(dynamic row) {
    if (row is Map<String, dynamic>) return row;
    if (row is Map) return Map<String, dynamic>.from(row);
    return {};
  }

  Future<void> _load() async {
    final user = _user;
    if (user == null) {
      _unsubscribeRealtime();
      setState(() {
        _loading = false;
        _notifications = [];
        _error = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final raw = await _notificationService.getNotifications(user.id);
      final list = <Map<String, dynamic>>[];
      for (final r in raw) {
        list.add(_asMap(r));
      }
      if (!mounted) return;
      setState(() {
        _notifications = list;
        _loading = false;
      });
      _subscribeRealtime(user.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is PostgrestException && e.message.isNotEmpty
            ? e.message
            : 'Could not load notifications.';
      });
    }
  }

  Future<void> _markAllRead() async {
    final user = _user;
    if (user == null || _notifications.isEmpty) return;

    try {
      await _notificationService.markAllAsRead(user.id);
      if (!mounted) return;
      setState(() {
        _notifications = [
          for (final n in _notifications) {...n, 'is_read': true},
        ];
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message.isNotEmpty ? e.message : 'Could not update')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Network error. Try again.')),
      );
    }
  }

  Future<void> _onTapNotification(Map<String, dynamic> item) async {
    final id = item['id']?.toString();
    final wasUnread = id != null && id.isNotEmpty && !_isRead(item);

    if (wasUnread) {
      try {
        await _notificationService.markAsRead(id);
        if (!mounted) return;
        final idx = _notifications.indexWhere((n) => n['id']?.toString() == id);
        if (idx >= 0) {
          setState(() {
            _notifications[idx] = {..._notifications[idx], 'is_read': true};
          });
        }
      } on PostgrestException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message.isNotEmpty ? e.message : 'Could not update')),
        );
        return;
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Network error. Try again.')),
        );
        return;
      }
    }

    final pollId = item['related_poll_id']?.toString() ?? item['poll_id']?.toString();
    if (!mounted) return;
    if (pollId != null && pollId.isNotEmpty) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => PollDetailScreen(pollId: pollId),
        ),
      );
    }
  }

  bool _isRead(Map<String, dynamic> n) {
    final v = n['is_read'];
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v?.toString().toLowerCase();
    return s == 'true' || s == 't' || s == '1';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final user = _user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (user != null && _notifications.isNotEmpty)
            TextButton(
              onPressed: _markAllRead,
              child: Text(
                'Mark all read',
                style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
      body: user == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Please sign in',
                  style: theme.textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            FilledButton.tonal(onPressed: _load, child: const Text('Retry')),
                          ],
                        ),
                      ),
                    )
                  : _notifications.isEmpty
                      ? Center(
                          child: Text(
                            'No notifications yet',
                            style: theme.textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: _notifications.length,
                            separatorBuilder: (_, _) => Divider(
                              height: 1,
                              indent: 72,
                              color: cs.outlineVariant.withValues(alpha: 0.4),
                            ),
                            itemBuilder: (context, index) {
                              return _NotificationTile(
                                item: _notifications[index],
                                isRead: _isRead(_notifications[index]),
                                onTap: () => _onTapNotification(_notifications[index]),
                              );
                            },
                          ),
                        ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.isRead,
    required this.onTap,
  });

  final Map<String, dynamic> item;
  final bool isRead;
  final VoidCallback onTap;

  static String _type(Map<String, dynamic> item) {
    final t = item['type'] ?? item['notification_type'];
    return t?.toString().toLowerCase().trim() ?? 'system';
  }

  static IconData _iconForType(String type) {
    switch (type) {
      case 'vote':
      case 'votes':
        return Icons.how_to_vote_outlined;
      case 'like':
      case 'likes':
        return Icons.favorite_outline_rounded;
      case 'comment':
      case 'comments':
        return Icons.chat_bubble_outline_rounded;
      case 'follow':
      case 'follows':
        return Icons.person_add_alt_1_outlined;
      case 'system':
      default:
        return Icons.notifications_outlined;
    }
  }

  static String _title(Map<String, dynamic> item) {
    return item['title']?.toString().trim().isNotEmpty == true
        ? item['title'].toString().trim()
        : 'Notification';
  }

  static String _message(Map<String, dynamic> item) {
    final m = item['message'] ?? item['body'] ?? item['content'];
    return m?.toString().trim() ?? '';
  }

  static String _relativeTime(dynamic createdAt) {
    if (createdAt == null) return '';
    DateTime? at;
    if (createdAt is DateTime) {
      at = createdAt;
    } else {
      at = DateTime.tryParse(createdAt.toString());
    }
    if (at == null) return '';
    final diff = DateTime.now().difference(at);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final type = _type(item);
    final title = _title(item);
    final message = _message(item);
    final time = _relativeTime(item['created_at']);

    return Material(
      color: isRead ? Colors.transparent : cs.primary.withValues(alpha: 0.06),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: cs.surfaceContainerHighest,
                    child: Icon(_iconForType(type), color: cs.primary, size: 22),
                  ),
                  if (!isRead)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: cs.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: cs.surface, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: isRead ? FontWeight.w600 : FontWeight.w700,
                      ),
                    ),
                    if (message.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        message,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (time.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        time,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
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
