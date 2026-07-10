import 'package:firebase_analytics/firebase_analytics.dart';

/// Thin, defensive wrapper over Firebase Analytics (BRD §11). Events show up in
/// the Firebase console. No-ops safely if Firebase isn't configured.
class AnalyticsService {
  static FirebaseAnalytics? _fa;

  static void init() {
    try {
      _fa = FirebaseAnalytics.instance;
    } catch (_) {
      _fa = null;
    }
  }

  static void log(String name, [Map<String, Object>? params]) {
    try {
      _fa?.logEvent(name: name, parameters: params);
    } catch (_) {/* best-effort */}
  }
}
