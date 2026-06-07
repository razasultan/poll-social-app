import 'package:flutter/material.dart';

import '../main_shell.dart';

/// Entry point of the authenticated app shell.
///
/// This is a guest-first app: browsing is always available, whether or not
/// the user is signed in. [MainShell] adapts its navigation and screens show
/// auth prompts only when a guest attempts an action that requires login.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return const MainShell();
  }
}
