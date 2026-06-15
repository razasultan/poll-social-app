import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poll_social_app/widgets/poll_card.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

void main() {
  group('PollOptionButton (pre-vote choice)', () {
    testWidgets('renders its label and reports taps', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          PollOptionButton(label: 'Coffee', onPressed: () => tapped = true),
        ),
      );

      expect(find.text('Coffee'), findsOneWidget);
      await tester.tap(find.text('Coffee'));
      expect(tapped, isTrue);
    });

    testWidgets('does not invoke onPressed when disabled', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          PollOptionButton(
            label: 'Tea',
            enabled: false,
            onPressed: () => tapped = true,
          ),
        ),
      );

      await tester.tap(find.text('Tea'));
      expect(tapped, isFalse);
    });

    testWidgets('omits a media thumbnail when the option has no media', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(PollOptionButton(label: 'Plain', onPressed: () {})),
      );
      expect(find.byType(OptionMediaThumbnail), findsNothing);
    });
  });

  group('PollResultBar (post-vote / expired results)', () {
    testWidgets('shows the option label, vote share, and progress bar', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          PollResultBar(
            label: 'Coffee',
            optionKey: 'opt-1',
            count: 3,
            totalVotes: 4,
            selected: false,
            percentage: 75,
          ),
        ),
      );

      expect(find.text('Coffee'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
      expect(find.byType(FractionallySizedBox), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('result_selected_indicator')),
        findsNothing,
      );
    });

    testWidgets('highlights the option the viewer selected', (tester) async {
      await tester.pumpWidget(
        _wrap(
          PollResultBar(
            label: 'Coffee',
            optionKey: 'opt-1',
            count: 3,
            totalVotes: 4,
            selected: true,
            percentage: 75,
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('result_selected_indicator')),
        findsOneWidget,
      );
    });

    testWidgets('omits a media thumbnail when the option has no media', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          PollResultBar(
            label: 'Coffee',
            optionKey: 'opt-1',
            count: 0,
            totalVotes: 0,
            selected: false,
            percentage: 0,
          ),
        ),
      );
      expect(find.byType(OptionMediaThumbnail), findsNothing);
    });
  });

  group('EngagementRow', () {
    testWidgets('renders engagement counts and reacts to like taps', (
      tester,
    ) async {
      var likeTapped = false;
      await tester.pumpWidget(
        _wrap(
          EngagementRow(
            votesCount: 12,
            likesCount: 5,
            commentsCount: 2,
            sharesCount: 1,
            liked: false,
            likeLoading: false,
            onLikeTap: () => likeTapped = true,
          ),
        ),
      );

      expect(find.text('12'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.favorite_border_rounded));
      expect(likeTapped, isTrue);
    });

    testWidgets('shows a filled heart once liked', (tester) async {
      await tester.pumpWidget(
        _wrap(
          EngagementRow(
            votesCount: 0,
            likesCount: 0,
            commentsCount: 0,
            sharesCount: 0,
            liked: true,
            likeLoading: false,
            onLikeTap: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
    });
  });

  group('PollMediaPreview (backward compatibility for media-less polls)', () {
    testWidgets('renders nothing when the poll has no main media', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const PollMediaPreview(mediaUrl: null)));
      expect(find.byType(Image), findsNothing);

      await tester.pumpWidget(_wrap(const PollMediaPreview(mediaUrl: '')));
      expect(find.byType(Image), findsNothing);
    });
  });

  group('OptionMediaThumbnail', () {
    testWidgets(
      'shows a play glyph over video options without fetching the network',
      (tester) async {
        await tester.pumpWidget(
          _wrap(const OptionMediaThumbnail(mediaUrl: null, mediaType: 'video')),
        );
        expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      },
    );

    testWidgets('omits the play glyph for image options', (tester) async {
      await tester.pumpWidget(
        _wrap(const OptionMediaThumbnail(mediaUrl: null, mediaType: 'image')),
      );
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    });
  });
}
