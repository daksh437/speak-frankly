import 'dart:math';

import 'package:flutter/material.dart';

import '../services/user_session.dart';
import '../theme/app_theme.dart';

/// An ADAPTIVE placement test (BRD §6.1). Questions are graded by CEFR level and
/// the test starts at the learner's current level, then moves up on a correct
/// answer and down on a wrong one — so the difficulty follows the learner instead
/// of showing the same fixed questions to everyone. After a few questions it
/// settles on an estimated level, sets it, and pops with it.
class PlacementTestScreen extends StatefulWidget {
  const PlacementTestScreen({super.key});
  @override
  State<PlacementTestScreen> createState() => _PlacementTestScreenState();
}

class _Question {
  final String prompt;
  final List<String> options;
  final int correct;
  const _Question(this.prompt, this.options, this.correct);
}

const _levels = ['A0', 'A1', 'A2', 'B1', 'B2', 'C1'];

/// Graded question bank — a few items per CEFR level, easiest → hardest.
const Map<String, List<_Question>> _bank = {
  'A0': [
    _Question('I ___ happy.', ['am', 'is', 'are'], 0),
    _Question('This ___ a cat.', ['is', 'are', 'am'], 0),
    _Question('___ name is Sam.', ['My', 'I', 'Me'], 0),
  ],
  'A1': [
    _Question('She ___ tea every morning.', ['drink', 'drinks', 'drinking'], 1),
    _Question('They ___ my friends.', ['is', 'are', 'am'], 1),
    _Question('He ___ got a car.', ['have', 'has', 'having'], 1),
  ],
  'A2': [
    _Question('Yesterday we ___ a film.', ['watch', 'watched', 'watching'], 1),
    _Question('I have three ___.', ['cat', 'cats', 'cates'], 1),
    _Question('___ you like some water?', ['Do', 'Would', 'Are'], 1),
  ],
  'B1': [
    _Question('If it rains, I ___ stay home.', ['will', 'would', 'am'], 0),
    _Question('She has ___ here for five years.', ['live', 'lived', 'living'], 1),
    _Question("I'm interested ___ music.", ['in', 'on', 'at'], 0),
  ],
  'B2': [
    _Question('She avoided ___ him.', ['to meet', 'meeting', 'meet'], 1),
    _Question('By 2030, I ___ here for a decade.', ['will have worked', 'will work', 'work'], 0),
    _Question('He spoke as if he ___ everything.', ['knew', 'knows', 'know'], 0),
  ],
  'C1': [
    _Question('___ harder, he would have passed.', ['Had he studied', 'If he studies', 'He studied'], 0),
    _Question('The plan was met with ___ skepticism.', ['considerable', 'consider', 'considerably'], 0),
    _Question('Not only ___ late, but he also forgot the file.', ['was he', 'he was', 'he is'], 0),
  ],
};

class _PlacementTestScreenState extends State<PlacementTestScreen> {
  static const _total = 6; // questions asked before settling on a level

  late int _cur; // index into _levels — the current difficulty
  final Map<int, int> _rot = {}; // rotating question index per level (avoids repeats)
  int _asked = 0;
  bool _done = false;
  String _level = 'A2';

  @override
  void initState() {
    super.initState();
    // Start at the learner's current level so the test adapts to them.
    final i = _levels.indexOf(UserSession.instance.level);
    _cur = i < 0 ? 2 : i; // default A2
  }

  _Question get _current {
    final list = _bank[_levels[_cur]]!;
    return list[(_rot[_cur] ?? 0) % list.length];
  }

  void _answer(int option) {
    final correct = option == _current.correct;
    _rot[_cur] = (_rot[_cur] ?? 0) + 1;
    // Adapt: harder on a correct answer, easier on a wrong one.
    if (correct) {
      _cur = min(_cur + 1, _levels.length - 1);
    } else {
      _cur = max(_cur - 1, 0);
    }
    _asked++;
    if (_asked >= _total) {
      setState(() {
        _level = _levels[_cur];
        _done = true;
      });
    } else {
      setState(() {});
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
    return Scaffold(
      appBar: AppBar(title: const Text('Placement test')),
      body: SafeArea(child: _done ? _result(context) : _quiz(context)),
    );
  }

  Widget _quiz(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = _current;
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
                  child: Text(q.options[i], style: const TextStyle(fontSize: 16)),
                ),
              ),
            )),
        const Spacer(flex: 2),
      ],
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
            child: Center(child: Text(_level, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white))),
          ),
          const SizedBox(height: 20),
          Text('Your level: ${_levelName(_level)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('The test adapted to your answers. The tutor will match this level — you can change it anytime in Profile.',
              textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5, height: 1.35)),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: () async {
                await UserSession.instance.setLevel(_level);
                if (context.mounted) Navigator.of(context).pop(_level);
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
