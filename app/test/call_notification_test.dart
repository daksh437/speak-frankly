// Tests for the hand-off between a tapped notification and the call screen.
//
// This is the piece that fails silently. If it breaks, the notification still
// arrives, still looks right, and tapping it still opens the app — it just
// lands on the home screen instead of starting the call, and nobody reports
// that as a bug. It is also the half of the daily call that cannot be checked
// by looking at the screen.
//
// The awkward case it exists for: tapping the notification is usually what
// LAUNCHES the app, so the tap happens before any screen is alive to receive
// it. That one has to be parked and replayed, exactly once.

import 'package:flutter_test/flutter_test.dart';

import 'package:speakflow/services/notification_service.dart';

void main() {
  setUp(() {
    NotificationService.onAction = null;
    NotificationService.takePendingAction(); // drain anything a prior test left
  });

  test('the daily call has a payload to route on', () {
    expect(NotificationService.callAction, isNotEmpty);
  });

  group('a tap while the app is running', () {
    test('goes straight to the listener', () {
      String? got;
      NotificationService.onAction = (a) => got = a;
      NotificationService.pendingAction = null;

      // What the plugin callback does on a tap.
      NotificationService.onAction?.call(NotificationService.callAction);

      expect(got, NotificationService.callAction);
      expect(NotificationService.takePendingAction(), isNull,
          reason: 'a delivered action must not also be parked');
    });
  });

  group('a tap that launched the app', () {
    test('is parked until something asks for it', () {
      NotificationService.pendingAction = NotificationService.callAction;
      expect(NotificationService.takePendingAction(), NotificationService.callAction);
    });

    test('is delivered exactly once', () {
      NotificationService.pendingAction = NotificationService.callAction;
      expect(NotificationService.takePendingAction(), isNotNull);
      // A second read must be empty, or re-entering the shell would start a
      // second call on top of the one already running.
      expect(NotificationService.takePendingAction(), isNull);
    });

    test('nothing parked means nothing happens', () {
      expect(NotificationService.takePendingAction(), isNull);
    });
  });
}
