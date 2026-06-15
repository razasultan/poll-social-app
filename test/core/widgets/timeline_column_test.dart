import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poll_social_app/core/widgets/timeline_column.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  const contentKey = ValueKey<String>('timeline_content');

  Widget fillerContent() => const SizedBox(
    key: contentKey,
    height: 400,
    width: double.infinity,
    child: ColoredBox(color: Colors.blue),
  );

  testWidgets(
    'constrains content to maxWidth and centers it on wide viewports',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(wrap(TimelineColumn(child: fillerContent())));
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byKey(contentKey));
      expect(size.width, TimelineColumn.maxWidth);

      final topLeft = tester.getTopLeft(find.byKey(contentKey));
      expect(topLeft.dx, greaterThan(0));
    },
  );

  testWidgets(
    'fills the available width with no centering on narrow viewports',
    (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(wrap(TimelineColumn(child: fillerContent())));
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byKey(contentKey));
      expect(size.width, 420);

      final topLeft = tester.getTopLeft(find.byKey(contentKey));
      expect(topLeft.dx, 0);
    },
  );
}
