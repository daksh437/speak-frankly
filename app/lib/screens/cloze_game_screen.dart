import 'dart:math';

import 'package:flutter/material.dart';

import '../services/gamification_service.dart';
import '../services/vocabulary_service.dart';
import '../theme/app_theme.dart';

/// Cloze game (BRD §5.2): a saved word is blanked out of its own example
/// sentence and the learner picks the right word from choices. Teaches words in
/// context (stronger than definition-only recall). Uses words that have an
/// example sentence containing the word.
class ClozeGameScreen extends StatefulWidget {
  const ClozeGameScreen({super.key});
  @override
  State<ClozeGameScreen> createState() => _ClozeGameScreenState();
}

class _ClozeItem {
  final String sentence; // with the word replaced by a blank
  final String answer;
  final List<String> options;
  _ClozeItem(this.sentence, this.answer, this.options);
}

class _ClozeGameScreenState extends State<ClozeGameScreen> {
  late final List<_ClozeItem> _items;
  int _index = 0;
  int _correct = 0;
  String? _picked;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _items = _build();
  }

  List<_ClozeItem> _build() {
    final rng = Random();
    final source = List.of(VocabularyService.instance.clozeWords)..shuffle(rng);
    final allWords = VocabularyService.instance.words.map((w) => w.word).toSet().toList();
    final items = <_ClozeItem>[];
    for (final w in source.take(10)) {
      final blanked = (w.example ?? '').replaceAll(
        RegExp(r'\b' + RegExp.escape(w.word) + r'\b', caseSensitive: false),
        '_____',
      );
      if (blanked == (w.example ?? '')) continue; // nothing replaced
      // 3 distractors from other saved words.
      final distractors = allWords.where((x) => x.toLowerCase() != w.word.toLowerCase()).toList()..shuffle(rng);
      final options = <String>[w.word, ...distractors.take(3)]..shuffle(rng);
      items.add(_ClozeItem(blanked, w.word, options));
    }
    return items;
  }

  void _pick(String option) {
    if (_picked != null) return;
    setState(() => _picked = option);
    final right = option.toLowerCase() == _items[_index].answer.toLowerCase();
    if (right) _correct++;
    GamificationService.instance.recordActivity(xpGain: 2);
    Future.delayed(const Duration(milliseconds: 750), () {
      if (!mounted) return;
      if (_index + 1 >= _items.length) {
        setState(() => _done = true);
      } else {
        setState(() {
          _index++;
          _picked = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cloze — fill the blank')),
      body: SafeArea(
        child: _items.isEmpty
            ? _empty(context)
            : _done
                ? _summary(context)
                : _game(context),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📝', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 14),
            const Text('Not enough words with examples', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Save a few more words from the dictionary (tap a word while chatting) to unlock Cloze.',
                textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5, height: 1.4)),
          ],
        ),
      ),
    );
  }

  Widget _game(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = _items[_index];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (_index + 1) / _items.length,
                    minHeight: 7,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text('${_index + 1}/${_items.length}', style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text('Fill the blank', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14)),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(item.sentence, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.4)),
        ),
        const SizedBox(height: 28),
        ...item.options.map((opt) {
          Color? bg;
          Color? fg;
          if (_picked != null) {
            final isAnswer = opt.toLowerCase() == item.answer.toLowerCase();
            final isPicked = opt == _picked;
            if (isAnswer) {
              bg = AppColors.success.withValues(alpha: 0.18);
              fg = AppColors.success;
            } else if (isPicked) {
              bg = const Color(0xFFEF4444).withValues(alpha: 0.15);
              fg = const Color(0xFFEF4444);
            }
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _pick(opt),
                style: OutlinedButton.styleFrom(
                  backgroundColor: bg,
                  foregroundColor: fg,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text(opt, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          );
        }),
        const Spacer(flex: 2),
      ],
    );
  }

  Widget _summary(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🎯', style: TextStyle(fontSize: 60)),
          const SizedBox(height: 16),
          const Text('Nice work!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('You got $_correct of ${_items.length} right.', style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
          ),
        ],
      ),
    );
  }
}
