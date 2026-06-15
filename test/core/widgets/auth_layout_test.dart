import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poll_social_app/core/constants/branding.dart';
import 'package:poll_social_app/core/widgets/auth_layout.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: AuthLayout(child: child)),
  );

  testWidgets('shows the brand panel content on wide viewports', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap(const SizedBox.shrink()));
    await tester.pumpAndSettle();

    expect(find.text(Branding.appName), findsOneWidget);
    expect(find.textContaining(Branding.heroTitlePrefix), findsOneWidget);
    expect(find.textContaining(Branding.heroTitleHighlight), findsOneWidget);

    expect(find.text('Alex Johnson'), findsOneWidget);
    expect(find.text('66%'), findsOneWidget);
    expect(find.text('24%'), findsOneWidget);
    expect(find.text('12%'), findsOneWidget);
    expect(find.text('3.2k'), findsOneWidget);

    expect(find.text('Real people'), findsOneWidget);
    expect(find.text('Live results'), findsOneWidget);
    expect(find.text('Built on trust'), findsOneWidget);
  });

  testWidgets('hides the brand panel on narrow viewports', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap(const SizedBox.shrink()));
    await tester.pumpAndSettle();

    expect(find.text('Alex Johnson'), findsNothing);
  });
}
