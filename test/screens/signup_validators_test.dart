import 'package:flutter_test/flutter_test.dart';
import 'package:poll_social_app/screens/auth/signup_screen.dart';

void main() {
  group('validateEmail', () {
    test('rejects empty input', () {
      expect(validateEmail(''), 'Email is required');
      expect(validateEmail('   '), 'Email is required');
      expect(validateEmail(null), 'Email is required');
    });

    test('rejects malformed addresses', () {
      expect(validateEmail('not-an-email'), 'Enter a valid email');
      expect(validateEmail('missing@domain'), 'Enter a valid email');
      expect(validateEmail('@nodomain.com'), 'Enter a valid email');
      expect(validateEmail('spaces in@email.com'), 'Enter a valid email');
    });

    test('accepts valid addresses', () {
      expect(validateEmail('user@example.com'), isNull);
      expect(validateEmail('  user.name+tag@sub.example.co.uk  '), isNull);
    });
  });

  group('validatePassword', () {
    test('requires at least 6 characters', () {
      expect(validatePassword(''), 'Password must be at least 6 characters');
      expect(validatePassword('abc12'), 'Password must be at least 6 characters');
      expect(validatePassword(null), 'Password must be at least 6 characters');
    });

    test('accepts 6+ characters', () {
      expect(validatePassword('abc123'), isNull);
    });
  });

  group('validateConfirmPassword', () {
    test('requires non-empty input', () {
      expect(validateConfirmPassword('', 'abc123'), 'Confirm your password');
      expect(validateConfirmPassword(null, 'abc123'), 'Confirm your password');
    });

    test('requires a match with the password', () {
      expect(validateConfirmPassword('different', 'abc123'), 'Passwords do not match');
      expect(validateConfirmPassword('abc123', 'abc123'), isNull);
    });
  });

  group('validateUsername', () {
    test('requires non-empty input', () {
      expect(validateUsername(''), 'Username is required');
      expect(validateUsername('  '), 'Username is required');
      expect(validateUsername(null), 'Username is required');
    });

    test('requires at least 2 characters after trimming', () {
      expect(validateUsername('a'), 'Username is too short');
      expect(validateUsername(' a '), 'Username is too short');
    });

    test('accepts valid usernames', () {
      expect(validateUsername('ab'), isNull);
      expect(validateUsername('  raza  '), isNull);
    });
  });
}
