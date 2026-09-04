import 'package:flutter/material.dart';

import '../services/progress_history.dart';
import '../services/vocabulary_service.dart';
import '../theme/app_theme.dart';

/// "Am I actually getting better?" — the question that decides whether someone
/// keeps a language app or quietly deletes it.
///
/// Everything on this screen is an OUTCOME. Streak, XP and scenarios completed
/// answer "how much did I show up", which a learner can already feel; none of
/// them answer this one. The numbers here were being produced all along and
/// thrown away: the chat screen computes a correction density at the end of
/// every session and used it once for a level nudge before discarding it, and
/// every pronunciation score went to analytics and never to the person who
/// earned it.
///
/// The screen refuses to draw a trend from too little practice. Ten sessions
/// over seven days is the floor. Below it, three sessions of noise can read as
/// a triumph or a collapse, and a learner who is told they improved when they
/// can feel that they have not will stop believing the app about anything.
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your progress')),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: ProgressHistory.instance,
          builder: (context, _) {
            final h = ProgressHistory.instance;
            final trend = h.thenAndNow();
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              children: [
                if (trend == null)
                  _NotYet(sessionsToGo: h.sessionsUntilTrend, days: h.days.length)
                else
                  _MistakesCard(then: trend.$1, now: trend.$2),
                const SizedBox(height: 16),
                if (h.days.isNotEmpty) _Sparkline(days: h.days),
                const SizedBox(height: 16),
                _Totals(history: h, trend: trend),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Shown until there is enough practice for a trend to mean anything.
class _NotYet extends StatelessWidget {
  final int sessionsToGo;
  final int days;
  const _NotYet({required this.sessionsToGo, required this.days});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = ProgressHistory.minSessionsForTrend - sessionsToGo;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Building your picture',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: scheme.onPrimaryContainer)),
          const SizedBox(height: 8),
          Text(
            sessionsToGo > 0
                ? "You've finished $done ${done == 1 ? 'conversation' : 'conversations'}. "
                    'After ${ProgressHistory.minSessionsForTrend} — across a few different days — '
                    "I'll show you exactly how much your English has changed."
                : 'A few more days of practice and your trend will appear here. '
                    'Right now it would be guesswork, and a made-up number is worth nothing.',
            style: TextStyle(fontSize: 14, height: 1.45, color: scheme.onPrimaryContainer.withValues(alpha: 0.9)),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (done / ProgressHistory.minSessionsForTrend).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: scheme.onPrimaryContainer.withValues(alpha: 0.15),
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 6),
          Text('$done of ${ProgressHistory.minSessionsForTrend} conversations · $days ${days == 1 ? 'day' : 'days'} practised',
              style: TextStyle(fontSize: 12, color: scheme.onPrimaryContainer.withValues(alpha: 0.75))),
        ],
      ),
    );
  }
}

/// The headline: mistakes then vs mistakes now.
class _MistakesCard extends StatelessWidget {
  final ProgressSummary then;
  final ProgressSummary now;
  const _MistakesCard({required this.then, required this.now});

  static String _phrase(double? perMistake) {
    if (perMistake == null) return '—';
    final n = perMistake.round();
    return n <= 1 ? 'almost every sentence' : 'every $n sentences';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final a = then.sentencesPerMistake;
    final b = now.sentencesPerMistake;
    final improved = a != null && b != null && b > a;
    final accent = improved ? AppColors.success : scheme.primary;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(improved ? Icons.trending_up_rounded : Icons.show_chart_rounded, color: accent, size: 20),
              const SizedBox(width: 8),
              Text(improved ? 'You are making fewer mistakes' : 'Your mistakes so far',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: accent)),
            ],
          ),
          const SizedBox(height: 16),
          _row(context, 'When you started', '1 mistake ${_phrase(a)}', muted: true),
          const SizedBox(height: 10),
          _row(context, 'Now', '1 mistake ${_phrase(b)}', muted: false, color: accent),
          if (!improved) ...[
            const SizedBox(height: 12),
            Text(
              'This moves slowly, and it moves up and down. Harder conversations '
              'produce more corrections — that is progress too, not a slip.',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value, {required bool muted, Color? color}) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
              fontSize: muted ? 17 : 22,
              fontWeight: muted ? FontWeight.w600 : FontWeight.w800,
              color: color ?? scheme.onSurfaceVariant,
            )),
      ],
    );
  }
}

/// One bar per practised day: how many sentences the learner got per mistake.
/// Taller is better. Deliberately unlabelled — it is a shape, not a dataset.
class _Sparkline extends StatelessWidget {
  final List<DayProgress> days;
  const _Sparkline({required this.days});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final recent = days.length > 30 ? days.sublist(days.length - 30) : days;
    final values = recent.map((d) {
      if (d.turns == 0) return 0.0;
      return d.turns / (d.corrections == 0 ? 1 : d.corrections);
    }).toList();
    final max = values.fold<double>(0, (m, v) => v > m ? v : m);
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xFF1E1B26),
        borderRadius: BorderRadius.circular(18),
        boxShadow: isLight
            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 5))]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sentences per mistake, by day',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurface)),
          const SizedBox(height: 12),
          SizedBox(
            height: 64,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final v in values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Container(
                        height: max == 0 ? 3 : (4 + (v / max) * 58),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: v == 0 ? 0.15 : 0.75),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text('${recent.length} ${recent.length == 1 ? 'day' : 'days'} practised · taller is better',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// The other two outcomes, plus the raw volume of speaking.
class _Totals extends StatelessWidget {
  final ProgressHistory history;
  final (ProgressSummary, ProgressSummary)? trend;
  const _Totals({required this.history, required this.trend});

  @override
  Widget build(BuildContext context) {
    final all = history.summarise(history.days);
    final mastery = history.masteryChange();
    final pronThen = trend?.$1.pronAverage;
    final pronNow = trend?.$2.pronAverage ?? all.pronAverage;

    return AnimatedBuilder(
      animation: VocabularyService.instance,
      builder: (context, _) => Column(
        children: [
          _Stat(
            emoji: '🎤',
            label: 'Pronunciation',
            value: pronNow == null ? 'Not measured yet' : '${pronNow.round()}%',
            change: (pronThen != null && pronNow != null && pronThen > 0)
                ? '${pronThen.round()}% → ${pronNow.round()}%'
                : (pronNow == null ? 'Tap "Say it" on a correction to start' : null),
            color: const Color(0xFFFF7A5A),
          ),
          const SizedBox(height: 10),
          _Stat(
            emoji: '📚',
            label: 'Words you have kept',
            value: '${VocabularyService.instance.masteredCount}',
            change: mastery == null ? 'Reviewed words that stuck' : '${mastery.$1} → ${mastery.$2}',
            color: const Color(0xFF00C2A8),
          ),
          const SizedBox(height: 10),
          _Stat(
            emoji: '💬',
            label: 'Times you have spoken',
            value: '${all.turns}',
            change: '${all.sessions} ${all.sessions == 1 ? 'conversation' : 'conversations'}',
            color: const Color(0xFF6366F1),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  final String? change;
  final Color color;
  const _Stat({
    required this.emoji,
    required this.label,
    required this.value,
    required this.change,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xFF1E1B26),
        borderRadius: BorderRadius.circular(16),
        boxShadow: isLight
            ? [BoxShadow(color: color.withValues(alpha: 0.10), blurRadius: 12, offset: const Offset(0, 5))]
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(13)),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                if (change != null)
                  Text(change!, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}
