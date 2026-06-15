import 'package:supabase_flutter/supabase_flutter.dart';

class VoteService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> vote({
    required String pollId,
    required String optionId,
    required String userId,
  }) async {
    await _supabase.from('votes').insert({
      'poll_id': pollId,
      'option_id': optionId,
      'user_id': userId,
    });
  }

  Future<dynamic> getUserVote({
    required String pollId,
    required String userId,
  }) async {
    final response = await _supabase
        .from('votes')
        .select()
        .eq('poll_id', pollId)
        .eq('user_id', userId)
        .maybeSingle();

    return response;
  }

  /// Poll IDs in [pollIds] the user has voted on (single batched query per chunk).
  Future<Set<String>> getPollIdsUserHasVoted({
    required String userId,
    required List<String> pollIds,
  }) async {
    if (pollIds.isEmpty) return {};
    const chunkSize = 80;
    final out = <String>{};
    for (var i = 0; i < pollIds.length; i += chunkSize) {
      final end = i + chunkSize > pollIds.length
          ? pollIds.length
          : i + chunkSize;
      final chunk = pollIds.sublist(i, end);
      try {
        final rows = await _supabase
            .from('votes')
            .select('poll_id')
            .eq('user_id', userId)
            .inFilter('poll_id', chunk);
        for (final dynamic row in rows) {
          final m = Map<String, dynamic>.from(row as Map);
          final pid = m['poll_id']?.toString();
          if (pid != null && pid.isNotEmpty) out.add(pid);
        }
      } catch (_) {
        /* ignore chunk */
      }
    }
    return out;
  }

  Future<List<dynamic>> getPollVotes(String pollId) async {
    return await _supabase
        .from('votes')
        .select('option_id')
        .eq('poll_id', pollId);
  }
}
