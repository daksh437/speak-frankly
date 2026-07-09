import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/user_session.dart';

/// Tap-a-word → dictionary card (meaning, phonetic, audio, L1 translation).
/// Shown as a bottom sheet so it doesn't interrupt the conversation.
void showDictionarySheet(BuildContext context, String word) {
  final cleaned = word.replaceAll(RegExp(r'[^A-Za-z\-]'), '').toLowerCase();
  if (cleaned.isEmpty) return;
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: FutureBuilder<DictionaryCard?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
          }
          final card = snap.data;
          if (card == null) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Text('No dictionary entry for "${widget.word}".'),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(card.word, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 10),
                  if (card.phonetic != null) Text(card.phonetic!, style: const TextStyle(color: Colors.grey)),
                  const Spacer(),
                  if (card.audio != null)
                    IconButton.filledTonal(
                      icon: const Icon(Icons.volume_up),
                      onPressed: () => _player.play(UrlSource(card.audio!)),
                    ),
                ],
              ),
              if (card.translation != null && card.translation!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(card.translation!,
                      style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer)),
                ),
              ],
              const SizedBox(height: 14),
              ...card.meanings.map((m) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (m.partOfSpeech.isNotEmpty)
                          Text(m.partOfSpeech, style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                        Text(m.definition),
                        if (m.example.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text('"${m.example}"', style: const TextStyle(color: Colors.grey)),
                          ),
                      ],
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }
}
