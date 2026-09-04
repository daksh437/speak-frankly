import 'package:flutter/material.dart';

import '../services/speech_service.dart';
import '../theme/app_theme.dart';

/// The word-by-word verdict of a pronunciation attempt.
///
/// Lived inside the Speak screen, which is why the conversation — where the
/// learner speaks far more — had no way to show it. Shared so every place that
/// asks someone to say something can show the same feedback in the same shape.
class PronunciationChips extends StatelessWidget {
  final List<WordScore> words;
  const PronunciationChips(this.words, {super.key});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [for (final w in words) _WordChip(w)],
    );
  }
}

/// One target word, tinted by how well it was pronounced: green = clear,
/// amber = close (heard, but slightly off), red = missed.
class _WordChip extends StatelessWidget {
  final WordScore word;
  const _WordChip(this.word);

  @override
  Widget build(BuildContext context) {
    final (Color c, IconData? icon) = switch (word.verdict) {
      WordVerdict.good => (AppColors.success, Icons.check_rounded),
      WordVerdict.close => (const Color(0xFFF59E0B), null),
      WordVerdict.missed => (const Color(0xFFEF4444), Icons.close_rounded),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: c), const SizedBox(width: 3)],
          Text(word.word, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 13.5)),
        ],
      ),
    );
  }
}

/// The colour and headline for an overall 0-100 score. Shared so a score means
/// the same thing, and looks the same, wherever it is shown.
(Color, String) scoreVerdict(BuildContext context, int score) {
  if (score >= 85) return (AppColors.success, 'Excellent! 🌟');
  if (score >= 60) return (const Color(0xFFF59E0B), 'Good, keep going 👍');
  return (const Color(0xFFEF4444), 'Keep practising 🔁');
}
