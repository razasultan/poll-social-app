/// Centralized brand identity. Swap these values (and [BrandMark]'s glyph)
/// to rebrand the app without touching layout code.
///
/// When renaming, also update the hard-coded copies that cannot import this
/// file because they run before Flutter initialises:
///   - web/index.html  (static HTML served to browsers and crawlers)
///   - web/manifest.json  (PWA manifest)
///   - supabase/functions/share-poll/index.ts  (const APP_NAME)
class Branding {
  Branding._();

  /// Short product name shown in wordmarks, auth headers, etc.
  static const String appName = 'Poll Social';

  /// One-line tagline summarizing the product.
  static const String tagline = 'The social network built around polls.';

  /// Hero headline split into a plain prefix and a highlighted suffix so the
  /// UI can render two-tone text via [Text.rich]. Concatenation of the two
  /// equals the full headline.
  static const String heroTitlePrefix = 'The social network ';
  static const String heroTitleHighlight = 'built around polls.';

  /// Subtitle shown under the hero headline.
  static const String heroSubtitle =
      'Ask questions. Start conversations. See what the world really thinks.';
}
