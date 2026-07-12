import 'package:flutter/material.dart';

import '../services/story_data.dart';
import '../theme/app_theme.dart';
import 'story_screen.dart';

/// Story mode (BRD §4.1) — a list of scripted branching role-plays. Each one is
/// a guided, offline conversation where the learner picks replies and the story
/// branches. Great for beginners and low-connectivity use.
class StoriesListScreen extends StatelessWidget {
  const StoriesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stories = allStories();
    return Scaffold(
      appBar: AppBar(title: const Text('Story mode')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text('Guided role-plays. Pick your reply and see where the story goes — works offline.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5, height: 1.35)),
            const SizedBox(height: 14),
            for (final s in stories)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Material(
                  color: Theme.of(context).brightness == Brightness.light ? Colors.white : const Color(0xFF23202B),
                  borderRadius: BorderRadius.circular(18),
                  elevation: Theme.of(context).brightness == Brightness.light ? 1 : 0,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StoryScreen(story: s))),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              gradient: AppColors.gradient(AppTheme.seed),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Center(child: Text(s.emoji, style: const TextStyle(fontSize: 26))),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(child: Text(s.title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700))),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
                                      child: Text(s.level, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(s.description, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, height: 1.3)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
