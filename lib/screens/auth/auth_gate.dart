import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main_shell.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

/// Routes between [MainShell] (signed in) and an auth [Navigator] (signed out).
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Route<dynamic> _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case SignupScreen.routeName:
        return MaterialPageRoute<void>(
          builder: (context) => const SignupScreen(),
          settings: settings,
        );
      case LoginScreen.routeName:
      default:
        return MaterialPageRoute<void>(
          builder: (context) => const LoginScreen(),
          settings: settings,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      return const MainShell();
    }

    return Navigator(
      initialRoute: LoginScreen.routeName,
      onGenerateRoute: _onGenerateRoute,
    );
  }
}
