import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/auth_service.dart';
import 'services/user_session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UserSession.instance.load();

  // Firebase is optional at boot: if google-services.json isn't in place yet
  // (or init fails), the app still runs using the local session id, so
  // development is never blocked. Once wired, we adopt the real Firebase UID.
  try {
    await Firebase.initializeApp();
    await AuthService.ensureSignedIn();
  } catch (e) {
    debugPrint('[Firebase] not configured yet, using local session id: $e');
  }

  runApp(const SpeakFranklyApp());
}

class SpeakFranklyApp extends StatelessWidget {
  const SpeakFranklyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Speak Frankly',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4F46E5)),
        useMaterial3: true,
      ),
      // OnboardingGate: show onboarding until the learner has set language/goal/level.
      home: UserSession.instance.onboarded ? const HomeScreen() : const OnboardingScreen(),
    );
  }
}
