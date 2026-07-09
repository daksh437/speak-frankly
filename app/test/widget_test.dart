// Basic smoke test: the app builds and shows onboarding for a fresh user.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:speakflow/main.dart';
import 'package:speakflow/services/user_session.dart';

void main() {
  testWidgets('Fresh app shows onboarding', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await UserSession.instance.load();

    await tester.pumpWidget(const SpeakFranklyApp());
    await tester.pump();

    expect(find.text('Get started'), findsOneWidget);
    expect(find.textContaining('Speak Frankly'), findsWidgets);
  });
}
