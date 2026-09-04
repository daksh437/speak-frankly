import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import 'api_service.dart';
import 'gamification_service.dart';
import 'user_session.dart';
import 'vocabulary_service.dart';

/// Cloud sync of progress + saved words + profile, keyed by the signed-in
/// account's Firebase UID. The pull happens on sign-in (see AccountService);
/// after that, local changes are debounce-pushed. Best-effort — offline/errors
/// are ignored so the app works without connectivity.
class SyncService {
  static Timer? _debounce;
  static bool _started = false;

  /// While true, nothing is pushed and no push is scheduled.
  ///
  /// Sign-out and account deletion CLEAR the local stores, and clearing them
  /// notifies the listeners below - which used to schedule a push of the
  /// freshly-zeroed state. Four seconds later that push overwrote the learner's
  /// cloud streak, XP and every saved word with zeros, under the uid the app
  /// was still sending. Suspending around the wipe is what stops "sign out"
  /// from meaning "erase my progress". The server refuses such a write too, but
  /// only from a build that has this fix does it never get sent.
  static bool _suspended = false;

  /// Set up push-on-change listeners (call once at boot).
  static void start() {
    if (_started) return;
    _started = true;
    GamificationService.instance.addListener(_schedulePush);
    VocabularyService.instance.addListener(_schedulePush);
  }

  /// Stop syncing and drop any push already queued. Call BEFORE wiping local
  /// data (sign-out, account deletion); [resume] re-enables it for the next
  /// account.
  static void suspend() {
    _suspended = true;
    _debounce?.cancel();
    _debounce = null;
  }

  /// Re-enable syncing for a signed-in account.
  static void resume() => _suspended = false;

  /// Whether a debounced push is waiting to fire. Visible for tests - this is
  /// the thing that must be empty while local data is being wiped.
  static bool get hasPendingPush => _debounce?.isActive ?? false;

  /// Pull the current account's cloud data and apply it. After an account
  /// switch (local reset) this is effectively a clean load of that account.
  static Future<void> pullAndApply() async {
    try {
      final data = await ApiService.instance.fetchProgress();
      if (data.isEmpty) return;
      await GamificationService.instance.mergeFrom(data);
      await VocabularyService.instance.mergeFrom(data['savedWords'] as List?);
      await UserSession.instance.applyCloudProfile(data);
    } catch (_) {/* offline / not deployed → no-op */}
  }

  static void _schedulePush() {
    if (_suspended) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), push);
  }

  static Future<void> push() async {
    if (_suspended) return;
    // Progress belongs to an account, so there must be one. Without this a
    // push that outlived a sign-out would still be sent, and the server accepts
    // the uid header while REQUIRE_AUTH_TOKEN is off.
    try {
      if (FirebaseAuth.instance.currentUser == null) return;
    } catch (_) {
      return; // Firebase unavailable -> nobody is signed in as far as we know
    }
    try {
      final payload = GamificationService.instance.toMap();
      payload['savedWords'] = VocabularyService.instance.toJsonList();
      payload.addAll(UserSession.instance.profileToCloud());
      await ApiService.instance.saveProgress(payload);
    } catch (_) {/* best-effort */}
  }
}
