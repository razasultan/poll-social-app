import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poll_social_app/screens/poll_detail_screen.dart';

KeyEvent _keyDown(LogicalKeyboardKey key) => KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.enter,
  logicalKey: key,
  timeStamp: Duration.zero,
);

KeyEvent _keyUp(LogicalKeyboardKey key) => KeyUpEvent(
  physicalKey: PhysicalKeyboardKey.enter,
  logicalKey: key,
  timeStamp: Duration.zero,
);

void main() {
  group('shouldSubmitCommentOnEnter', () {
    test('a lone Enter key-down (no shift) should submit', () {
      expect(
        shouldSubmitCommentOnEnter(
          _keyDown(LogicalKeyboardKey.enter),
          shiftPressed: false,
        ),
        isTrue,
      );
    });

    test('a lone numpad Enter key-down (no shift) should submit', () {
      expect(
        shouldSubmitCommentOnEnter(
          _keyDown(LogicalKeyboardKey.numpadEnter),
          shiftPressed: false,
        ),
        isTrue,
      );
    });

    test('Shift+Enter should NOT submit (lets the newline through)', () {
      expect(
        shouldSubmitCommentOnEnter(
          _keyDown(LogicalKeyboardKey.enter),
          shiftPressed: true,
        ),
        isFalse,
      );
    });

    test(
      'an Enter key-up event should NOT submit (only key-down triggers)',
      () {
        expect(
          shouldSubmitCommentOnEnter(
            _keyUp(LogicalKeyboardKey.enter),
            shiftPressed: false,
          ),
          isFalse,
        );
      },
    );

    test('a non-Enter key should NOT submit', () {
      expect(
        shouldSubmitCommentOnEnter(
          _keyDown(LogicalKeyboardKey.keyA),
          shiftPressed: false,
        ),
        isFalse,
      );
    });
  });
}
