import 'package:flutter_test/flutter_test.dart';
import 'package:poll_social_app/services/social_service.dart';

void main() {
  group('toggleCommentLikeState', () {
    test(
      'liking an unliked comment flips liked to true and increments count',
      () {
        final result = toggleCommentLikeState(
          currentlyLiked: false,
          currentLikesCount: 0,
        );
        expect(result.liked, isTrue);
        expect(result.likesCount, 1);
      },
    );

    test(
      'unliking a liked comment flips liked to false and decrements count',
      () {
        final result = toggleCommentLikeState(
          currentlyLiked: true,
          currentLikesCount: 1,
        );
        expect(result.liked, isFalse);
        expect(result.likesCount, 0);
      },
    );

    test(
      'increments correctly from a non-zero count (other users already liked it)',
      () {
        final result = toggleCommentLikeState(
          currentlyLiked: false,
          currentLikesCount: 5,
        );
        expect(result.liked, isTrue);
        expect(result.likesCount, 6);
      },
    );

    test('decrements correctly from a count above 1', () {
      final result = toggleCommentLikeState(
        currentlyLiked: true,
        currentLikesCount: 5,
      );
      expect(result.liked, isFalse);
      expect(result.likesCount, 4);
    });

    test(
      'applying the result of a like then its inverse (unlike) is idempotent',
      () {
        final liked = toggleCommentLikeState(
          currentlyLiked: false,
          currentLikesCount: 2,
        );
        final unliked = toggleCommentLikeState(
          currentlyLiked: liked.liked,
          currentLikesCount: liked.likesCount,
        );
        expect(unliked.liked, isFalse);
        expect(unliked.likesCount, 2);
      },
    );
  });
}
