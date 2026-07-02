import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Initializes Supabase with dummy local credentials so widgets that touch
/// `Supabase.instance.client` (e.g. via [AuthService]) can be built in
/// widget tests. Safe to call from multiple test files / `setUpAll` blocks —
/// [Supabase.initialize] is a no-op if already initialized.
Future<void> initSupabaseForTests() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  await Supabase.initialize(
    url: 'http://localhost:54321',
    publishableKey: 'test-anon-key',
  );
}
