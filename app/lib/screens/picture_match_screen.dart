import 'package:flutter/material.dart';

import '../services/analytics_service.dart';
import '../services/gamification_service.dart';
import '../theme/app_theme.dart';

/// Visual-first learning (BRD §4.3): see a scene, pick the sentence that
/// matches it. Uses emoji scenes so it works offline with no image assets.
class PictureMatchScreen extends StatefulWidget {
  const PictureMatchScreen({super.key});
  @override
  State<PictureMatchScreen> createState() => _PictureMatchScreenState();
}

class _PictureMatchScreenState extends State<PictureMatchScreen> {
  static const _items = <(String, String, List<String>)>[
    ('🍕', 'They are eating pizza.', ['She is reading a book.', 'He is driving a car.']),
    ('🏖️', 'They are relaxing at the beach.', ['He is cooking dinner.', 'She is studying at night.']),
    ('🐶', 'The dog is running in the park.', ['The cat is sleeping.', 'The bird is singing.']),
    ('☔', 'It is raining outside.', ['The sun is shining.', 'It is snowing.']),
    ('🚌', 'She is waiting for the bus.', ['He is riding a bicycle.', 'They are taking a taxi.']),
    ('☕', 'He is drinking a cup of coffee.', ['She is eating an apple.', 'They are playing football.']),
    ('📚', 'The student is reading a book.', ['The chef is cooking.', 'The doctor is working.']),
    ('🎂', 'They are celebrating a birthday.', ['He is cleaning the house.', 'She is buying clothes.']),
    ('✈️', 'The plane is taking off.', ['The train is arriving.', 'The car is parking.']),
    ('🏥', 'She is visiting the doctor.', ['He is going to school.', 'They are at the market.']),
  ];

  int _index = 0;
  int _correctCount = 0;
  int? _selected;
  bool _done = false;
  late List<String> _options;
  late int _correctIndex;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  void _prepare() {
    final item = _items[_index];
    final opts = [item.$2, ...item.$3]..shuffle();
    _options = opts;
    _correctIndex = opts.indexOf(item.$2);
    _selected = null;
  }

  void _select(int i) {
    if (_selected != null) return;
    setState(() {
      _selected = i;
      if (i == _correctIndex) {
        _correctCount++;
        GamificationService.instance.recordActivity(xpGain: 3);
      }
    });
  }

  void _next() {
    if (_index + 1 >= _items.length) {
      AnalyticsService.log('picture_match_done', {'score': _correctCount});
      setState(() => _done = true);
    } else {
      setState(() {
        _index++;
        _prepare();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Picture match')),
      body: SafeArea(child: _done ? _summary(context) : _quiz(context)),
    );
  }

  Widget _quiz(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final item = _items[_index];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_index + 1) / _items.length,
              minHeight: 7,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('Which sentence matches?', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5)),
        const SizedBox(height: 12),
        Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Center(child: Text(item.$1, style: const TextStyle(fontSize: 90))),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              for (int i = 0; i < _options.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: _OptionButton(
                    text: _options[i],
                    state: _selected == null
                        ? _OptState.idle
                        : (i == _correctIndex
                            ? _OptState.correct
                            : (i == _selected ? _OptState.wrong : _OptState.idle)),
                    onTap: () => _select(i),
                  ),
                ),
            ],
          ),
        ),
        if (_selected != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(onPressed: _next, child: Text(_index + 1 >= _items.length ? 'Finish' : 'Next')),
            ),
          ),
      ],
    );
  }

  Widget _summary(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🖼️', style: TextStyle(fontSize: 60)),
          const SizedBox(height: 16),
          const Text('Nice work!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('You matched $_correctCount of ${_items.length}.', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
            child: Text('+${_correctCount * 3} XP  ⭐', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFB45309))),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
          ),
        ],
      ),
    );
  }
}

enum _OptState { idle, correct, wrong }

class _OptionButton extends StatelessWidget {
  final String text;
  final _OptState state;
  final VoidCallback onTap;
  const _OptionButton({required this.text, required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    Color bg;
    Color border;
    switch (state) {
      case _OptState.correct:
        bg = AppColors.success.withValues(alpha: 0.15);
        border = AppColors.success;
        break;
      case _OptState.wrong:
        bg = const Color(0xFFEF4444).withValues(alpha: 0.15);
        border = const Color(0xFFEF4444);
        break;
      case _OptState.idle:
        bg = isLight ? Colors.white : const Color(0xFF1E1B26);
        border = Colors.transparent;
        break;
    }
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: border, width: 2)),
          child: Row(
            children: [
              Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
              if (state == _OptState.correct) Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
              if (state == _OptState.wrong) const Icon(Icons.cancel_rounded, color: Color(0xFFEF4444), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
