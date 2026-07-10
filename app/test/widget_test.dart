// Smoke test: the login screen builds and shows the Google sign-in button.
// (The full app is gated behind Firebase auth, which isn't initialized in tests.)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:speakflow/screens/login_screen.dart';

void main() {
  testWidgets('Login screen shows Continue with Google', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pump();

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.textContaining('Speak Frankly'), findsWidgets);
  });
}
