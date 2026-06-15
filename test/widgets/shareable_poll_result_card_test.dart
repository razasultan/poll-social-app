import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poll_social_app/widgets/poll_result_chart.dart';
import 'package:poll_social_app/widgets/shareable_poll_result_card.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  const entries = [
    PollChartEntry(label: 'Coffee', count: 3, percentage: 75, selected: true),
    PollChartEntry(label: 'Tea', count: 1, percentage: 25, selected: false),
  ];

  group('ShareablePollResultCard', () {
    testWidgets('renders the question, branding, options, and vote total', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ShareablePollResultCard(
            question: 'Coffee or tea?',
            entries: entries,
            totalVotes: 4,
          ),
        ),
      );

      expect(find.text('Poll Social'), findsOneWidget);
      expect(find.text('Coffee or tea?'), findsOneWidget);
      expect(find.text('Coffee'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('Tea'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
      expect(find.text('4 votes'), findsOneWidget);
    });

    testWidgets(
      'omits optional rows when post text, author, and share URL are absent',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const ShareablePollResultCard(
              question: 'Coffee or tea?',
              entries: entries,
              totalVotes: 4,
            ),
          ),
        );

        expect(find.textContaining('@'), findsNothing);
      },
    );

    testWidgets(
      'renders post text, author handle, and share URL when provided',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const ShareablePollResultCard(
              question: 'Coffee or tea?',
              entries: entries,
              totalVotes: 4,
              postText: 'A classic debate.',
              authorName: 'razasultan',
              shareUrl: 'poll-social.app/p/abc123',
            ),
          ),
        );

        expect(find.text('A classic debate.'), findsOneWidget);
        expect(find.text('@razasultan'), findsOneWidget);
        expect(find.text('poll-social.app/p/abc123'), findsOneWidget);
      },
    );

    testWidgets('uses the singular "vote" label for exactly one vote', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ShareablePollResultCard(
            question: 'Coffee or tea?',
            entries: [
              PollChartEntry(
                label: 'Coffee',
                count: 1,
                percentage: 100,
                selected: true,
              ),
            ],
            totalVotes: 1,
          ),
        ),
      );

      expect(find.text('1 vote'), findsOneWidget);
      expect(find.text('1 votes'), findsNothing);
    });
  });
}
