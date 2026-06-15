import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poll_social_app/core/widgets/oauth_buttons.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows Google and Apple buttons', (tester) async {
    await tester.pumpWidget(
      wrap(OAuthButtonsSection(onGoogleTap: () {}, onAppleTap: () {})),
    );

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.text('or'), findsOneWidget);
  });

  testWidgets('taps invoke the provided callbacks', (tester) async {
    var googleTaps = 0;
    var appleTaps = 0;

    await tester.pumpWidget(
      wrap(
        OAuthButtonsSection(
          onGoogleTap: () => googleTaps++,
          onAppleTap: () => appleTaps++,
        ),
      ),
    );

    await tester.tap(find.text('Continue with Google'));
    await tester.tap(find.text('Continue with Apple'));
    await tester.pump();

    expect(googleTaps, 1);
    expect(appleTaps, 1);
  });

  testWidgets('disables both buttons while loading', (tester) async {
    var googleTaps = 0;
    var appleTaps = 0;

    await tester.pumpWidget(
      wrap(
        OAuthButtonsSection(
          loading: true,
          onGoogleTap: () => googleTaps++,
          onAppleTap: () => appleTaps++,
        ),
      ),
    );

    await tester.tap(find.text('Continue with Google'), warnIfMissed: false);
    await tester.tap(find.text('Continue with Apple'), warnIfMissed: false);
    await tester.pump();

    expect(googleTaps, 0);
    expect(appleTaps, 0);
  });
}
