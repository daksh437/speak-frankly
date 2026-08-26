// Smoke test: the login screen builds and shows the Google sign-in button.
// (The full app is gated behind Firebase auth, which isn't initialized in tests.)
//
// The MaterialApp here must carry the real localization delegates: LoginScreen
// reads its strings through `AppLocalizations.of(context)!`, so a bare
// MaterialApp gives it a null localization and the screen throws before it can
// render anything.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:speakflow/l10n/app_localizations.dart';
import 'package:speakflow/screens/login_screen.dart';

void main() {
  testWidgets('Login screen shows Continue with Google', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const LoginScreen(),
    ));
    await tester.pump();

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.textContaining('Speak Frankly'), findsWidgets);
  });
}
