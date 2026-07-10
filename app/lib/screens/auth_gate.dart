import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/account_service.dart';
import '../services/user_session.dart';
import 'login_screen.dart';
import 'main_shell.dart';
import 'onboarding_screen.dart';

/// Routes by auth state: signed out → LoginScreen; signed in → prepare that
/// account's session (reset+load if a different account) → onboarding/app.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _authStream = FirebaseAuth.instance.authStateChanges();
  String? _readyUid; // uid whose session has been prepared
  bool _preparing = false;

  Future<void> _prepare(String uid) async {
    if (_preparing || _readyUid == uid) return;
    _preparing = true;
    await AccountService.switchTo(uid);
    if (!mounted) return;
    setState(() {
      _readyUid = uid;
      _preparing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _Loader();
        }
        final user = snap.data;
        if (user == null) {
          _readyUid = null; // so the next sign-in re-prepares
          return const LoginScreen();
        }
        if (_readyUid != user.uid) {
          _prepare(user.uid); // async; shows loader until ready
          return const _Loader();
        }
        return UserSession.instance.onboarded ? const MainShell() : const OnboardingScreen();
      },
    );
  }
}

class _Loader extends StatelessWidget {
  const _Loader();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}
