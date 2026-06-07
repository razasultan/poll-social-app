import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';

/// Subtle floating badge shown in debug builds when [AppConfig.isDev].
class DevEnvironmentBanner extends StatelessWidget {
  const DevEnvironmentBanner({super.key, required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode || !AppConfig.isDev) {
      return child ?? const SizedBox.shrink();
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ?child,
        Positioned(
          top: MediaQuery.paddingOf(context).top + 6,
          right: 10,
          child: IgnorePointer(
            child: Material(
              elevation: 1,
              color: Colors.orange.shade700.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(4),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  'DEV',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
