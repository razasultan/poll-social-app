/// One page of feed results from [FeedService].
class FeedPage {
  const FeedPage({required this.items, required this.hasMore});

  final List<dynamic> items;
  final bool hasMore;

  static FeedPage empty() =>
      FeedPage(items: List<dynamic>.empty(growable: false), hasMore: false);
}
