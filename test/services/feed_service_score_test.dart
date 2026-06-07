import 'package:flutter_test/flutter_test.dart';
import 'package:poll_social_app/services/feed_service.dart';

void main() {
  final now = DateTime(2026, 1, 1, 12);

  Map<String, dynamic> poll({
    String id = 'p1',
    String userId = 'u1',
    int votes = 0,
    DateTime? createdAt,
  }) {
    return {
      'id': id,
      'user_id': userId,
      'created_at': (createdAt ?? now).toIso8601String(),
      'poll_analytics': {'votes_count': votes},
    };
  }

  group('FeedService.computeForYouScore', () {
    test('boosts polls from followed authors', () {
      final p = poll(userId: 'friend');
      final following = FeedService.computeForYouScore(
        p,
        followingUserIds: {'friend'},
        votedPollIds: {},
        now: now,
      );
      final stranger = FeedService.computeForYouScore(
        p,
        followingUserIds: {},
        votedPollIds: {},
        now: now,
      );
      expect(following - stranger, closeTo(10, 0.001));
    });

    test('boosts polls the user has not voted on', () {
      final p = poll(id: 'p1');
      final notVoted = FeedService.computeForYouScore(
        p,
        followingUserIds: {},
        votedPollIds: {},
        now: now,
      );
      final voted = FeedService.computeForYouScore(
        p,
        followingUserIds: {},
        votedPollIds: {'p1'},
        now: now,
      );
      expect(notVoted - voted, closeTo(5, 0.001));
    });

    test('adds a tenth of the vote count', () {
      final p = poll(votes: 30);
      final score = FeedService.computeForYouScore(
        p,
        followingUserIds: {},
        votedPollIds: {'p1'},
        now: now,
      );
      // base contributions: not-following (0) + already-voted (0) + votes/10 (3) - age (0)
      expect(score, closeTo(3, 0.001));
    });

    test('penalizes older polls relative to fresher ones', () {
      final fresh = poll(id: 'fresh', createdAt: now);
      final old = poll(id: 'old', createdAt: now.subtract(const Duration(hours: 50)));

      final freshScore = FeedService.computeForYouScore(
        fresh,
        followingUserIds: {},
        votedPollIds: {'fresh', 'old'},
        now: now,
      );
      final oldScore = FeedService.computeForYouScore(
        old,
        followingUserIds: {},
        votedPollIds: {'fresh', 'old'},
        now: now,
      );
      expect(freshScore, greaterThan(oldScore));
      expect(freshScore - oldScore, closeTo(10, 0.001));
    });

    test('combines all factors additively', () {
      final p = poll(id: 'p1', userId: 'friend', votes: 20, createdAt: now.subtract(const Duration(hours: 10)));
      final score = FeedService.computeForYouScore(
        p,
        followingUserIds: {'friend'},
        votedPollIds: {},
        now: now,
      );
      // following (10) + not voted (5) + votes/10 (2) - hoursOld/5 (2)
      expect(score, closeTo(15, 0.001));
    });
  });
}
