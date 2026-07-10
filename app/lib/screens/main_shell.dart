import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'home_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          HomeScreen(),
          SpeakScreen(),
          VocabScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.chat_bubble_outline_rounded), selectedIcon: const Icon(Icons.chat_bubble_rounded), label: l.navPractice),
          NavigationDestination(icon: const Icon(Icons.mic_none_rounded), selectedIcon: const Icon(Icons.mic_rounded), label: l.navSpeak),
          NavigationDestination(icon: const Icon(Icons.bookmark_border_rounded), selectedIcon: const Icon(Icons.bookmark_rounded), label: l.navWords),
          NavigationDestination(icon: const Icon(Icons.person_outline_rounded), selectedIcon: const Icon(Icons.person_rounded), label: l.navProfile),
        ],
      ),
    );
  }
}
