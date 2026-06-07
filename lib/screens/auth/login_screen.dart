import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import 'signup_screen.dart';

/// Email / password sign-in.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  static const String routeName = '/auth/login';

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  late final AuthService _authService;

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _authService = AuthService();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String? _emailValidator(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Email is required';
    if (!s.contains('@')) return 'Enter a valid email';
    return null;
  }

  String? _passwordValidator(String? v) {
    if ((v ?? '').isEmpty) return 'Password is required';
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _loading) return;

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    try {
      await _authService.signIn(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      if (!mounted) return;
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      final parts = <String>[
        if (e.message.isNotEmpty) e.message,
        if (e.code != null && e.code!.isNotEmpty) '(${e.code})',
      ];
      _snack(parts.isNotEmpty ? parts.join(' ') : 'Could not sign in.');
    } catch (_) {
      if (!mounted) return;
      _snack('Network error. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForgotPassword() async {
    final emailCtrl = TextEditingController(text: _emailCtrl.text.trim());
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reset password'),
          content: TextField(
            controller: emailCtrl,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send link')),
          ],
        ),
      );
      if (ok != true || !mounted) return;

      final email = emailCtrl.text.trim();
      if (email.isEmpty) {
        _snack('Enter your email address.');
        return;
      }

      try {
        await _authService.resetPassword(email);
        if (!mounted) return;
        _snack('Check your inbox for a reset link.');
      } on AuthException catch (e) {
        if (!mounted) return;
        _snack(e.message.isNotEmpty ? e.message : 'Could not send reset email.');
      } catch (_) {
        if (!mounted) return;
        _snack('Network error. Try again.');
      }
    } finally {
      emailCtrl.dispose();
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    Icon(Icons.how_to_vote_rounded, size: 56, color: cs.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Welcome back',
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sign in to vote and share polls',
                      style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 36),
                    TextFormField(
                      controller: _emailCtrl,
                      decoration: _fieldDecoration(context, 'Email', prefix: const Icon(Icons.mail_outline_rounded)),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      validator: _emailValidator,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordCtrl,
                      decoration: _fieldDecoration(context, 'Password', prefix: const Icon(Icons.lock_outline_rounded)),
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      validator: _passwordValidator,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _loading ? null : _openForgotPassword,
                        child: const Text('Forgot password?'),
                      ),
                    ),
                    const SizedBox(height: 8),
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
                          : const Text('Sign in'),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('New here?', style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const SignupScreen()),
                                  );
                                },
                          child: const Text('Create an account'),
                        ),
                      ],
                    ),
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
