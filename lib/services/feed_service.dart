import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/feed_page.dart';
import 'vote_service.dart';

class FeedService {
  FeedService({SupabaseClient? supabase, VoteService? voteService})
      : _supabase = supabase ?? Supabase.instance.client,
        _voteService = voteService ?? VoteService();

  final SupabaseClient _supabase;
  final VoteService _voteService;

  /// Shared poll payload shape for feed cards.
  static const String _pollFeedSelect = '''
          id,
          user_id,
          question,
          description,
          created_at,
          expires_at,
          visibility,
          share_slug,
          allow_embedding,
          country,
          city,
          profiles(username, display_name, avatar_url),
          poll_options(id, option_text, option_order, media_url, media_type),
          poll_media(media_type, media_url, thumbnail_url),
          poll_analytics(votes_count, likes_count, comments_count, shares_count)
        ''';

  static const int _defaultPageSize = 12;

  /// Score used only for "For You" ranking (Dart-side).
  static double computeForYouScore(
    Map<String, dynamic> poll, {
    required Set<String> followingUserIds,
    required Set<String> votedPollIds,
    required DateTime now,
  }) {
    var s = 0.0;
    final author = poll['user_id']?.toString();
    if (author != null && author.isNotEmpty && followingUserIds.contains(author)) {
      s += 10;
    }
    final id = poll['id']?.toString();
    if (id != null && id.isNotEmpty && !votedPollIds.contains(id)) {
      s += 5;
    }
    s += _votesCount(poll) / 10;
    final hoursOld = now.difference(_pollCreatedAt(poll)).inHours;
    s -= hoursOld / 5;
    return s;
  }

  static int _votesCount(Map<String, dynamic> poll) {
    final raw = poll['poll_analytics'];
    Map<String, dynamic>? m;
    if (raw is Map<String, dynamic>) {
      m = raw;
    } else if (raw is Map) {
      m = Map<String, dynamic>.from(raw);
    } else if (raw is List && raw.isNotEmpty) {
      final first = raw.first;
      if (first is Map<String, dynamic>) {
        m = first;
      } else if (first is Map) {
        m = Map<String, dynamic>.from(first);
      }
    }
    final v = m?['votes_count'];
    if (v is num) return v.round();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  // --- Paginated public feeds -------------------------------------------------

  Future<FeedPage> getLatestFeedPage({int limit = _defaultPageSize, int offset = 0}) async {
    try {
      final want = limit + 1;
      final to = offset + want - 1;
      final rows = await _supabase
          .from('polls')
          .select(_pollFeedSelect)
          .eq('status', 'active')
          .eq('visibility', 'public')
          .order('created_at', ascending: false)
          .range(offset, to);

      final list = _normalizeDynamicList(rows);
      final hasMore = list.length > limit;
      final items = hasMore ? list.sublist(0, limit) : list;
      return FeedPage(items: items, hasMore: hasMore);
    } catch (_) {
      return FeedPage.empty();
    }
  }

  Future<FeedPage> getTrendingFeedPage({int limit = _defaultPageSize, int offset = 0}) async {
    try {
      final want = limit + 1;
      final to = offset + want - 1;
      final rows = await _supabase
          .from('trending_polls')
          .select()
          .order('trending_score', ascending: false)
          .range(offset, to);

      final merged = await _hydrateTrendingRows(rows);
      final hasMore = merged.length > limit;
      final items = hasMore ? merged.sublist(0, limit) : merged;
      return FeedPage(items: List<dynamic>.from(items), hasMore: hasMore);
    } catch (_) {
      return FeedPage.empty();
    }
  }

  /// Personalized page; pass persisted + in-session IDs in [excludePollIds].
  Future<FeedPage> getForYouFeedPage(
    String currentUserId, {
    int limit = _defaultPageSize,
    required Set<String> excludePollIds,
  }) async {
    try {
      final followingIds = await _getFollowingIds(currentUserId);
      final (country, city) = await _getProfileCountryCity(currentUserId);

      final exclude = Set<String>.from(excludePollIds);

      final followingPolls =
          await _fetchFollowingPollsForYou(followingIds, exclude, fetchCap: 48);
      final excludeB = {...exclude, ..._idsOf(followingPolls)};

      final regionalPolls = await _fetchRegionalPollsForYou(country, city, excludeB, fetchCap: 48);
      final excludeC = {...excludeB, ..._idsOf(regionalPolls)};

      final trendingPolls = await _fetchTrendingMapsForYou(excludeC, take: 48);
      final excludeD = {...excludeC, ..._idsOf(trendingPolls)};

      final latestPolls = await _fetchLatestPollsForYou(excludeD, take: 64);

      final pool = <Map<String, dynamic>>[];
      final inPool = <String>{};
      void addPreservingOrder(List<Map<String, dynamic>> bucket) {
        for (final m in bucket) {
          final id = m['id']?.toString();
          if (id == null || id.isEmpty || exclude.contains(id) || inPool.contains(id)) continue;
          inPool.add(id);
          pool.add(m);
        }
      }

      addPreservingOrder(followingPolls);
      addPreservingOrder(regionalPolls);
      addPreservingOrder(trendingPolls);
      addPreservingOrder(latestPolls);

      if (pool.isEmpty) {
        return const FeedPage(items: [], hasMore: false);
      }

      final pollIds = pool.map((m) => m['id']?.toString()).whereType<String>().toList();
      final voted = await _voteService.getPollIdsUserHasVoted(
        userId: currentUserId,
        pollIds: pollIds,
      );

      final followingSet = followingIds.toSet();
      final now = DateTime.now();

      pool.sort((a, b) {
        final sa = computeForYouScore(
          a,
          followingUserIds: followingSet,
          votedPollIds: voted,
          now: now,
        );
        final sb = computeForYouScore(
          b,
          followingUserIds: followingSet,
          votedPollIds: voted,
          now: now,
        );
        final c = sb.compareTo(sa);
        if (c != 0) return c;
        return _pollCreatedAt(b).compareTo(_pollCreatedAt(a));
      });

      final want = limit + 1;
      final slice = pool.take(want).toList();
      final hasMore = slice.length > limit;
      final page = hasMore ? slice.sublist(0, limit) : slice;
      return FeedPage(items: page.cast<dynamic>(), hasMore: hasMore);
    } catch (_) {
      return FeedPage.empty();
    }
  }

  // --- Legacy list APIs (unchanged call sites) --------------------------------

  Future<List<dynamic>> getLatestFeed() async {
    final page = await getLatestFeedPage(limit: 500, offset: 0);
    return page.items;
  }

  Future<List<dynamic>> getTrendingFeed({int? limit}) async {
    if (limit == null) {
      try {
        final rows =
            await _supabase.from('trending_polls').select().order('trending_score', ascending: false);
        final hydrated = await _hydrateTrendingRows(rows);
        return List<dynamic>.from(hydrated);
      } catch (_) {
        return [];
      }
    }
    final page = await getTrendingFeedPage(limit: limit, offset: 0);
    return page.items;
  }

  Future<List<dynamic>> getForYouFeed(String currentUserId) async {
    final page = await getForYouFeedPage(currentUserId, limit: 48, excludePollIds: {});
    return page.items;
  }

  // --- Internals --------------------------------------------------------------

  Set<String> _idsOf(List<Map<String, dynamic>> polls) {
    final s = <String>{};
    for (final m in polls) {
      final id = m['id']?.toString();
      if (id != null && id.isNotEmpty) s.add(id);
    }
    return s;
  }

  List<dynamic> _normalizeDynamicList(List<dynamic> rows) {
    final list = <dynamic>[];
    for (final dynamic raw in rows) {
      list.add(raw is Map<String, dynamic> ? raw : Map<String, dynamic>.from(raw as Map));
    }
    return list;
  }

  Future<List<Map<String, dynamic>>> _hydrateTrendingRows(List<dynamic> rows) async {
    if (rows.isEmpty) return [];

    final pollIds = <String>[];
    final orderIds = <String>[];
    for (final dynamic row in rows) {
      final map = Map<String, dynamic>.from(row as Map);
      final id = (map['poll_id'] ?? map['id'])?.toString();
      if (id != null && id.isNotEmpty) {
        pollIds.add(id);
        orderIds.add(id);
      }
    }
    if (pollIds.isEmpty) return [];

    final polls = await _supabase.from('polls').select(_pollFeedSelect).eq('status', 'active').inFilter('id', pollIds);

    final byId = <String, Map<String, dynamic>>{};
    for (final dynamic p in polls) {
      final map = Map<String, dynamic>.from(p as Map);
      final id = map['id']?.toString();
      if (id != null) byId[id] = map;
    }

    final merged = <Map<String, dynamic>>[];
    for (final dynamic row in rows) {
      final map = Map<String, dynamic>.from(row as Map);
      final pollId = (map['poll_id'] ?? map['id'])?.toString();
      if (pollId == null) continue;
      final base = byId[pollId];
      if (base == null) continue;
      merged.add({
        ...base,
        'trending_score': map['trending_score'],
      });
    }
    return merged;
  }

  Future<List<String>> _getFollowingIds(String followerId) async {
    try {
      final rows =
          await _supabase.from('follows').select('following_id').eq('follower_id', followerId);
      final ids = <String>[];
      for (final dynamic row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final id = map['following_id']?.toString();
        if (id != null && id.isNotEmpty) ids.add(id);
      }
      return ids;
    } catch (_) {
      return [];
    }
  }

  Future<(String?, String?)> _getProfileCountryCity(String userId) async {
    try {
      final row =
          await _supabase.from('profiles').select('country, city').eq('id', userId).maybeSingle();
      if (row == null) return (null, null);
      final map = Map<String, dynamic>.from(row as Map);
      final country = _trimOrNull(map['country']?.toString());
      final city = _trimOrNull(map['city']?.toString());
      return (country, city);
    } catch (_) {
      return (null, null);
    }
  }

  String? _trimOrNull(String? s) {
    if (s == null) return null;
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  Future<List<Map<String, dynamic>>> _fetchFollowingPollsForYou(
    List<String> followingIds,
    Set<String> exclude, {
    required int fetchCap,
  }) async {
    if (followingIds.isEmpty) return [];
    try {
      final rows = await _supabase
          .from('polls')
          .select(_pollFeedSelect)
          .eq('status', 'active')
          .eq('visibility', 'public')
          .inFilter('user_id', followingIds)
          .order('created_at', ascending: false)
          .limit(fetchCap);
      return _normalizePollRows(rows).where((m) {
        final id = m['id']?.toString();
        return id != null && id.isNotEmpty && !exclude.contains(id);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchRegionalPollsForYou(
    String? country,
    String? city,
    Set<String> exclude, {
    required int fetchCap,
  }) async {
    if (country == null && city == null) return [];

    final candidates = <Map<String, dynamic>>[];
    try {
      if (country != null) {
        final rows = await _supabase
            .from('polls')
            .select(_pollFeedSelect)
            .eq('status', 'active')
            .eq('visibility', 'public')
            .eq('country', country)
            .order('created_at', ascending: false)
            .limit(fetchCap);
        candidates.addAll(_normalizePollRows(rows));
      }
      if (city != null) {
        final rows = await _supabase
            .from('polls')
            .select(_pollFeedSelect)
            .eq('status', 'active')
            .eq('visibility', 'public')
            .eq('city', city)
            .order('created_at', ascending: false)
            .limit(fetchCap);
        candidates.addAll(_normalizePollRows(rows));
      }
    } catch (_) {
      return [];
    }

    final byId = <String, Map<String, dynamic>>{};
    for (final m in candidates) {
      final id = m['id']?.toString();
      if (id == null || exclude.contains(id)) continue;
      final prev = byId[id];
      if (prev == null || _pollCreatedAt(m).isAfter(_pollCreatedAt(prev))) {
        byId[id] = m;
      }
    }

    final sorted = byId.values.toList()..sort((a, b) => _pollCreatedAt(b).compareTo(_pollCreatedAt(a)));
    return sorted.take(fetchCap).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchTrendingMapsForYou(
    Set<String> exclude, {
    required int take,
  }) async {
    try {
      final rows = await _supabase
          .from('trending_polls')
          .select()
          .order('trending_score', ascending: false)
          .limit(take * 2);
      final merged = await _hydrateTrendingRows(rows);
      return merged.where((m) {
        final id = m['id']?.toString();
        return id != null && id.isNotEmpty && !exclude.contains(id);
      }).take(take).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchLatestPollsForYou(
    Set<String> exclude, {
    required int take,
  }) async {
    try {
      final rows = await _supabase
          .from('polls')
          .select(_pollFeedSelect)
          .eq('status', 'active')
          .eq('visibility', 'public')
          .order('created_at', ascending: false)
          .limit(120);
      final out = <Map<String, dynamic>>[];
      for (final m in _normalizePollRows(rows)) {
        final id = m['id']?.toString();
        if (id == null || exclude.contains(id)) continue;
        out.add(m);
        if (out.length >= take) break;
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  List<Map<String, dynamic>> _normalizePollRows(List<dynamic> rows) {
    final out = <Map<String, dynamic>>[];
    for (final dynamic raw in rows) {
      out.add(Map<String, dynamic>.from(raw as Map));
    }
    return out;
  }

  static DateTime _pollCreatedAt(Map<String, dynamic> poll) {
    final raw = poll['created_at'];
    if (raw == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (raw is DateTime) return raw;
    return DateTime.tryParse(raw.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Polls authored by [userId]. When [publicOnly] is true, only public polls are returned.
  Future<List<dynamic>> getPollsForUser(String userId, {bool publicOnly = false}) async {
    final builder = _supabase
        .from('polls')
        .select(_pollFeedSelect)
        .eq('user_id', userId)
        .eq('status', 'active');

    final filtered = publicOnly ? builder.eq('visibility', 'public') : builder;
    final response = await filtered.order('created_at', ascending: false);
    return response;
  }
}
