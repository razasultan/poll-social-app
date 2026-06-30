import 'package:shared_preferences/shared_preferences.dart';

/// Persists the opaque anonymous-voter session token issued by the
/// `vote-anonymous` Edge Function, so a guest's later votes (and the
/// function's own server-side dedup) can recognize repeat visits from the
/// same device/browser.
class AnonVoteSessionStore {
  AnonVoteSessionStore._();

  static final AnonVoteSessionStore instance = AnonVoteSessionStore._();

  static const String _key = 'anon_vote_session_id_v1';

  String? _cache;

  Future<String?> read() async {
    if (_cache != null) return _cache;
    final prefs = await SharedPreferences.getInstance();
    _cache = prefs.getString(_key);
    return _cache;
  }

  Future<void> save(String anonSessionId) async {
    _cache = anonSessionId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, anonSessionId);
  }
}
