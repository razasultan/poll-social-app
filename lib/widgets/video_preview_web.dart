import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../core/media/video_manager.dart';

/// Flutter web implementation of [VideoPreview].
///
/// Reads the video's native dimensions from the [HTMLVideoElement.loadedmetadata]
/// event and sizes the container to match the aspect ratio (no cropping).
/// [height] is a cap: landscape videos fill the full width; portrait or
/// square videos shrink horizontally so they never exceed [height].
class VideoPreview extends StatefulWidget {
  const VideoPreview({super.key, required this.url, this.height = 300});

  final String url;

  /// Maximum display height in logical pixels. The widget may be shorter
  /// when the native aspect ratio would produce a smaller height.
  final double height;

  @override
  State<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> {
  static int _nextId = 0;

  late String _viewType;
  late web.HTMLVideoElement _video;
  bool _playing = false;

  /// Native aspect ratio (width / height). Null until metadata loads.
  double? _aspectRatio;

  @override
  void initState() {
    super.initState();
    _register(widget.url);
    videoNowPlaying.addListener(_onNowPlayingChanged);
  }

  @override
  void didUpdateWidget(VideoPreview old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _clearPlaying();
      _video.pause();
      setState(() {
        _playing = false;
        _aspectRatio = null;
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
      // contain: show the whole video without cropping (letterbox if needed).
      ..style.objectFit = 'contain'
      ..style.background = '#000';

    // Read native dimensions once metadata arrives.
    _video.addEventListener(
      'loadedmetadata',
      ((JSAny? _) {
        final w = _video.videoWidth;
        final h = _video.videoHeight;
        if (mounted && w > 0 && h > 0) {
          setState(() => _aspectRatio = w / h);
        }
      }).toJS,
    );

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

  void _togglePlay() {
    if (_playing) {
      _video.pause();
      _clearPlaying();
      setState(() => _playing = false);
    } else {
      videoNowPlaying.value = _viewType;
      _video.play(); // JSPromise discarded intentionally
      setState(() => _playing = true);
    }
  }

  @override
  void dispose() {
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          final maxH = widget.height;

          // Before metadata: show a fixed-size loading placeholder.
          final ratio = _aspectRatio;
          double displayW, displayH;
          if (ratio == null) {
            displayW = maxW;
            displayH = maxH;
          } else {
            // Fit the video within maxW × maxH preserving the native ratio.
            displayH = maxW / ratio;
            displayW = maxW;
            if (displayH > maxH) {
              displayH = maxH;
              displayW = maxH * ratio;
            }
          }

          return SizedBox(
            height: displayH,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: displayW,
                  height: displayH,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: HtmlElementView(viewType: _viewType),
                      ),
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
            ),
          );
        },
      ),
    );
  }
}
