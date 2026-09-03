import 'dart:math';

import 'package:flutter/material.dart';

import '../services/speech_service.dart';
import '../services/sync_service.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';

/// An ADAPTIVE, multi-skill placement test (BRD §6.1). It mixes grammar and
/// LISTENING questions (graded by CEFR level, starting at the learner's current
/// level and adapting up/down), then a short SPEAKING check, and finally
/// estimates a level and sets it.
class PlacementTestScreen extends StatefulWidget {
  const PlacementTestScreen({super.key});
  @override
  State<PlacementTestScreen> createState() => _PlacementTestScreenState();
}

enum _QType { grammar, listening }

enum _Phase { quiz, speaking, result }

class _Question {
  final String prompt; // grammar: sentence with a blank · listening: the spoken sentence
  final List<String> options;
  final int correct;
  final _QType type;
  const _Question(this.prompt, this.options, this.correct, {this.type = _QType.grammar});
}

const _levels = ['A0', 'A1', 'A2', 'B1', 'B2', 'C1'];

/// Graded bank — grammar + listening items per CEFR level, easiest → hardest.
const Map<String, List<_Question>> _bank = {
  'A0': [
    _Question('I ___ happy.', ['am', 'is', 'are'], 0),
    _Question('This ___ a cat.', ['is', 'are', 'am'], 0),
    _Question('___ name is Sam.', ['My', 'I', 'Me'], 0),
  ],
  'A1': [
    _Question('She ___ tea every morning.', ['drink', 'drinks', 'drinking'], 1),
    _Question('He ___ got a car.', ['have', 'has', 'having'], 1),
    _Question('She is my sister.', ['She is my sister.', 'He is my brother.', 'They are my friends.'], 0, type: _QType.listening),
  ],
  'A2': [
    _Question('Yesterday we ___ a film.', ['watch', 'watched', 'watching'], 1),
    _Question('___ you like some water?', ['Do', 'Would', 'Are'], 1),
    _Question('I bought some apples yesterday.', ['I bought some apples yesterday.', 'I will buy apples tomorrow.', 'I am eating an apple now.'], 0, type: _QType.listening),
  ],
  'B1': [
    _Question('If it rains, I ___ stay home.', ['will', 'would', 'am'], 0),
    _Question("I'm interested ___ music.", ['in', 'on', 'at'], 0),
    _Question('If it rains, we will stay inside.', ['If it rains, we will stay inside.', 'It was raining all day.', 'We stayed inside yesterday.'], 0, type: _QType.listening),
  ],
  'B2': [
    _Question('She avoided ___ him.', ['to meet', 'meeting', 'meet'], 1),
    _Question('He spoke as if he ___ everything.', ['knew', 'knows', 'know'], 0),
    _Question('She had already left when I arrived.', ['She had already left when I arrived.', 'She will leave before I arrive.', 'She leaves as soon as I arrive.'], 0, type: _QType.listening),
  ],
  'C1': [
    _Question('___ harder, he would have passed.', ['Had he studied', 'If he studies', 'He studied'], 0),
    _Question('The plan was met with ___ skepticism.', ['considerable', 'consider', 'considerably'], 0),
    _Question('Not only ___ late, but he also forgot the file.', ['was he', 'he was', 'he is'], 0),
  ],
};

/// A short phrase to read aloud in the speaking check, by placed level.
const Map<String, String> _speakingPhrase = {
  'A0': 'Hello, how are you?',
  'A1': 'Nice to meet you.',
  'A2': 'I would like a cup of tea.',
  'B1': 'Could you tell me where the station is?',
  'B2': "I've been learning English for a while now.",
  'C1': "I'd appreciate it if you could clarify that.",
};

class _PlacementTestScreenState extends State<PlacementTestScreen> {
  static const _total = 6;

  late int _cur; // index into _levels — current difficulty
  final Map<int, int> _rot = {};
  int _asked = 0;
  _Phase _phase = _Phase.quiz;

  /// Level the grammar/listening quiz settled on. The speaking check is read
  /// against a phrase at THIS level, so it has to be fixed before that phase.
  String _quizLevel = 'A2';

  // Speaking check state.
  String _spokenText = '';
  int? _spokenScore;
  bool _spokenDone = false;

  @override
  void initState() {
    super.initState();
    final i = _levels.indexOf(UserSession.instance.level);
    _cur = i < 0 ? 2 : i;
  }

  @override
  void dispose() {
    SpeechService.instance.stopListening();
    super.dispose();
  }

  _Question get _current {
    final list = _bank[_levels[_cur]]!;
    return list[(_rot[_cur] ?? 0) % list.length];
  }

  String get _phrase => _speakingPhrase[_quizLevel] ?? _speakingPhrase['A2']!;

  /// The level we actually place the learner at.
  ///
  /// The quiz result, nudged down one step when the learner DID attempt the
  /// speaking check and could not read a phrase at their own placed level back
  /// clearly. The screen has always told learners the test "adapted to your
  /// answers across grammar, listening and speaking" — until now the speaking
  /// score was measured, shown, and then thrown away, so a learner who could
  /// not say a word of it was still placed on their written answers alone.
  ///
  /// A skipped check changes nothing, and neither does a check the microphone
  /// heard nothing at all in — silence is a device problem, not a level.
  String get _placedLevel {
    final score = _spokenScore;
    if (score == null || _spokenText.trim().isEmpty || score >= _speakingFloor) return _quizLevel;
    final i = _levels.indexOf(_quizLevel);
    return i > 0 ? _levels[i - 1] : _quizLevel;
  }

  /// Below this, the reading was too far off to support the written placement.
  /// Deliberately generous — the recognizer is on-device, and this must never
  /// punish an accent it simply parsed badly.
  static const int _speakingFloor = 40;

  void _answer(int option) {
    final correct = option == _current.correct;
    _rot[_cur] = (_rot[_cur] ?? 0) + 1;
    if (correct) {
      _cur = min(_cur + 1, _levels.length - 1);
    } else {
      _cur = max(_cur - 1, 0);
    }
    _asked++;
    if (_asked >= _total) {
      setState(() {
        _quizLevel = _levels[_cur];
        _phase = _Phase.speaking; // then a quick speaking check
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _recordSpeaking() async {
    setState(() {
      _spokenText = '';
      _spokenScore = null;
      _spokenDone = false;
    });
    final ok = await SpeechService.instance.startListening(
      onResult: (text, isFinal) {
        if (!mounted) return;
        setState(() => _spokenText = text);
        if (isFinal && !_spokenDone) {
          _spokenDone = true;
          setState(() => _spokenScore = pronunciationScore(_phrase, text));
        }
      },
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speech recognition is not available on this device.')),
      );
    }
  }

  static String _levelName(String l) {
    switch (l) {
      case 'A0':
        return 'Beginner';
      case 'A1':
        return 'Elementary';
      case 'A2':
        return 'Pre-intermediate';
      case 'B1':
        return 'Intermediate';
      case 'B2':
        return 'Upper-intermediate';
      case 'C1':
        return 'Advanced';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    switch (_phase) {
      case _Phase.quiz:
        body = _quiz(context);
        break;
      case _Phase.speaking:
        body = _speaking(context);
        break;
      case _Phase.result:
        body = _result(context);
        break;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Placement test')),
      body: SafeArea(child: body),
    );
  }

  Widget _quiz(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = _current;
    final isListening = q.type == _QType.listening;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_asked + 1) / _total,
              minHeight: 7,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text('Question ${_asked + 1} of $_total', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
        ),
        const Spacer(),
        if (isListening) ...[
          const Text('🎧', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 8),
          Text('Listen and choose what you heard', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => SpeechService.instance.speak(q.prompt),
            icon: const Icon(Icons.volume_up_rounded),
            label: const Text('Play audio'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(q.prompt, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.3)),
          ),
        const SizedBox(height: 28),
        ...List.generate(q.options.length, (i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _answer(i),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(q.options[i], textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                ),
              ),
            )),
        const Spacer(flex: 2),
      ],
    );
  }

  Widget _speaking(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 8),
          const Text('🎙️', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 8),
          const Text('Quick speaking check', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Read this out loud (optional)', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5)),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.light ? Colors.white : const Color(0xFF1E1B26),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Text(_phrase, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.3)),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () => SpeechService.instance.speak(_phrase),
                  icon: const Icon(Icons.volume_up_rounded),
                  label: const Text('Listen'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (_spokenText.isNotEmpty || _spokenScore != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('You said', style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Text(_spokenText.isEmpty ? '…' : '"$_spokenText"', style: const TextStyle(fontSize: 15)),
                  if (_spokenScore != null) ...[
                    const SizedBox(height: 8),
                    Text(_spokenScore! >= 70 ? 'Clear! Nicely done 🌟' : 'Good try — keep practising 👍',
                        style: TextStyle(fontWeight: FontWeight.w700, color: _spokenScore! >= 70 ? AppColors.success : const Color(0xFFF59E0B))),
                  ],
                ],
              ),
            ),
          const Spacer(),
          AnimatedBuilder(
            animation: SpeechService.instance,
            builder: (context, _) {
              final listening = SpeechService.instance.isListening;
              return GestureDetector(
                onTap: listening ? SpeechService.instance.stopListening : _recordSpeaking,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    gradient: AppColors.gradient(listening ? const Color(0xFFEF4444) : AppTheme.seed),
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: (listening ? const Color(0xFFEF4444) : AppTheme.seed).withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 8))],
                  ),
                  child: Icon(listening ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white, size: 34),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: () => setState(() => _phase = _Phase.result),
              child: Text(_spokenScore != null ? 'Continue' : 'Skip'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _result(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(gradient: AppColors.gradient(AppTheme.seed), shape: BoxShape.circle),
            child: Center(child: Text(_placedLevel, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white))),
          ),
          const SizedBox(height: 20),
          Text('Your level: ${_levelName(_placedLevel)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('The test adapted to your answers across grammar, listening and speaking. You can change it anytime in Profile.',
              textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5, height: 1.35)),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: () async {
                await UserSession.instance.setLevel(_placedLevel);
                // Otherwise the result lives only on this device, and the next
                // cloud pull replaces it with the level the test just measured.
                SyncService.push();
                if (context.mounted) Navigator.of(context).pop(_placedLevel);
              },
              child: const Text('Use this level'),
            ),
          ),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Skip')),
        ],
      ),
    );
  }
}
