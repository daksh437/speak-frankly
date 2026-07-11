import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../l10n/app_localizations.dart';
import '../services/achievements.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/gamification_service.dart';
import '../services/user_session.dart';
import '../services/vocabulary_service.dart';
import '../theme/app_theme.dart';
import 'premium_screen.dart';
import 'placement_test_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<Map<String, dynamic>>? _access;

  @override
  void initState() {
    super.initState();
    _access = ApiService.instance.fetchAccess();
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: UserSession.instance.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Enter your name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (name != null) {
      await UserSession.instance.setDisplayName(name);
      if (mounted) setState(() {});
    }
  }

  Future<void> _takePlacement() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlacementTestScreen()));
    if (mounted) setState(() {});
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('Your progress is saved to your Google account.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (confirm == true) await AuthService.signOut();
    // AuthGate reacts to sign-out and shows the login screen.
  }

  Future<void> _changeLevel() async {
    const levels = {'A0': 'Beginner', 'A2': 'Some words', 'B1': 'Conversational', 'B2': 'Advanced'};
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(8), child: Text('Choose your level', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            for (final e in levels.entries)
              ListTile(
                title: Text('${e.key} — ${e.value}'),
                trailing: UserSession.instance.level == e.key ? Icon(Icons.check_rounded, color: AppTheme.seed) : null,
                onTap: () => Navigator.pop(ctx, e.key),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) {
      await UserSession.instance.setLevel(picked);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(loc.navProfile)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          _ProfileHeader(onEditName: _editName),
          const SizedBox(height: 18),
          AnimatedBuilder(
            animation: Listenable.merge([GamificationService.instance, VocabularyService.instance]),
            builder: (context, _) {
              final g = GamificationService.instance;
              return Row(
                children: [
                  _StatCard(emoji: '🔥', value: '${g.streak}', label: g.streak == 1 ? 'day streak' : 'day streak', color: const Color(0xFFFF7A5A)),
                  const SizedBox(width: 12),
                  _StatCard(emoji: '⭐', value: '${g.xp}', label: 'XP earned', color: const Color(0xFFF59E0B)),
                  const SizedBox(width: 12),
                  _StatCard(emoji: '📚', value: '${VocabularyService.instance.count}', label: 'words saved', color: const Color(0xFF00C2A8)),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          const _FluencyMap(),
          const SizedBox(height: 18),
          const _Badges(),
          const SizedBox(height: 18),
          _PlanCard(access: _access),
          const SizedBox(height: 18),
          _SectionCard(
            title: loc.yourLearning,
            children: [
              _InfoRow(icon: Icons.translate_rounded, label: loc.nativeLanguage, value: UserSession.instance.nativeLanguage.isEmpty ? '—' : UserSession.instance.nativeLanguage),
              _InfoRow(icon: Icons.flag_rounded, label: loc.goalLabel, value: UserSession.instance.goal.isEmpty ? '—' : UserSession.instance.goal),
              _InfoRow(icon: Icons.bar_chart_rounded, label: loc.levelLabel, value: UserSession.instance.level, onTap: _changeLevel, trailingArrow: true),
            ],
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: loc.settings,
            children: [
              _InfoRow(icon: Icons.person_outline_rounded, label: loc.nameLabel, value: UserSession.instance.displayName, onTap: _editName, trailingArrow: true),
              _InfoRow(icon: Icons.quiz_outlined, label: loc.testMyLevel, value: '', onTap: _takePlacement, trailingArrow: true),
              if (FirebaseAuth.instance.currentUser?.email != null)
                _InfoRow(icon: Icons.account_circle_outlined, label: 'Account', value: FirebaseAuth.instance.currentUser!.email!),
              _InfoRow(icon: Icons.privacy_tip_outlined, label: 'Privacy Policy', value: '', onTap: () => _open(AppConfig.privacyUrl), trailingArrow: true),
              _InfoRow(icon: Icons.description_outlined, label: 'Terms of Service', value: '', onTap: () => _open(AppConfig.termsUrl), trailingArrow: true),
              _InfoRow(icon: Icons.info_outline_rounded, label: loc.aboutLabel, value: 'Speak Frankly', onTap: () => _showAbout(context)),
              _InfoRow(icon: Icons.logout_rounded, label: 'Sign out', value: '', onTap: _signOut),
            ],
          ),
          const SizedBox(height: 24),
          Center(child: Text('Speak Frankly · v1.0', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12))),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Speak Frankly',
      applicationVersion: '1.0',
      applicationLegalese: 'Learn English by talking — no fear, just conversation.',
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final VoidCallback onEditName;
  const _ProfileHeader({required this.onEditName});

  @override
  Widget build(BuildContext context) {
    final session = UserSession.instance;
    final initial = session.displayName.isNotEmpty ? session.displayName[0].toUpperCase() : '🗣️';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.gradient(AppTheme.seed),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: AppTheme.seed.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), shape: BoxShape.circle),
            child: Center(child: Text(initial, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white))),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.displayName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 2),
                Text('Level ${session.level}${session.goal.isNotEmpty ? ' · ${session.goal}' : ''}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          IconButton(onPressed: onEditName, icon: const Icon(Icons.edit_rounded, color: Colors.white)),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  final Color color;
  const _StatCard({required this.emoji, required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: isLight ? Colors.white : const Color(0xFF1E1B26),
          borderRadius: BorderRadius.circular(16),
          boxShadow: isLight ? [BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 5))] : null,
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final Future<Map<String, dynamic>>? access;
  const _PlanCard({required this.access});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<Map<String, dynamic>>(
      future: access,
      builder: (context, snap) {
        final d = snap.data ?? {};
        final isPremium = (d['planType'] ?? 'free').toString() == 'premium';
        String title;
        String subtitle;
        if (isPremium) {
          title = 'Premium 💜';
          subtitle = 'Unlimited conversations. Thank you!';
        } else {
          final used = (d['dailyUsed'] ?? 0) as num;
          final limit = (d['dailyLimit'] ?? 25) as num;
          final left = (limit - used).clamp(0, limit).toInt();
          title = 'Free plan';
          subtitle = snap.hasData ? '$left of ${limit.toInt()} left today — tap to go Premium' : 'Tap to unlock unlimited practice';
        }
        final card = Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Icon(isPremium ? Icons.workspace_premium_rounded : Icons.workspace_premium_outlined, color: scheme.onPrimaryContainer),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: scheme.onPrimaryContainer.withValues(alpha: 0.85), fontSize: 12.5)),
                  ],
                ),
              ),
              if (!isPremium) Icon(Icons.chevron_right_rounded, color: scheme.onPrimaryContainer),
            ],
          ),
        );
        if (isPremium) return card;
        return InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PremiumScreen())),
          borderRadius: BorderRadius.circular(18),
          child: card,
        );
      },
    );
  }
}

/// Fluency map — skill progress bars from real (local) stats (BRD §8).
class _FluencyMap extends StatelessWidget {
  const _FluencyMap();

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return AnimatedBuilder(
      animation: Listenable.merge([GamificationService.instance, VocabularyService.instance]),
      builder: (context, _) {
        final loc = AppLocalizations.of(context)!;
        final g = GamificationService.instance;
        final skills = <(String, String, int, int, Color)>[
          (loc.skillConversations, '💬', g.scenariosCompleted, 20, const Color(0xFF4C9AFF)),
          (loc.skillSpeaking, '🎤', g.speakingReps, 30, const Color(0xFFFF7A5A)),
          (loc.skillVocabulary, '📚', VocabularyService.instance.count, 30, const Color(0xFF00C2A8)),
          (loc.skillConsistency, '🔥', g.streak, 30, const Color(0xFFF59E0B)),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(loc.fluencyMap, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isLight ? Colors.white : const Color(0xFF1E1B26),
                borderRadius: BorderRadius.circular(18),
                boxShadow: isLight ? [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 5))] : null,
              ),
              child: Column(
                children: [
                  for (int i = 0; i < skills.length; i++) ...[
                    if (i > 0) const SizedBox(height: 14),
                    _SkillBar(label: skills[i].$1, emoji: skills[i].$2, value: skills[i].$3, cap: skills[i].$4, color: skills[i].$5),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SkillBar extends StatelessWidget {
  final String label;
  final String emoji;
  final int value;
  final int cap;
  final Color color;
  const _SkillBar({required this.label, required this.emoji, required this.value, required this.cap, required this.color});

  @override
  Widget build(BuildContext context) {
    final progress = (value / cap).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('$value', style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Milestone badges — earned ones are colored, locked ones greyed (BRD §8).
class _Badges extends StatelessWidget {
  const _Badges();

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return AnimatedBuilder(
      animation: Listenable.merge([GamificationService.instance, VocabularyService.instance]),
      builder: (context, _) {
        final items = computeAchievements();
        final earned = items.where((a) => a.earned).length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Row(
                children: [
                  Text(AppLocalizations.of(context)!.badges, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('$earned/${items.length} earned',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              decoration: BoxDecoration(
                color: isLight ? Colors.white : const Color(0xFF1E1B26),
                borderRadius: BorderRadius.circular(18),
                boxShadow: isLight ? [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 5))] : null,
              ),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 16,
                children: [for (final a in items) _BadgeTile(a)],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BadgeTile extends StatelessWidget {
  final Achievement a;
  const _BadgeTile(this.a);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: '${a.title} — ${a.description}',
      child: SizedBox(
        width: 74,
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                gradient: a.earned ? AppColors.gradient(AppTheme.seed) : null,
                color: a.earned ? null : scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: a.earned
                    ? Text(a.emoji, style: const TextStyle(fontSize: 24))
                    : Icon(Icons.lock_rounded, color: scheme.onSurfaceVariant, size: 20),
              ),
            ),
            const SizedBox(height: 6),
            Text(a.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: a.earned ? scheme.onSurface : scheme.onSurfaceVariant,
                )),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
        Container(
          decoration: BoxDecoration(
            color: isLight ? Colors.white : const Color(0xFF1E1B26),
            borderRadius: BorderRadius.circular(18),
            boxShadow: isLight ? [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 5))] : null,
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool trailingArrow;
  const _InfoRow({required this.icon, required this.label, required this.value, this.onTap, this.trailingArrow = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: scheme.primary),
            const SizedBox(width: 14),
            Text(label, style: const TextStyle(fontSize: 14.5)),
            const Spacer(),
            Flexible(
              child: Text(value,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14)),
            ),
            if (trailingArrow) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ],
        ),
      ),
    );
  }
}
