import 'gamification_service.dart';
import 'vocabulary_service.dart';

/// A milestone badge, earned by reaching a stat threshold (BRD §8 rewards).
class Achievement {
  final String emoji;
  final String title;
  final String description;
  final bool earned;
  const Achievement(this.emoji, this.title, this.description, this.earned);
}

/// Derived (not stored) from local stats — recomputed on demand.
List<Achievement> computeAchievements() {
  final g = GamificationService.instance;
  final words = VocabularyService.instance.count;
  return [
    Achievement('🎯', 'First chat', 'Finish a conversation', g.scenariosCompleted >= 1),
    Achievement('🔥', 'On a roll', '3-day streak', g.streak >= 3),
    Achievement('🗓️', 'Weekly warrior', '7-day streak', g.streak >= 7),
    Achievement('📚', 'Word collector', 'Save 10 words', words >= 10),
    Achievement('🎤', 'Speaker', '10 speaking reps', g.speakingReps >= 10),
    Achievement('💬', 'Conversationalist', 'Finish 10 chats', g.scenariosCompleted >= 10),
    Achievement('⭐', 'Rising star', 'Earn 100 XP', g.xp >= 100),
    Achievement('🏆', 'Champion', 'Earn 500 XP', g.xp >= 500),
  ];
}
