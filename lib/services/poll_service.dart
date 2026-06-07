import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class PollService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<dynamic> createPoll({
    required String userId,
    required String question,
    String? description,
    required List<String> options,
    String pollType = 'single_choice',
    String visibility = 'public',
    String? country,
    String? city,
    DateTime? expiresAt,
  }) async {
    final poll = await _supabase
        .from('polls')
        .insert({
          'user_id': userId,
          'question': question,
          'description': description,
          'poll_type': pollType,
          'visibility': visibility,
          'country': country,
          'city': city,
          'expires_at': expiresAt?.toIso8601String(),
        })
        .select()
        .single();

    final pollId = poll['id'];

    final optionRows = options.asMap().entries.map((entry) {
      return {
        'poll_id': pollId,
        'option_text': entry.value,
        'option_order': entry.key + 1,
      };
    }).toList();

    await _supabase.from('poll_options').insert(optionRows);

    return poll;
  }

  /// Links existing [topicIds] to [pollId] via `poll_topics`.
  Future<void> attachTopics({
    required String pollId,
    required List<String> topicIds,
  }) async {
    if (topicIds.isEmpty) return;
    final rows = topicIds
        .map((topicId) => {'poll_id': pollId, 'topic_id': topicId})
        .toList();
    await _supabase.from('poll_topics').insert(rows);
  }

  /// Normalizes each tag (via the `get_or_create_hashtag` RPC) and links it
  /// to [pollId] via `poll_hashtags`.
  Future<void> attachHashtags({
    required String pollId,
    required List<String> tags,
  }) async {
    if (tags.isEmpty) return;
    final hashtagIds = <String>{};
    for (final tag in tags) {
      final cleaned = tag.trim();
      if (cleaned.isEmpty) continue;
      final id = await _supabase.rpc('get_or_create_hashtag', params: {'tag_name': cleaned});
      if (id != null) hashtagIds.add(id.toString());
    }
    if (hashtagIds.isEmpty) return;
    final rows = hashtagIds
        .map((hashtagId) => {'poll_id': pollId, 'hashtag_id': hashtagId})
        .toList();
    await _supabase.from('poll_hashtags').insert(rows);
  }

  /// Uploads [bytes] to the `poll-media` storage bucket under the owning
  /// user's folder, then records a `poll_media` row pointing at the public URL.
  Future<void> uploadPollMedia({
    required String userId,
    required String pollId,
    required Uint8List bytes,
    required String fileName,
    required String mediaType,
  }) async {
    final path = '$userId/$pollId/$fileName';
    final storage = _supabase.storage.from('poll-media');
    await storage.uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(upsert: true),
    );
    final mediaUrl = storage.getPublicUrl(path);

    await _supabase.from('poll_media').insert({
      'poll_id': pollId,
      'media_type': mediaType,
      'media_url': mediaUrl,
    });
  }

  Future<void> deletePoll(String pollId) async {
    await _supabase.from('polls').delete().eq('id', pollId);
  }

  Future<dynamic> getPollById(String pollId) async {
    return await _supabase
        .from('polls')
        .select('''
          *,
          profiles(username, avatar_url),
          poll_options(id, option_text, option_order),
          poll_media(*),
          poll_analytics(*)
        ''')
        .eq('id', pollId)
        .single();
  }
}