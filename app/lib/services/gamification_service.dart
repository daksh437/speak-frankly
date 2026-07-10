import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local gamification state: daily streak, XP, and scenarios completed.
/// ChangeNotifier so the UI updates live (no provider dependency needed).
/// Stored in prefs for now; can sync to Firestore later.
class GamificationService extends ChangeNotifier {
  static final GamificationService instance = GamificationService._();
  GamificationService._();

  static const _kStreak = 'sf_streak';
  static const _kXp = 'sf_xp';
  static const _kScenarios = 'sf_scenarios_done';
  static const _kSpeaking = 'sf_speaking_reps';
  static const _kLastActive = 'sf_last_active';

  int streak = 0;
  int xp = 0;
  int scenariosCompleted = 0;
  int speakingReps = 0;
  String _lastActive = '';

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    streak = p.getInt(_kStreak) ?? 0;
    xp = p.getInt(_kXp) ?? 0;
    scenariosCompleted = p.getInt(_kScenarios) ?? 0;
    speakingReps = p.getInt(_kSpeaking) ?? 0;
    _lastActive = p.getString(_kLastActive) ?? '';
  }

  /// Clear all local gamification state (e.g. when a different account signs in).
  Future<void> reset() async {
    streak = 0;
    xp = 0;
    scenariosCompleted = 0;
    speakingReps = 0;
    _lastActive = '';
    await _persist();
    notifyListeners();
  }

  /// A completed speaking-practice rep (counts toward the fluency map + streak/XP).
  Future<void> recordSpeaking({int xpGain = 5}) async {
    speakingReps += 1;
    await recordActivity(xpGain: xpGain);
  }

  static String _dateStr(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Call on any practice activity (e.g. sending a chat message).
  /// Advances the daily streak (consecutive days) and adds XP.
  Future<void> recordActivity({int xpGain = 5}) async {
    final now = DateTime.now();
    final today = _dateStr(now);
    final yesterday = _dateStr(now.subtract(const Duration(days: 1)));

    if (_lastActive != today) {
      if (_lastActive == yesterday) {
        streak += 1; // consecutive day
      } else {
        streak = 1; // first day or streak broken
      }
      _lastActive = today;
    }
    xp += xpGain;
    await _persist();
    notifyListeners();
  }

  /// Call when a conversation session is finished.
  Future<void> completeScenario({int xpBonus = 20}) async {
    scenariosCompleted += 1;
    xp += xpBonus;
    await _persist();
    notifyListeners();
  }

  /// Snapshot for cloud sync.
  Map<String, dynamic> toMap() => {
        'streak': streak,
        'xp': xp,
        'scenariosCompleted': scenariosCompleted,
        'speakingReps': speakingReps,
        'lastActive': _lastActive,
      };

  /// Merge cloud state in (take the higher of each counter, later lastActive)
  /// so nothing is lost when syncing across devices/reinstalls.
  Future<void> mergeFrom(Map<String, dynamic> m) async {
    int higher(int a, dynamic b) {
      final bi = b is num ? b.toInt() : 0;
      return a > bi ? a : bi;
    }

    streak = higher(streak, m['streak']);
    xp = higher(xp, m['xp']);
    scenariosCompleted = higher(scenariosCompleted, m['scenariosCompleted']);
    speakingReps = higher(speakingReps, m['speakingReps']);
    final serverLast = (m['lastActive'] ?? '').toString();
    if (serverLast.compareTo(_lastActive) > 0) _lastActive = serverLast;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kStreak, streak);
    await p.setInt(_kXp, xp);
    await p.setInt(_kScenarios, scenariosCompleted);
    await p.setInt(_kSpeaking, speakingReps);
    await p.setString(_kLastActive, _lastActive);
  }
}
