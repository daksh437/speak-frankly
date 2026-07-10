import 'package:flutter/material.dart';

import '../services/analytics_service.dart';
import '../services/api_service.dart';
import '../services/vocabulary_service.dart';
import '../theme/app_theme.dart';

/// Content import (BRD §9): paste any text/article → AI pulls out useful
/// vocabulary (word + simple meaning) that the learner can save with one tap.
class ImportTextScreen extends StatefulWidget {
  const ImportTextScreen({super.key});
  @override
  State<ImportTextScreen> createState() => _ImportTextScreenState();
}

class _ImportTextScreenState extends State<ImportTextScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  List<Map<String, dynamic>>? _results;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _extract() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      final words = await ApiService.instance.extractVocab(text);
      if (!mounted) return;
      setState(() {
        _results = words;
        _loading = false;
      });
      AnalyticsService.log('content_import', {'count': words.length});
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not extract words. Try again.')));
    }
  }

  void _saveAll() {
    for (final w in _results ?? []) {
      VocabularyService.instance.addWord((w['word'] ?? '').toString(), (w['meaning'] ?? '').toString());
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved to your words ✓')));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Import text')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Paste an article, message, or any English text — we’ll pull out useful words to learn.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5)),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Paste text here…'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: _loading ? null : _extract,
                icon: _loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_awesome_rounded),
                label: Text(_loading ? 'Finding words…' : 'Find words'),
              ),
            ),
            if (_results != null) ...[
              const SizedBox(height: 20),
              if (_results!.isEmpty)
                Text('No words found. Try a longer text.', style: TextStyle(color: scheme.onSurfaceVariant))
              else ...[
                Row(
                  children: [
                    const Text('Tap to save', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    TextButton.icon(onPressed: _saveAll, icon: const Icon(Icons.done_all_rounded, size: 18), label: const Text('Save all')),
                  ],
                ),
                const SizedBox(height: 4),
                AnimatedBuilder(
                  animation: VocabularyService.instance,
                  builder: (context, _) => Column(
                    children: [
                      for (final w in _results!) _ImportWordCard(word: (w['word'] ?? '').toString(), meaning: (w['meaning'] ?? '').toString()),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ImportWordCard extends StatelessWidget {
  final String word;
  final String meaning;
  const _ImportWordCard({required this.word, required this.meaning});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final saved = VocabularyService.instance.isSaved(word);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xFF1E1B26),
        borderRadius: BorderRadius.circular(14),
        boxShadow: isLight ? [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))] : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(word, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                if (meaning.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(meaning, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              if (saved) {
                VocabularyService.instance.remove(word);
              } else {
                VocabularyService.instance.addWord(word, meaning);
              }
            },
            icon: Icon(saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: saved ? AppTheme.seed : scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
