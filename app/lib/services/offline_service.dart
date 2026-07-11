import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'picture_match_data.dart';
import 'speaking_phrases.dart';
import 'user_session.dart';

/// Offline download packs (BRD §7.2). Proactively fetches and caches the
/// content that has local play value — the scenario library, today's speaking
/// phrases, and picture-match items — so the learner can practise with no
/// connection. Speaking/picture-match reuse their own daily caches (we just
/// prime them); scenarios are cached here and read back by [ApiService] when
/// the network is unreachable.
class OfflineService extends ChangeNotifier {
  static final OfflineService instance = OfflineService._();
  OfflineService._();

  /// Key ApiService reads directly (kept in sync here) for offline scenarios.
  static const kScenariosKey = 'sf_offline_scenarios';
  static const _kAt = 'sf_offline_at';
  static const _kLevel = 'sf_offline_level';
  static const _kCounts = 'sf_offline_counts';

  bool downloading = false;
  DateTime? downloadedAt;
  String? level;
  int scenarioCount = 0;
  int phraseCount = 0;
  int pictureCount = 0;

  bool get isDownloaded => downloadedAt != null;

  /// Read saved status into memory (call at boot / when opening the screen).
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final at = p.getString(_kAt);
    downloadedAt = at != null ? DateTime.tryParse(at) : null;
    level = p.getString(_kLevel);
    final counts = p.getString(_kCounts);
    if (counts != null) {
      try {
        final m = jsonDecode(counts) as Map<String, dynamic>;
        scenarioCount = (m['s'] as num?)?.toInt() ?? 0;
        phraseCount = (m['p'] as num?)?.toInt() ?? 0;
        pictureCount = (m['g'] as num?)?.toInt() ?? 0;
      } catch (_) {/* ignore */}
    }
    notifyListeners();
  }

  /// Download (or refresh) the pack for the learner's current level. Returns
  /// false if nothing usable could be fetched (e.g. fully offline already).
  Future<bool> download() async {
    if (downloading) return false;
    downloading = true;
    notifyListeners();
    var ok = false;
    try {
      final p = await SharedPreferences.getInstance();
      final lvl = UserSession.instance.level;

      // Scenario library → cache raw so ApiService can serve it offline.
      final scenarios = await ApiService.instance.fetchScenarios();
      final scJson = jsonEncode(scenarios
          .map((s) => {
                'id': s.id,
                'title': s.title,
                'emoji': s.emoji,
                'theme': s.theme,
                'level': s.level,
                'description': s.description,
                'goals': s.goals,
                'starter': s.starter,
                'keywords': s.keywords,
                'setup': s.setup,
              })
          .toList());
      await p.setString(kScenariosKey, scJson);

      // Speaking + picture-match reuse their own daily caches — priming them
      // guarantees the exact format their screens read back offline.
      final phrases = await SpeakingPhrases.getToday(forceRefresh: true);
      final pictures = await PictureMatchData.getToday(forceRefresh: true);

      scenarioCount = scenarios.length;
      phraseCount = phrases.length;
      pictureCount = pictures.length;
      level = lvl;
      downloadedAt = DateTime.now();

      await p.setString(_kAt, downloadedAt!.toIso8601String());
      await p.setString(_kLevel, lvl);
      await p.setString(_kCounts, jsonEncode({'s': scenarioCount, 'p': phraseCount, 'g': pictureCount}));
      ok = scenarioCount > 0 || phraseCount > 0 || pictureCount > 0;
    } catch (_) {
      ok = false;
    }
    downloading = false;
    notifyListeners();
    return ok;
  }

  /// Delete the downloaded scenario pack (frees space). Daily phrase/picture
  /// caches expire on their own.
  Future<void> clearPack() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(kScenariosKey);
    await p.remove(_kAt);
    await p.remove(_kLevel);
    await p.remove(_kCounts);
    downloadedAt = null;
    level = null;
    scenarioCount = phraseCount = pictureCount = 0;
    notifyListeners();
  }
}
