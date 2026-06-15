import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poll_social_app/core/constants/branding.dart';
import 'package:poll_social_app/core/widgets/brand_mark.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('BrandMark renders an icon', (tester) async {
    await tester.pumpWidget(wrap(const BrandMark()));

    expect(find.byType(Icon), findsOneWidget);
  });

  testWidgets('BrandMark renders inside a tile when tile is true', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const BrandMark(tile: true)));

    expect(find.byType(Container), findsWidgets);
    expect(find.byType(Icon), findsOneWidget);
  });

  testWidgets('BrandWordmark renders the app name', (tester) async {
    await tester.pumpWidget(wrap(const BrandWordmark()));

    expect(find.text(Branding.appName), findsOneWidget);
  });
}
