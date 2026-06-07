import 'package:flutter/material.dart';

import 'core/config/app_config.dart';
import 'core/config/supabase_config.dart';
import 'core/widgets/dev_environment_banner.dart';
import 'screens/auth/auth_gate.dart';
import 'screens/backend_test_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!AppConfig.isSupabaseConfigured) {
    debugPrint('[App] ${AppConfig.missingConfigMessage}');
    debugPrint('[App] APP_ENV=${AppConfig.appEnvironment}');
    runApp(
      _StartupErrorApp(
        title: 'Configuration required',
        message: AppConfig.missingConfigMessage,
      ),
    );
    return;
  }

  try {
    await SupabaseConfig.initialize();
  } catch (e, st) {
    debugPrint('[App] Supabase initialization failed: $e');
    debugPrint('$st');
    runApp(_StartupErrorApp(
      title: 'Supabase initialization failed',
      message: e.toString(),
    ));
    return;
  }

  debugPrint(
    '[App] Started (APP_ENV=${AppConfig.appEnvironment}, '
    'isDev=${AppConfig.isDev})',
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  /// X (Twitter)-style accent: signature sky blue on a stark black/white canvas.
  static const Color _xBlue = Color(0xFF1D9BF0);

  static final ThemeData _lightTheme = _buildTheme(Brightness.light);
  static final ThemeData _darkTheme = _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: _xBlue,
      brightness: brightness,
    ).copyWith(
      primary: _xBlue,
      onPrimary: Colors.white,
      surface: isLight ? Colors.white : const Color(0xFF000000),
      onSurface: isLight ? const Color(0xFF0F1419) : const Color(0xFFE7E9EA),
      outlineVariant: isLight ? const Color(0xFFEFF3F4) : const Color(0xFF2F3336),
    );

    final hairline = scheme.outlineVariant;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      fontFamily: 'Roboto',
      visualDensity: VisualDensity.standard,
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface.withValues(alpha: 0.92),
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
      dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: hairline),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.12),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scheme.surface,
        elevation: 0,
        selectedItemColor: scheme.onSurface,
        unselectedItemColor: scheme.onSurfaceVariant,
        showSelectedLabels: false,
        showUnselectedLabels: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.onSurface,
          foregroundColor: scheme.surface,
          textStyle: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.1),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? const Color(0xFFF7F9F9) : const Color(0xFF16181C),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      textTheme: Typography.material2021(platform: TargetPlatform.android)
          .black
          .apply(
            bodyColor: scheme.onSurface,
            displayColor: scheme.onSurface,
          )
          .copyWith(
            titleLarge: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.4),
            titleMedium: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.2),
            titleSmall: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.1),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: ThemeMode.system,
      home: const AuthGate(),
      debugShowCheckedModeBanner: false,
      routes: {
        '/debug': (context) => const BackendTestScreen(),
      },
      builder: (context, child) {
        return DevEnvironmentBanner(child: child);
      },
    );
  }
}

/// Shown when dart-defines are missing or Supabase fails to start.
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(message),
                const SizedBox(height: 24),
                Text(
                  'Use the "Flutter DEV" or "Flutter PROD" launch configuration '
                  'in .vscode/launch.json, or pass --dart-define on the CLI.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
