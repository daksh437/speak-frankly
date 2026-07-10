import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// A saved vocabulary word.
class SavedWord {
  final String word;
  final String? phonetic;
  final String definition;
  final String? translation;
  final String? audio;
  SavedWord({required this.word, this.phonetic, required this.definition, this.translation, this.audio});

  Map<String, dynamic> toJson() => {
        'word': word,
        'phonetic': phonetic,
        'definition': definition,
        'translation': translation,
        'audio': audio,
      };

  factory SavedWord.fromJson(Map<String, dynamic> j) => SavedWord(
        word: j['word'] ?? '',
        phonetic: j['phonetic'],
        definition: j['definition'] ?? '',
        translation: j['translation'],
        audio: j['audio'],
      );

  factory SavedWord.fromCard(DictionaryCard c) => SavedWord(
        word: c.word,
        phonetic: c.phonetic,
        definition: c.meanings.isNotEmpty ? c.meanings.first.definition : '',
        translation: c.translation,
        audio: c.audio,
      );
}

/// Local saved-words store. ChangeNotifier for live UI updates.
class VocabularyService extends ChangeNotifier {
  static final VocabularyService instance = VocabularyService._();
  VocabularyService._();

  static const _kWords = 'sf_saved_words';
  final List<SavedWord> _words = [];

  List<SavedWord> get words => List.unmodifiable(_words.reversed); // newest first
  int get count => _words.length;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kWords);
    _words.clear();
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        _words.addAll(list.whereType<Map<String, dynamic>>().map(SavedWord.fromJson));
      } catch (_) {/* ignore corrupt store */}
    }
  }

  bool isSaved(String word) => _words.any((w) => w.word.toLowerCase() == word.toLowerCase());

  Future<void> toggle(DictionaryCard card) async {
    final existing = _words.indexWhere((w) => w.word.toLowerCase() == card.word.toLowerCase());
    if (existing != -1) {
      _words.removeAt(existing);
    } else {
      _words.add(SavedWord.fromCard(card));
    }
    await _persist();
    notifyListeners();
  }

  /// Add a word with a meaning (e.g. from content import). No-op if already saved.
  Future<void> addWord(String word, String meaning) async {
    final w = word.trim();
    if (w.isEmpty || isSaved(w)) return;
    _words.add(SavedWord(word: w, definition: meaning.trim()));
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String word) async {
    _words.removeWhere((w) => w.word.toLowerCase() == word.toLowerCase());
    await _persist();
    notifyListeners();
  }

  /// Clear all saved words (e.g. when a different account signs in).
  Future<void> reset() async {
    _words.clear();
    await _persist();
    notifyListeners();
  }

  List<Map<String, dynamic>> toJsonList() => _words.map((w) => w.toJson()).toList();

  /// Union server-saved words into the local list (dedupe by word) for cloud sync.
  Future<void> mergeFrom(List? serverWords) async {
    if (serverWords == null || serverWords.isEmpty) return;
    final existing = _words.map((w) => w.word.toLowerCase()).toSet();
    for (final e in serverWords) {
      if (e is Map<String, dynamic>) {
        final sw = SavedWord.fromJson(e);
        if (sw.word.isNotEmpty && !existing.contains(sw.word.toLowerCase())) {
          _words.add(sw);
          existing.add(sw.word.toLowerCase());
        }
      }
    }
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kWords, jsonEncode(_words.map((w) => w.toJson()).toList()));
  }
}
