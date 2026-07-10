import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/analytics_service.dart';
import '../services/api_service.dart';
import '../services/gamification_service.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';
import 'chat_screen.dart';
import 'picture_match_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _future = ApiService.instance.fetchScenarios();
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

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<List<Scenario>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _ErrorState(onRetry: _reload, message: "Couldn't reach the server.\nCheck your connection and retry.");
            }
            final scenarios = snap.data ?? [];
            if (scenarios.isEmpty) {
              return _ErrorState(onRetry: _reload, message: 'No scenarios yet.');
            }
            return AnimatedBuilder(
              animation: GamificationService.instance,
              builder: (context, _) {
                final xp = GamificationService.instance.xp;
                return CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _Header(greeting: _greeting)),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      sliver: SliverToBoxAdapter(child: _TalkAboutAnythingCard(onTap: _startCustom)),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      sliver: SliverToBoxAdapter(
                        child: _MiniGameCard(
                          emoji: '🖼️',
                          title: 'Picture match',
                          subtitle: 'Match the scene to the sentence',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const PictureMatchScreen()),
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      sliver: SliverToBoxAdapter(
                        child: Text('Choose a scenario',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: SliverList.separated(
                        itemCount: scenarios.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 14),
                        itemBuilder: (_, i) {
                          final needed = _unlockXp(i);
                          final locked = xp < needed;
                          return _ScenarioCard(
                            scenario: scenarios[i],
                            locked: locked,
                            requiredXp: needed,
                            onTap: locked
                                ? () => _showLocked(context, needed, xp)
                                : () => Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => ChatScreen(scenario: scenarios[i])),
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
  final String greeting;
  const _Header({required this.greeting});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                    Text('$greeting 👋', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text("Let's speak English",
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
                child: const Center(child: Text('🗣️', style: TextStyle(fontSize: 22))),
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
                  Expanded(child: _StatChip(icon: Icons.local_fire_department_rounded, label: 'Streak', value: '${g.streak}')),
                  const SizedBox(width: 10),
                  Expanded(child: _StatChip(icon: Icons.star_rounded, label: 'XP', value: '${g.xp}')),
                  const SizedBox(width: 10),
                  Expanded(child: _StatChip(icon: Icons.bar_chart_rounded, label: 'Level', value: session.level)),
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
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Talk about anything', style: TextStyle(color: Colors.white, fontSize: 16.5, fontWeight: FontWeight.w800)),
                    SizedBox(height: 2),
                    Text('Type any topic — the tutor starts a chat', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
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
