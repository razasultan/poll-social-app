import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../core/media/video_manager.dart';
import '../core/navigation/route_observer.dart';

/// Flutter web implementation of [VideoPreview].
///
/// Uses [videoNowPlaying] from [VideoManager] as the shared playback
/// coordinator — when any instance plays it broadcasts its viewType so all
/// others pause, and external callers (tab switches, route changes) can call
/// [VideoManager.pauseAll] to stop everything without touching widget state.
class VideoPreview extends StatefulWidget {
  const VideoPreview({super.key, required this.url, this.height = 200});

  final String url;
  final double height;

  @override
  State<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> with RouteAware {
  static int _nextId = 0;

  late String _viewType;
  late web.HTMLVideoElement _video;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _register(widget.url);
    videoNowPlaying.addListener(_onNowPlayingChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) appRouteObserver.subscribe(this, route);
  }

  /// Route push (e.g. feed → poll detail). Pause immediately.
  @override
  void didPushNext() => _pause();

  @override
  void didUpdateWidget(VideoPreview old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _clearPlaying();
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

    _video.addEventListener(
      'ended',
      ((JSAny? _) {
        _clearPlaying();
        if (mounted) setState(() => _playing = false);
      }).toJS,
    );

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int id) => _video,
    );
  }

  void _clearPlaying() {
    if (videoNowPlaying.value == _viewType) videoNowPlaying.value = null;
  }

  void _onNowPlayingChanged() {
    if (videoNowPlaying.value != _viewType && _playing) {
      _video.pause();
      if (mounted) setState(() => _playing = false);
    }
  }

  void _pause() {
    if (_playing) {
      _video.pause();
      _clearPlaying();
      if (mounted) setState(() => _playing = false);
    }
  }

  void _togglePlay() {
    if (_playing) {
      _pause();
    } else {
      videoNowPlaying.value = _viewType; // triggers others to pause
      _video.play(); // JSPromise discarded intentionally
      setState(() => _playing = true);
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    videoNowPlaying.removeListener(_onNowPlayingChanged);
    _clearPlaying();
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
