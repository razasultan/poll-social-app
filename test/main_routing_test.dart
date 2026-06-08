import 'package:flutter_test/flutter_test.dart';
import 'package:poll_social_app/main.dart';

void main() {
  group('publicPollShareSlugFromRouteName', () {
    test('extracts the slug from a /p/:shareSlug route', () {
      expect(publicPollShareSlugFromRouteName('/p/abc123'), 'abc123');
    });

    test('extracts the slug from a legacy /poll/:shareSlug route', () {
      expect(publicPollShareSlugFromRouteName('/poll/abc123'), 'abc123');
    });

    test('returns null for unrelated routes', () {
      expect(publicPollShareSlugFromRouteName('/'), isNull);
      expect(publicPollShareSlugFromRouteName('/debug'), isNull);
      expect(publicPollShareSlugFromRouteName('/p'), isNull);
      expect(publicPollShareSlugFromRouteName('/p/abc/extra'), isNull);
    });

    test('returns null for blank slugs and null route names', () {
      expect(publicPollShareSlugFromRouteName('/p/ '), isNull);
      expect(publicPollShareSlugFromRouteName(null), isNull);
    });
  });

  group('embedPollShareSlugFromRouteName', () {
    test('extracts the slug from an /embed/poll/:shareSlug route', () {
      expect(embedPollShareSlugFromRouteName('/embed/poll/abc123'), 'abc123');
    });

    test('returns null for routes that are not /embed/poll/:shareSlug', () {
      expect(embedPollShareSlugFromRouteName('/embed'), isNull);
      expect(embedPollShareSlugFromRouteName('/embed/poll'), isNull);
      expect(embedPollShareSlugFromRouteName('/embed/abc123'), isNull);
      expect(embedPollShareSlugFromRouteName('/p/abc123'), isNull);
      expect(embedPollShareSlugFromRouteName('/embed/poll/abc/extra'), isNull);
    });

    test('returns null for blank slugs and null route names', () {
      expect(embedPollShareSlugFromRouteName('/embed/poll/ '), isNull);
      expect(embedPollShareSlugFromRouteName(null), isNull);
    });
  });
}
