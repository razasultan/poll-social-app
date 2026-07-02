import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../core/navigation/route_observer.dart';

/// Flutter web implementation of [VideoPreview].
///
/// Two design decisions:
/// 1. No native `controls` — Flutter's canvas sits on top of [HtmlElementView]
///    in canvaskit rendering, so browser-native controls never receive clicks
///    inside modals or overlays. Instead a Flutter [GestureDetector] calls
///    [HTMLVideoElement.play] / [HTMLVideoElement.pause] directly.
/// 2. Static [_nowPlaying] [ValueNotifier] — when any instance starts playing
///    it broadcasts its view-type ID so every other live instance pauses itself.
class VideoPreview extends StatefulWidget {
  const VideoPreview({super.key, required this.url, this.height = 200});

  final String url;
  final double height;

  @override
  State<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> with RouteAware {
  // Broadcasts the viewType of whichever video is currently playing.
  // null means nothing is playing. Every active instance listens and pauses
  // itself when a different viewType is announced.
  static final ValueNotifier<String?> _nowPlaying = ValueNotifier(null);

  static int _nextId = 0;

  late String _viewType;
  late web.HTMLVideoElement _video;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _register(widget.url);
    _nowPlaying.addListener(_onNowPlayingChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      appRouteObserver.subscribe(this, route);
    }
  }

  /// Called when another route is pushed on top of this one (e.g. tapping a
  /// poll card in the feed navigates to PollDetailScreen). Pause immediately
  /// so the video doesn't keep playing in the background route.
  @override
  void didPushNext() {
    if (_playing) {
      _video.pause();
      if (_nowPlaying.value == _viewType) _nowPlaying.value = null;
      if (mounted) setState(() => _playing = false);
    }
  }

  @override
  void didUpdateWidget(VideoPreview old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      if (_nowPlaying.value == _viewType) _nowPlaying.value = null;
      _video.pause();
      setState(() {
        _playing = false;
        _register(widget.url);
      });
    }
  }

  void _register(String url) {
    _viewType = 'poll-video-${_nextId++}';
    _video = web.HTMLVideoElement()
      ..src = url
      ..preload = 'metadata'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover'
      ..style.background = '#000';

    // Reset play button when the video finishes naturally.
    _video.addEventListener(
      'ended',
      ((JSAny? _) {
        if (_nowPlaying.value == _viewType) _nowPlaying.value = null;
        if (mounted) setState(() => _playing = false);
      }).toJS,
    );

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int id) => _video,
    );
  }

  void _onNowPlayingChanged() {
    // Another video started — pause this one.
    if (_nowPlaying.value != _viewType && _playing) {
      _video.pause();
      if (mounted) setState(() => _playing = false);
    }
  }

  void _togglePlay() {
    if (_playing) {
      _video.pause();
      if (_nowPlaying.value == _viewType) _nowPlaying.value = null;
      setState(() => _playing = false);
    } else {
      // Announce before playing so listeners pause immediately.
      _nowPlaying.value = _viewType;
      _video.play(); // JSPromise return is intentionally discarded.
      setState(() => _playing = true);
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    _nowPlaying.removeListener(_onNowPlayingChanged);
    if (_nowPlaying.value == _viewType) _nowPlaying.value = null;
    // Setting src to '' unloads the media and stops playback even if the
    // HTMLVideoElement lingers in the DOM after the platform view is released.
    _video.pause();
    _video.src = '';
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _togglePlay,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(child: HtmlElementView(viewType: _viewType)),
              // Scrim + play button rendered by Flutter (always on top of
              // the platform-view layer, receives taps via GestureDetector).
              if (!_playing)
                IgnorePointer(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
