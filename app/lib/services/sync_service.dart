import 'dart:async';

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

  /// Set up push-on-change listeners (call once at boot).
  static void start() {
    if (_started) return;
    _started = true;
    GamificationService.instance.addListener(_schedulePush);
    VocabularyService.instance.addListener(_schedulePush);
  }

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
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), push);
  }

  static Future<void> push() async {
    try {
      final payload = GamificationService.instance.toMap();
      payload['savedWords'] = VocabularyService.instance.toJsonList();
      payload.addAll(UserSession.instance.profileToCloud());
      await ApiService.instance.saveProgress(payload);
    } catch (_) {/* best-effort */}
  }
}
