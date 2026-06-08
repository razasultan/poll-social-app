import 'package:flutter_test/flutter_test.dart';
import 'package:poll_social_app/widgets/poll_result_chart.dart';

void main() {
  group('buildPollChartEntries', () {
    final options = [
      {'id': 'opt-1', 'option_text': 'Coffee', 'option_order': 0},
      {'id': 'opt-2', 'option_text': 'Tea', 'option_order': 1},
      {'id': 'opt-3', 'option_text': 'Neither', 'option_order': 2},
    ];

    test('maps each option to its label, count, and percentage in order', () {
      final entries = buildPollChartEntries(
        options: options,
        voteCounts: const {'opt-1': 3, 'opt-2': 1},
        totalVotes: 4,
        selectedOptionId: null,
      );

      expect(entries, hasLength(3));
      expect(entries[0].label, 'Coffee');
      expect(entries[0].count, 3);
      expect(entries[0].percentage, 75);
      expect(entries[1].label, 'Tea');
      expect(entries[1].count, 1);
      expect(entries[1].percentage, 25);
      expect(entries[2].label, 'Neither');
      expect(entries[2].count, 0);
      expect(entries[2].percentage, 0);
    });

    test('marks only the matching option as selected', () {
      final entries = buildPollChartEntries(
        options: options,
        voteCounts: const {'opt-1': 3, 'opt-2': 1},
        totalVotes: 4,
        selectedOptionId: 'opt-2',
      );

      expect(entries[0].selected, isFalse);
      expect(entries[1].selected, isTrue);
      expect(entries[2].selected, isFalse);
    });

    test('treats a null/unknown selection as nothing selected', () {
      final entries = buildPollChartEntries(
        options: options,
        voteCounts: const {},
        totalVotes: 0,
        selectedOptionId: 'does-not-exist',
      );

      expect(entries.every((e) => !e.selected), isTrue);
      expect(entries.every((e) => e.percentage == 0), isTrue);
    });

    test('returns an empty list for an empty option set', () {
      final entries = buildPollChartEntries(
        options: const [],
        voteCounts: const {},
        totalVotes: 0,
        selectedOptionId: null,
      );

      expect(entries, isEmpty);
    });
  });
}
