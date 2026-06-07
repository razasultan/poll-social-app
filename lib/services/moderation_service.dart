import 'package:supabase_flutter/supabase_flutter.dart';

class ModerationService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> reportContent({
    required String reporterId,
    required String targetType,
    required String targetId,
    required String reason,
    String? details,
  }) async {
    await _supabase.from('reports').insert({
      'reporter_id': reporterId,
      'target_type': targetType,
      'target_id': targetId,
      'reason': reason,
      'details': details,
    });
  }

  Future<void> blockUser({
    required String blockerId,
    required String blockedId,
  }) async {
    await _supabase.from('blocks').insert({
      'blocker_id': blockerId,
      'blocked_id': blockedId,
    });
  }

  Future<void> unblockUser({
    required String blockerId,
    required String blockedId,
  }) async {
    await _supabase
        .from('blocks')
        .delete()
        .eq('blocker_id', blockerId)
        .eq('blocked_id', blockedId);
  }

  Future<List<dynamic>> getBlockedUsers(String userId) async {
    return await _supabase
        .from('blocks')
        .select('blocked_id, profiles!blocks_blocked_id_fkey(username, avatar_url)')
        .eq('blocker_id', userId);
  }
}