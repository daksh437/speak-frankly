import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'day_key.dart';

/// What one day of practice actually produced.
///
/// Everything here is an OUTCOME, not an activity count. Streak, XP and
/// "scenarios completed" say how much someone showed up; these say whether they
/// are getting better, which is the question people quietly ask themselves
/// before they delete a language app.
class DayProgress {
  final String date; // YYYY-MM-DD, local

  /// Conversations finished today.
  int sessions;

  /// Turns the LEARNER spoke or typed — the denominator for mistakes.
  int turns;

  /// Corrections the tutor offered across those turns.
  int corrections;

  /// Pronunciation scores, kept as sum + count so days can be added together
  /// without weighting a day with one attempt the same as one with twenty.
  int pronSum;
  int pronCount;

  /// Saved words at Leitner box 3 or higher, as a snapshot taken today. Not
  /// additive — the highest reading of the day is the day's value.
  int wordsMastered;

  DayProgress({
    required this.date,
    this.sessions = 0,
    this.turns = 0,
    this.corrections = 0,
    this.pronSum = 0,
    this.pronCount = 0,
    this.wordsMastered = 0,
  });

  /// Average pronunciation score for the day, or null if nothing was scored.
  double? get pronAverage => pronCount == 0 ? null : pronSum / pronCount;

  Map<String, dynamic> toJson() => {
        's': sessions,
        't': turns,
        'c': corrections,
        'ps': pronSum,
        'pc': pronCount,
        'wm': wordsMastered,
      };

  static DayProgress fromJson(String date, Map<String, dynamic> j) {
    int n(Object? v) => v is num ? v.toInt() : 0;
    return DayProgress(
      date: date,
      sessions: n(j['s']),
      turns: n(j['t']),
      corrections: n(j['c']),
      pronSum: n(j['ps']),
      pronCount: n(j['pc']),
      wordsMastered: n(j['wm']),
    );
  }

  /// Take the higher of each field.
  ///
  /// A day's numbers only ever grow while that day is happening, so "higher"
  /// is the same as "more complete". That makes a re-sent day a no-op, which is
  /// what lets this sync without any de-duplication: the client can push the
  /// same day as often as it likes and nothing is double-counted.
  void mergeHigher(DayProgress other) {
    sessions = sessions > other.sessions ? sessions : other.sessions;
    turns = turns > other.turns ? turns : other.turns;
    corrections = corrections > other.corrections ? corrections : other.corrections;
    if (other.pronCount > pronCount) {
      pronCount = other.pronCount;
      pronSum = other.pronSum;
    }
    wordsMastered = wordsMastered > other.wordsMastered ? wordsMastered : other.wordsMastered;
  }
}

/// A window of days, summarised.
class ProgressSummary {
  /// Learner turns per correction — "one mistake every N sentences". Higher is
  /// better. Null when there were no turns to measure.
  final double? sentencesPerMistake;

  /// Mean pronunciation score, or null when nothing was scored in the window.
  final double? pronAverage;

  final int sessions;
  final int turns;
  const ProgressSummary({
    required this.sentencesPerMistake,
    required this.pronAverage,
    required this.sessions,
    required this.turns,
  });
}

/// Rolling record of how a learner is actually doing, day by day.
///
/// The raw material was already being produced and thrown away: the chat screen
/// computes a correction density at the end of every session and used it once,
/// for a level nudge, before discarding it; every pronunciation score was logged
/// to analytics and never shown to the person who earned it. This keeps them.
///
/// Stored locally and synced with the rest of the learner's progress, so the
/// trend survives a reinstall — a trend that resets is worse than none, because
/// the one thing it exists to prove is that the last month was not wasted.
class ProgressHistory extends ChangeNotifier {
  static final ProgressHistory instance = ProgressHistory._();
  ProgressHistory._();

  static const _kDays = 'sf_progress_days';

  /// Days kept. Long enough to show a real change, short enough that the synced
  /// document stays small. Nobody looks back further than this.
  static const int keepDays = 90;

  /// Below this there is no trend, only noise, and claiming one would be a lie
  /// the learner can feel is wrong. Both must be met.
  static const int minSessionsForTrend = 10;
  static const int minDaysForTrend = 7;

  final Map<String, DayProgress> _days = {};

  /// Every day on record, oldest first — including days whose only entry is a
  /// vocabulary snapshot. Used where "what did this number read that day" is
  /// the question, rather than "did they practise".
  List<DayProgress> get allDays {
    final list = _days.values.toList();
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  /// Days the learner actually PRACTISED, oldest first.
  ///
  /// A mastery snapshot is written on every sync, so a day where nothing was
  /// done still leaves a row. Counting those as practice would let the trend
  /// gate below be satisfied by a week of opening the app and closing it.
  List<DayProgress> get days {
    final list = _days.values.where((d) => d.turns > 0 || d.pronCount > 0 || d.sessions > 0).toList();
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  int get totalSessions => _days.values.fold(0, (s, d) => s + d.sessions);

  /// Whether there is enough practice behind the numbers to draw a trend.
  bool get hasTrend {
    final d = days;
    return d.length >= minDaysForTrend && totalSessions >= minSessionsForTrend && d.length >= 2;
  }

  /// How many more sessions before a trend can be shown. 0 once it can.
  int get sessionsUntilTrend {
    final need = minSessionsForTrend - totalSessions;
    return need > 0 ? need : 0;
  }

  DayProgress _today() =>
      _days.putIfAbsent(todayKey(), () => DayProgress(date: todayKey()));

  // ---- recording ----------------------------------------------------------

  /// A finished conversation. [turns] is how many times the learner spoke,
  /// [corrections] how many fixes the tutor offered across them.
  Future<void> recordSession({required int turns, required int corrections}) async {
    final d = _today();
    d.sessions += 1;
    d.turns += turns;
    d.corrections += corrections;
    await _persist();
    notifyListeners();
  }

  /// One scored pronunciation attempt, from anywhere in the app.
  Future<void> recordPronunciation(int score) async {
    final d = _today();
    d.pronSum += score.clamp(0, 100);
    d.pronCount += 1;
    await _persist();
    notifyListeners();
  }

  /// Today's count of words the learner has actually retained. A snapshot, so
  /// the highest reading of the day wins rather than accumulating.
  Future<void> recordWordsMastered(int count) async {
    final d = _today();
    if (count <= d.wordsMastered) return;
    d.wordsMastered = count;
    await _persist();
    notifyListeners();
  }

  // ---- reading ------------------------------------------------------------

  /// Summarise a list of days.
  ProgressSummary summarise(List<DayProgress> window) {
    var turns = 0, corrections = 0, sessions = 0, pronSum = 0, pronCount = 0;
    for (final d in window) {
      turns += d.turns;
      corrections += d.corrections;
      sessions += d.sessions;
      pronSum += d.pronSum;
      pronCount += d.pronCount;
    }
    return ProgressSummary(
      // No mistakes at all is not "infinity sentences per mistake" — it is the
      // best possible reading, so the turn count itself stands in for it.
      sentencesPerMistake: turns == 0 ? null : turns / (corrections == 0 ? 1 : corrections),
      pronAverage: pronCount == 0 ? null : pronSum / pronCount,
      sessions: sessions,
      turns: turns,
    );
  }

  /// The window split in two halves, older first — what "then" and "now" mean.
  ///
  /// Halving the days that HAVE data, rather than taking fixed calendar
  /// windows, is what makes this work for someone who practises three times a
  /// week: a fixed "last 7 days vs the 7 before" would compare a busy week to
  /// an empty one and call it a collapse.
  (ProgressSummary, ProgressSummary)? thenAndNow() {
    if (!hasTrend) return null;
    final d = days;
    final mid = d.length ~/ 2;
    return (summarise(d.sublist(0, mid)), summarise(d.sublist(mid)));
  }

  /// Words mastered at the start of the record and now.
  (int, int)? masteryChange() {
    // allDays, not days: vocabulary can move on a day spent only reviewing
    // words, which leaves no conversation turns behind.
    final d = allDays.where((x) => x.wordsMastered > 0).toList();
    if (d.length < 2) return null;
    return (d.first.wordsMastered, d.last.wordsMastered);
  }

  // ---- storage + sync -----------------------------------------------------

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _days.clear();
    final raw = p.getString(_kDays);
    if (raw == null || raw.isEmpty) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      m.forEach((date, v) {
        if (v is Map<String, dynamic>) _days[date] = DayProgress.fromJson(date, v);
      });
    } catch (_) {/* ignore a corrupt store rather than lose the app */}
    _prune();
  }

  /// Clear everything (a different account signed in).
  Future<void> reset() async {
    _days.clear();
    await _persist();
    notifyListeners();
  }

  Map<String, dynamic> toCloud() => {
        for (final e in _days.entries) e.key: e.value.toJson(),
      };

  /// Union the cloud copy in, taking the fuller reading of any shared day.
  Future<void> mergeFrom(Map<String, dynamic>? cloud) async {
    if (cloud == null || cloud.isEmpty) return;
    cloud.forEach((date, v) {
      if (v is! Map) return;
      final incoming = DayProgress.fromJson(date, Map<String, dynamic>.from(v));
      final mine = _days[date];
      if (mine == null) {
        _days[date] = incoming;
      } else {
        mine.mergeHigher(incoming);
      }
    });
    _prune();
    await _persist();
    notifyListeners();
  }

  /// Drop anything older than [keepDays] so the synced document stays small.
  void _prune() {
    if (_days.length <= keepDays) return;
    final keys = _days.keys.toList()..sort();
    for (final k in keys.take(_days.length - keepDays)) {
      _days.remove(k);
    }
  }

  Future<void> _persist() async {
    _prune();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDays, jsonEncode(toCloud()));
  }
}
