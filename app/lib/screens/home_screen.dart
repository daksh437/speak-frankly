import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../services/analytics_service.dart';
import '../services/api_service.dart';
import '../services/gamification_service.dart';
import '../services/notification_service.dart';
import '../services/speech_service.dart';
import '../services/user_session.dart';
import '../services/word_of_day.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/dictionary_sheet.dart';
import 'chat_screen.dart';
import 'picture_match_screen.dart';
import 'stories_list_screen.dart';

/// XP needed to unlock the scenario at [index] (first two are always open).
int _unlockXp(int index) => index < 2 ? 0 : (index - 1) * 60;

void _showLocked(BuildContext context, int needed, int xp) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Locked — earn $needed XP to unlock (you have $xp). Keep practicing! 🔥')),
  );
}

/// Home = the scenario library ("worlds"). Premium card layout with a friendly
/// header and per-scenario accent colors.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Scenario>> _future;
  String _query = '';
  String? _levelFilter; // null = All

  @override
  void initState() {
    super.initState();
    _future = ApiService.instance.fetchScenarios();
    // Ask for notification permission + schedule the daily reminder once the
    // learner is in the app (fire-and-forget).
    NotificationService.instance.requestAndSchedule();
  }

  List<Scenario> _applyFilters(List<Scenario> all) {
    final q = _query.trim().toLowerCase();
    return all.where((s) {
      if (_levelFilter != null && s.level != _levelFilter) return false;
      if (q.isEmpty) return true;
      return s.title.toLowerCase().contains(q) ||
          s.description.toLowerCase().contains(q) ||
          s.theme.toLowerCase().contains(q) ||
          s.keywords.any((k) => k.toLowerCase().contains(q));
    }).toList();
  }

  void _reload() => setState(() => _future = ApiService.instance.fetchScenarios());

  /// Context Generator: ask for any topic, build a scenario, start chatting.
  Future<void> _startCustom() async {
    final controller = TextEditingController();
    final topic = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Talk about anything'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Type any topic and the tutor will start a conversation about it.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'e.g. cricket, my job interview, ordering pizza'),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Start')),
        ],
      ),
    );
    if (topic == null || topic.trim().isEmpty || !mounted) return;

    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    try {
      final scenario = await ApiService.instance.fetchCustomScenario(topic.trim());
      AnalyticsService.log('custom_scenario');
      if (!mounted) return;
      Navigator.pop(context); // close loader
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(scenario: scenario)));
    } catch (_) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not start that topic. Try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<List<Scenario>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _ErrorState(onRetry: _reload, message: loc.couldntReachServer);
            }
            final scenarios = snap.data ?? [];
            if (scenarios.isEmpty) {
              return _ErrorState(onRetry: _reload, message: loc.couldntReachServer);
            }
            return AnimatedBuilder(
              animation: GamificationService.instance,
              builder: (context, _) {
                final xp = GamificationService.instance.xp;
                final levels = (scenarios.map((s) => s.level).toSet().toList()..sort());
                final filtered = _applyFilters(scenarios);
                return CustomScrollView(
                  slivers: [
                    const SliverToBoxAdapter(child: _Header()),
                    const SliverPadding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
                      sliver: SliverToBoxAdapter(child: _WordOfDayCard()),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      sliver: SliverToBoxAdapter(child: _TalkAboutAnythingCard(onTap: _startCustom)),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      sliver: SliverToBoxAdapter(
                        child: _MiniGameCard(
                          emoji: '📖',
                          title: 'Story mode',
                          subtitle: 'Guided role-plays — pick your reply · works offline',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const StoriesListScreen()),
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      sliver: SliverToBoxAdapter(
                        child: _MiniGameCard(
                          emoji: '🖼️',
                          title: loc.pictureMatch,
                          subtitle: loc.pictureMatchSub,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const PictureMatchScreen()),
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      sliver: SliverToBoxAdapter(
                        child: Text(loc.chooseScenario,
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      sliver: SliverToBoxAdapter(
                        child: _ScenarioFilters(
                          levels: levels,
                          selectedLevel: _levelFilter,
                          onQuery: (q) => setState(() => _query = q),
                          onLevel: (l) => setState(() => _levelFilter = l),
                        ),
                      ),
                    ),
                    if (filtered.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                          child: Text('No scenarios match your search.',
                              textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        sliver: SliverList.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 14),
                          itemBuilder: (_, i) {
                            final s = filtered[i];
                            final needed = _unlockXp(scenarios.indexOf(s)); // stable unlock by original order
                            final locked = xp < needed;
                            return _ScenarioCard(
                              scenario: s,
                              locked: locked,
                              requiredXp: needed,
                              onTap: locked
                                  ? () => _showLocked(context, needed, xp)
                                  : () => Navigator.of(context).push(
                                        MaterialPageRoute(builder: (_) => ChatScreen(scenario: s)),
                                      ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  String _greeting(AppLocalizations loc) {
    final h = DateTime.now().hour;
    if (h < 12) return loc.goodMorning;
    if (h < 17) return loc.goodAfternoon;
    return loc.goodEvening;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context)!;
    final session = UserSession.instance;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_greeting(loc)} 👋', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(loc.letsSpeak,
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: scheme.onSurface)),
                  ],
                ),
              ),
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.gradient(AppTheme.seed),
                ),
                child: const Center(child: AppLogo(size: 28)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AnimatedBuilder(
            animation: GamificationService.instance,
            builder: (context, _) {
              final g = GamificationService.instance;
              return Row(
                children: [
                  Expanded(child: _StatChip(icon: Icons.local_fire_department_rounded, label: loc.statStreak, value: '${g.streak}')),
                  const SizedBox(width: 10),
                  Expanded(child: _StatChip(icon: Icons.star_rounded, label: loc.statXp, value: '${g.xp}')),
                  const SizedBox(width: 10),
                  Expanded(child: _StatChip(icon: Icons.bar_chart_rounded, label: loc.statLevel, value: session.level)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatChip({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cardColor = Theme.of(context).brightness == Brightness.light ? Colors.white : const Color(0xFF1E1B26);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
            ],
          ),
        ],
      ),
    );
  }
}

class _TalkAboutAnythingCard extends StatelessWidget {
  final VoidCallback onTap;
  const _TalkAboutAnythingCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: AppColors.gradient(AppTheme.seed),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: AppTheme.seed.withValues(alpha: 0.3), blurRadius: 18, offset: const Offset(0, 8))],
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), shape: BoxShape.circle),
                child: const Center(child: Text('🎙️', style: TextStyle(fontSize: 22))),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(loc.talkAnything, style: const TextStyle(color: Colors.white, fontSize: 16.5, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(loc.talkAnythingSub, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                  ],
                ),
              ),
              const Icon(Icons.auto_awesome_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

/// Word of the Day (daily challenge) — one useful word/phrase each day, with a
/// meaning, example, Listen (TTS), and tap-to-look-up.
class _WordOfDayCard extends StatelessWidget {
  const _WordOfDayCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final w = WordOfDay.today();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('📅', style: TextStyle(fontSize: 15)),
              const SizedBox(width: 6),
              Text('WORD OF THE DAY',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: scheme.onPrimaryContainer.withValues(alpha: 0.7))),
              const Spacer(),
              InkWell(
                onTap: () => SpeechService.instance.speak('${w.word}. ${w.example}'),
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.volume_up_rounded, size: 20, color: scheme.onPrimaryContainer),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => showDictionarySheet(context, w.word),
            child: Text(w.word,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: scheme.onPrimaryContainer)),
          ),
          const SizedBox(height: 2),
          Text(w.meaning, style: TextStyle(fontSize: 13.5, color: scheme.onPrimaryContainer.withValues(alpha: 0.9))),
          const SizedBox(height: 6),
          Text('“${w.example}”',
              style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: scheme.onPrimaryContainer.withValues(alpha: 0.8))),
        ],
      ),
    );
  }
}

/// Search box + level filter chips for the scenario library.
class _ScenarioFilters extends StatelessWidget {
  final List<String> levels;
  final String? selectedLevel;
  final ValueChanged<String> onQuery;
  final ValueChanged<String?> onLevel;
  const _ScenarioFilters({
    required this.levels,
    required this.selectedLevel,
    required this.onQuery,
    required this.onLevel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          onChanged: onQuery,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search scenarios…',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            filled: true,
            fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _chip(context, 'All', selectedLevel == null, () => onLevel(null)),
              for (final l in levels) _chip(context, l, selectedLevel == l, () => onLevel(l)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip(BuildContext context, String label, bool selected, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? scheme.primary : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? scheme.onPrimary : scheme.onSurfaceVariant)),
          ),
        ),
      ),
    );
  }
}

class _MiniGameCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _MiniGameCard({required this.emoji, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Material(
      color: isLight ? Colors.white : const Color(0xFF1E1B26),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(14)),
                child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    Text(subtitle, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScenarioCard extends StatelessWidget {
  final Scenario scenario;
  final VoidCallback onTap;
  final bool locked;
  final int requiredXp;
  const _ScenarioCard({required this.scenario, required this.onTap, this.locked = false, this.requiredXp = 0});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = AppColors.forScenario(scenario.theme);
    final isLight = Theme.of(context).brightness == Brightness.light;
    final cardColor = isLight ? Colors.white : const Color(0xFF1E1B26);

    return Material(
      color: cardColor,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: isLight
                ? [BoxShadow(color: accent.withValues(alpha: 0.10), blurRadius: 18, offset: const Offset(0, 8))]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(child: Text(scenario.emoji, style: const TextStyle(fontSize: 28))),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(scenario.title,
                                style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
                            child: Text(scenario.level,
                                style: TextStyle(fontSize: 11, color: accent, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(locked ? '🔒 Unlock at $requiredXp XP' : scenario.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, height: 1.3)),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(locked ? Icons.lock_rounded : Icons.arrow_forward_rounded, size: 18, color: accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  final String message;
  const _ErrorState({required this.onRetry, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 44, color: Colors.grey),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
