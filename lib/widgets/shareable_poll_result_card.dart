import 'package:flutter/material.dart';

import 'poll_result_chart.dart' show PollChartEntry;

/// Branded, self-contained card designed to be captured as a shareable PNG
/// (see [PollCard]'s "share" action, which renders this off-screen inside a
/// [RepaintBoundary]). Uses fixed colors rather than [Theme.of] so exported
/// images look the same regardless of the viewer's light/dark mode.
class ShareablePollResultCard extends StatelessWidget {
  const ShareablePollResultCard({
    super.key,
    required this.question,
    required this.entries,
    required this.totalVotes,
    this.postText,
    this.authorName,
    this.shareUrl,
  });

  final String question;
  final List<PollChartEntry> entries;
  final int totalVotes;
  final String? postText;
  final String? authorName;

  /// Public URL for the poll (`PollCard._shareUrl`, built from the poll's
  /// `share_slug`). Null when the poll has no slug.
  final String? shareUrl;

  static const Color _bg = Color(0xFFFFFFFF);
  static const Color _ink = Color(0xFF0F1419);
  static const Color _muted = Color(0xFF536471);
  static const Color _track = Color(0xFFEFF3F4);
  static const Color _accent = Color(0xFF6C5CE7);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _track),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.how_to_vote_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Poll Social',
                  style: TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                if (authorName != null && authorName!.trim().isNotEmpty)
                  Flexible(
                    child: Text(
                      '@${authorName!.trim()}',
                      style: const TextStyle(color: _muted, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            if (postText != null && postText!.trim().isNotEmpty) ...[
              Text(
                postText!.trim(),
                style: const TextStyle(
                  color: _muted,
                  fontSize: 14,
                  height: 1.35,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
            ],
            Text(
              question,
              style: const TextStyle(
                color: _ink,
                fontWeight: FontWeight.w700,
                fontSize: 19,
                height: 1.3,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 18),
            for (final entry in entries) ...[
              _ResultRow(entry: entry),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 4),
            Text(
              '$totalVotes ${totalVotes == 1 ? 'vote' : 'votes'}',
              style: const TextStyle(
                color: _muted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (shareUrl != null && shareUrl!.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(height: 1, color: _track),
              const SizedBox(height: 14),
              Text(
                shareUrl!.trim(),
                style: const TextStyle(
                  color: _accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.entry});

  final PollChartEntry entry;

  @override
  Widget build(BuildContext context) {
    final pct = entry.percentage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                entry.label,
                style: TextStyle(
                  color: ShareablePollResultCard._ink,
                  fontWeight: entry.selected
                      ? FontWeight.w800
                      : FontWeight.w600,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${pct.toStringAsFixed(0)}%',
              style: const TextStyle(
                color: ShareablePollResultCard._ink,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: [
                const Positioned.fill(
                  child: ColoredBox(color: ShareablePollResultCard._track),
                ),
                FractionallySizedBox(
                  widthFactor: (pct / 100).clamp(0.0, 1.0),
                  child: ColoredBox(
                    color: entry.selected
                        ? ShareablePollResultCard._accent
                        : ShareablePollResultCard._accent.withValues(
                            alpha: 0.55,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
