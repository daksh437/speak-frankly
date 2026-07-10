import 'package:flutter/material.dart';

import '../services/analytics_service.dart';
import '../services/gamification_service.dart';
import '../services/vocabulary_service.dart';
import '../theme/app_theme.dart';

/// "Guess the word" review game (a cloze-style micro-game, BRD §5.2): read a
/// meaning, pick the matching saved word from four options.
class WordGuessScreen extends StatefulWidget {
  const WordGuessScreen({super.key});
  @override
  State<WordGuessScreen> createState() => _WordGuessScreenState();
}

class _WordGuessScreenState extends State<WordGuessScreen> {
  late final List<SavedWord> _words;
  int _index = 0;
  int _correctCount = 0;
  int? _selected;
  bool _done = false;
  late List<String> _options;
  late int _correctIndex;

  @override
  void initState() {
    super.initState();
    _words = List.of(VocabularyService.instance.words)..shuffle();
    _prepare();
  }

  void _prepare() {
    final target = _words[_index];
    final others = _words.where((w) => w.word.toLowerCase() != target.word.toLowerCase()).toList()..shuffle();
    final opts = [target.word, ...others.take(3).map((w) => w.word)]..shuffle();
    _options = opts;
    _correctIndex = opts.indexOf(target.word);
    _selected = null;
  }

  void _select(int i) {
    if (_selected != null) return;
    setState(() {
      _selected = i;
      if (i == _correctIndex) {
        _correctCount++;
        GamificationService.instance.recordActivity(xpGain: 3);
      }
    });
  }

  void _next() {
    if (_index + 1 >= _words.length) {
      AnalyticsService.log('word_guess_done', {'score': _correctCount});
      setState(() => _done = true);
    } else {
      setState(() {
        _index++;
        _prepare();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guess the word')),
      body: SafeArea(child: _done ? _summary(context) : _quiz(context)),
    );
  }

  Widget _quiz(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final target = _words[_index];
    final def = target.definition.isNotEmpty ? target.definition : 'Which word did you save?';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_index + 1) / _words.length,
              minHeight: 7,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Which word means…', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5)),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(20)),
          child: Text(def, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.3)),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              for (int i = 0; i < _options.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: _Opt(
                    text: _options[i],
                    state: _selected == null
                        ? 0
                        : (i == _correctIndex ? 1 : (i == _selected ? 2 : 0)),
                    onTap: () => _select(i),
                  ),
                ),
            ],
          ),
        ),
        if (_selected != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(onPressed: _next, child: Text(_index + 1 >= _words.length ? 'Finish' : 'Next')),
            ),
          ),
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
          const Text('🧠', style: TextStyle(fontSize: 60)),
          const SizedBox(height: 16),
          const Text('Great memory!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('You knew $_correctCount of ${_words.length}.', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
            child: Text('+${_correctCount * 3} XP  ⭐', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFB45309))),
          ),
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

class _Opt extends StatelessWidget {
  final String text;
  final int state; // 0 idle, 1 correct, 2 wrong
  final VoidCallback onTap;
  const _Opt({required this.text, required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    Color bg;
    Color border;
    if (state == 1) {
      bg = AppColors.success.withValues(alpha: 0.15);
      border = AppColors.success;
    } else if (state == 2) {
      bg = const Color(0xFFEF4444).withValues(alpha: 0.15);
      border = const Color(0xFFEF4444);
    } else {
      bg = isLight ? Colors.white : const Color(0xFF1E1B26);
      border = Colors.transparent;
    }
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: border, width: 2)),
          child: Row(
            children: [
              Expanded(child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
              if (state == 1) Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
              if (state == 2) const Icon(Icons.cancel_rounded, color: Color(0xFFEF4444), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
