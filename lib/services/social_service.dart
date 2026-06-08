import 'package:supabase_flutter/supabase_flutter.dart';

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
  }) =>
      isFollowing(followerId: followerId, followingId: followingId);

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
      final rows =
          await _supabase.from('follows').select('following_id').eq('follower_id', userId);
      return rows.length;
    } catch (_) {
      return 0;
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

  Future<void> updateComment({
    required String commentId,
    required String userId,
    required String commentText,
  }) async {
    await _supabase
        .from('comments')
        .update({'comment_text': commentText})
        .eq('id', commentId)
        .eq('user_id', userId);
  }

  /// Removes the row. Prefer this over soft-delete when RLS allows DELETE but blocks
  /// UPDATE that sets `status` away from `active`.
  Future<void> deleteComment({
    required String commentId,
    required String userId,
  }) async {
    await _supabase.from('comments').delete().eq('id', commentId).eq('user_id', userId);
  }

  // TODO: reportComment via ModerationService when target_type for comments is defined.
}