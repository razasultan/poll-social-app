import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/auth_card.dart';
import '../../core/widgets/auth_layout.dart';
import '../../core/widgets/oauth_buttons.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';

final RegExp _emailPattern = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$');

/// Pure validators extracted for unit testing — mirror the form field rules.
String? validateEmail(String? v) {
  final s = v?.trim() ?? '';
  if (s.isEmpty) return 'Email is required';
  if (!_emailPattern.hasMatch(s)) return 'Enter a valid email';
  return null;
}

String? validatePassword(String? v) {
  final s = v ?? '';
  if (s.length < 6) return 'Password must be at least 6 characters';
  return null;
}

String? validateConfirmPassword(String? v, String password) {
  if ((v ?? '').isEmpty) return 'Confirm your password';
  if (v != password) return 'Passwords do not match';
  return null;
}

String? validateUsername(String? v) {
  final s = v?.trim() ?? '';
  if (s.isEmpty) return 'Username is required';
  if (s.length < 2) return 'Username is too short';
  return null;
}

/// Registration with profile row creation when session is active.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  static const String routeName = '/auth/signup';

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();

  late final AuthService _authService;
  late final ProfileService _profileService;

  bool _loading = false;
  // Inline error displayed persistently below the submit button — survives
  // after the SnackBar auto-dismisses so the user always knows what failed.
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _authService = AuthService();
    _profileService = ProfileService();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _usernameCtrl.dispose();
    _displayNameCtrl.dispose();
    _countryCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Maps raw Supabase / network error messages to user-readable copy and
  /// stores them in [_submitError] so they persist after the SnackBar
  /// auto-dismisses. The SnackBar is kept for immediate visibility; the
  /// inline error is the permanent record.
  void _setError(String rawMessage) {
    final lower = rawMessage.toLowerCase();
    final friendly = lower.contains('invalid') && lower.contains('email')
        ? "That email address doesn't appear to be valid. Please use a different one."
        : lower.contains('already') || lower.contains('unique')
        ? 'An account with this email or username already exists.'
        : lower.contains('password')
        ? 'Password is too weak or doesn\'t meet the requirements.'
        : rawMessage.isNotEmpty
        ? rawMessage
        : 'Sign up failed. Please check your details and try again.';
    setState(() => _submitError = friendly);
    _snack(friendly);
  }

  String? _emailValidator(String? v) => validateEmail(v);

  String? _passwordValidator(String? v) => validatePassword(v);

  String? _confirmValidator(String? v) =>
      validateConfirmPassword(v, _passwordCtrl.text);

  String? _usernameValidator(String? v) => validateUsername(v);

  InputDecoration _fieldDecoration(
    BuildContext context,
    String label, {
    Widget? prefix,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      prefixIcon: prefix,
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _loading) return;

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    final email = _emailCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    final displayName = _displayNameCtrl.text.trim();
    final country = _countryCtrl.text.trim();
    final city = _cityCtrl.text.trim();

    setState(() => _submitError = null);

    try {
      final available = await _profileService.isUsernameAvailable(username);
      if (!mounted) return;
      if (!available) {
        setState(() => _loading = false);
        _setError('That username is already taken.');
        return;
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _setError('Could not verify username. Check your connection.');
      return;
    }

    try {
      final res = await _authService.signUp(
        email: email,
        password: _passwordCtrl.text,
        data: {
          'username': username,
          if (displayName.isNotEmpty) 'display_name': displayName,
          if (country.isNotEmpty) 'country': country,
          if (city.isNotEmpty) 'city': city,
        },
      );

      final user = res.user;
      final session = res.session;

      if (!mounted) return;

      if (user == null) {
        setState(() => _loading = false);
        _setError('Could not sign up. Check your email and try again.');
        return;
      }

      // When email confirmation is required, `session` is null and we have
      // no `auth.uid()` yet, so RLS blocks this insert. That's expected —
      // the profile is created from `user_metadata` once the user confirms
      // and signs in (see ProfileService.ensureProfileExists).
      if (session != null) {
        try {
          await _profileService.createProfile(
            id: user.id,
            username: username,
            displayName: displayName.isEmpty ? null : displayName,
            country: country.isEmpty ? null : country,
            city: city.isEmpty ? null : city,
          );
        } catch (e) {
          if (!mounted) return;
          setState(() => _loading = false);
          final msg = e is PostgrestException && e.message.isNotEmpty
              ? e.message
              : 'Account created but profile setup failed. Try updating profile in Settings.';
          _snack(msg);
          return;
        }
      }

      if (!mounted) return;
      setState(() => _loading = false);

      if (session == null) {
        _snack(
          'Account created! Check your inbox to confirm your email, then log in.',
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else if (Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _setError(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _setError('Network error. Try again.');
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await _authService.signInWithGoogle();
    } on AuthException catch (e) {
      if (!mounted) return;
      _snack(
        e.message.isNotEmpty ? e.message : 'Could not sign in with Google.',
      );
    } catch (_) {
      if (!mounted) return;
      _snack('Network error. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithApple() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await _authService.signInWithApple();
    } on AuthException catch (e) {
      if (!mounted) return;
      _snack(
        e.message.isNotEmpty ? e.message : 'Could not sign in with Apple.',
      );
    } catch (_) {
      if (!mounted) return;
      _snack('Network error. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: AuthLayout(
          child: Form(
            key: _formKey,
            child: AuthCard(
              title: 'Create your account',
              subtitle: 'Choose a username and optional profile details.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OAuthButtonsSection(
                    loading: _loading,
                    onGoogleTap: _signInWithGoogle,
                    onAppleTap: _signInWithApple,
                  ),
                  TextFormField(
                    controller: _emailCtrl,
                    decoration: _fieldDecoration(
                      context,
                      'Email',
                      prefix: const Icon(Icons.mail_outline_rounded),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    validator: _emailValidator,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _passwordCtrl,
                    decoration: _fieldDecoration(
                      context,
                      'Password',
                      prefix: const Icon(Icons.lock_outline_rounded),
                    ),
                    obscureText: true,
                    validator: _passwordValidator,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _confirmCtrl,
                    decoration: _fieldDecoration(
                      context,
                      'Confirm password',
                      prefix: const Icon(Icons.lock_outline_rounded),
                    ),
                    obscureText: true,
                    validator: _confirmValidator,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _usernameCtrl,
                    decoration: _fieldDecoration(
                      context,
                      'Username',
                      prefix: const Icon(Icons.alternate_email_rounded),
                    ),
                    autocorrect: false,
                    validator: _usernameValidator,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _displayNameCtrl,
                    decoration: _fieldDecoration(
                      context,
                      'Display name (optional)',
                      prefix: const Icon(Icons.badge_outlined),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _countryCtrl,
                    decoration: _fieldDecoration(
                      context,
                      'Country (optional)',
                      prefix: const Icon(Icons.public_outlined),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _cityCtrl,
                    decoration: _fieldDecoration(
                      context,
                      'City (optional)',
                      prefix: const Icon(Icons.location_city_outlined),
                    ),
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (_submitError != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: cs.errorContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 18,
                            color: cs.onErrorContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _submitError!,
                              style: TextStyle(
                                color: cs.onErrorContainer,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _loading
                        ? SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.onPrimary,
                            ),
                          )
                        : const Text('Sign up'),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
