import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/plan_status.dart';
import '../widgets/ad_banner.dart';
import 'home_screen.dart';
import 'premium_screen.dart';
import 'profile_screen.dart';
import 'speak_screen.dart';
import 'vocab_screen.dart';

/// Root shell with bottom navigation: Practice (scenarios), Words (saved vocab),
/// and Profile. Screens are kept alive via IndexedStack.
class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  /// Tabs the learner has actually opened.
  ///
  /// IndexedStack builds every child, visible or not, so all five screens used
  /// to run their initState on app launch - including Speak, which fetches the
  /// day's phrases from the AI. That spent a Gemini call and one of the
  /// learner's daily aux allowance on every single launch, for a tab most of
  /// them never opened. An unbuilt tab is a cheap placeholder; once opened it
  /// is built and, as before, kept alive for the rest of the session.
  final Set<int> _visited = {0};

  static const List<Widget> _tabs = [
    HomeScreen(),
    SpeakScreen(),
    VocabScreen(),
    PremiumScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                for (int i = 0; i < _tabs.length; i++)
                  _visited.contains(i) ? _tabs[i] : const SizedBox.shrink(),
              ],
            ),
          ),
          // Banner ad for FREE users only, and only on the calm tabs (Home/Words)
          // — never on Speak (mic), Premium (paywall) or Profile.
          AnimatedBuilder(
            animation: PlanStatus.instance,
            builder: (context, _) {
              final showBanner = PlanStatus.instance.planType == 'free' && (_index == 0 || _index == 2);
              return showBanner ? const AdBannerWidget() : const SizedBox.shrink();
            },
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() {
          _index = i;
          _visited.add(i);
        }),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.chat_bubble_outline_rounded), selectedIcon: const Icon(Icons.chat_bubble_rounded), label: l.navPractice),
          NavigationDestination(icon: const Icon(Icons.mic_none_rounded), selectedIcon: const Icon(Icons.mic_rounded), label: l.navSpeak),
          NavigationDestination(icon: const Icon(Icons.bookmark_border_rounded), selectedIcon: const Icon(Icons.bookmark_rounded), label: l.navWords),
          const NavigationDestination(icon: Icon(Icons.workspace_premium_outlined), selectedIcon: Icon(Icons.workspace_premium_rounded), label: 'Premium'),
          NavigationDestination(icon: const Icon(Icons.person_outline_rounded), selectedIcon: const Icon(Icons.person_rounded), label: l.navProfile),
        ],
      ),
    );
  }
}
