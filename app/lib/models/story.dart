/// Scripted branching dialogue trees (BRD §4.1). A [Story] is a hand-written
/// role-play: each [StoryNode] is a tutor line plus a set of learner [StoryChoice]s
/// that branch to the next node. No AI/network — deterministic, offline, free,
/// and beginner-safe (controlled vocabulary + per-choice feedback).
library;

class StoryChoice {
  /// The line the learner picks (what they "say").
  final String text;

  /// Id of the next node. Empty string means this choice ends the story.
  final String next;

  /// Optional gentle tip shown after choosing (e.g. a more natural phrasing).
  final String? note;

  /// Whether this is a natural/correct choice (vs. understandable-but-awkward).
  final bool good;

  const StoryChoice(this.text, this.next, {this.note, this.good = true});

  bool get isEnd => next.isEmpty;
}

class StoryNode {
  final String id;

  /// The tutor's line at this point in the conversation.
  final String tutor;

  /// Learner options. Empty = terminal node (the story ends here).
  final List<StoryChoice> choices;

  /// Shown on a terminal node as the closing line.
  final String? ending;

  const StoryNode(this.id, this.tutor, {this.choices = const [], this.ending});

  bool get isEnd => choices.isEmpty;
}

class Story {
  final String id;
  final String title;
  final String emoji;
  final String level; // CEFR-ish, e.g. 'A1'
  final String description;
  final List<String> keywords;
  final String startId;
  final Map<String, StoryNode> nodes;

  const Story({
    required this.id,
    required this.title,
    required this.emoji,
    required this.level,
    required this.description,
    required this.keywords,
    required this.startId,
    required this.nodes,
  });

  StoryNode get start => nodes[startId]!;
  StoryNode? node(String id) => nodes[id];
}
