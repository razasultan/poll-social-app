import 'package:flutter_test/flutter_test.dart';
import 'package:poll_social_app/screens/profile_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('asProfileMap', () {
    test('passes through a typed map', () {
      final m = <String, dynamic>{'username': 'raza'};
      expect(identical(asProfileMap(m), m), isTrue);
    });

    test('converts an untyped map', () {
      final Map raw = {'username': 'raza'};
      expect(asProfileMap(raw), {'username': 'raza'});
    });

    test('returns an empty map for anything else', () {
      expect(asProfileMap(null), <String, dynamic>{});
      expect(asProfileMap('nope'), <String, dynamic>{});
    });
  });

  group('asPollList', () {
    test('normalizes a list of mixed map types', () {
      final Map untyped = {'id': '2'};
      final result = asPollList([
        {'id': '1'},
        untyped,
        'not a map',
      ]);
      expect(result, [
        {'id': '1'},
        {'id': '2'},
        <String, dynamic>{},
      ]);
    });

    test('returns an empty list for non-list input', () {
      expect(asPollList(null), isEmpty);
      expect(asPollList({'id': '1'}), isEmpty);
    });
  });

  group('asLikedPollList', () {
    test('unwraps the embedded polls map from each likes row', () {
      final result = asLikedPollList([
        {
          'created_at': '2026-01-01',
          'polls': {'id': 'p1', 'question': 'Q1'},
        },
        {
          'created_at': '2026-01-02',
          'polls': {'id': 'p2', 'question': 'Q2'},
        },
      ]);
      expect(result, [
        {'id': 'p1', 'question': 'Q1'},
        {'id': 'p2', 'question': 'Q2'},
      ]);
    });

    test('skips rows with a missing or empty polls map', () {
      final result = asLikedPollList([
        {'created_at': '2026-01-01', 'polls': null},
        {'created_at': '2026-01-02', 'polls': <String, dynamic>{}},
        {'created_at': '2026-01-03'},
      ]);
      expect(result, isEmpty);
    });

    test('returns an empty list for non-list input', () {
      expect(asLikedPollList(null), isEmpty);
    });
  });

  group('profileErrorMessage', () {
    test('maps "0 rows" / PGRST116 to a not-found message', () {
      expect(
        profileErrorMessage(const PostgrestException(message: '0 rows returned', code: 'PGRST116')),
        'Profile not found.',
      );
      expect(
        profileErrorMessage(const PostgrestException(message: 'Results contain 0 rows')),
        'Profile not found.',
      );
    });

    test('falls back to the exception message when present', () {
      expect(
        profileErrorMessage(const PostgrestException(message: 'permission denied')),
        'permission denied',
      );
    });

    test('uses a generic message for non-Postgrest errors', () {
      expect(profileErrorMessage(Exception('boom')), 'Could not load profile. Check your connection.');
    });
  });

  group('isDuplicateFollowError', () {
    test('detects unique-violation error code 23505', () {
      expect(isDuplicateFollowError(const PostgrestException(message: 'oops', code: '23505')), isTrue);
    });

    test('detects duplicate-related wording in the message', () {
      expect(isDuplicateFollowError(const PostgrestException(message: 'duplicate key value violates constraint')), isTrue);
      expect(isDuplicateFollowError(const PostgrestException(message: 'relation already exists')), isTrue);
      expect(isDuplicateFollowError(const PostgrestException(message: 'violates unique constraint')), isTrue);
    });

    test('returns false for unrelated errors', () {
      expect(isDuplicateFollowError(const PostgrestException(message: 'permission denied', code: '42501')), isFalse);
    });
  });
}
