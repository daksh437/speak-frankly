import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/user_session.dart';
import 'login_screen.dart';
import 'main_shell.dart';
import 'onboarding_screen.dart';

/// Routes by auth state: signed out → LoginScreen; signed in → onboarding (if
/// not done) → MainShell. Reacts live to sign-in / sign-out.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snap.data;
        if (user == null) return const LoginScreen();

        // Signed in — adopt the Google UID (idempotent; persisted for API calls).
        if (UserSession.instance.uid != user.uid) {
          UserSession.instance.setUid(user.uid);
        }
        return UserSession.instance.onboarded ? const MainShell() : const OnboardingScreen();
      },
    );
  }
}
