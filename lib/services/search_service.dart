import 'package:supabase_flutter/supabase_flutter.dart';

class SearchService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<dynamic>> searchPolls(String query) async {
    return await _supabase.rpc('search_polls', params: {'search_text': query});
  }

  Future<List<dynamic>> searchUsers(String query) async {
    return await _supabase.rpc('search_users', params: {'search_text': query});
  }

  Future<List<dynamic>> searchHashtags(String query) async {
    return await _supabase.rpc(
      'search_hashtags',
      params: {'search_text': query},
    );
  }

  Future<List<dynamic>> searchTopics(String query) async {
    return await _supabase.rpc('search_topics', params: {'search_text': query});
  }
}
