import 'package:supabase_flutter/supabase_flutter.dart';

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

  Future<dynamic> getProfile(String userId) async {
    return await _supabase.from('profiles').select().eq('id', userId).single();
  }

  Future<dynamic> updateProfile({
    required String userId,
    String? username,
    String? displayName,
    String? avatarUrl,
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
}
