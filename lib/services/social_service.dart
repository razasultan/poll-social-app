import 'package:supabase_flutter/supabase_flutter.dart';

/// Groups a flat, chronologically-ordered list of comment maps (as returned
/// by a Supabase `.select()`) into a two-level tree. Each top-level comment
/// map gains a `'replies'` key holding its direct replies in the same order
/// they appear in [flat]. Only one level of nesting is supported — replies
/// cannot themselves have sub-replies (matching Instagram/X/Reddit patterns).
/// Orphan replies (whose parent id matches no top-level comment, e.g. because
/// the parent was deleted) are silently dropped. Exposed as a top-level
/// function so it can be unit-tested without a live Supabase backend.
List<Map<String, dynamic>> groupCommentsIntoThread(
  List<Map<String, dynamic>> flat,
) {
  // Single pass: bucket into top-level vs. reply maps. The input is already
  // chronologically sorted so both buckets are implicitly ordered correctly.
  final replyMap = <String, List<Map<String, dynamic>>>{};
  final topLevel = <Map<String, dynamic>>[];

  for (final c in flat) {
    final parentId = c['parent_comment_id']?.toString();
    if (parentId == null || parentId.isEmpty) {
      topLevel.add({...c, 'replies': <Map<String, dynamic>>[]});
    } else {
      replyMap.putIfAbsent(parentId, () => []).add(c);
    }
  }

  for (final top in topLevel) {
    final id = top['id']?.toString();
    if (id != null && replyMap.containsKey(id)) {
      top['replies'] = replyMap[id]!;
    }
  }

  return topLevel;
}

class SocialService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> followUser({
    required String followerId,
    required String followingId,
  }) async {
    await _supabase.from('follows').insert({
      'follower_id': followerId,
      'following_id': followingId,
    });
  }

  Future<void> unfollowUser({
    required String followerId,
    required String followingId,
  }) async {
    await _supabase
        .from('follows')
        .delete()
        .eq('follower_id', followerId)
        .eq('following_id', followingId);
  }

  Future<bool> isFollowing({
    required String followerId,
    required String followingId,
  }) async {
    final row = await _supabase
        .from('follows')
        .select('follower_id')
        .eq('follower_id', followerId)
        .eq('following_id', followingId)
        .maybeSingle();
    return row != null;
  }

  /// Whether [followerId] follows [followingId].
  Future<bool> getFollowStatus({
    required String followerId,
    required String followingId,
  }) => isFollowing(followerId: followerId, followingId: followingId);

  /// How many accounts follow [userId]. Returns 0 if the query fails (e.g. RLS).
  Future<int> getFollowersCount(String userId) async {
    try {
      final rows = await _supabase
          .from('follows')
          .select('follower_id')
          .eq('following_id', userId);
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  /// How many accounts [userId] follows. Returns 0 if the query fails (e.g. RLS).
  Future<int> getFollowingCount(String userId) async {
    try {
      final rows = await _supabase
          .from('follows')
          .select('following_id')
          .eq('follower_id', userId);
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  /// A handful of profiles [currentUserId] doesn't already follow, for the
  /// "You might like" suggestions rail. Returns an empty list on failure
  /// (e.g. RLS) rather than throwing.
  Future<List<Map<String, dynamic>>> getSuggestedUsers({
    required String? currentUserId,
    int limit = 3,
  }) async {
    try {
      final excludeIds = <String>{};
      if (currentUserId != null) {
        excludeIds.add(currentUserId);
        final following = await _supabase
            .from('follows')
            .select('following_id')
            .eq('follower_id', currentUserId);
        for (final row in following) {
          final id = (row as Map)['following_id']?.toString();
          if (id != null) excludeIds.add(id);
        }
      }

      var query = _supabase
          .from('profiles')
          .select('id, username, display_name, avatar_url, bio');
      if (excludeIds.isNotEmpty) {
        query = query.not('id', 'in', '(${excludeIds.join(',')})');
      }
      final rows = await query
          .order('created_at', ascending: false)
          .limit(limit);
      return rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Alias for [getFollowersCount].
  Future<int> countFollowers(String userId) => getFollowersCount(userId);

  /// Alias for [getFollowingCount].
  Future<int> countFollowing(String userId) => getFollowingCount(userId);

  Future<void> likePoll({
    required String pollId,
    required String userId,
  }) async {
    await _supabase.from('likes').insert({
      'poll_id': pollId,
      'user_id': userId,
    });
  }

  Future<void> unlikePoll({
    required String pollId,
    required String userId,
  }) async {
    await _supabase
        .from('likes')
        .delete()
        .eq('poll_id', pollId)
        .eq('user_id', userId);
  }

  /// Returns the like row if present; otherwise null.
  Future<dynamic> getUserLike({
    required String pollId,
    required String userId,
  }) async {
    return _supabase
        .from('likes')
        .select()
        .eq('poll_id', pollId)
        .eq('user_id', userId)
        .maybeSingle();
  }

  /// Polls [userId] has liked, most-recently-liked first, in the same shape
  /// PollCard expects (each row wraps the poll under `polls`).
  Future<List<dynamic>> getLikedPollsForUser(String userId) async {
    return await _supabase
        .from('likes')
        .select('''
          created_at,
          polls(
            id,
            user_id,
            question,
            description,
            created_at,
            expires_at,
            visibility,
            share_slug,
            allow_embedding,
            country,
            city,
            profiles(username, display_name, avatar_url),
            poll_options(id, option_text, option_order, media_url, media_type),
            poll_media(media_type, media_url, thumbnail_url),
            poll_analytics(votes_count, likes_count, comments_count, shares_count)
          )
        ''')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
  }

  Future<void> addComment({
    required String pollId,
    required String userId,
    required String commentText,
    String? parentCommentId,
  }) async {
    await _supabase.from('comments').insert({
      'poll_id': pollId,
      'user_id': userId,
      'comment_text': commentText,
      'parent_comment_id': parentCommentId,
    });
  }

  Future<List<dynamic>> getComments(String pollId) async {
    return await _supabase
        .from('comments')
        .select('*, profiles(username, display_name, avatar_url)')
        .eq('poll_id', pollId)
        .eq('status', 'active')
        .order('created_at', ascending: true);
  }

  /// Fetches all active comments for [pollId] in one ordered query and
  /// groups them into a two-level tree via [groupCommentsIntoThread].
  Future<List<Map<String, dynamic>>> getCommentThread(String pollId) async {
    final flat = await _supabase
        .from('comments')
        .select('*, profiles(username, display_name, avatar_url)')
        .eq('poll_id', pollId)
        .eq('status', 'active')
        .order('created_at', ascending: true);

    return groupCommentsIntoThread(flat);
  }

  Future<void> updateComment({
    required String commentId,
    required String userId,
    required String commentText,
  }) async {
    final updated = await _supabase
        .from('comments')
        .update({'comment_text': commentText})
        .eq('id', commentId)
        .eq('user_id', userId)
        .select('id');
    if (updated.isEmpty) {
      throw StateError(
        'Comment not found or you do not have permission to edit it.',
      );
    }
  }

  /// Removes the row. Prefer this over soft-delete when RLS allows DELETE but blocks
  /// UPDATE that sets `status` away from `active`.
  ///
  /// Without `.select()`, a 0-row delete (wrong/stale id, already deleted,
  /// not the owner) returns the same success response as a 1-row delete —
  /// the caller would show "Comment deleted" even though nothing happened.
  Future<void> deleteComment({
    required String commentId,
    required String userId,
  }) async {
    final deleted = await _supabase
        .from('comments')
        .delete()
        .eq('id', commentId)
        .eq('user_id', userId)
        .select('id');
    if (deleted.isEmpty) {
      throw StateError(
        'Comment not found or you do not have permission to delete it.',
      );
    }
  }

  // TODO: reportComment via ModerationService when target_type for comments is defined.
}
