import 'package:flutter/foundation.dart';

/// Incremented whenever the current user saves changes to their profile
/// (avatar, header, or profile fields). Any [ProfileScreen] instance that
/// owns the authenticated user's profile subscribes to this and calls
/// [_load()] so the updated data appears immediately without a manual refresh.
final ValueNotifier<int> profileUpdateNotifier = ValueNotifier<int>(0);

/// Incremented to trigger a data reload on the own-profile tab — e.g. when
/// the user publishes a new poll or navigates to the Profile branch so the
/// poll count and list stay fresh.
final ValueNotifier<int> profileReloadNotifier = ValueNotifier<int>(0);
