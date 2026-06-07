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

  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

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
