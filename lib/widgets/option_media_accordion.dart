import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'video_preview.dart';

/// Accordion-style media preview for a single poll option.
///
/// Default state: a compact 68px strip showing a thumbnail + filename +
/// chevron. Tapping expands the full preview inline (image at natural
/// aspect ratio, video via [VideoPreview]). Tapping again collapses.
///
/// Exactly one of [imageBytes] / [imageUrl] must be non-null for an image,
/// or [videoUrl] for a video. [mediaType] must be `'image'` or `'video'`.
class OptionMediaAccordion extends StatefulWidget {
  const OptionMediaAccordion({
    super.key,
    this.imageBytes,
    this.imageUrl,
    this.videoUrl,
    required this.fileName,
    required this.mediaType,
    required this.onRemove,
    this.onReplace,
  });

  final Uint8List? imageBytes;
  final String? imageUrl;
  final String? videoUrl;
  final String fileName;
  final String mediaType;
  final VoidCallback onRemove;

  /// Optional replace callback shown as a swap icon in the strip.
  final VoidCallback? onReplace;

  @override
  State<OptionMediaAccordion> createState() => _OptionMediaAccordionState();
}

class _OptionMediaAccordionState extends State<OptionMediaAccordion> {
  bool _expanded = false;

  String get _displayName {
    if (widget.fileName.isNotEmpty) return widget.fileName;
    if (widget.imageUrl != null) {
      final segments = widget.imageUrl!.split('/')..removeWhere((s) => s.isEmpty);
      return segments.isNotEmpty ? segments.last.split('?').first : 'image';
    }
    return widget.mediaType == 'video' ? 'video' : 'image';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Collapsed strip ─────────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: SizedBox(
              height: 68,
              child: Row(
                children: [
                  // Thumbnail
                  SizedBox(
                    width: 80,
                    height: 68,
                    child: _buildThumb(cs),
                  ),
                  const SizedBox(width: 10),
                  // File info
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _expanded ? 'Tap to collapse' : 'Tap to preview',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Actions
                  if (widget.onReplace != null)
                    IconButton(
                      tooltip: 'Replace',
                      icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                      color: cs.onSurfaceVariant,
                      onPressed: widget.onReplace,
                    ),
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: cs.onSurfaceVariant,
                    onPressed: widget.onRemove,
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: cs.onSurfaceVariant,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),

          // ── Expanded preview ─────────────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeInOut,
            child: _expanded
                ? Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: cs.outlineVariant),
                      ),
                    ),
                    child: _buildFullPreview(cs),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _buildThumb(ColorScheme cs) {
    if (widget.mediaType == 'image') {
      if (widget.imageBytes != null) {
        return Image.memory(
          widget.imageBytes!,
          fit: BoxFit.cover,
          width: 80,
          height: 68,
        );
      }
      if (widget.imageUrl != null) {
        return Image.network(
          widget.imageUrl!,
          fit: BoxFit.cover,
          width: 80,
          height: 68,
          errorBuilder: (_, _, _) => _thumbPlaceholder(cs, Icons.image_outlined),
        );
      }
    }
    if (widget.mediaType == 'video') {
      return Container(
        color: Colors.black,
        child: Center(
          child: Icon(
            Icons.play_circle_outline_rounded,
            size: 28,
            color: cs.onSurfaceVariant,
          ),
        ),
      );
    }
    return _thumbPlaceholder(cs, Icons.attach_file_rounded);
  }

  Widget _thumbPlaceholder(ColorScheme cs, IconData icon) {
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(icon, size: 24, color: cs.onSurfaceVariant),
      ),
    );
  }

  Widget _buildFullPreview(ColorScheme cs) {
    if (widget.mediaType == 'video' && widget.videoUrl != null) {
      return VideoPreview(url: widget.videoUrl!, height: 200);
    }
    if (widget.mediaType == 'image') {
      if (widget.imageBytes != null) {
        return Image.memory(
          widget.imageBytes!,
          fit: BoxFit.fitWidth,
          width: double.infinity,
        );
      }
      if (widget.imageUrl != null) {
        return Image.network(
          widget.imageUrl!,
          fit: BoxFit.fitWidth,
          width: double.infinity,
          loadingBuilder: (ctx, child, progress) => progress == null
              ? child
              : Container(
                  height: 160,
                  color: cs.surfaceContainerHighest,
                  child: const Center(child: CircularProgressIndicator()),
                ),
          errorBuilder: (_, _, _) => Container(
            height: 100,
            color: cs.surfaceContainerHighest,
            child: Center(
              child: Icon(Icons.broken_image_outlined,
                  color: cs.onSurfaceVariant),
            ),
          ),
        );
      }
    }
    return const SizedBox.shrink();
  }
}
