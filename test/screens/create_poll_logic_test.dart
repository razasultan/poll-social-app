import 'package:flutter_test/flutter_test.dart';
import 'package:poll_social_app/core/config/app_config.dart';
import 'package:poll_social_app/screens/create_poll_screen.dart';

void main() {
  final now = DateTime(2026, 6, 7, 12);

  group('publicShareUrlForSlug', () {
    test('builds the public poll URL from the share base URL and slug', () {
      expect(
        publicShareUrlForSlug('abc123'),
        '${AppConfig.publicShareBaseUrl}/p/abc123',
      );
    });
  });

  group('nonEmptyOptionIndices', () {
    test('returns indices of non-blank options in order', () {
      expect(nonEmptyOptionIndices(['Coffee', '', 'Tea', '   ']), [0, 2]);
    });

    test('returns all indices when none are blank', () {
      expect(nonEmptyOptionIndices(['A', 'B', 'C']), [0, 1, 2]);
    });

    test('returns an empty list when all options are blank', () {
      expect(nonEmptyOptionIndices(['', '  ', '']), isEmpty);
    });
  });

  group('parseHashtagInput', () {
    test('splits on whitespace and commas, strips leading #, lowercases', () {
      expect(parseHashtagInput('#Travel, food   #Music'), [
        'travel',
        'food',
        'music',
      ]);
    });

    test('dedupes within the input', () {
      expect(parseHashtagInput('#sports sports #Sports'), ['sports']);
    });

    test('skips tags already present in existing', () {
      expect(parseHashtagInput('#sports #music', existing: {'Sports'}), [
        'music',
      ]);
    });

    test('ignores empty tokens', () {
      expect(parseHashtagInput('  ,, #  , '), isEmpty);
    });
  });

  group('resolveExpiresAt', () {
    test('returns null for "none"', () {
      expect(resolveExpiresAt(expirationNone, now: now), isNull);
    });

    test('adds the expected duration for relative presets', () {
      expect(
        resolveExpiresAt(expiration1h, now: now),
        now.add(const Duration(hours: 1)),
      );
      expect(
        resolveExpiresAt(expiration24h, now: now),
        now.add(const Duration(days: 1)),
      );
      expect(
        resolveExpiresAt(expiration7d, now: now),
        now.add(const Duration(days: 7)),
      );
    });

    test('returns the custom timestamp for "custom"', () {
      final custom = DateTime(2026, 7, 1);
      expect(
        resolveExpiresAt(expirationCustom, customExpiresAt: custom, now: now),
        custom,
      );
      expect(resolveExpiresAt(expirationCustom, now: now), isNull);
    });
  });

  group('validatePollDraft', () {
    String? draft({
      String question = 'Question?',
      List<String> options = const ['A', 'B'],
      String preset = expirationNone,
      DateTime? custom,
    }) {
      return validatePollDraft(
        question: question,
        optionTexts: options,
        expirationPreset: preset,
        customExpiresAt: custom,
        now: now,
      );
    }

    test('requires a non-empty question', () {
      expect(draft(question: '   '), 'Enter a question.');
    });

    test('requires at least two non-empty options', () {
      expect(
        draft(options: const ['Only one', '']),
        'Add at least two answer choices.',
      );
    });

    test('rejects more than five options', () {
      expect(
        draft(options: const ['A', 'B', 'C', 'D', 'E', 'F']),
        'A poll can have at most five options.',
      );
    });

    test('rejects duplicate options (case-insensitive)', () {
      expect(
        draft(options: const ['Yes', 'yes']),
        'Each option must be unique.',
      );
    });

    test('requires a custom date when the custom preset is chosen', () {
      expect(
        draft(preset: expirationCustom),
        'Pick an expiration date and time.',
      );
    });

    test('requires the custom date to be in the future', () {
      expect(
        draft(
          preset: expirationCustom,
          custom: now.subtract(const Duration(hours: 1)),
        ),
        'Expiration must be in the future.',
      );
    });

    test('accepts a valid draft', () {
      expect(draft(), isNull);
      expect(
        draft(
          preset: expirationCustom,
          custom: now.add(const Duration(hours: 1)),
        ),
        isNull,
      );
    });
  });
}
