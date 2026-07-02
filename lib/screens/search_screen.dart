import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:go_router/go_router.dart';

import '../core/navigation/branch_utils.dart';
import '../services/search_service.dart';
import '../utils/profile_navigation.dart';

/// Search polls, users, hashtags, and topics via Supabase RPCs.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.initialQuery, this.initialTabIndex});

  /// Pre-fills the search field and runs the search immediately, e.g. when
  /// arriving from a tapped `#hashtag` in a poll's post text.
  final String? initialQuery;

  /// Tab to select when [initialQuery] is provided (0=Polls, 1=Users,
  /// 2=Hashtags, 3=Topics).
  final int? initialTabIndex;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final SearchService _searchService = SearchService();
  final TextEditingController _searchCtrl = TextEditingController();
  late TabController _tabController;
  Timer? _debounce;
  int _requestId = 0;

  bool _loading = false;
  int _loadingTabIndex = -1;
  List<Map<String, dynamic>> _pollResults = [];
  List<Map<String, dynamic>> _userResults = [];
  List<Map<String, dynamic>> _hashtagResults = [];
  List<Map<String, dynamic>> _topicResults = [];

  @override
  void initState() {
    super.initState();
    final initialIndex = widget.initialTabIndex ?? 0;
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: initialIndex.clamp(0, 3),
    );
    _tabController.addListener(_onTabChanged);

    final initialQuery = widget.initialQuery?.trim();
    if (initialQuery != null && initialQuery.isNotEmpty) {
      _searchCtrl.text = initialQuery;
      unawaited(_executeSearch(initialQuery));
    }
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    _debounce?.cancel();
    final q = _searchCtrl.text.trim();
    if (q.length >= 2) {
      unawaited(_executeSearch(q));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _asMap(dynamic item) {
    if (item is Map<String, dynamic>) return item;
    if (item is Map) return Map<String, dynamic>.from(item);
    return {};
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    final q = _searchCtrl.text.trim();
    if (q.length < 2) {
      _requestId++;
      setState(() {
        _loading = false;
        _loadingTabIndex = -1;
        _pollResults = [];
        _userResults = [];
        _hashtagResults = [];
        _topicResults = [];
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_executeSearch(q));
    });
  }

  List<Map<String, dynamic>> _parseList(dynamic raw) {
    if (raw is! List) return [];
    return raw.map(_asMap).toList();
  }

  Future<void> _executeSearch(String query) async {
    if (!mounted) return;
    final id = ++_requestId;
    final tabIdx = _tabController.index;

    setState(() {
      _loading = true;
      _loadingTabIndex = tabIdx;
    });

    try {
      List<Map<String, dynamic>> parsed = [];
      switch (tabIdx) {
        case 0:
          parsed = _parseList(await _searchService.searchPolls(query));
          break;
        case 1:
          parsed = _parseList(await _searchService.searchUsers(query));
          break;
        case 2:
          parsed = _parseList(await _searchService.searchHashtags(query));
          break;
        case 3:
          parsed = _parseList(await _searchService.searchTopics(query));
          break;
      }

      if (!mounted || id != _requestId) return;

      setState(() {
        switch (tabIdx) {
          case 0:
            _pollResults = parsed;
            break;
          case 1:
            _userResults = parsed;
            break;
          case 2:
            _hashtagResults = parsed;
            break;
          case 3:
            _topicResults = parsed;
            break;
        }
        _loading = false;
        _loadingTabIndex = -1;
      });
    } on PostgrestException catch (e) {
      if (!mounted || id != _requestId) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message.isNotEmpty ? e.message : 'Search failed'),
        ),
      );
      setState(() {
        _clearResultsForTab(tabIdx);
        _loading = false;
        _loadingTabIndex = -1;
      });
    } catch (_) {
      if (!mounted || id != _requestId) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Network error. Try again.')),
      );
      setState(() {
        _clearResultsForTab(tabIdx);
        _loading = false;
        _loadingTabIndex = -1;
      });
    }
  }

  void _clearResultsForTab(int tabIdx) {
    switch (tabIdx) {
      case 0:
        _pollResults = [];
        break;
      case 1:
        _userResults = [];
        break;
      case 2:
        _hashtagResults = [];
        break;
      case 3:
        _topicResults = [];
        break;
    }
  }

  List<Map<String, dynamic>> _resultsForTab(int index) {
    switch (index) {
      case 0:
        return _pollResults;
      case 1:
        return _userResults;
      case 2:
        return _hashtagResults;
      case 3:
        return _topicResults;
      default:
        return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final query = _searchCtrl.text.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Polls'),
            Tab(text: 'Users'),
            Tab(text: 'Hashtags'),
            Tab(text: 'Topics'),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search polls, users, hashtags, topics…',
                prefixIcon: Icon(Icons.search_rounded, color: cs.primary),
                suffixIcon: query.isNotEmpty
                    ? IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onQueryChanged();
                          setState(() {});
                        },
                      )
                    : null,
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: cs.primary.withValues(alpha: 0.55),
                  ),
                ),
              ),
              onChanged: (_) {
                _onQueryChanged();
                setState(() {});
              },
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _SearchResultsTab(
                  loading: _loading && _loadingTabIndex == 0,
                  query: query,
                  results: _resultsForTab(0),
                  emptyLabel: 'No results found',
                  initialHint: 'Search polls, users, hashtags, or topics',
                  builder: (ctx, item) => _PollSearchTile(
                    item: item,
                    onTap: () {
                      final id =
                          item['id']?.toString() ?? item['poll_id']?.toString();
                      if (id == null || id.isEmpty) return;
                      ctx.push('${branchPrefixFor(ctx)}/poll/$id');
                    },
                  ),
                ),
                _SearchResultsTab(
                  loading: _loading && _loadingTabIndex == 1,
                  query: query,
                  results: _resultsForTab(1),
                  emptyLabel: 'No results found',
                  initialHint: 'Search polls, users, hashtags, or topics',
                  builder: (ctx, item) => _UserSearchTile(
                    item: item,
                    onTap: () {
                      final userId =
                          item['id']?.toString() ?? item['user_id']?.toString();
                      if (userId == null || userId.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('Could not open profile'),
                          ),
                        );
                        return;
                      }
                      openProfile(ctx, userId);
                    },
                  ),
                ),
                _SearchResultsTab(
                  loading: _loading && _loadingTabIndex == 2,
                  query: query,
                  results: _resultsForTab(2),
                  emptyLabel: 'No results found',
                  initialHint: 'Search polls, users, hashtags, or topics',
                  builder: (ctx, item) => _HashtagSearchTile(
                    item: item,
                    onTap: () {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('Hashtag feed coming soon'),
                        ),
                      );
                    },
                  ),
                ),
                _SearchResultsTab(
                  loading: _loading && _loadingTabIndex == 3,
                  query: query,
                  results: _resultsForTab(3),
                  emptyLabel: 'No results found',
                  initialHint: 'Search polls, users, hashtags, or topics',
                  builder: (ctx, item) => _TopicSearchTile(
                    item: item,
                    onTap: () {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Topic feed coming soon')),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchResultsTab extends StatelessWidget {
  const _SearchResultsTab({
    required this.loading,
    required this.query,
    required this.results,
    required this.emptyLabel,
    required this.initialHint,
    required this.builder,
  });

  final bool loading;
  final String query;
  final List<Map<String, dynamic>> results;
  final String emptyLabel;
  final String initialHint;
  final Widget Function(BuildContext context, Map<String, dynamic> item)
  builder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (query.length < 2) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            initialHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    if (loading && results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!loading && results.isEmpty) {
      return Center(
        child: Text(
          emptyLabel,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      );
    }

    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: results.length,
          separatorBuilder: (_, _) => Divider(
            height: 1,
            color: cs.outlineVariant.withValues(alpha: 0.35),
          ),
          itemBuilder: (context, index) => builder(context, results[index]),
        ),
        if (loading && results.isNotEmpty)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }
}

class _PollSearchTile extends StatelessWidget {
  const _PollSearchTile({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  static String? _pollUsername(Map<String, dynamic> item) {
    final direct = item['username']?.toString();
    if (direct != null && direct.isNotEmpty) return direct;
    final profiles = item['profiles'];
    if (profiles is Map) {
      final u = profiles['username']?.toString();
      if (u != null && u.isNotEmpty) return u;
    }
    return null;
  }

  static String _formatCreated(dynamic v) {
    if (v == null) return '';
    DateTime? at;
    if (v is DateTime) {
      at = v;
    } else {
      at = DateTime.tryParse(v.toString());
    }
    if (at == null) return '';
    final now = DateTime.now();
    final diff = now.difference(at);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final question = item['question']?.toString() ?? 'Untitled poll';
    final user = _pollUsername(item) ?? 'Unknown';
    final created = _formatCreated(item['created_at']);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              question,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.person_outline_rounded,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    user,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (created.isNotEmpty)
                  Text(
                    created,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UserSearchTile extends StatelessWidget {
  const _UserSearchTile({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final username = item['username']?.toString() ?? 'Unknown';
    final displayName = item['display_name']?.toString() ?? '';
    final bio = item['bio']?.toString() ?? '';
    final avatarUrl = item['avatar_url']?.toString();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: cs.primaryContainer,
              backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                  ? NetworkImage(avatarUrl)
                  : null,
              child: avatarUrl == null || avatarUrl.isEmpty
                  ? Text(
                      username.isNotEmpty ? username[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    username,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (displayName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      displayName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.primary,
                      ),
                    ),
                  ],
                  if (bio.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      bio,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HashtagSearchTile extends StatelessWidget {
  const _HashtagSearchTile({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  static String _label(Map<String, dynamic> item) {
    final raw =
        item['hashtag']?.toString() ??
        item['tag']?.toString() ??
        item['name']?.toString() ??
        '';
    final s = raw.trim();
    if (s.isEmpty) return '#';
    return s.startsWith('#') ? s : '#$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(Icons.tag_rounded, color: cs.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _label(item),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicSearchTile extends StatelessWidget {
  const _TopicSearchTile({required this.item, required this.onTap});

  final Map<String, dynamic> item;
  final VoidCallback onTap;

  static String _name(Map<String, dynamic> item) {
    return item['name']?.toString() ??
        item['topic_name']?.toString() ??
        item['title']?.toString() ??
        'Topic';
  }

  static String? _description(Map<String, dynamic> item) {
    final d = item['description']?.toString();
    if (d == null || d.trim().isEmpty) return null;
    return d.trim();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final name = _name(item);
    final desc = _description(item);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.topic_rounded, color: cs.primary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (desc != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 34),
                child: Text(
                  desc,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.35,
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
