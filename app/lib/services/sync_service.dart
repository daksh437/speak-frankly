import 'dart:async';

import 'api_service.dart';
import 'gamification_service.dart';
import 'vocabulary_service.dart';

/// Two-way cloud sync of progress + saved words. On start it pulls the cloud
/// copy, merges it with local (no data loss), pushes the merged truth back, then
/// debounce-pushes on any later change. Best-effort — offline/errors are ignored,
/// so the app works fully without connectivity.
///
/// Cross-device sync becomes meaningful once Anonymous auth gives a stable
/// Firebase UID; with the local fallback id it still backs up this device.
class SyncService {
  static Timer? _debounce;
  static bool _started = false;

  static Future<void> start() async {
    if (_started) return;
    _started = true;
    await _pull();
    GamificationService.instance.addListener(_schedulePush);
    VocabularyService.instance.addListener(_schedulePush);
  }

  static Future<void> _pull() async {
    try {
      final data = await ApiService.instance.fetchProgress();
      if (data.isEmpty) return;
      await GamificationService.instance.mergeFrom(data);
      await VocabularyService.instance.mergeFrom(data['savedWords'] as List?);
      await _push(); // persist the merged result to the cloud
    } catch (_) {/* offline / not deployed yet → no-op */}
  }

  static void _schedulePush() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), _push);
  }

  static Future<void> _push() async {
    try {
      final payload = GamificationService.instance.toMap();
      payload['savedWords'] = VocabularyService.instance.toJsonList();
      await ApiService.instance.saveProgress(payload);
    } catch (_) {/* best-effort */}
  }
}
