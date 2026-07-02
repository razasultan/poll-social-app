import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Flutter web implementation of [VideoPreview].
/// Uses a native HTML <video> element via [HtmlElementView] so both
/// blob: URLs (locally-picked files from image_picker on web) and
/// https: Supabase Storage URLs work without any CORS or MIME restrictions.
class VideoPreview extends StatefulWidget {
  const VideoPreview({super.key, required this.url, this.height = 200});

  final String url;
  final double height;

  @override
  State<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> {
  static int _nextId = 0;

  late String _viewType;

  @override
  void initState() {
    super.initState();
    _register(widget.url);
  }

  @override
  void didUpdateWidget(VideoPreview old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      // Each URL change needs a new factory registration — registrations
      // are immutable once committed.
      setState(() => _register(widget.url));
    }
  }

  void _register(String url) {
    _viewType = 'poll-video-preview-${_nextId++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int id) {
      final video = web.HTMLVideoElement();
      video.src = url;
      video.controls = true;
      video.style.width = '100%';
      video.style.height = '100%';
      video.style.objectFit = 'cover';
      video.style.setProperty('border-radius', '12px');
      video.style.background = '#000';
      return video;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: HtmlElementView(viewType: _viewType),
      ),
    );
  }
}
