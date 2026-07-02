import 'package:flutter/material.dart';

/// Legacy entry-point widget — superseded by [appRouter] (go_router).
/// Kept as a stub so existing test imports don't break.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
