// Tests for the progress record — the numbers the app uses to tell a learner
// whether they are actually getting better.
//
// This is the one place in the app where a wrong number does real damage. A
// learner cannot check the claim: if the app says they improved and they have
// not, they believe it until they meet a real conversation and find out. So the
// rules that decide WHETHER to make a claim matter as much as the arithmetic.
//
// What these lock in: a day's numbers only grow, so re-sending one is a no-op;
// pronunciation is averaged over attempts rather than over days; and no trend
// is drawn until there is enough practice behind it to mean something.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:speakflow/services/day_key.dart';
import 'package:speakflow/services/progress_history.dart';

/// Build a cloud-shaped history: {date: {s,t,c,ps,pc,wm}}.
Map<String, dynamic> cloud(List<(String, int, int, int, int, int)> rows) => {
      for (final (date, s, t, c, ps, pc) in rows)
        date: {'s': s, 't': t, 'c': c, 'ps': ps, 'pc': pc, 'wm': 0},
    };

/// N days ending today, each with the given turns/corrections.
List<(String, int, int, int, int, int)> streak(int days, {required int turns, required int corrections}) {
  final now = DateTime.now();
  return [
    for (var i = days - 1; i >= 0; i--)
      (dayKey(now.subtract(Duration(days: i))), 2, turns, corrections, 0, 0),
  ];
}

void main() {
  final h = ProgressHistory.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await h.reset();
  });

  group('recording', () {
    test('a session lands on today', () async {
      await h.recordSession(turns: 6, corrections: 2);
      expect(h.days.length, 1);
      expect(h.days.first.date, todayKey());
      expect(h.days.first.turns, 6);
      expect(h.days.first.corrections, 2);
      expect(h.days.first.sessions, 1);
    });

    test('sessions on the same day accumulate', () async {
      await h.recordSession(turns: 6, corrections: 2);
      await h.recordSession(turns: 4, corrections: 1);
      expect(h.days.single.sessions, 2);
      expect(h.days.single.turns, 10);
      expect(h.days.single.corrections, 3);
    });

    test('pronunciation is kept as a sum and a count', () async {
      await h.recordPronunciation(80);
      await h.recordPronunciation(90);
      expect(h.days.single.pronCount, 2);
      expect(h.days.single.pronAverage, 85);
    });

    test('a score outside 0..100 cannot skew the average', () async {
      await h.recordPronunciation(400);
      await h.recordPronunciation(-50);
      expect(h.days.single.pronAverage, 50); // 100 and 0
    });

    test('mastered words are a snapshot, not a running total', () async {
      await h.recordWordsMastered(5);
      await h.recordWordsMastered(9);
      await h.recordWordsMastered(7); // a word lapsed; the day's best stands
      expect(h.allDays.single.wordsMastered, 9);
    });

    test('a mastery snapshot alone is not a day of practice', () async {
      // It is written on every sync, so counting it would let a week of opening
      // the app and closing it satisfy the trend gate.
      await h.recordWordsMastered(9);
      expect(h.allDays.length, 1);
      expect(h.days, isEmpty);
    });

    test('but the mastery trend still sees those days', () async {
      await h.mergeFrom({
        '2026-08-01': {'wm': 4},
        '2026-08-20': {'wm': 18},
      });
      expect(h.masteryChange(), (4, 18));
    });
  });

  group('no trend without enough practice', () {
    test('a fresh account has none', () {
      expect(h.hasTrend, isFalse);
      expect(h.thenAndNow(), isNull);
    });

    test('plenty of sessions on too few days is not a trend', () async {
      // Twenty conversations, all crammed into one afternoon. That is not a
      // month of improvement, and must not be drawn as one.
      for (var i = 0; i < 20; i++) {
        await h.recordSession(turns: 5, corrections: 1);
      }
      expect(h.totalSessions, 20);
      expect(h.hasTrend, isFalse);
    });

    test('many days with too few sessions is not a trend either', () async {
      await h.mergeFrom(cloud([
        for (var i = 9; i >= 0; i--)
          (dayKey(DateTime.now().subtract(Duration(days: i))), 0, 1, 0, 0, 0),
      ]));
      expect(h.hasTrend, isFalse);
    });

    test('the countdown says how many conversations are left', () async {
      await h.recordSession(turns: 5, corrections: 1);
      await h.recordSession(turns: 5, corrections: 1);
      expect(h.sessionsUntilTrend, ProgressHistory.minSessionsForTrend - 2);
    });

    test('and stops at zero rather than going negative', () async {
      for (var i = 0; i < 15; i++) {
        await h.recordSession(turns: 5, corrections: 1);
      }
      expect(h.sessionsUntilTrend, 0);
    });
  });

  group('then and now', () {
    test('improvement reads as more sentences per mistake', () async {
      // First half: a mistake every 2 sentences. Second half: every 8.
      await h.mergeFrom(cloud([
        ...streak(8, turns: 8, corrections: 4).take(4),
      ]));
      final older = h.days.map((d) => d.date).toList();
      await h.mergeFrom(cloud([
        for (var i = 3; i >= 0; i--)
          (dayKey(DateTime.now().subtract(Duration(days: i))), 2, 8, 1, 0, 0),
      ]));
      expect(older.isNotEmpty, isTrue);
      final trend = h.thenAndNow();
      expect(trend, isNotNull);
      expect(trend!.$2.sentencesPerMistake! > trend.$1.sentencesPerMistake!, isTrue);
    });

    test('a flawless window is the best reading, not a division by zero', () {
      final s = h.summarise([
        DayProgress(date: '2026-09-01', sessions: 2, turns: 12, corrections: 0),
      ]);
      expect(s.sentencesPerMistake, 12);
      expect(s.sentencesPerMistake, isNot(double.infinity));
    });

    test('a window with no turns has no reading at all', () {
      final s = h.summarise([DayProgress(date: '2026-09-01')]);
      expect(s.sentencesPerMistake, isNull);
      expect(s.pronAverage, isNull);
    });

    test('pronunciation averages over attempts, not over days', () {
      // One day with a single 100, another with three 40s. The honest mean is
      // 55, not the 70 you get by averaging the two days.
      final s = h.summarise([
        DayProgress(date: '2026-09-01', pronSum: 100, pronCount: 1),
        DayProgress(date: '2026-09-02', pronSum: 120, pronCount: 3),
      ]);
      expect(s.pronAverage, 55);
    });
  });

  group('sync', () {
    test('a cloud day the device never had is adopted', () async {
      await h.mergeFrom(cloud([('2026-08-01', 2, 10, 3, 160, 2)]));
      expect(h.days.single.turns, 10);
      expect(h.days.single.pronAverage, 80);
    });

    test('the fuller reading of a shared day wins', () async {
      await h.recordSession(turns: 4, corrections: 1);
      await h.mergeFrom({
        todayKey(): {'s': 3, 't': 20, 'c': 2, 'ps': 0, 'pc': 0, 'wm': 0},
      });
      expect(h.days.single.turns, 20);
      expect(h.days.single.sessions, 3);
    });

    test('a thinner cloud copy cannot erase local practice', () async {
      await h.recordSession(turns: 12, corrections: 1);
      await h.mergeFrom({
        todayKey(): {'s': 0, 't': 0, 'c': 0, 'ps': 0, 'pc': 0, 'wm': 0},
      });
      expect(h.days.single.turns, 12);
    });

    test('merging the same payload twice changes nothing', () async {
      final payload = cloud([('2026-08-01', 2, 10, 3, 160, 2)]);
      await h.mergeFrom(payload);
      final once = h.toCloud().toString();
      await h.mergeFrom(payload);
      expect(h.toCloud().toString(), once);
    });

    test('an empty or null cloud copy is ignored', () async {
      await h.recordSession(turns: 5, corrections: 1);
      await h.mergeFrom(null);
      await h.mergeFrom({});
      expect(h.days.single.turns, 5);
    });

    test('a corrupt cloud entry is skipped, not thrown on', () async {
      await h.mergeFrom({'2026-08-01': 'not a map', '2026-08-02': {'t': 6}});
      expect(h.days.length, 1);
      expect(h.days.single.turns, 6);
    });

    test('history is capped so the synced document stays small', () async {
      final many = <String, dynamic>{};
      for (var i = 0; i < ProgressHistory.keepDays + 40; i++) {
        many[dayKey(DateTime(2026, 1, 1).add(Duration(days: i)))] = {'s': 1, 't': 1, 'c': 0};
      }
      await h.mergeFrom(many);
      expect(h.toCloud().length, ProgressHistory.keepDays);
      // The newest days are the ones kept.
      final kept = h.toCloud().keys.toList()..sort();
      expect(kept.last, dayKey(DateTime(2026, 1, 1).add(Duration(days: ProgressHistory.keepDays + 39))));
    });
  });

  group('persistence', () {
    test('a reload restores what was recorded', () async {
      await h.recordSession(turns: 7, corrections: 2);
      await h.recordPronunciation(75);
      await h.load();
      expect(h.days.single.turns, 7);
      expect(h.days.single.pronAverage, 75);
    });

    test('reset clears everything, including on disk', () async {
      await h.recordSession(turns: 7, corrections: 2);
      await h.reset();
      await h.load();
      expect(h.days, isEmpty);
      expect(h.totalSessions, 0);
    });
  });
}
