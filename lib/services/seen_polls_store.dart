import 'package:shared_preferences/shared_preferences.dart';

/// Persists recently surfaced poll IDs so "For You" can avoid repeats (FIFO cap [maxStored]).
class SeenPollsStore {
  SeenPollsStore._();

  static final SeenPollsStore instance = SeenPollsStore._();

  static const String _key = 'feed_seen_poll_ids_v1';
  static const int maxStored = 200;

  List<String>? _cache;

  Future<List<String>> _loadList() async {
    if (_cache != null) return List<String>.from(_cache!);
    final prefs = await SharedPreferences.getInstance();
    _cache = List<String>.from(prefs.getStringList(_key) ?? []);
    return List<String>.from(_cache!);
  }

  Future<Set<String>> seenIds() async {
    final list = await _loadList();
    return list.toSet();
  }

  Future<void> markPollsSeen(Iterable<String> pollIds) async {
    var list = await _loadList();
    for (final raw in pollIds) {
      final id = raw.trim();
      if (id.isEmpty) continue;
      list.remove(id);
      list.add(id);
    }
    while (list.length > maxStored) {
      list.removeAt(0);
    }
    _cache = list;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, list);
  }
}
