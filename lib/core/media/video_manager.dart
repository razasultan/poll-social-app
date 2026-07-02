import 'package:flutter/foundation.dart';

/// Cross-platform coordinator for [VideoPreview] playback state.
///
/// [nowPlaying] holds the viewType of the currently-playing video (null when
/// nothing is playing). Each [VideoPreview] instance subscribes to it and
/// pauses itself when a different viewType is announced.
///
/// [pauseAll] is a convenience that clears [nowPlaying], triggering every
/// active subscriber to pause. Call it on tab switches, route changes, etc.
final ValueNotifier<String?> videoNowPlaying = ValueNotifier<String?>(null);

abstract final class VideoManager {
  /// Pause every active [VideoPreview] instance immediately.
  static void pauseAll() => videoNowPlaying.value = null;
}
