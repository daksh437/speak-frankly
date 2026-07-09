/// Plain data models mirroring the backend JSON shapes.
library;

class Scenario {
  final String id;
  final String title;
  final String emoji;
  final String theme;
  final String level;
  final String description;
  final List<String> goals;
  final String starter;
  final List<String> keywords;

  Scenario({
    required this.id,
    required this.title,
    required this.emoji,
    required this.theme,
    required this.level,
    required this.description,
    required this.goals,
    required this.starter,
    required this.keywords,
  });

  factory Scenario.fromJson(Map<String, dynamic> j) => Scenario(
        id: j['id'] ?? '',
        title: j['title'] ?? '',
        emoji: j['emoji'] ?? '💬',
        theme: j['theme'] ?? '',
        level: j['level'] ?? '',
        description: j['description'] ?? '',
        goals: (j['goals'] as List?)?.map((e) => e.toString()).toList() ?? [],
        starter: j['starter'] ?? '',
        keywords: (j['keywords'] as List?)?.map((e) => e.toString()).toList() ?? [],
      );
}

class Correction {
  final String original;
  final String better;
  final String reason;
  Correction({required this.original, required this.better, required this.reason});

  factory Correction.fromJson(Map<String, dynamic> j) => Correction(
        original: j['original']?.toString() ?? '',
        better: j['better']?.toString() ?? '',
        reason: j['reason']?.toString() ?? '',
      );
}

class TutorReply {
  final String reply;
  final List<Correction> corrections;
  final List<String> suggestions;

  TutorReply({required this.reply, required this.corrections, required this.suggestions});

  factory TutorReply.fromJson(Map<String, dynamic> j) => TutorReply(
        reply: j['reply']?.toString() ?? '',
        corrections: (j['corrections'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(Correction.fromJson)
                .toList() ??
            [],
        suggestions: (j['suggestions'] as List?)?.map((e) => e.toString()).toList() ?? [],
      );
}

/// A message in the chat UI. `role` is 'user' or 'model' (matches backend).
class ChatMessage {
  final String role;
  final String text;
  final List<Correction> corrections;
  ChatMessage({required this.role, required this.text, this.corrections = const []});

  bool get isUser => role == 'user';
  Map<String, String> toApi() => {'role': role, 'text': text};
}

class DictionaryCard {
  final String word;
  final String? phonetic;
  final String? audio;
  final String? translation;
  final List<DictMeaning> meanings;

  DictionaryCard({
    required this.word,
    this.phonetic,
    this.audio,
    this.translation,
    required this.meanings,
  });

  factory DictionaryCard.fromJson(Map<String, dynamic> j) => DictionaryCard(
        word: j['word'] ?? '',
        phonetic: j['phonetic'],
        audio: j['audio'],
        translation: j['translation'],
        meanings: (j['meanings'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(DictMeaning.fromJson)
                .toList() ??
            [],
      );
}

class DictMeaning {
  final String partOfSpeech;
  final String definition;
  final String example;
  DictMeaning({required this.partOfSpeech, required this.definition, required this.example});

  factory DictMeaning.fromJson(Map<String, dynamic> j) => DictMeaning(
        partOfSpeech: j['partOfSpeech'] ?? '',
        definition: j['definition'] ?? '',
        example: j['example'] ?? '',
      );
}
