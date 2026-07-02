import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:go_router/go_router.dart';

import '../../core/widgets/auth_card.dart';
import '../../core/widgets/auth_layout.dart';
import '../../core/widgets/oauth_buttons.dart';
import '../../services/auth_service.dart';

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
  bool _obscurePassword = true;

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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
      if (context.canPop()) context.pop();
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
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Send link'),
            ),
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
        _snack(
          e.message.isNotEmpty ? e.message : 'Could not send reset email.',
        );
      } catch (_) {
        if (!mounted) return;
        _snack('Network error. Try again.');
      }
    } finally {
      emailCtrl.dispose();
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: AuthLayout(
          child: Form(
            key: _formKey,
            child: AuthCard(
              title: 'Welcome back',
              subtitle: 'Sign in to vote and share polls',
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
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    validator: _emailValidator,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordCtrl,
                    decoration:
                        _fieldDecoration(
                          context,
                          'Password',
                          prefix: const Icon(Icons.lock_outline_rounded),
                        ).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            tooltip: _obscurePassword
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                    obscureText: _obscurePassword,
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
                        : const Text('Sign in'),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'New here?',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () => context.push('/signup'),
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
    );
  }
}
