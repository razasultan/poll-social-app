import 'package:flutter/material.dart';

import '../screens/create_poll_screen.dart';
import '../screens/edit_poll_screen.dart';

/// Matches MainShell's own wide-layout breakpoint (NavigationRail vs
/// BottomNavigationBar), so the modal switches presentation at the same
/// point the rest of the shell does.
const double _wideLayoutBreakpoint = 700;

/// Presents [CreatePollScreen] as a centered dialog on desktop/tablet
/// (>=700px) or a full-height bottom sheet on mobile, instead of a full-page
/// route that hides the feed entirely. Returns the same `true`/`null` result
/// [CreatePollScreen] already pops with on publish/cancel.
Future<bool?> showCreatePollModal(BuildContext context) {
  final isWide = MediaQuery.sizeOf(context).width >= _wideLayoutBreakpoint;

  if (isWide) {
    return showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
          child: const CreatePollScreen(),
        ),
      ),
    );
  }

  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.94,
      child: const CreatePollScreen(),
    ),
  );
}

/// Presents [EditPollScreen] using the same adaptive presentation as
/// [showCreatePollModal]: a centered dialog on wide screens, a tall bottom
/// sheet on mobile. Returns [true] when saved, ['deleted'] when the poll is
/// deleted, or null on cancel.
Future<dynamic> showEditPollModal(
  BuildContext context,
  Map<String, dynamic> poll,
) {
  final isWide = MediaQuery.sizeOf(context).width >= _wideLayoutBreakpoint;

  if (isWide) {
    return showDialog<dynamic>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 820),
          child: EditPollScreen(poll: poll),
        ),
      ),
    );
  }

  return showModalBottomSheet<dynamic>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.94,
      child: EditPollScreen(poll: poll),
    ),
  );
}
