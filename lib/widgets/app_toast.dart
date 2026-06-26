import 'package:flutter/material.dart';

/// Visual/semantic variant for [AppToast].
enum AppToastType { success, error, warning, info }

/// Shared toast/snackbar helper so feedback across the app is visually
/// consistent (icon + color per variant) and doesn't get hidden behind
/// bottom-pinned UI like a comment input bar.
///
/// Replaces ad-hoc `ScaffoldMessenger.of(context).showSnackBar(...)` calls.
/// Existing call sites are being migrated incrementally — see the
/// "Replace Full-Screen Notifications With Toast/Snackbar System" issue.
class AppToast {
  AppToast._();

  static void success(
    BuildContext context,
    String message, {
    double extraBottomOffset = 0,
  }) => _show(
    context,
    message,
    type: AppToastType.success,
    extraBottomOffset: extraBottomOffset,
  );

  static void error(
    BuildContext context,
    String message, {
    double extraBottomOffset = 0,
  }) => _show(
    context,
    message,
    type: AppToastType.error,
    extraBottomOffset: extraBottomOffset,
  );

  static void warning(
    BuildContext context,
    String message, {
    double extraBottomOffset = 0,
  }) => _show(
    context,
    message,
    type: AppToastType.warning,
    extraBottomOffset: extraBottomOffset,
  );

  static void info(
    BuildContext context,
    String message, {
    double extraBottomOffset = 0,
  }) => _show(
    context,
    message,
    type: AppToastType.info,
    extraBottomOffset: extraBottomOffset,
  );

  static void _show(
    BuildContext context,
    String message, {
    required AppToastType type,
    double extraBottomOffset = 0,
  }) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final cs = Theme.of(context).colorScheme;
    final (icon, background, foreground) = switch (type) {
      AppToastType.success => (
        Icons.check_circle_rounded,
        cs.primary,
        cs.onPrimary,
      ),
      AppToastType.error => (Icons.error_rounded, cs.error, cs.onError),
      AppToastType.warning => (
        Icons.warning_rounded,
        Colors.amber.shade800,
        Colors.white,
      ),
      AppToastType.info => (
        Icons.info_rounded,
        cs.secondaryContainer,
        cs.onSecondaryContainer,
      ),
    };

    // Floating snackbars don't know about bottom-pinned widgets that aren't
    // Scaffold.bottomNavigationBar/bottomSheet (e.g. a comment input bar
    // laid out as a regular Column child) — callers near one of those pass
    // extraBottomOffset to clear it, on top of the device safe area.
    final bottomInset =
        MediaQuery.viewPaddingOf(context).bottom + 12 + extraBottomOffset;

    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Semantics(
            liveRegion: true,
            child: Row(
              children: [
                Icon(icon, color: foreground, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(message, style: TextStyle(color: foreground)),
                ),
              ],
            ),
          ),
          backgroundColor: background,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: EdgeInsets.fromLTRB(16, 0, 16, bottomInset),
          duration: const Duration(seconds: 3),
        ),
      );
  }
}
