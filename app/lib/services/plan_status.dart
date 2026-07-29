import 'package:flutter/foundation.dart';

import 'api_service.dart';

/// Lightweight cache of the learner's plan (from the server `/access` endpoint).
/// The backend is authoritative for AI usage; this is just for UI gating of
/// premium-only extras (e.g. offline packs) and showing plan state.
///
/// "Premium access" = a paid subscription OR an active free trial — trial users
/// get the full experience.
class PlanStatus extends ChangeNotifier {
  static final PlanStatus instance = PlanStatus._();
  PlanStatus._();

  String planType = 'free'; // 'trial' | 'free' | 'premium'
  DateTime? trialEndsAt;
  bool loaded = false;

  bool get isPremium => planType == 'premium';
  bool get isTrial => planType == 'trial';
  bool get hasPremiumAccess => isPremium || isTrial;

  /// Re-fetch from the server. Keeps the last known value on error.
  Future<void> refresh() async {
    try {
      final a = await ApiService.instance.fetchAccess();
      planType = (a['planType'] ?? 'free').toString();
      final iso = a['trialEndsAtUtc'];
      trialEndsAt = iso != null ? DateTime.tryParse(iso.toString()) : null;
      loaded = true;
      notifyListeners();
    } catch (_) {
      // Network hiccup — keep whatever we had; never lock a user out on error.
    }
  }
}
