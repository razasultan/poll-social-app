/// Compile-time app configuration via `--dart-define`.
///
/// Run with launch configs in `.vscode/launch.json` or pass defines manually:
/// `flutter run --dart-define=APP_ENV=dev --dart-define=SUPABASE_URL=...`
class AppConfig {
  AppConfig._();

  static const String appEnvironment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'dev',
  );

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  /// Base URL the deployed Flutter web build is hosted at, used to build
  /// shareable public poll links (`$publicShareBaseUrl/p/:shareSlug`).
  ///
  /// Defaults to a local dev-server URL until the app has a public hosting
  /// domain — pass `--dart-define=PUBLIC_SHARE_BASE_URL=https://your-domain.example`
  /// once it's deployed (see `.vscode/launch.json`). Update this default (and
  /// the `share-poll` Edge Function's `APP_WEB_BASE_URL`) to the real domain
  /// once one is chosen.
  static const String publicShareBaseUrl = String.fromEnvironment(
    'PUBLIC_SHARE_BASE_URL',
    defaultValue: 'http://localhost:9555',
  );

  static const bool isDev = appEnvironment == 'dev';
  static const bool isProd = appEnvironment == 'prod';

  /// True when both Supabase defines were provided at build/run time.
  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Human-readable hint when [isSupabaseConfigured] is false.
  static String get missingConfigMessage {
    final missing = <String>[];
    if (supabaseUrl.isEmpty) missing.add('SUPABASE_URL');
    if (supabaseAnonKey.isEmpty) missing.add('SUPABASE_ANON_KEY');
    return 'Missing --dart-define values: ${missing.join(', ')}. '
        'Use the "Flutter DEV" or "Flutter PROD" launch configuration in '
        '.vscode/launch.json, or pass the defines on the command line.';
  }
}
