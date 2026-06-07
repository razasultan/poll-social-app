import 'dart:async';

import 'package:flutter/material.dart';

import '../models/feed_page.dart';
import '../screens/poll_detail_screen.dart';
import 'poll_card.dart';

/// Cursor for the next page: API offset (Latest/Trending) and/or loaded IDs (For You exclusions).
class PagedPollCursor {
  const PagedPollCursor({
    this.offset = 0,
    this.loadedPollIds = const {},
  });

  final int offset;
  final Set<String> loadedPollIds;
}

typedef PagedPollFetcher = Future<FeedPage> Function(PagedPollCursor cursor);

/// Infinite-scroll poll list with pull-to-refresh, bottom loader, and optional seen tracking.
class PagedPollFeed extends StatefulWidget {
  const PagedPollFeed({
    super.key,
    required this.pageStorageKey,
    required this.fetch,
    required this.emptyMessage,
    this.isTrendingTab = false,
    this.trendingScoreWhenPresent = false,
    this.onPollIdsBecameVisible,
    this.reloadListenable,
  });

  final String pageStorageKey;
  final PagedPollFetcher fetch;
  final String emptyMessage;
  final bool isTrendingTab;
  final bool trendingScoreWhenPresent;
  final void Function(Set<String> pollIds)? onPollIdsBecameVisible;

  /// When notified, reloads first page (cursor reset).
  final Listenable? reloadListenable;

  @override
  State<PagedPollFeed> createState() => _PagedPollFeedState();
}

class _PagedPollFeedState extends State<PagedPollFeed> with AutomaticKeepAliveClientMixin {
  final ScrollController _scroll = ScrollController();

  List<dynamic> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  Timer? _seenDebounce;

  static const double _estimatedCardHeight = 320;

  @override
  bool get wantKeepAlive => true;

  Set<String> _collectIds() {
    final ids = <String>{};
    for (final raw in _items) {
      if (raw is! Map) continue;
      final m = raw is Map<String, dynamic> ? raw : Map<String, dynamic>.from(raw);
      final id = m['id']?.toString();
      if (id != null && id.isNotEmpty) ids.add(id);
    }
    return ids;
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    widget.reloadListenable?.addListener(_onExternalReload);
    _bootstrap();
  }

  @override
  void didUpdateWidget(PagedPollFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadListenable != widget.reloadListenable) {
      oldWidget.reloadListenable?.removeListener(_onExternalReload);
      widget.reloadListenable?.addListener(_onExternalReload);
    }
  }

  @override
  void dispose() {
    widget.reloadListenable?.removeListener(_onExternalReload);
    _seenDebounce?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onExternalReload() {
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _items = [];
      _hasMore = true;
    });
    try {
      final page = await widget.fetch(const PagedPollCursor());
      if (!mounted) return;
      setState(() {
        _items = List<dynamic>.from(page.items);
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = [];
        _hasMore = false;
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    try {
      final page = await widget.fetch(const PagedPollCursor());
      if (!mounted) return;
      setState(() {
        _items = List<dynamic>.from(page.items);
        _hasMore = page.hasMore;
      });
    } catch (_) {
      if (!mounted) return;
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.fetch(PagedPollCursor(
        offset: _items.length,
        loadedPollIds: _collectIds(),
      ));
      if (!mounted) return;
      setState(() {
        final existing = _collectIds();
        final merged = <dynamic>[..._items];
        for (final dynamic raw in page.items) {
          final m = raw is Map<String, dynamic> ? raw : Map<String, dynamic>.from(raw as Map);
          final id = m['id']?.toString();
          if (id == null || id.isEmpty || existing.contains(id)) continue;
          existing.add(id);
          merged.add(m);
        }
        _items = merged;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.maxScrollExtent - pos.pixels < 480) {
      unawaited(_loadMore());
    }
    _scheduleSeenUpdate();
  }

  void _scheduleSeenUpdate() {
    _seenDebounce?.cancel();
    _seenDebounce = Timer(const Duration(milliseconds: 220), _flushSeen);
  }

  void _flushSeen() {
    if (!mounted || widget.onPollIdsBecameVisible == null || _items.isEmpty) return;
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final n = _items.length;
    final first = (pos.pixels / _estimatedCardHeight).floor().clamp(0, n - 1);
    final lastExclusive =
        ((pos.pixels + pos.viewportDimension) / _estimatedCardHeight).ceil().clamp(0, n);
    final ids = <String>{};
    for (var i = first; i < lastExclusive; i++) {
      final raw = _items[i];
      if (raw is! Map) continue;
      final m = raw is Map<String, dynamic> ? raw : Map<String, dynamic>.from(raw);
      final id = m['id']?.toString();
      if (id != null && id.isNotEmpty) ids.add(id);
    }
    if (ids.isEmpty) return;
    widget.onPollIdsBecameVisible!(ids);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          key: PageStorageKey<String>('${widget.pageStorageKey}_empty'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    widget.emptyMessage,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        key: PageStorageKey<String>(widget.pageStorageKey),
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _items.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            );
          }

          final raw = _items[index];
          final poll = raw is Map<String, dynamic> ? raw : Map<String, dynamic>.from(raw as Map);
          final showScore = widget.trendingScoreWhenPresent
              ? (poll['trending_score'] != null)
              : widget.isTrendingTab;

          return PollCard(
            key: ValueKey<String>('poll_${poll['id']}'),
            poll: poll,
            showTrendingScore: showScore,
            onPollTap: () {
              final id = poll['id']?.toString();
              if (id == null || id.isEmpty) return;
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (context) => PollDetailScreen(pollId: id),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
