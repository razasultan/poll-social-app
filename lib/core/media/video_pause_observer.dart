import 'package:flutter/widgets.dart';

import 'video_manager.dart';

/// Pauses all active [VideoPreview] instances whenever a new route is pushed
/// onto a navigator (branch navigator in the shell, or the root navigator).
class VideoPauseObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    VideoManager.pauseAll();
  }
}
