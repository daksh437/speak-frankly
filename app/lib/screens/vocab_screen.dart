import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../services/vocabulary_service.dart';
import '../theme/app_theme.dart';

/// Saved vocabulary — words the learner bookmarked from the dictionary.
/// (Phase 2: spaced-repetition review games will build on this list.)
class VocabScreen extends StatelessWidget {
  const VocabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved Words')),
      body: AnimatedBuilder(
        animation: VocabularyService.instance,
        builder: (context, _) {
          final words = VocabularyService.instance.words;
          if (words.isEmpty) return const _EmptyVocab();
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: words.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _WordCard(word: words[i]),
          );
        },
      ),
    );
  }
}

class _WordCard extends StatelessWidget {
  final SavedWord word;
  const _WordCard({required this.word});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final cardColor = isLight ? Colors.white : const Color(0xFF1E1B26);

    return Dismissible(
      key: ValueKey(word.word),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => VocabularyService.instance.remove(word.word),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(18)),
        child: Icon(Icons.delete_rounded, color: scheme.onErrorContainer),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(18),
          boxShadow: isLight ? [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 5))] : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(child: Text(word.word, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                      if (word.phonetic != null) ...[
                        const SizedBox(width: 8),
                        Text(word.phonetic!, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                      ],
                    ],
                  ),
                ),
                if (word.audio != null)
                  _AudioButton(url: word.audio!),
              ],
            ),
            const SizedBox(height: 6),
            Text(word.definition, style: const TextStyle(fontSize: 14.5, height: 1.3)),
            if (word.translation != null && word.translation!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
                  child: Text(word.translation!, style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 13)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AudioButton extends StatefulWidget {
  final String url;
  const _AudioButton({required this.url});
  @override
  State<_AudioButton> createState() => _AudioButtonState();
}

class _AudioButtonState extends State<_AudioButton> {
  final _player = AudioPlayer();
  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => _player.play(UrlSource(widget.url)),
      icon: Icon(Icons.volume_up_rounded, color: AppTheme.seed),
      tooltip: 'Play pronunciation',
    );
  }
}

class _EmptyVocab extends StatelessWidget {
  const _EmptyVocab();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
              child: Icon(Icons.bookmark_border_rounded, size: 40, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 18),
            const Text('No saved words yet', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'While chatting, tap any word and press the\nbookmark to save it here for review.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
