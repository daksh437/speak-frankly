import '../models/models.dart';
import '../services/api_service.dart';
import '../services/user_session.dart';

/// Whether the daily call ships.
///
/// The screen, the scenario picker and the notification routing are all built
/// and tested — what has not been proved is the FEEL. Every turn carries a gap
/// while the recogniser settles and the model answers, and a gap that reads as
/// thoughtful in a chat can read as a dropped line in a call. That is not
/// something code review can settle; it needs a few real three-minute
/// conversations on a real phone.
///
/// So it stays off for this release, which is a review resubmission and the
/// wrong moment to put an untested headline feature at the top of the home
/// screen. Flip this to true — nothing else — to ship it.
const bool kDailyCallEnabled = false;

/// Which conversation the daily call should be about.
///
/// The call has to start the moment it is answered — a picker between the
/// notification and the first word would undo the whole point, which is that
/// there is nothing to decide and no way to stall. So this chooses, and the
/// learner just talks.
///
/// It prefers a scenario at the learner's own level, and rotates by day so the
/// call is not the same conversation every evening. If the library cannot be
/// reached it falls back to open conversation, because a call that fails to
/// start is worse than a call with no scenario.
Future<Scenario> pickCallScenario() async {
  try {
    final all = await ApiService.instance.fetchScenarios();
    if (all.isNotEmpty) {
      final level = UserSession.instance.level;
      final atLevel = all.where((s) => s.level == level).toList();
      final pool = atLevel.isNotEmpty ? atLevel : all;
      // Rotate by the day number so consecutive days differ, and so the same
      // day is the same conversation if the learner answers twice.
      final day = DateTime.now().difference(DateTime(2026)).inDays;
      return pool[day.abs() % pool.length];
    }
  } catch (_) {/* offline, or the library is unreachable */}
  return _openConversation;
}

/// Used when there is no scenario to hand. Deliberately about the learner's own
/// day: it needs no setup and anyone can answer it.
final Scenario _openConversation = Scenario(
  id: 'daily-call',
  title: 'Daily call',
  emoji: '📞',
  theme: 'small-talk',
  level: UserSession.instance.level,
  description: 'Three minutes of talking about your day.',
  goals: const ['Talk about your day', 'Answer follow-up questions'],
  starter: 'Hi! Good to hear from you. How has your day been so far?',
  keywords: const [],
  setup: 'You are a warm, curious friend on a short phone call with an English '
      'learner. Ask about their day and follow up on what they say. Keep every '
      'reply to one or two short sentences, as a person on a call would — never '
      'a paragraph. Ask one question at a time.',
);
