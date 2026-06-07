import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String? _emailValidator(String? v) => validateEmail(v);

  String? _passwordValidator(String? v) => validatePassword(v);

  String? _confirmValidator(String? v) => validateConfirmPassword(v, _passwordCtrl.text);

  String? _usernameValidator(String? v) => validateUsername(v);

  InputDecoration _fieldDecoration(BuildContext context, String label, {Widget? prefix}) {
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

    try {
      final available = await _profileService.isUsernameAvailable(username);
      if (!mounted) return;
      if (!available) {
        setState(() => _loading = false);
        _snack('That username is already taken.');
        return;
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Could not verify username. Check your connection.');
      return;
    }

    try {
      final res = await _authService.signUp(
        email: email,
        password: _passwordCtrl.text,
      );

      final user = res.user;
      final session = res.session;

      if (!mounted) return;

      if (user == null) {
        setState(() => _loading = false);
        _snack('Could not sign up. Check your email and try again.');
        return;
      }

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

      if (!mounted) return;
      setState(() => _loading = false);

      if (session == null) {
        _snack('Account created! Check your inbox to confirm your email, then log in.');
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else if (Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack(e.message.isNotEmpty ? e.message : 'Could not sign up.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Network error. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create account'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Join the community',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Choose a username and optional profile details.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _emailCtrl,
                      decoration: _fieldDecoration(context, 'Email', prefix: const Icon(Icons.mail_outline_rounded)),
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      validator: _emailValidator,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordCtrl,
                      decoration: _fieldDecoration(context, 'Password', prefix: const Icon(Icons.lock_outline_rounded)),
                      obscureText: true,
                      validator: _passwordValidator,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _confirmCtrl,
                      decoration:
                          _fieldDecoration(context, 'Confirm password', prefix: const Icon(Icons.lock_outline_rounded)),
                      obscureText: true,
                      validator: _confirmValidator,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _usernameCtrl,
                      decoration:
                          _fieldDecoration(context, 'Username', prefix: const Icon(Icons.alternate_email_rounded)),
                      autocorrect: false,
                      validator: _usernameValidator,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _displayNameCtrl,
                      decoration:
                          _fieldDecoration(context, 'Display name (optional)', prefix: const Icon(Icons.badge_outlined)),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _countryCtrl,
                      decoration:
                          _fieldDecoration(context, 'Country (optional)', prefix: const Icon(Icons.public_outlined)),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _cityCtrl,
                      decoration:
                          _fieldDecoration(context, 'City (optional)', prefix: const Icon(Icons.location_city_outlined)),
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _loading
                          ? SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
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
      ),
    );
  }
}
