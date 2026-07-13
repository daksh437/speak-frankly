import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Asks happy learners to rate the app (Play in-app review) — but only after
/// they've completed a few sessions, and only once. Best-effort and silent.
class RatePrompt {
  static const _kCount = 'sf_rate_sessions';
  static const _kAsked = 'sf_rate_asked';
  static const int _threshold = 3; // ask after 3 completed sessions

  /// Call after a learner finishes a session. On the Nth session, requests a
  /// review once. Never throws.
  static Future<void> onSessionComplete() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getBool(_kAsked) ?? false) return;
      final count = (p.getInt(_kCount) ?? 0) + 1;
      await p.setInt(_kCount, count);
      if (count < _threshold) return;

      final review = InAppReview.instance;
      if (await review.isAvailable()) {
        await review.requestReview();
        await p.setBool(_kAsked, true);
      }
    } catch (_) {/* best-effort */}
  }
}
