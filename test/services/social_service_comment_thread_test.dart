import 'package:flutter_test/flutter_test.dart';
import 'package:poll_social_app/services/social_service.dart';

void main() {
  group('groupCommentsIntoThread', () {
    Map<String, dynamic> comment(String id, {String? parentId, String? text}) =>
        {
          'id': id,
          'parent_comment_id': parentId,
          'comment_text': text ?? 'comment $id',
          'created_at': '2026-01-01T00:00:0${id}Z',
        };

    test('empty input returns empty list', () {
      expect(groupCommentsIntoThread([]), isEmpty);
    });

    test('all top-level comments carry an empty replies list', () {
      final result = groupCommentsIntoThread([comment('1'), comment('2')]);
      expect(result, hasLength(2));
      expect(result[0]['replies'], isEmpty);
      expect(result[1]['replies'], isEmpty);
    });

    test('reply is attached to its parent and not in the top-level list', () {
      final result = groupCommentsIntoThread([
        comment('1'),
        comment('2', parentId: '1'),
      ]);
      expect(result, hasLength(1));
      final replies = result[0]['replies'] as List;
      expect(replies, hasLength(1));
      expect(replies[0]['id'], '2');
    });

    test('multiple replies attach to the correct parent in order', () {
      final result = groupCommentsIntoThread([
        comment('1'),
        comment('2', parentId: '1'),
        comment('3', parentId: '1'),
        comment('4'),
        comment('5', parentId: '4'),
      ]);
      expect(result, hasLength(2));
      final repliesOf1 = result[0]['replies'] as List;
      expect(repliesOf1.map((r) => r['id']), ['2', '3']);
      final repliesOf4 = result[1]['replies'] as List;
      expect(repliesOf4.map((r) => r['id']), ['5']);
    });

    test('reply whose parent is not in the list is silently dropped', () {
      final result = groupCommentsIntoThread([
        comment('1'),
        comment('orphan', parentId: 'deleted-parent-id'),
      ]);
      expect(result, hasLength(1));
      expect(result[0]['id'], '1');
      expect((result[0]['replies'] as List), isEmpty);
    });

    test('original comment fields are preserved on top-level items', () {
      final result = groupCommentsIntoThread([
        comment('1', text: 'hello world'),
      ]);
      expect(result[0]['comment_text'], 'hello world');
      expect(result[0]['id'], '1');
    });

    test('replies list preserves original field values', () {
      final result = groupCommentsIntoThread([
        comment('1'),
        comment('2', parentId: '1', text: 'reply text'),
      ]);
      final reply = (result[0]['replies'] as List)[0];
      expect(reply['comment_text'], 'reply text');
    });

    test('top-level order matches input order', () {
      final result = groupCommentsIntoThread([
        comment('3'),
        comment('1'),
        comment('2'),
      ]);
      expect(result.map((c) => c['id']), ['3', '1', '2']);
    });
  });
}
