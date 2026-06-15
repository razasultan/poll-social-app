import 'package:flutter/material.dart';

import '../screens/profile_screen.dart';

/// Navigates to [ProfileScreen] for [userId]. No-op if [userId] is empty.
void openProfile(BuildContext context, String userId) {
  final id = userId.trim();
  if (id.isEmpty) return;
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (context) => ProfileScreen(userId: id)),
  );
}
