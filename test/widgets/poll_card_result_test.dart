import 'package:flutter_test/flutter_test.dart';
import 'package:poll_social_app/widgets/poll_card.dart';

void main() {
  group('pollResultPercentage', () {
    test('returns 0 when there are no votes', () {
      expect(pollResultPercentage(0, 0), 0);
    });

    test('computes a simple share of the total', () {
      expect(pollResultPercentage(1, 4), 25);
      expect(pollResultPercentage(3, 4), 75);
    });

    test('handles a single option taking all votes', () {
      expect(pollResultPercentage(10, 10), 100);
    });

    test('does not divide by zero when total is negative or zero', () {
      expect(pollResultPercentage(5, 0), 0);
      expect(pollResultPercentage(5, -1), 0);
    });

    test('keeps fractional precision for uneven splits', () {
      expect(pollResultPercentage(1, 3), closeTo(33.333, 0.001));
    });
  });

  group('pollAllowsAnonymousVote', () {
    test('allows anonymous voting on public polls', () {
      expect(pollAllowsAnonymousVote({'visibility': 'public'}), true);
    });

    test('blocks anonymous voting on followers-only polls', () {
      expect(pollAllowsAnonymousVote({'visibility': 'followers'}), false);
    });

    test('blocks anonymous voting on private polls', () {
      expect(pollAllowsAnonymousVote({'visibility': 'private'}), false);
    });

    test('blocks anonymous voting when visibility is missing', () {
      expect(pollAllowsAnonymousVote({}), false);
    });
  });
}
