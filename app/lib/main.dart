import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'screens/main_shell.dart';
import 'screens/onboarding_screen.dart';
import 'services/analytics_service.dart';
import 'services/auth_service.dart';
import 'services/gamification_service.dart';
import 'services/sync_service.dart';
import 'services/user_session.dart';
import 'services/vocabulary_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UserSession.instance.load();
  await GamificationService.instance.load();
  await VocabularyService.instance.load();

  // Firebase is optional at boot: if google-services.json isn't in place yet
  // (or init fails), the app still runs using the local session id, so
  // development is never blocked. Once wired, we adopt the real Firebase UID.
  try {
    await Firebase.initializeApp();
    await AuthService.ensureSignedIn();
    AnalyticsService.init();
  } catch (e) {
    debugPrint('[Firebase] not configured yet, using local session id: $e');
  }

  // Best-effort cloud sync of progress + saved words (non-blocking).
  SyncService.start();

  runApp(const SpeakFranklyApp());
}

class SpeakFranklyApp extends StatelessWidget {
  const SpeakFranklyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Speak Frankly',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      // OnboardingGate: show onboarding until the learner has set language/goal/level.
      home: UserSession.instance.onboarded ? const MainShell() : const OnboardingScreen(),
    );
  }
}
