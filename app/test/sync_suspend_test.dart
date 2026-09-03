// Tests for the guard that stops a sign-out from erasing cloud progress.
//
// The bug these lock out: clearing the local stores notifies SyncService's
// listeners, which debounce a push. On sign-out and on account deletion the
// stores are cleared deliberately — so four seconds later the app uploaded an
// empty streak, zero XP and an empty word list, under the uid it was still
// sending, and the learner's cloud progress was gone. The same push racing a
// slow cloud pull could do it to an existing account signing in on a new
// device.
//
// No Firebase and no network here: what is being asserted is that a wipe never
// leaves a push queued, which is the step everything else hangs off.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:speakflow/services/gamification_service.dart';
import 'package:speakflow/services/sync_service.dart';
import 'package:speakflow/services/vocabulary_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SyncService.start(); // idempotent; wires the listeners once
    SyncService.resume();
  });

  tearDown(SyncService.suspend);

  test('a normal local change still schedules a push', () async {
    await GamificationService.instance.recordActivity();
    expect(SyncService.hasPendingPush, isTrue);
  });

  test('suspend drops a push that was already queued', () async {
    await GamificationService.instance.recordActivity();
    expect(SyncService.hasPendingPush, isTrue);

    SyncService.suspend();
    expect(SyncService.hasPendingPush, isFalse);
  });

  test('wiping progress while suspended queues nothing', () async {
    SyncService.suspend();
    await GamificationService.instance.reset();
    await VocabularyService.instance.reset();
    expect(SyncService.hasPendingPush, isFalse);
  });

  test('resume brings syncing back for the next account', () async {
    SyncService.suspend();
    await GamificationService.instance.reset();
    expect(SyncService.hasPendingPush, isFalse);

    SyncService.resume();
    await GamificationService.instance.recordActivity();
    expect(SyncService.hasPendingPush, isTrue);
  });

  test('a suspended push is a no-op even when called directly', () async {
    SyncService.suspend();
    // Would otherwise reach ApiService (and, in the wild, the server). It must
    // return without doing anything rather than throw.
    await SyncService.push();
  });
}
