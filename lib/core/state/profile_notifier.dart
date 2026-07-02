import 'package:flutter/foundation.dart';

/// Incremented whenever the current user saves changes to their profile
/// (avatar, header, or profile fields). Any [ProfileScreen] instance that
/// owns the authenticated user's profile subscribes to this and calls
/// [_load()] so the updated data appears immediately without a manual refresh.
final ValueNotifier<int> profileUpdateNotifier = ValueNotifier<int>(0);
