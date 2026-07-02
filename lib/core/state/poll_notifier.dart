import 'package:flutter/foundation.dart';

/// Incremented whenever the current user edits a poll (question, media, etc.).
/// [MainShell] listens and bumps the feed reload token so updated polls
/// appear in the feed without a manual pull-to-refresh.
final ValueNotifier<int> pollUpdateNotifier = ValueNotifier<int>(0);
