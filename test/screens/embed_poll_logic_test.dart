import 'package:flutter_test/flutter_test.dart';
import 'package:poll_social_app/core/config/app_config.dart';
import 'package:poll_social_app/screens/embed_poll_screen.dart';

void main() {
  group('embedUrlForShareSlug', () {
    test('builds the embed URL from the share base URL and slug', () {
      expect(
        embedUrlForShareSlug('abc123'),
        '${AppConfig.publicShareBaseUrl}/embed/poll/abc123',
      );
    });
  });

  group('embedSnippetForShareSlug', () {
    test('builds an iframe snippet pointing at the embed URL', () {
      final snippet = embedSnippetForShareSlug('abc123');
      expect(snippet, startsWith('<iframe '));
      expect(snippet, contains('src="${embedUrlForShareSlug('abc123')}"'));
      expect(snippet, contains('</iframe>'));
    });
  });
}
