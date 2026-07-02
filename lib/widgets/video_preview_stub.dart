import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Non-web fallback: uses the [video_player] package.
/// On Flutter web the conditional export in video_preview.dart selects
/// video_preview_web.dart instead, which uses a native <video> element and
/// supports blob: URLs returned by image_picker.
class VideoPreview extends StatefulWidget {
  const VideoPreview({super.key, required this.url, this.height = 200});

  final String url;
  final double height;

  @override
  State<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> {
  late VideoPlayerController _controller;
  bool _initialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _init(widget.url);
  }

  @override
  void didUpdateWidget(VideoPreview old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _controller.dispose();
      setState(() {
        _initialized = false;
        _hasError = false;
      });
      _init(widget.url);
    }
  }

  void _init(String url) {
    _controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller
        .initialize()
        .then((_) {
          if (mounted) setState(() => _initialized = true);
        })
        .catchError((_) {
          if (mounted) setState(() => _hasError = true);
        });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    setState(() {
      _controller.value.isPlaying ? _controller.pause() : _controller.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_hasError) {
      return _shell(
        cs,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.videocam_off_outlined,
              size: 32,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              'Could not load video',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (!_initialized) {
      return _shell(cs, child: const CircularProgressIndicator());
    }

    final isPlaying = _controller.value.isPlaying;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: _controller.value.size.width,
                  height: _controller.value.size.height,
                  child: VideoPlayer(_controller),
                ),
              ),
            ),
            if (!isPlaying)
              Container(color: Colors.black.withValues(alpha: 0.3)),
            GestureDetector(
              onTap: _togglePlay,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shell(ColorScheme cs, {required Widget child}) {
    return Container(
      height: widget.height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(child: child),
    );
  }
}
