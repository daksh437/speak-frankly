import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/analytics_service.dart';
import '../services/gamification_service.dart';
import '../services/speech_service.dart';
import '../theme/app_theme.dart';
import 'pronunciation_chips.dart';

/// Say a known phrase out loud and hear how it landed, word by word.
///
/// WHY THIS IS A SHEET AND NOT A SCORE ON THE CHAT BUBBLE
/// Scoring pronunciation needs a REFERENCE — the sentence the learner was
/// trying to say. In free conversation there isn't one: the transcript is the
/// recogniser's own best guess, so grading it against itself scores full marks
/// every time and teaches nothing. Anywhere the app already knows the intended
/// sentence, though, the assessment is real. Two places in a conversation do:
///
///   - a correction card, where the tutor has just written the natural version
///     of what the learner tried to say;
///   - a tutor line, which the learner can repeat back (shadowing).
///
/// Both hand a genuine target to [assessPronunciation], which is the same
/// engine the Speak tab uses — Needleman-Wunsch alignment, partial credit for
/// near-misses, and the recogniser's own confidence blended in.
///
/// Opening this closes the practice loop the app was missing: you said it a bit
/// wrong, here is the right way, now say the right way, here is how that went.
Future<void> showSayItSheet(
  BuildContext context, {
  required String phrase,
  required Color accent,

  /// What the learner is practising, for analytics: 'correction' or 'tutor_line'.
  required String source,
}) {
  final target = phrase.trim();
  if (target.isEmpty) return Future.value();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).brightness == Brightness.light ? Colors.white : const Color(0xFF1E1B26),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => _SayItSheet(phrase: target, accent: accent, source: source),
  );
}

class _SayItSheet extends StatefulWidget {
  final String phrase;
  final Color accent;
  final String source;
  const _SayItSheet({required this.phrase, required this.accent, required this.source});
  @override
  State<_SayItSheet> createState() => _SayItSheetState();
}

class _SayItSheetState extends State<_SayItSheet> {
  String _heard = '';
  PronunciationResult? _result;

  /// One score per attempt. The recogniser can deliver a final result more than
  /// once, and each of those must not count as another rep.
  bool _scored = false;

  @override
  void dispose() {
    SpeechService.instance.stopListening();
    super.dispose();
  }

  Future<void> _listen() => SpeechService.instance.speak(widget.phrase);

  Future<void> _record() async {
    await SpeechService.instance.stopSpeaking(); // don't record our own playback
    setState(() {
      _heard = '';
      _result = null;
      _scored = false;
    });
    final ok = await SpeechService.instance.startListening(
      onResult: (text, isFinal) {
        if (!mounted) return;
        setState(() => _heard = text);
        if (isFinal && !_scored) _score(text);
      },
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.speechUnavailable)),
      );
    }
  }

  void _score(String said) {
    _scored = true;
    final result = assessPronunciation(
      widget.phrase,
      said,
      confidence: SpeechService.instance.lastConfidence,
    );
    // Same XP ladder the Speak tab pays, so a rep is worth the same wherever it
    // happens — and it counts towards the speaking stat either way.
    final xp = result.score >= 85 ? 10 : (result.score >= 60 ? 6 : 2);
    GamificationService.instance.recordSpeaking(xpGain: xp);
    AnalyticsService.log('say_it_attempt', {'score': result.score, 'source': widget.source});
    setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    final result = _result;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 4, 22, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.record_voice_over_rounded, size: 18, color: widget.accent),
                const SizedBox(width: 8),
                Text('Say it out loud',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: widget.accent)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: widget.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: widget.accent.withValues(alpha: 0.25)),
              ),
              child: Text(widget.phrase,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.35)),
            ),
            const SizedBox(height: 10),
            Center(
              child: OutlinedButton.icon(
                onPressed: _listen,
                icon: const Icon(Icons.volume_up_rounded, size: 18),
                label: Text(l.listenLabel),
                style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              ),
            ),
            if (_heard.isNotEmpty || result != null) ...[
              const SizedBox(height: 16),
              _ResultPanel(heard: _heard, result: result),
            ],
            const SizedBox(height: 18),
            AnimatedBuilder(
              animation: SpeechService.instance,
              builder: (context, _) {
                final listening = SpeechService.instance.isListening;
                return Column(
                  children: [
                    Text(
                      listening
                          ? l.shadowingListening
                          : (result == null ? 'Tap the mic and say it' : 'Tap the mic to try again'),
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: listening ? SpeechService.instance.stopListening : _record,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: listening ? 76 : 68,
                        height: listening ? 76 : 68,
                        decoration: BoxDecoration(
                          gradient: AppColors.gradient(listening ? const Color(0xFFEF4444) : widget.accent),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: (listening ? const Color(0xFFEF4444) : widget.accent).withValues(alpha: 0.4),
                              blurRadius: listening ? 22 : 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Icon(listening ? Icons.stop_rounded : Icons.mic_rounded,
                            color: Colors.white, size: 30),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  final String heard;
  final PronunciationResult? result;
  const _ResultPanel({required this.heard, required this.result});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    final r = result;
    final (color, label) = r == null ? (scheme.onSurfaceVariant, '') : scoreVerdict(context, r.score);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(l.youSaid, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
              const Spacer(),
              if (r != null)
                Text('${r.score}%', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: color)),
            ],
          ),
          const SizedBox(height: 4),
          Text(heard.isEmpty ? '…' : '"$heard"', style: const TextStyle(fontSize: 15)),
          if (r != null && r.words.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(l.wordByWord, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
            const SizedBox(height: 6),
            PronunciationChips(r.words),
          ],
          if (label.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          ],
        ],
      ),
    );
  }
}
