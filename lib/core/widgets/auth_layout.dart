import 'package:flutter/material.dart';

/// Shared auth-screen scaffold body. On narrow viewports it just centers
/// [child] (a [Form]) in a scrollable column, matching the previous mobile
/// layout. On wide (desktop web) viewports it adds a branded left panel so
/// the sign-in/sign-up screens don't read as a bare floating form on a large
/// canvas.
class AuthLayout extends StatelessWidget {
  const AuthLayout({super.key, required this.child});

  final Widget child;

  static const double _wideBreakpoint = 880;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _wideBreakpoint;

        final form = SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: child,
            ),
          ),
        );

        if (!isWide) return _GlowBackdrop(child: form);

        return Row(
          children: [
            const Expanded(child: _BrandPanel()),
            Expanded(child: _GlowBackdrop(child: form)),
          ],
        );
      },
    );
  }
}

/// Soft radial glow behind the form so the right-hand panel doesn't read as
/// a flat void on large screens.
class _GlowBackdrop extends StatelessWidget {
  const _GlowBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.5),
          radius: 1.1,
          colors: [
            cs.primary.withValues(alpha: 0.10),
            cs.surface.withValues(alpha: 0),
          ],
        ),
      ),
      child: child,
    );
  }
}

/// Decorative left panel: gradient backdrop, wordmark, headline, and a small
/// "live poll" preview card so the panel reads as a product showcase rather
/// than empty space.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isLight
              ? const [Color(0xFF0F1419), Color(0xFF1D3A52)]
              : const [Color(0xFF000000), Color(0xFF0B2436)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -70,
            top: -70,
            child: _GhostCircle(
              size: 240,
              color: const Color(0xFF1D9BF0).withValues(alpha: 0.20),
            ),
          ),
          Positioned(
            left: -60,
            bottom: -40,
            child: _GhostCircle(
              size: 220,
              color: const Color(0xFFF91880).withValues(alpha: 0.14),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(48),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.how_to_vote_rounded,
                            color: Color(0xFF1D9BF0),
                            size: 34,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Poll Social',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 36),
                      Text(
                        'Where your\nopinion is\nthe headline.',
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          height: 1.12,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: 320,
                        child: Text(
                          'Ask the question, drop the options, and watch real opinions '
                          'roll in — live.',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: Colors.white.withValues(alpha: 0.65),
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                      const _PollPreviewCard(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GhostCircle extends StatelessWidget {
  const _GhostCircle({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// A miniature poll-result card matching the live feed's visual language —
/// gives the brand panel a concrete sense of "this is the product".
class _PollPreviewCard extends StatelessWidget {
  const _PollPreviewCard();

  static const _entries = [
    (label: 'Yes, every week', fraction: 0.64, selected: true),
    (label: 'A few days', fraction: 0.24, selected: false),
    (label: 'No, never', fraction: 0.12, selected: false),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 320,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(
                  color: Color(0xFF1D9BF0),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Text(
                  'P',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Poll Social · now',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF00BA7C).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(
                    color: Color(0xFF00BA7C),
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Should remote work be the default?',
            style: theme.textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 14),
          for (final e in _entries) ...[
            _PreviewResultBar(
              label: e.label,
              fraction: e.fraction,
              selected: e.selected,
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 2),
          Text(
            '12.4K votes · Ends in 6h',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewResultBar extends StatelessWidget {
  const _PreviewResultBar({
    required this.label,
    required this.fraction,
    required this.selected,
  });

  final String label;
  final double fraction;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fillColor = selected
        ? const Color(0xFF1D9BF0).withValues(alpha: 0.35)
        : Colors.white.withValues(alpha: 0.16);

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 30,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.white.withValues(alpha: 0.06)),
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fraction,
                heightFactor: 1,
                child: ColoredBox(color: fillColor),
              ),
            ),
            if (selected)
              Align(
                alignment: Alignment.centerLeft,
                child: Container(width: 3, color: const Color(0xFF1D9BF0)),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${(fraction * 100).round()}%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
