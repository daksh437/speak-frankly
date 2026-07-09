import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';

/// Tap-a-word → dictionary card (meaning, phonetic, audio, L1 translation).
/// Premium bottom sheet so it doesn't interrupt the conversation.
void showDictionarySheet(BuildContext context, String word) {
  final cleaned = word.replaceAll(RegExp(r'[^A-Za-z\-]'), '').toLowerCase();
  if (cleaned.isEmpty) return;
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).brightness == Brightness.light ? Colors.white : const Color(0xFF1E1B26),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => _DictionarySheet(word: cleaned),
  );
}

class _DictionarySheet extends StatefulWidget {
  final String word;
  const _DictionarySheet({required this.word});
  @override
  State<_DictionarySheet> createState() => _DictionarySheetState();
}

class _DictionarySheetState extends State<_DictionarySheet> {
  late Future<DictionaryCard?> _future;
  final _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _future = ApiService.instance.lookupWord(widget.word, target: UserSession.instance.nativeLanguage);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 4, 22, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: FutureBuilder<DictionaryCard?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Padding(padding: EdgeInsets.all(36), child: Center(child: CircularProgressIndicator()));
          }
          final card = snap.data;
          if (card == null) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Row(
                children: [
                  const Icon(Icons.search_off_rounded, color: Colors.grey),
                  const SizedBox(width: 10),
                  Expanded(child: Text('No dictionary entry for "${widget.word}".')),
                ],
              ),
            );
          }
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(card.word, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                          if (card.phonetic != null)
                            Text(card.phonetic!, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14)),
                        ],
                      ),
                    ),
                    if (card.audio != null)
                      GestureDetector(
                        onTap: () => _player.play(UrlSource(card.audio!)),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(gradient: AppColors.gradient(AppTheme.seed), shape: BoxShape.circle),
                          child: const Icon(Icons.volume_up_rounded, color: Colors.white),
                        ),
                      ),
                  ],
                ),
                if (card.translation != null && card.translation!.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.translate_rounded, size: 18, color: scheme.onPrimaryContainer),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(card.translation!, style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 14.5)),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                ...card.meanings.map((m) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (m.partOfSpeech.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                              child: Text(m.partOfSpeech,
                                  style: TextStyle(fontStyle: FontStyle.italic, color: scheme.onSurfaceVariant, fontSize: 12.5)),
                            ),
                          const SizedBox(height: 6),
                          Text(m.definition, style: const TextStyle(fontSize: 15, height: 1.35)),
                          if (m.example.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: Text('"${m.example}"',
                                  style: TextStyle(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic, fontSize: 13.5)),
                            ),
                        ],
                      ),
                    )),
              ],
            ),
          );
        },
      ),
    );
  }
}
