import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poll_social_app/screens/auth/signup_screen.dart';

import '../test_helpers/supabase_test_init.dart';

void main() {
  setUpAll(() async {
    await initSupabaseForTests();
  });

  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('renders the create-account header and OAuth buttons', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const SignupScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
  });
}
