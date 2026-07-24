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
    String mediaLayout = 'scrim',
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
          'media_layout': mediaLayout,
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
      final id = await _supabase.rpc(
        'get_or_create_hashtag',
        params: {'tag_name': cleaned},
      );
      if (id != null) hashtagIds.add(id.toString());
    }
    if (hashtagIds.isEmpty) return;
    final rows = hashtagIds
        .map((hashtagId) => {'poll_id': pollId, 'hashtag_id': hashtagId})
        .toList();
    await _supabase.from('poll_hashtags').insert(rows);
  }

  /// Extracts the storage object path from a Supabase public URL so old
  /// files can be deleted with [StorageFileApi.remove].
  /// e.g. `https://.../poll-media/userId/pollId/file.mp4` → `userId/pollId/file.mp4`
  static String? _storagePathFromUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    const marker = '/poll-media/';
    final cleanUrl = url.split('?').first; // strip any cache-bust query params
    final idx = cleanUrl.indexOf(marker);
    if (idx < 0) return null;
    return cleanUrl.substring(idx + marker.length);
  }

  /// Silently removes a file from the poll-media bucket. Non-fatal — if the
  /// file is already gone or the path is invalid, the error is swallowed so
  /// the caller's main operation isn't blocked.
  Future<void> _deleteStorageFile(String? url) async {
    final path = _storagePathFromUrl(url);
    if (path == null || path.isEmpty) return;
    try {
      await _supabase.storage.from('poll-media').remove([path]);
    } catch (_) {
      // Best-effort; orphaned storage files are non-critical.
    }
  }

  /// Returns a storage-safe filename: keeps only [a-zA-Z0-9._-], replaces
  /// everything else (spaces, emojis, &, etc.) with underscores, and
  /// prepends a millisecond timestamp so each upload is unique (cache-bust).
  static String _safeFileName(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    final ext = dotIndex >= 0
        ? fileName.substring(dotIndex + 1).toLowerCase()
        : 'bin';
    final base = dotIndex >= 0 ? fileName.substring(0, dotIndex) : fileName;
    final safeBase = base.replaceAll(RegExp(r'[^\w\-]'), '_');
    return '${DateTime.now().millisecondsSinceEpoch}_$safeBase.$ext';
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
    final path = '$userId/$pollId/${_safeFileName(fileName)}';
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

  /// Uploads [bytes] for the option at [optionOrder] (1-based, matching
  /// `poll_options.option_order`) to the `poll-media` bucket under
  /// `{userId}/{pollId}/option-{optionId}/{fileName}`, then records the
  /// public URL on that option's `media_url`/`media_type`.
  Future<void> uploadOptionMedia({
    required String userId,
    required String pollId,
    required int optionOrder,
    required Uint8List bytes,
    required String fileName,
    required String mediaType,
  }) async {
    final option = await _supabase
        .from('poll_options')
        .select('id')
        .eq('poll_id', pollId)
        .eq('option_order', optionOrder)
        .maybeSingle();
    final optionId = option?['id']?.toString();
    if (optionId == null) return;

    final path = '$userId/$pollId/option-$optionId/${_safeFileName(fileName)}';
    final storage = _supabase.storage.from('poll-media');
    await storage.uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(upsert: true),
    );
    final mediaUrl = storage.getPublicUrl(path);

    await _supabase
        .from('poll_options')
        .update({'media_url': mediaUrl, 'media_type': mediaType})
        .eq('id', optionId);
  }

  Future<void> updatePoll({
    required String pollId,
    required String question,
    String? description,
    required String visibility,
    DateTime? expiresAt,
    bool clearExpiry = false,
    String? mediaLayout,
  }) async {
    await _supabase
        .from('polls')
        .update({
          'question': question,
          'description': description?.isEmpty == true ? null : description,
          'visibility': visibility,
          'expires_at': clearExpiry ? null : expiresAt?.toIso8601String(),
          if (mediaLayout != null) 'media_layout': mediaLayout,
        })
        .eq('id', pollId);
  }

  Future<void> updatePollOptionText({
    required String optionId,
    required String optionText,
  }) async {
    await _supabase
        .from('poll_options')
        .update({'option_text': optionText})
        .eq('id', optionId);
  }

  /// Replaces (or sets for the first time) the poll-level attached media.
  /// Deletes any existing [poll_media] rows for the poll first, then uploads
  /// and inserts a fresh row so there is always at most one poll-level media.
  Future<void> replacePollMedia({
    required String userId,
    required String pollId,
    required Uint8List bytes,
    required String fileName,
    required String mediaType,
  }) async {
    // Fetch old URL before deleting the row so we can clean up storage too.
    final existing = await _supabase
        .from('poll_media')
        .select('media_url')
        .eq('poll_id', pollId)
        .maybeSingle();
    await _supabase.from('poll_media').delete().eq('poll_id', pollId);
    await _deleteStorageFile(existing?['media_url']?.toString());
    await uploadPollMedia(
      userId: userId,
      pollId: pollId,
      bytes: bytes,
      fileName: fileName,
      mediaType: mediaType,
    );
  }

  /// Replaces the media for a specific option identified by [optionId].
  Future<void> replaceOptionMedia({
    required String userId,
    required String pollId,
    required String optionId,
    required Uint8List bytes,
    required String fileName,
    required String mediaType,
  }) async {
    // Fetch old URL so we can clean up the storage file after upload.
    final existing = await _supabase
        .from('poll_options')
        .select('media_url')
        .eq('id', optionId)
        .maybeSingle();
    final path = '$userId/$pollId/option-$optionId/${_safeFileName(fileName)}';
    final storage = _supabase.storage.from('poll-media');
    await storage.uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(upsert: true),
    );
    final mediaUrl = storage.getPublicUrl(path);
    await _supabase
        .from('poll_options')
        .update({'media_url': mediaUrl, 'media_type': mediaType})
        .eq('id', optionId);
    await _deleteStorageFile(existing?['media_url']?.toString());
  }

  /// Removes the media for a specific option (clears media_url/media_type
  /// in the DB and deletes the file from storage).
  Future<void> removeOptionMedia({required String optionId}) async {
    final existing = await _supabase
        .from('poll_options')
        .select('media_url')
        .eq('id', optionId)
        .maybeSingle();
    await _supabase
        .from('poll_options')
        .update({'media_url': null, 'media_type': null})
        .eq('id', optionId);
    await _deleteStorageFile(existing?['media_url']?.toString());
  }

  /// Removes all poll-level attached media rows for [pollId] and deletes
  /// the corresponding files from storage.
  Future<void> removePollMedia({required String pollId}) async {
    final rows = await _supabase
        .from('poll_media')
        .select('media_url')
        .eq('poll_id', pollId);
    await _supabase.from('poll_media').delete().eq('poll_id', pollId);
    for (final row in rows) {
      await _deleteStorageFile(row['media_url']?.toString());
    }
  }

  /// Returns the total number of votes cast on [pollId].
  /// Used by the edit screen to decide whether option text is locked.
  Future<int> getPollVoteCount(String pollId) async {
    final rows = await _supabase
        .from('votes')
        .select('id')
        .eq('poll_id', pollId);
    return rows.length;
  }

  Future<void> deletePoll(String pollId) async {
    await _supabase.from('polls').delete().eq('id', pollId);
  }

  Future<dynamic> getPollById(String pollId) async {
    return await _supabase
        .from('polls')
        .select('''
          *,
          profiles(username, display_name, avatar_url, bio),
          poll_options(id, option_text, option_order, media_url, media_type),
          poll_media(*),
          poll_analytics(*)
        ''')
        .eq('id', pollId)
        .single();
  }

  /// Looks up a poll by its public [shareSlug] (used by the public poll page
  /// at `/p/:shareSlug`). Returns `null` when no poll matches — e.g. an
  /// unknown or mistyped slug.
  Future<dynamic> getPollByShareSlug(String shareSlug) async {
    return await _supabase
        .from('polls')
        .select('''
          *,
          profiles(username, display_name, avatar_url, bio),
          poll_options(id, option_text, option_order, media_url, media_type),
          poll_media(*),
          poll_analytics(*)
        ''')
        .eq('share_slug', shareSlug)
        .maybeSingle();
  }

  // Poll IDs whose view has already been recorded this app session — prevents
  // double-counting when the user navigates away and back to the same poll
  // within one session. Intentionally not persisted across restarts (a restart
  // counts as a new session) and not a SharedPreferences key (analytics
  // precision isn't the goal; avoiding rapid re-fires within a session is).
  static final Set<String> _viewedThisSession = {};

  /// Records a view for [pollId] via the `increment_poll_views` RPC.
  /// No-ops silently if the same poll was already recorded in this session
  /// or if the RPC call fails — analytics misses are non-fatal.
  Future<void> recordView(String pollId) async {
    if (pollId.isEmpty || _viewedThisSession.contains(pollId)) return;
    _viewedThisSession.add(pollId);
    try {
      await _supabase.rpc(
        'increment_poll_views',
        params: {'p_poll_id': pollId},
      );
    } catch (_) {
      _viewedThisSession.remove(pollId);
    }
  }

  /// Records a share for [pollId] via the `increment_poll_shares` RPC.
  /// No-ops silently on failure — analytics misses are non-fatal.
  Future<void> recordShare(String pollId) async {
    if (pollId.isEmpty) return;
    try {
      await _supabase.rpc(
        'increment_poll_shares',
        params: {'p_poll_id': pollId},
      );
    } catch (_) {}
  }
}
