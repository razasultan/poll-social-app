import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../core/navigation/branch_utils.dart';

/// Pushes [ProfileScreen] for [userId] onto the current branch's navigator
/// stack. No-op when [userId] is empty.
void openProfile(BuildContext context, String userId) {
  final id = userId.trim();
  if (id.isEmpty) return;
  context.push('${branchPrefixFor(context)}/user/$id');
}
