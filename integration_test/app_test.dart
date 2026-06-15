// E2E tests that drive the real app against the DEV Supabase backend.
//
// NOTE: as of Flutter 3.41.6, `-d chrome` is NOT supported for
// integration_test ("Web devices are not supported for integration tests
// yet"). Run against a desktop target instead, e.g. (from the project root):
//   flutter test integration_test/app_test.dart -d windows \
//     --dart-define=APP_ENV=dev \
//     --dart-define=SUPABASE_URL=https://uwomsxkvjqrvhdpnbkit.supabase.co \
//     --dart-define=SUPABASE_ANON_KEY=<dev anon key>
//
// Uses the seeded test account `gherkintester1`
// (razasultan.gherkintest1@gmail.com / GherkinTest123!), which already has a
// confirmed email and a profile row.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:poll_social_app/core/config/supabase_config.dart';
import 'package:poll_social_app/main.dart';
import 'package:poll_social_app/screens/create_poll_screen.dart';
import 'package:poll_social_app/screens/profile_screen.dart';
import 'package:poll_social_app/widgets/poll_card.dart';

const String _testEmail = 'razasultan.gherkintest1@gmail.com';
const String _testPassword = 'GherkinTest123!';

Future<void> _settle(WidgetTester tester) =>
    tester.pumpAndSettle(const Duration(milliseconds: 300));

Future<void> _signOutIfNeeded() async {
  if (Supabase.instance.client.auth.currentSession != null) {
    await Supabase.instance.client.auth.signOut();
  }
}

Future<void> _enterCredentialsAndSubmit(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  final emailField = find.widgetWithText(TextFormField, 'Email');
  final passwordField = find.widgetWithText(TextFormField, 'Password');
  expect(emailField, findsOneWidget);
  expect(passwordField, findsOneWidget);

  await tester.enterText(emailField, email);
  await tester.enterText(passwordField, password);
  await _settle(tester);

  await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
  await _settle(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await SupabaseConfig.initialize();
  });

  tearDownAll(() async {
    await _signOutIfNeeded();
  });

  testWidgets('shows an error when signing in with invalid credentials', (
    tester,
  ) async {
    await _signOutIfNeeded();

    await tester.pumpWidget(const MyApp());
    await _settle(tester);

    expect(find.text('Welcome back'), findsOneWidget);

    await _enterCredentialsAndSubmit(
      tester,
      email:
          'no-such-user-${DateTime.now().millisecondsSinceEpoch}@example.com',
      password: 'wrong-password-123',
    );

    // Still on the login screen — sign-in failed and surfaced a snackbar.
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets(
    'login -> create poll with topic & hashtag -> appears in feed & own profile -> like -> appears in Liked tab',
    (tester) async {
      await _signOutIfNeeded();

      await tester.pumpWidget(const MyApp());
      await _settle(tester);

      // --- Sign in -----------------------------------------------------------
      expect(find.text('Welcome back'), findsOneWidget);
      await _enterCredentialsAndSubmit(
        tester,
        email: _testEmail,
        password: _testPassword,
      );

      // AuthGate swaps to MainShell once the auth stream emits a session.
      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.text('Welcome back'), findsNothing);

      // --- Create a poll with a topic and a hashtag --------------------------
      final uniqueQuestion =
          'E2E test poll ${DateTime.now().millisecondsSinceEpoch}?';

      await tester.tap(find.text('Create'));
      await _settle(tester);
      expect(find.byType(CreatePollScreen), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Question'),
        uniqueQuestion,
      );

      // Drag directly on the (always-present) CreatePollScreen rather than
      // depending on a Scrollable finder — the form's Scrollable set shifts as
      // sections grow (topic suggestions, chips), which made scrollUntilVisible
      // flicker between targets and throw "Bad state: No element".
      final createPollScreen = find.byType(CreatePollScreen);
      Future<void> scrollFormUntilVisible(Finder target) async {
        for (var i = 0; i < 12; i++) {
          if (tester.any(target)) return;
          await tester.drag(createPollScreen, const Offset(0, -300));
          await _settle(tester);
        }
        expect(
          tester.any(target),
          isTrue,
          reason: 'Could not scroll target into view',
        );
      }

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Option 1'),
        'Option A',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Option 2'),
        'Option B',
      );
      await _settle(tester);

      // The remaining sections live further down the form's ListView — the
      // SliverChildListDelegate only materializes elements once they're
      // scrolled into the viewport, so scroll each into view before use.
      final topicSearchField = find.widgetWithText(
        TextFormField,
        'Search topics',
      );
      await scrollFormUntilVisible(topicSearchField);
      await _settle(tester);

      // Pick a topic suggestion (curated topics were seeded — "Music" exists).
      await tester.enterText(topicSearchField, 'Music');
      await tester.pumpAndSettle(const Duration(seconds: 1));
      final topicChip = find.widgetWithText(ActionChip, 'Music');
      if (tester.any(topicChip)) {
        await tester.tap(topicChip);
        await _settle(tester);
      }

      // Add a hashtag via free-text entry.
      final hashtagField = find.widgetWithText(TextFormField, 'Add hashtags');
      await scrollFormUntilVisible(hashtagField);
      await _settle(tester);
      await tester.enterText(hashtagField, '#e2etest ');
      await _settle(tester);
      expect(find.widgetWithText(InputChip, '#e2etest'), findsOneWidget);

      final publishButton = find.widgetWithText(FilledButton, 'Post');
      await scrollFormUntilVisible(publishButton);
      await _settle(tester);
      await tester.tap(publishButton);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Publishing pops back to the feed with a confirmation snackbar.
      expect(find.byType(CreatePollScreen), findsNothing);
      expect(find.text('Poll published'), findsOneWidget);

      // --- Verify it appears in the Latest feed ------------------------------
      await tester.tap(find.text('Latest'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      Future<bool> findInScrollable(Finder target, Finder scrollable) async {
        for (var i = 0; i < 8; i++) {
          if (tester.any(target)) return true;
          await tester.drag(scrollable, const Offset(0, -400));
          await _settle(tester);
        }
        return tester.any(target);
      }

      final questionFinder = find.text(uniqueQuestion);
      final feedScrollable = find.byType(Scrollable).first;
      expect(
        await findInScrollable(questionFinder, feedScrollable),
        isTrue,
        reason: 'Newly published poll should appear in the Latest feed',
      );

      // --- Verify it appears on the user's own profile (Bug #4 regression) ---
      await tester.tap(find.text('Profile'));
      await _settle(tester);

      // Note: "Polls" also appears as a profile stat-cell label, so scope to the Tab.
      expect(find.widgetWithText(Tab, 'Polls'), findsOneWidget);
      expect(find.widgetWithText(Tab, 'Liked'), findsOneWidget);

      final profileScrollable = find.byType(Scrollable).first;
      expect(
        await findInScrollable(questionFinder, profileScrollable),
        isTrue,
        reason:
            'Newly published poll should appear on the author\'s own profile '
            'immediately (validates the profile-reload-token fix)',
      );

      // --- Like the poll from the profile list --------------------------------
      // Scope to descendants of ProfileScreen — MainShell's IndexedStack keeps
      // the Latest feed mounted (and therefore matchable) in the background,
      // so an unscoped search could find/tap the wrong (offstage) PollCard.
      final pollCardFinder = find
          .ancestor(
            of: find.descendant(
              of: find.byType(ProfileScreen),
              matching: questionFinder,
            ),
            matching: find.byType(PollCard),
          )
          .first;
      final likeIcon = find.descendant(
        of: pollCardFinder,
        matching: find.byIcon(Icons.favorite_border_rounded),
      );
      if (tester.any(likeIcon)) {
        // Scroll so the icon sits clear of the bottom nav bar / overlays —
        // a partially-obscured tap previously landed on the wrong widget and
        // navigated away from the Profile screen entirely.
        await tester.ensureVisible(likeIcon);
        await _settle(tester);
        await tester.tap(likeIcon, warnIfMissed: false);
        await _settle(tester);
      }

      // The like action may still be on the Profile screen; if a stray tap
      // knocked us elsewhere, navigate back before looking for the tab.
      if (tester.any(find.widgetWithText(Tab, 'Liked')) == false) {
        await tester.tap(find.text('Profile'));
        await _settle(tester);
      }

      // --- Verify it now appears under the "Liked" tab -----------------------
      await tester.tap(find.widgetWithText(Tab, 'Liked'));
      await _settle(tester);

      final likedScrollable = find.byType(Scrollable).first;

      // The Liked tab's list is fetched once in _load() and isn't refreshed
      // just by liking a poll elsewhere on the page — pull-to-refresh (which
      // re-runs _load via the RefreshIndicator) to pick up the new like.
      await tester.fling(likedScrollable, const Offset(0, 400), 800);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(
        await findInScrollable(questionFinder, likedScrollable),
        isTrue,
        reason:
            'A liked poll should show up under the Liked tab on the profile',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
