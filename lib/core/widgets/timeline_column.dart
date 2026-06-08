import 'package:flutter/material.dart';

/// Centers feed/profile/poll-detail content into an X-style ~600px column on
/// wide (web/desktop) viewports, with thin hairline side borders that delimit
/// it — matching X's centered timeline. On narrow/mobile viewports the column
/// fills the available width with no borders, so nothing changes there.
class TimelineColumn extends StatelessWidget {
  const TimelineColumn({super.key, required this.child});

  final Widget child;

  static const double maxWidth = 600;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= maxWidth) return child;

        final cs = Theme.of(context).colorScheme;
        return Align(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxWidth),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: cs.outlineVariant),
                  right: BorderSide(color: cs.outlineVariant),
                ),
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
