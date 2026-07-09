import 'package:flutter/material.dart';

import '../services/user_session.dart';
import 'main_shell.dart';

/// A friendly, step-by-step onboarding (BRD §6.1 / §7): one decision per screen,
/// big tap targets, minimal text, a welcome hero, and a progress bar.
/// Flow: Welcome → Language → Goal → Level → Start.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _page = PageController();
  int _index = 0;

  String? _lang;
  String? _goal;
  String _level = 'A2';

  static const _languages = [
    ('🇮🇳', 'Hindi'),
    ('🇪🇸', 'Spanish'),
    ('🇸🇦', 'Arabic'),
    ('🇧🇷', 'Portuguese'),
    ('🇫🇷', 'French'),
    ('🌐', 'Other'),
  ];
  static const _goals = [
    ('💼', 'Job / Interview', 'Job / Interview'),
    ('✈️', 'Travel', 'Travel'),
    ('🎓', 'Study abroad', 'Study abroad'),
    ('💬', 'Just talking', 'Just talking'),
  ];
  static const _levels = [
    ('🌱', 'Beginner', 'I am just starting', 'A0'),
    ('🌿', 'Some words', 'I know a few words & phrases', 'A2'),
    ('🌳', 'Conversational', 'I can already hold a chat', 'B1'),
  ];

  bool get _canContinue {
    switch (_index) {
      case 1:
        return _lang != null;
      case 2:
        return _goal != null;
      case 3:
        return _level.isNotEmpty;
      default:
        return true;
    }
  }

  void _next() {
    if (_index >= 3) {
      _finish();
      return;
    }
    _page.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  void _back() {
    if (_index == 0) return;
    _page.previousPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  Future<void> _finish() async {
    await UserSession.instance.completeOnboarding(
      nativeLanguage: _lang!,
      goal: _goal!,
      level: _level,
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainShell()),
    );
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scheme.primaryContainer.withValues(alpha: 0.45),
              scheme.surface,
              scheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top bar: back + progress (hidden on the welcome page).
              AnimatedOpacity(
                opacity: _index == 0 ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _index == 0 ? null : _back,
                        icon: const Icon(Icons.arrow_back),
                      ),
                      Expanded(child: _ProgressBar(step: _index, total: 3)),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _page,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _index = i),
                  children: [
                    _WelcomePage(onStart: _next),
                    _ChoicePage(
                      title: 'What language do you speak?',
                      subtitle: "We'll translate and explain in your language.",
                      children: [
                        for (final l in _languages)
                          _OptionCard(
                            emoji: l.$1,
                            label: l.$2,
                            selected: _lang == l.$2,
                            onTap: () => setState(() => _lang = l.$2),
                          ),
                      ],
                    ),
                    _ChoicePage(
                      title: 'Why do you want English?',
                      subtitle: "We'll pick scenarios that fit your goal.",
                      children: [
                        for (final g in _goals)
                          _OptionCard(
                            emoji: g.$1,
                            label: g.$2,
                            selected: _goal == g.$3,
                            onTap: () => setState(() => _goal = g.$3),
                          ),
                      ],
                    ),
                    _ChoicePage(
                      title: "What's your level?",
                      subtitle: "No test needed — just pick what feels right.",
                      children: [
                        for (final lv in _levels)
                          _OptionCard(
                            emoji: lv.$1,
                            label: lv.$2,
                            sublabel: lv.$3,
                            selected: _level == lv.$4,
                            onTap: () => setState(() => _level = lv.$4),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // Bottom action (hidden on welcome page, which has its own button).
              if (_index != 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      onPressed: _canContinue ? _next : null,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(
                        _index == 3 ? 'Start learning  🎉' : 'Continue',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final int step; // 1..3 (0 = welcome)
  final int total;
  const _ProgressBar({required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (int i = 1; i <= total; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: 6,
              decoration: BoxDecoration(
                color: i <= step ? scheme.primary : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          if (i < total) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _WelcomePage extends StatelessWidget {
  final VoidCallback onStart;
  const _WelcomePage({required this.onStart});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
      child: Column(
        children: [
          const Spacer(flex: 2),
          // Hero badge
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary, scheme.tertiary],
              ),
              boxShadow: [
                BoxShadow(color: scheme.primary.withValues(alpha: 0.35), blurRadius: 30, offset: const Offset(0, 12)),
              ],
            ),
            child: const Center(child: Text('🗣️', style: TextStyle(fontSize: 62))),
          ),
          const SizedBox(height: 32),
          Text(
            'Speak Frankly',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(
            'Learn English by talking —\nno fear, just real conversation.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: const [
              _Pill('🎭 Real-life scenarios'),
              _Pill('👆 Tap any word'),
              _Pill('💬 Gentle corrections'),
            ],
          ),
          const Spacer(flex: 3),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              onPressed: onStart,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Get started', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 8),
          Text('Takes 30 seconds', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  const _Pill(this.text);
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
    );
  }
}

class _ChoicePage extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;
  const _ChoicePage({required this.title, required this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14)),
        const SizedBox(height: 22),
        ...children,
      ],
    );
  }
}

class _OptionCard extends StatelessWidget {
  final String emoji;
  final String label;
  final String? sublabel;
  final bool selected;
  final VoidCallback onTap;
  const _OptionCard({
    required this.emoji,
    required this.label,
    this.sublabel,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? scheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
                          )),
                      if (sublabel != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(sublabel!,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: selected ? scheme.onPrimaryContainer.withValues(alpha: 0.8) : scheme.onSurfaceVariant,
                              )),
                        ),
                    ],
                  ),
                ),
                AnimatedScale(
                  scale: selected ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.check_circle, color: scheme.primary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
