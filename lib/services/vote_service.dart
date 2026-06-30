import 'package:supabase_flutter/supabase_flutter.dart';

import 'anon_vote_session_store.dart';

/// Thrown when the `vote-anonymous` Edge Function reports the caller
/// already voted on this poll (matched by session token or IP), so callers
/// can show the same "already voted" UX as the authenticated duplicate-vote
/// path without parsing error bodies themselves.
class AlreadyVotedException implements Exception {}

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

  /// Votes as an unauthenticated visitor via the `vote-anonymous` Edge
  /// Function, which applies its own server-side dedup since RLS has no
  /// path for anon INSERTs into `votes`. Persists the session token the
  /// function issues (or echoes back the one already stored) so repeat
  /// visits are recognized.
  Future<void> voteAnonymous({
    required String pollId,
    required String optionId,
  }) async {
    final existingSessionId = await AnonVoteSessionStore.instance.read();

    final response = await _supabase.functions.invoke(
      'vote-anonymous',
      body: {
        'pollId': pollId,
        'optionId': optionId,
        'anonSessionId': ?existingSessionId,
      },
    );

    final data = response.data;
    final anonSessionId = data is Map
        ? data['anonSessionId']?.toString()
        : null;
    if (anonSessionId != null && anonSessionId.isNotEmpty) {
      await AnonVoteSessionStore.instance.save(anonSessionId);
    }

    if (response.status != 200) {
      final error = data is Map ? data['error']?.toString() : null;
      if (error == 'already_voted') throw AlreadyVotedException();
      throw Exception(error ?? 'Could not submit vote.');
    }
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

  /// Mirrors [getUserVote] for an anonymous voter, keyed by their persisted
  /// session token instead of a user id. Plain SELECT - `votes` rows are
  /// readable by everyone via RLS, so no Edge Function round-trip is needed.
  Future<dynamic> getAnonVote({
    required String pollId,
    required String anonSessionId,
  }) async {
    final response = await _supabase
        .from('votes')
        .select()
        .eq('poll_id', pollId)
        .eq('anon_session_id', anonSessionId)
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
