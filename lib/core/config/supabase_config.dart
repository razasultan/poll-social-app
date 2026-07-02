import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_config.dart';

/// Centralized Supabase client initialization for all environments.
class SupabaseConfig {
  SupabaseConfig._();

  /// Initializes Supabase using [AppConfig] dart-defines.
  ///
  /// Throws [StateError] when required config is missing or init fails.
  static Future<void> initialize() async {
    if (!AppConfig.isSupabaseConfigured) {
      debugPrint('[Supabase] ${AppConfig.missingConfigMessage}');
      debugPrint('[Supabase] APP_ENV=${AppConfig.appEnvironment}');
      throw StateError(AppConfig.missingConfigMessage);
    }

    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );

    if (kDebugMode) {
      debugPrint(
        '[Supabase] Initialized (${AppConfig.appEnvironment}) '
        'url=${AppConfig.supabaseUrl}',
      );
    }
  }
}
