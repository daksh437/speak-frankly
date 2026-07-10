import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'user_session.dart';

/// One picture-match item: (emoji scene, correct sentence, distractor sentences).
typedef PictureItem = (String emoji, String correct, List<String> distractors);

/// Provides the day's picture-match items — fetches a fresh AI-generated,
/// level-aware set once per day and caches it (new pictures each day), with a
/// last-cache then static fallback so the game always works offline.
class PictureMatchData {
  static const _kItems = 'sf_pm_items';
  static const _kDate = 'sf_pm_date';

  static const List<PictureItem> fallback = [
    ('🍕', 'They are eating pizza.', ['She is reading a book.', 'He is driving a car.']),
    ('🏖️', 'They are relaxing at the beach.', ['He is cooking dinner.', 'She is studying at night.']),
    ('🐶', 'The dog is running in the park.', ['The cat is sleeping.', 'The bird is singing.']),
    ('☔', 'It is raining outside.', ['The sun is shining.', 'It is snowing.']),
    ('🚌', 'She is waiting for the bus.', ['He is riding a bicycle.', 'They are taking a taxi.']),
    ('☕', 'He is drinking a cup of coffee.', ['She is eating an apple.', 'They are playing football.']),
    ('📚', 'The student is reading a book.', ['The chef is cooking.', 'The doctor is working.']),
    ('🎂', 'They are celebrating a birthday.', ['He is cleaning the house.', 'She is buying clothes.']),
    ('✈️', 'The plane is taking off.', ['The train is arriving.', 'The car is parking.']),
    ('🏥', 'She is visiting the doctor.', ['He is going to school.', 'They are at the market.']),
  ];

  static String _today() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static Future<List<PictureItem>> getToday({bool forceRefresh = false}) async {
    final p = await SharedPreferences.getInstance();
    final cachedDate = p.getString(_kDate);
    final cached = _decode(p.getString(_kItems));

    if (!forceRefresh && cachedDate == _today() && cached.length >= 4) return cached;

    try {
      final raw = await ApiService.instance.fetchPictureMatch(level: UserSession.instance.level);
      final items = _fromMaps(raw);
      if (items.length >= 4) {
        await p.setString(_kItems, _encode(items));
        await p.setString(_kDate, _today());
        return items;
      }
    } catch (_) {/* offline / not deployed → fall through */}

    if (cached.length >= 4) return cached;
    return fallback;
  }

  static List<PictureItem> _fromMaps(List<Map<String, dynamic>> raw) => raw
      .map((m) {
        final emoji = (m['emoji'] ?? '').toString();
        final correct = (m['correct'] ?? '').toString();
        final distractors = ((m['distractors'] as List?) ?? []).map((e) => e.toString()).toList();
        return (emoji, correct, distractors);
      })
      .where((it) => it.$1.isNotEmpty && it.$2.isNotEmpty && it.$3.length >= 2)
      .toList();

  static String _encode(List<PictureItem> items) =>
      jsonEncode(items.map((i) => {'emoji': i.$1, 'correct': i.$2, 'distractors': i.$3}).toList());

  static List<PictureItem> _decode(String? s) {
    if (s == null || s.isEmpty) return [];
    try {
      final list = jsonDecode(s) as List;
      return _fromMaps(list.whereType<Map<String, dynamic>>().toList());
    } catch (_) {
      return [];
    }
  }
}
