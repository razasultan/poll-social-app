import 'package:flutter/foundation.dart';

/// Bump to trigger a reload of the feed and trending rail (e.g. after a poll
/// is published). Consumed by [FeedScreen] and [TrendingRail] directly so
/// neither needs a constructor prop from [MainShell].
final ValueNotifier<int> feedReloadNotifier = ValueNotifier<int>(0);
