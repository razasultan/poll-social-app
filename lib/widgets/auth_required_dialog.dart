import 'package:flutter/material.dart';

import '../screens/auth/login_screen.dart';
import '../screens/auth/signup_screen.dart';

/// Shows a "Login required" prompt for guests trying to use a gated action.
///
/// Use from any screen: `await showAuthRequiredDialog(context);`
Future<void> showAuthRequiredDialog(BuildContext context) async {
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Login required'),
        content: const Text('Please log in to continue'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('login'),
            child: const Text('Login'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('signup'),
            child: const Text('Sign up'),
          ),
        ],
      );
    },
  );

  if (!context.mounted || result == null) return;

  if (result == 'login') {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  } else if (result == 'signup') {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SignupScreen()),
    );
  }
}
