import 'package:flutter/material.dart';

import '../services/gamification_service.dart';
import '../services/vocabulary_service.dart';
import '../theme/app_theme.dart';

/// Matching review game: pair each saved word with its meaning. A spaced-
/// repetition micro-game (BRD §5.2) alongside flashcards.
class MatchGameScreen extends StatefulWidget {
  const MatchGameScreen({super.key});
  @override
  State<MatchGameScreen> createState() => _MatchGameScreenState();
}

class _MatchGameScreenState extends State<MatchGameScreen> {
  late final List<SavedWord> _pairs;
  late final List<int> _defOrder; // definition slot j -> word index
  int? _selWord;
  int? _wrongDef;
  final Set<int> _matched = {};
  bool _done = false;

  @override
  void initState() {
    super.initState();
    // Only words that actually carry a meaning can be matched TO one. Imported
    // words are saved with whatever meaning the extractor returned, which is
    // sometimes nothing - and a blank right-hand tile is not a puzzle, it is an
    // invisible target the learner has to find by elimination.
    final all = List.of(VocabularyService.instance.words)..shuffle();
    _pairs = all.where((w) => w.definition.trim().isNotEmpty).take(5).toList();
    _defOrder = List.generate(_pairs.length, (i) => i)..shuffle();
  }

  void _tapWord(int i) {
    if (_matched.contains(i)) return;
    setState(() => _selWord = i);
  }

  void _tapDef(int j) {
    final wordIdx = _defOrder[j];
    if (_matched.contains(wordIdx) || _selWord == null) return;
    if (wordIdx == _selWord) {
      setState(() {
        _matched.add(wordIdx);
        _selWord = null;
        if (_matched.length == _pairs.length) {
          _done = true;
          GamificationService.instance.recordActivity(xpGain: _pairs.length * 2);
        }
      });
    } else {
      setState(() => _wrongDef = j);
      Future.delayed(const Duration(milliseconds: 450), () {
        if (mounted) setState(() { _wrongDef = null; _selWord = null; });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Match the words')),
      body: SafeArea(
        child: _pairs.length < 2
            ? _notEnough(context)
            : (_done ? _summary(context) : _board(context)),
      ),
    );
  }

  /// Reachable when the learner's saved words have no meanings attached - the
  /// Words tab counts them, so the game can be opened with nothing to match.
  Widget _notEnough(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🧩', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 14),
            const Text('Not enough words with meanings', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Save a few more words from the dictionary (tap a word while chatting) to play the matching game.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5, height: 1.4)),
          ],
        ),
      ),
    );
  }

  Widget _board(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Tap a word, then its meaning',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5)),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Words column
                Expanded(
                  child: Column(
                    children: [
                      for (int i = 0; i < _pairs.length; i++)
                        _Tile(
                          text: _pairs[i].word,
                          selected: _selWord == i,
                          matched: _matched.contains(i),
                          onTap: () => _tapWord(i),
                          isWord: true,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Definitions column (shuffled)
                Expanded(
                  child: Column(
                    children: [
                      for (int j = 0; j < _defOrder.length; j++)
                        _Tile(
                          text: _pairs[_defOrder[j]].definition,
                          selected: false,
                          matched: _matched.contains(_defOrder[j]),
                          wrong: _wrongDef == j,
                          onTap: () => _tapDef(j),
                          isWord: false,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('${_matched.length}/${_pairs.length} matched',
              style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
      ],
    );
  }

  Widget _summary(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🧩', style: TextStyle(fontSize: 60)),
          const SizedBox(height: 16),
          const Text('All matched!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
            child: Text('+${_pairs.length * 2} XP  ⭐', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFB45309))),
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

class _Tile extends StatelessWidget {
  final String text;
  final bool selected;
  final bool matched;
  final bool wrong;
  final bool isWord;
  final VoidCallback onTap;
  const _Tile({
    required this.text,
    required this.selected,
    required this.matched,
    required this.onTap,
    required this.isWord,
    this.wrong = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    Color bg;
    Color fg = scheme.onSurface;
    if (matched) {
      bg = AppColors.success.withValues(alpha: 0.18);
      fg = isLight ? const Color(0xFF0B7A54) : AppColors.success;
    } else if (wrong) {
      bg = const Color(0xFFEF4444).withValues(alpha: 0.18);
    } else if (selected) {
      bg = scheme.primaryContainer;
      fg = scheme.onPrimaryContainer;
    } else {
      bg = isLight ? Colors.white : const Color(0xFF1E1B26);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: matched ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isWord ? 15 : 12.5,
                fontWeight: isWord ? FontWeight.w700 : FontWeight.w500,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
