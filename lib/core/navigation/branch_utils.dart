import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Returns the shell branch prefix ("/home", "/search", "/notifications",
/// "/profile") for the current go_router location. Used by widgets that
/// need to push sub-routes (poll detail, user profile) onto the right
/// branch stack without knowing the active tab at compile time.
String branchPrefixFor(BuildContext context) {
  final path = GoRouterState.of(context).uri.path;
  if (path.startsWith('/search')) return '/search';
  if (path.startsWith('/notifications')) return '/notifications';
  if (path.startsWith('/profile')) return '/profile';
  return '/home';
}
