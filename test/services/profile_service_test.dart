import 'package:flutter_test/flutter_test.dart';
import 'package:poll_social_app/services/profile_service.dart';

void main() {
  group('usernameBaseFromEmail', () {
    test('derives a lowercase username from the email local part', () {
      expect(
        usernameBaseFromEmail('Jane.Doe@example.com', 'user-id-12345678'),
        'janedoe',
      );
    });

    test('strips characters that are not allowed in usernames', () {
      expect(
        usernameBaseFromEmail('j+d 99!@example.com', 'user-id-12345678'),
        'jd99',
      );
    });

    test(
      'falls back to a user-id-based name when the local part is too short',
      () {
        expect(
          usernameBaseFromEmail('a@example.com', 'abcdef1234567890'),
          'user_abcdef12',
        );
      },
    );

    test('falls back to a user-id-based name when there is no email', () {
      expect(usernameBaseFromEmail(null, 'abcdef1234567890'), 'user_abcdef12');
    });
  });
}
