// Selects the platform-appropriate VideoPreview implementation:
//   - Flutter web  → video_preview_web.dart  (native <video> via HtmlElementView)
//   - Everything else → video_preview_stub.dart (video_player package)
export 'video_preview_stub.dart'
    if (dart.library.html) 'video_preview_web.dart';
