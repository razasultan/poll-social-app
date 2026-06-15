import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  User? get currentUser => _supabase.auth.currentUser;

  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  /// [data] is stored as the new user's `user_metadata` (e.g. username,
  /// display_name, country, city). It survives even when email confirmation
  /// defers session creation, so it can be used later to create the profile
  /// row once the user is authenticated.
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? data,
  }) async {
    return await _supabase.auth.signUp(
      email: email,
      password: password,
      data: data,
    );
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  Future<void> resetPassword(String email) async {
    await _supabase.auth.resetPasswordForEmail(email);
  }

  /// Starts the Google OAuth sign-in flow (browser redirect on web). The
  /// returned future completes once the redirect has been launched, not once
  /// sign-in finishes — the resulting session arrives later via
  /// [authStateChanges]. Throws [AuthException] if the Google provider isn't
  /// enabled in the Supabase dashboard.
  Future<bool> signInWithGoogle({String? redirectTo}) async {
    return _supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: redirectTo,
    );
  }

  /// Starts the Apple OAuth sign-in flow. See [signInWithGoogle].
  Future<bool> signInWithApple({String? redirectTo}) async {
    return _supabase.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: redirectTo,
    );
  }
}
