import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'user_session.dart';

/// Provides the day's speaking-practice phrases. Fetches a fresh AI-generated
/// set once per day (level/goal-aware) and caches it, so the learner sees new
/// phrases each day. Falls back to the last cached set, then a static list.
class SpeakingPhrases {
  static const _kPhrases = 'sf_speak_phrases';
  static const _kDate = 'sf_speak_phrases_date';

  static const fallback = <String>[
    'Good morning! How are you today?',
    'Nice to meet you.',
    'Could you help me, please?',
    'I would like a cup of coffee.',
    'How much does this cost?',
    'Where is the train station?',
    'Can you repeat that, please?',
    'I have been learning English for a month.',
    'What time does the meeting start?',
    'Thank you very much for your help.',
    'I am looking for a new job.',
    'I really enjoyed the movie.',
  ];

  static String _today() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// Returns today's phrases. [forceRefresh] ignores the daily cache (e.g. a
  /// "new set" button). New AI set is fetched at most once per day otherwise.
  static Future<List<String>> getToday({bool forceRefresh = false}) async {
    final p = await SharedPreferences.getInstance();
    final cachedDate = p.getString(_kDate);
    List<String> cached = [];
    final cachedJson = p.getString(_kPhrases);
    if (cachedJson != null) {
      try {
        cached = (jsonDecode(cachedJson) as List).map((e) => e.toString()).toList();
      } catch (_) {/* ignore */}
    }

    // Already fetched today → reuse (unless forced).
    if (!forceRefresh && cachedDate == _today() && cached.length >= 4) return cached;

    // Fetch a fresh level/goal-aware set.
    try {
      final goal = UserSession.instance.goal.isEmpty ? 'everyday conversation' : UserSession.instance.goal;
      final phrases = await ApiService.instance.fetchSpeakingPhrases(level: UserSession.instance.level, goal: goal);
      if (phrases.length >= 4) {
        await p.setString(_kPhrases, jsonEncode(phrases));
        await p.setString(_kDate, _today());
        return phrases;
      }
    } catch (_) {/* offline / server error → fall through */}

    if (cached.length >= 4) return cached;
    return fallback;
  }
}
