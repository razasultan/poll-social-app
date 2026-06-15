import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poll_social_app/screens/auth/login_screen.dart';

import '../test_helpers/supabase_test_init.dart';

void main() {
  setUpAll(() async {
    await initSupabaseForTests();
  });

  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('renders welcome header, OAuth buttons, and form fields', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const LoginScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in to vote and share polls'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
  });

  testWidgets('password visibility toggle flips obscureText and icon', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const LoginScreen()));
    await tester.pumpAndSettle();

    final field = find.descendant(
      of: find.widgetWithText(TextFormField, 'Password'),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(field).obscureText, isTrue);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();

    expect(tester.widget<EditableText>(field).obscureText, isFalse);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
  });

  testWidgets('tapping a OAuth button does not crash', (tester) async {
    await tester.pumpWidget(wrap(const LoginScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue with Google'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
  });
}
