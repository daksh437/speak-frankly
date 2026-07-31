import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// A saved vocabulary word, with spaced-repetition schedule (Leitner boxes).
class SavedWord {
  final String word;
  final String? phonetic;
  final String definition;
  final String? translation;
  final String? audio;

  /// An example sentence (from the dictionary) — powers the Cloze game.
  final String? example;

  /// Spaced repetition: Leitner box (0..5) and when the word is next due (epoch
  /// ms; 0 = due now). Higher box = longer interval between reviews.
  int box;
  int dueAtMs;

  SavedWord({
    required this.word,
    this.phonetic,
    required this.definition,
    this.translation,
    this.audio,
    this.example,
    this.box = 0,
    this.dueAtMs = 0,
  });

  /// True if this word has a usable cloze (an example that contains the word).
  bool get hasCloze =>
      (example ?? '').toLowerCase().contains(word.toLowerCase()) && word.trim().isNotEmpty;

  /// Days until the next review for each box.
  static const List<int> _intervalsDays = [0, 1, 3, 7, 16, 35];

  bool get isDue => dueAtMs <= DateTime.now().millisecondsSinceEpoch;

  /// Update the schedule after a review. [known] false → reset to box 0 and
  /// resurface soon; true → promote to the next box (longer interval).
  void schedule(bool known) {
    box = known ? (box + 1).clamp(0, _intervalsDays.length - 1) : 0;
    final now = DateTime.now();
    dueAtMs = known
        ? now.add(Duration(days: _intervalsDays[box])).millisecondsSinceEpoch
        : now.add(const Duration(minutes: 10)).millisecondsSinceEpoch; // "again" → soon
  }

  Map<String, dynamic> toJson() => {
        'word': word,
        'phonetic': phonetic,
        'definition': definition,
        'translation': translation,
        'audio': audio,
        'example': example,
        'box': box,
        'dueAtMs': dueAtMs,
      };

  factory SavedWord.fromJson(Map<String, dynamic> j) => SavedWord(
        word: j['word'] ?? '',
        phonetic: j['phonetic'],
        definition: j['definition'] ?? '',
        translation: j['translation'],
        audio: j['audio'],
        example: j['example'],
        box: (j['box'] is num) ? (j['box'] as num).toInt() : 0,
        dueAtMs: (j['dueAtMs'] is num) ? (j['dueAtMs'] as num).toInt() : 0,
      );

  factory SavedWord.fromCard(DictionaryCard c) {
    final m = c.meanings.isNotEmpty ? c.meanings.first : null;
    return SavedWord(
      word: c.word,
      phonetic: c.phonetic,
      definition: m?.definition ?? '',
      translation: c.translation,
      audio: c.audio,
      example: (m?.example.isNotEmpty ?? false) ? m!.example : null,
    );
  }
}

/// Local saved-words store. ChangeNotifier for live UI updates.
class VocabularyService extends ChangeNotifier {
  static final VocabularyService instance = VocabularyService._();
  VocabularyService._();

  static const _kWords = 'sf_saved_words';
  final List<SavedWord> _words = [];

  List<SavedWord> get words => List.unmodifiable(_words.reversed); // newest first
  int get count => _words.length;

  /// Words due for spaced-repetition review right now (soonest-due first).
  List<SavedWord> get dueWords {
    final now = DateTime.now().millisecondsSinceEpoch;
    final due = _words.where((w) => w.dueAtMs <= now).toList();
    due.sort((a, b) => a.dueAtMs.compareTo(b.dueAtMs));
    return due;
  }

  int get dueCount => dueWords.length;

  /// Words that have a usable example sentence for the Cloze game.
  List<SavedWord> get clozeWords => _words.where((w) => w.hasCloze).toList();

  /// Record a spaced-repetition review result and reschedule the word.
  Future<void> review(String word, bool known) async {
    final i = _words.indexWhere((w) => w.word.toLowerCase() == word.toLowerCase());
    if (i == -1) return;
    _words[i].schedule(known);
    await _persist();
    notifyListeners();
  }

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
