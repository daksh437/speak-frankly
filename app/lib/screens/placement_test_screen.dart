import 'package:flutter/material.dart';

import '../services/user_session.dart';
import '../theme/app_theme.dart';

/// A quick, self-contained placement test (BRD §6.1). Six graded questions →
/// an estimated CEFR level. Sets the learner's level and pops with it.
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

class _PlacementTestScreenState extends State<PlacementTestScreen> {
  static const _questions = <_Question>[
    _Question('She ___ my sister.', ['is', 'are', 'am'], 0),
    _Question('I have three ___.', ['cat', 'cats', 'cates'], 1),
    _Question('___ you like some water?', ['Do', 'Would', 'Are'], 1),
    _Question('Yesterday we ___ a movie.', ['watch', 'watched', 'watching'], 1),
    _Question('If it rains, I ___ stay home.', ['will', 'would', 'am'], 0),
    _Question('She avoided ___ him.', ['to meet', 'meeting', 'meet'], 1),
  ];

  int _index = 0;
  int _correct = 0;
  bool _done = false;
  String _level = 'A2';

  void _answer(int option) {
    if (option == _questions[_index].correct) _correct++;
    if (_index + 1 >= _questions.length) {
      setState(() {
        _level = _levelFromScore(_correct);
        _done = true;
      });
    } else {
      setState(() => _index++);
    }
  }

  static String _levelFromScore(int c) {
    if (c <= 1) return 'A0';
    if (c == 2) return 'A1';
    if (c == 3) return 'A2';
    if (c <= 5) return 'B1';
    return 'B2';
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
    final q = _questions[_index];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_index + 1) / _questions.length,
              minHeight: 7,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text('Question ${_index + 1} of ${_questions.length}', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
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
          Text('You got $_correct of ${_questions.length} correct.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14)),
          const SizedBox(height: 8),
          Text('The tutor will match this level. You can change it anytime in Profile.',
              textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
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
