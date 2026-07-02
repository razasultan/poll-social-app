import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Action-level auth gate for guest browsing.
///
/// Wrap any interactive action (vote, like, comment, follow, create, …) with
/// [requireAuth]: if the user is signed in, [onAuthenticated] runs immediately;
/// otherwise a login/signup prompt is shown instead of the action.
class AuthGuard {
  AuthGuard._();

  static Future<void> requireAuth(
    BuildContext context, {
    required Future<void> Function() onAuthenticated,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      await onAuthenticated();
      return;
    }
    await _showLoginPrompt(context);
  }

  static Future<void> _showLoginPrompt(BuildContext context) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Log in to interact with polls and follow creators.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop('login'),
                    child: const Text('Log in'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(sheetContext).pop('signup'),
                    child: const Text('Create account'),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('Not now'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!context.mounted || result == null) return;

    if (result == 'login') {
      context.push('/login');
    } else if (result == 'signup') {
      context.push('/signup');
    }
  }
}
