import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Derives a username candidate from an email's local part, falling back to
/// `user_<id prefix>` when the local part has no usable characters. Pure
/// function extracted for unit testing — mirrors the rule applied by
/// [ProfileService.ensureProfileExists] when no username metadata is
/// available (e.g. OAuth sign-ins).
String usernameBaseFromEmail(String? email, String userId) {
  final local = email?.split('@').first ?? '';
  final sanitized = local.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
  if (sanitized.length >= 2) return sanitized;
  return 'user_${userId.substring(0, 8)}';
}

class ProfileService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<dynamic> createProfile({
    required String id,
    required String username,
    String? displayName,
    String? avatarUrl,
    String? bio,
    String? country,
    String? city,
    String? website,
    DateTime? birthDate,
  }) async {
    return await _supabase
        .from('profiles')
        .insert({
          'id': id,
          'username': username,
          'display_name': displayName,
          'avatar_url': avatarUrl,
          'bio': bio,
          'country': country,
          'city': city,
          'website': website,
          'birth_date': birthDate?.toIso8601String().split('T').first,
        })
        .select()
        .single();
  }

  /// Fetches the profile for [userId]. If it's the signed-in user's own
  /// profile and the row doesn't exist yet — e.g. a race with
  /// [ensureProfileExists] right after the first authenticated load — this
  /// creates it on the fly and retries once, instead of surfacing a
  /// confusing "Cannot coerce the result to a single JSON object" error.
  Future<dynamic> getProfile(String userId) async {
    try {
      return await _supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();
    } on PostgrestException catch (e) {
      final currentUser = _supabase.auth.currentUser;
      if (e.code == 'PGRST116' && currentUser?.id == userId) {
        await ensureProfileExists(currentUser!);
        return await _supabase
            .from('profiles')
            .select()
            .eq('id', userId)
            .single();
      }
      rethrow;
    }
  }

  Future<dynamic> updateProfile({
    required String userId,
    String? username,
    String? displayName,
    String? avatarUrl,
    String? headerUrl,
    String? bio,
    String? country,
    String? city,
    String? website,
    DateTime? birthDate,
    bool clearBirthDate = false,
  }) async {
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (username != null) updates['username'] = username;
    if (displayName != null) updates['display_name'] = displayName;
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
    if (headerUrl != null) updates['header_url'] = headerUrl;
    if (bio != null) updates['bio'] = bio;
    if (country != null) updates['country'] = country;
    if (city != null) updates['city'] = city;
    if (website != null) updates['website'] = website;
    if (clearBirthDate) {
      updates['birth_date'] = null;
    } else if (birthDate != null) {
      updates['birth_date'] = birthDate.toIso8601String().split('T').first;
    }

    return await _supabase
        .from('profiles')
        .update(updates)
        .eq('id', userId)
        .select()
        .single();
  }

  /// Ensures a `profiles` row exists for [user], creating one if missing.
  ///
  /// Fallback for signup flows where the profile couldn't be created at
  /// signup time — e.g. email confirmation deferred the session (so the
  /// insert was blocked by RLS), or the user signed in via OAuth and never
  /// went through the signup form. Uses `user.userMetadata` for
  /// username/display name/country/city when available, falling back to a
  /// username derived from the email.
  Future<void> ensureProfileExists(User user) async {
    final existing = await _supabase
        .from('profiles')
        .select('id')
        .eq('id', user.id)
        .maybeSingle();
    if (existing != null) return;

    final metadata = user.userMetadata ?? {};
    final username = await _resolveAvailableUsername(
      (metadata['username'] as String?)?.trim(),
      user.email,
      user.id,
    );

    String? nonEmpty(String? v) => (v == null || v.isEmpty) ? null : v;

    await createProfile(
      id: user.id,
      username: username,
      displayName: nonEmpty((metadata['display_name'] as String?)?.trim()),
      country: nonEmpty((metadata['country'] as String?)?.trim()),
      city: nonEmpty((metadata['city'] as String?)?.trim()),
    );
  }

  /// Picks a username for the new profile: prefers [requested] if it's
  /// available, else derives one from [email]'s local part (or [userId] as
  /// a last resort), appending a numeric suffix until an available one is
  /// found.
  Future<String> _resolveAvailableUsername(
    String? requested,
    String? email,
    String userId,
  ) async {
    if (requested != null &&
        requested.isNotEmpty &&
        await isUsernameAvailable(requested)) {
      return requested;
    }

    final base = usernameBaseFromEmail(email, userId);
    var candidate = base;
    var suffix = 0;
    while (!await isUsernameAvailable(candidate)) {
      suffix++;
      candidate = '$base$suffix';
    }
    return candidate;
  }

  Future<bool> isUsernameAvailable(String username) async {
    final response = await _supabase
        .from('profiles')
        .select('id')
        .eq('username', username)
        .maybeSingle();

    return response == null;
  }

  /// Resolves a `@username` mention to its profile id, or `null` when no
  /// matching profile exists. Lookup is case-insensitive.
  Future<String?> getUserIdByUsername(String username) async {
    final response = await _supabase
        .from('profiles')
        .select('id')
        .ilike('username', username)
        .maybeSingle();

    return response?['id']?.toString();
  }

  /// Uploads [bytes] as the user's avatar to the `poll-media` bucket under
  /// `{userId}/profile/avatar.{ext}`, saves the public URL on
  /// `profiles.avatar_url`, and returns it. `upsert: true` overwrites any
  /// previous avatar at that fixed path.
  Future<String> uploadAvatar({
    required String userId,
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    final path = '$userId/profile/avatar.$fileExtension';
    final storage = _supabase.storage.from('poll-media');
    await storage.uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(upsert: true),
    );
    final url = storage.getPublicUrl(path);

    await updateProfile(userId: userId, avatarUrl: url);
    return url;
  }

  /// Uploads [bytes] as the user's profile header/cover image to the
  /// `poll-media` bucket under `{userId}/profile/header.{ext}`, saves the
  /// public URL on `profiles.header_url`, and returns it. `upsert: true`
  /// overwrites any previous header at that fixed path.
  Future<String> uploadHeader({
    required String userId,
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    final path = '$userId/profile/header.$fileExtension';
    final storage = _supabase.storage.from('poll-media');
    await storage.uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(upsert: true),
    );
    final url = storage.getPublicUrl(path);

    await updateProfile(userId: userId, headerUrl: url);
    return url;
  }
}
