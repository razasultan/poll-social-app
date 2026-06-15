import 'package:flutter/material.dart';

import '../constants/branding.dart';

/// Centralized brand glyph. Currently renders [Icons.how_to_vote_rounded],
/// optionally inside a rounded-square "tile" background. Swap the icon (or
/// replace the body with an `Image.asset`) here to rebrand everywhere at
/// once.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 28,
    this.color,
    this.background,
    this.tile = false,
  });

  /// Icon size, or the tile's edge length when [tile] is true.
  final double size;

  /// Icon color. Defaults to [ColorScheme.primary], or white when [tile] is
  /// true and no explicit color is given.
  final Color? color;

  /// Tile background color when [tile] is true. Defaults to a primary-tinted
  /// surface.
  final Color? background;

  /// When true, wraps the glyph in a small rounded-square tile, matching the
  /// reference design's logo chip.
  final bool tile;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (!tile) {
      return Icon(
        Icons.how_to_vote_rounded,
        size: size,
        color: color ?? cs.primary,
      );
    }

    final iconColor = color ?? Colors.white;
    final tileColor = background ?? cs.primary;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tileColor,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.how_to_vote_rounded,
        size: size * 0.6,
        color: iconColor,
      ),
    );
  }
}

/// Wordmark text ([Branding.appName]) styled per the surrounding theme.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.color, this.style});

  /// Text color override.
  final Color? color;

  /// Style override. Defaults to `titleLarge` with a heavy weight.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      Branding.appName,
      style:
          style ??
          theme.textTheme.titleLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
    );
  }
}
