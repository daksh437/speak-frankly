import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'screens/auth_gate.dart';
import 'services/analytics_service.dart';
import 'services/gamification_service.dart';
import 'services/locale_controller.dart';
import 'services/sync_service.dart';
import 'services/user_session.dart';
import 'services/vocabulary_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await UserSession.instance.load();
  LocaleController.setFromLanguage(UserSession.instance.nativeLanguage);
  await GamificationService.instance.load();
  await VocabularyService.instance.load();

  // Initialize Firebase (needed for Google sign-in + Firestore). If it fails,
  // AuthGate shows the login screen (the user can't proceed without an account).
  try {
    await Firebase.initializeApp();
    AnalyticsService.init();
  } catch (e) {
    debugPrint('[Firebase] init failed: $e');
  }

  // Best-effort cloud sync of progress + saved words (non-blocking).
  SyncService.start();

  runApp(const SpeakFranklyApp());
}

class SpeakFranklyApp extends StatelessWidget {
  const SpeakFranklyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale?>(
      valueListenable: LocaleController.locale,
      builder: (context, locale, _) => MaterialApp(
        title: 'Speak Frankly',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // AuthGate: login (Google) → onboarding → app.
        home: const AuthGate(),
      ),
    );
  }
}
