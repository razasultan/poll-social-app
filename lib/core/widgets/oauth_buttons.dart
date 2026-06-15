import 'dart:math' as math;

import 'package:flutter/material.dart';

/// "Continue with Google" / "Continue with Apple" buttons plus an "or"
/// divider. Stateless and presentational — callers supply tap callbacks and
/// a shared [loading] flag (disables both buttons while any auth call is in
/// flight).
class OAuthButtonsSection extends StatelessWidget {
  const OAuthButtonsSection({
    super.key,
    required this.onGoogleTap,
    required this.onAppleTap,
    this.loading = false,
  });

  final VoidCallback? onGoogleTap;
  final VoidCallback? onAppleTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: loading ? null : onGoogleTap,
            icon: const GoogleLogoIcon(),
            label: const Text('Continue with Google'),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              side: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: loading ? null : onAppleTap,
            icon: const Icon(Icons.apple),
            label: const Text('Continue with Apple'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const _OrDivider(),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(child: Divider(color: cs.outlineVariant)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        Expanded(child: Divider(color: cs.outlineVariant)),
      ],
    );
  }
}

/// Hand-painted four-color Google "G" glyph, avoiding the need for a bundled
/// logo asset.
class GoogleLogoIcon extends StatelessWidget {
  const GoogleLogoIcon({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: const _GoogleGPainter(),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  const _GoogleGPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.22;
    final radius = (size.shortestSide - strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    const colors = [
      Color(0xFF4285F4), // blue
      Color(0xFF34A853), // green
      Color(0xFFFBBC05), // yellow
      Color(0xFFEA4335), // red
    ];

    const start = -1.1; // radians; leaves a gap on the right for the crossbar
    const sweepEach = (2 * math.pi) / 4 * 0.96;

    var angle = start;
    for (final color in colors) {
      arcPaint.color = color;
      canvas.drawArc(rect, angle, sweepEach, false, arcPaint);
      angle += (2 * math.pi) / 4;
    }

    // Blue crossbar of the "G", filling the gap on the right side.
    final barPaint = Paint()..color = const Color(0xFF4285F4);
    final barRect = Rect.fromLTWH(
      center.dx,
      center.dy - strokeWidth / 2,
      radius + strokeWidth / 2,
      strokeWidth,
    );
    canvas.drawRect(barRect, barPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
