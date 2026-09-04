import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../l10n/app_localizations.dart';
import '../services/achievements.dart';
import '../services/account_service.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/gamification_service.dart';
import '../services/user_session.dart';
import '../services/vocabulary_service.dart';
import '../theme/app_theme.dart';
import '../services/notification_service.dart';
import '../services/plan_status.dart';
import '../services/progress_history.dart';
import '../services/sync_service.dart';
import 'offline_downloads_screen.dart';
import 'premium_screen.dart';
import 'placement_test_screen.dart';
import 'progress_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<Map<String, dynamic>>? _access;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _access = ApiService.instance.fetchAccess();
    // This screen is kept alive in the app's tab stack, so the plan it fetched
    // on first open was the plan it showed for the rest of the session - a
    // learner who bought Premium in the next tab came back to "Free plan".
    PlanStatus.instance.addListener(_refreshAccess);
    _loadVersion();
  }

  @override
  void dispose() {
    PlanStatus.instance.removeListener(_refreshAccess);
    super.dispose();
  }

  void _refreshAccess() {
    if (!mounted) return;
    setState(() => _access = ApiService.instance.fetchAccess());
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = '${info.version} (${info.buildNumber})');
    } catch (_) {/* leave blank */}
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
    controller.dispose();
    if (name != null) {
      await UserSession.instance.setDisplayName(name);
      // Without this the new name never leaves the device, and the next cloud
      // pull overwrites it with the stale one this account last synced.
      SyncService.push();
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

  /// Delete this account and all its data, from inside the app.
  ///
  /// Play requires an in-app deletion path for any app that lets people create
  /// an account — an email address on a web page is not enough. This is that
  /// path: the server erases the data, then we wipe the device and sign out.
  ///
  /// Irreversible, so it asks twice: once with the full list of what goes, and
  /// again for the actual "yes, delete it".
  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This permanently deletes:'),
            SizedBox(height: 8),
            Text('•  Your account and email\n'
                '•  Your streak, XP and completed scenarios\n'
                '•  Your saved words and level'),
            SizedBox(height: 12),
            Text('This cannot be undone.', style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(height: 12),
            Text(
              'If you pay for Premium, cancel it separately in Play Store → Subscriptions — '
              'Google bills that, not us.',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep my account')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    // Block the UI while the server works — tapping twice must not fire two
    // deletes, and a silent 30s wait would look like nothing happened.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 20),
          Expanded(child: Text('Deleting your account…')),
        ]),
      ),
    );

    final ok = await ApiService.instance.deleteAccount();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // close the progress dialog

    if (!ok) {
      // Say nothing was deleted, because nothing was. Offering the email path
      // beats a bare "try again" when the server is the thing that's broken.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Couldn't delete your account. Nothing was removed — "
            'please try again, or email instaflow38@gmail.com.'),
        duration: Duration(seconds: 6),
      ));
      return;
    }

    // Server side is gone; clear the device and sign out. AuthGate then routes
    // to the login screen on its own.
    await AccountService.wipeAfterDeletion();
    await FirebaseAuth.instance.signOut();
  }

  /// "8 PM" for 20. The daily call is scheduled on the hour, because a learner
  /// choosing a time does not care about the minutes and a picker that offers
  /// them just makes the decision slower.
  static String _hourLabel(int hour) {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    return '$h ${hour < 12 ? 'AM' : 'PM'}';
  }

  /// Pick when the call goes out. The only time that works is the one they
  /// chose themselves, so this is a real setting rather than a fixed 7 PM.
  Future<void> _pickCallTime() async {
    final current = NotificationService.instance.hour;
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('When should your tutor call?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            for (final h in const [7, 8, 9, 12, 17, 18, 19, 20, 21, 22])
              ListTile(
                title: Text(_hourLabel(h)),
                trailing: h == current ? Icon(Icons.check_rounded, color: AppTheme.seed) : null,
                onTap: () => Navigator.pop(ctx, h),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) await NotificationService.instance.setHour(picked);
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
      SyncService.push(); // the level follows the account, not the device
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
          const _ProgressEntry(),
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
              _InfoRow(
                icon: Icons.download_for_offline_outlined,
                label: 'Offline downloads',
                value: '',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OfflineDownloadsScreen())),
                trailingArrow: true,
              ),
              AnimatedBuilder(
                animation: NotificationService.instance,
                builder: (context, _) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.notifications_active_outlined),
                  title: const Text('Daily call'),
                  subtitle: Text('Three minutes of speaking at '
                      '${_hourLabel(NotificationService.instance.hour)}'),
                  value: NotificationService.instance.enabled,
                  onChanged: (v) async {
                    if (v) {
                      await NotificationService.instance.requestAndSchedule();
                    } else {
                      await NotificationService.instance.setEnabled(false);
                    }
                  },
                ),
              ),
              AnimatedBuilder(
                animation: NotificationService.instance,
                builder: (context, _) => NotificationService.instance.enabled
                    ? _InfoRow(
                        icon: Icons.schedule_rounded,
                        label: 'Call time',
                        value: _hourLabel(NotificationService.instance.hour),
                        onTap: _pickCallTime,
                        trailingArrow: true,
                      )
                    : const SizedBox.shrink(),
              ),
              if (FirebaseAuth.instance.currentUser?.email != null)
                _InfoRow(icon: Icons.account_circle_outlined, label: 'Account', value: FirebaseAuth.instance.currentUser!.email!),
              _InfoRow(icon: Icons.privacy_tip_outlined, label: 'Privacy Policy', value: '', onTap: () => _open(AppConfig.privacyUrl), trailingArrow: true),
              _InfoRow(icon: Icons.description_outlined, label: 'Terms of Service', value: '', onTap: () => _open(AppConfig.termsUrl), trailingArrow: true),
              _InfoRow(icon: Icons.info_outline_rounded, label: loc.aboutLabel, value: 'Speak Frankly', onTap: () => _showAbout(context)),
              _InfoRow(icon: Icons.logout_rounded, label: 'Sign out', value: '', onTap: _signOut),
              // Play requires an in-app account-deletion path, not just the
              // web page at AppConfig.deleteAccountUrl.
              _InfoRow(icon: Icons.delete_forever_outlined, label: 'Delete account', value: '', onTap: _deleteAccount, danger: true),
            ],
          ),
          const SizedBox(height: 24),
          Center(child: Text('Speak Frankly${_version.isEmpty ? '' : ' · v$_version'}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12))),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Speak Frankly',
      applicationVersion: _version.isEmpty ? null : 'v$_version',
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

/// Doorway to the outcome view, with its headline already on the card.
///
/// The fluency map below this shows how much the learner has DONE. This shows
/// whether it worked, which is the question that actually decides whether they
/// keep the app - so it goes first, and it says something real even before
/// there is enough data for a trend.
class _ProgressEntry extends StatelessWidget {
  const _ProgressEntry();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ProgressHistory.instance,
      builder: (context, _) {
        final h = ProgressHistory.instance;
        final trend = h.thenAndNow();
        final now = trend?.$2.sentencesPerMistake;
        final then = trend?.$1.sentencesPerMistake;
        final improved = then != null && now != null && now > then;

        final String line;
        if (trend == null) {
          final togo = h.sessionsUntilTrend;
          line = togo > 0
              ? '$togo more ${togo == 1 ? 'conversation' : 'conversations'} and your trend appears'
              : 'A few more days and your trend appears';
        } else if (improved) {
          line = '1 mistake every ${now.round()} sentences, up from ${then.round()}';
        } else {
          line = '1 mistake every ${now!.round()} ${now.round() == 1 ? 'sentence' : 'sentences'}';
        }

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProgressScreen()),
            ),
            borderRadius: BorderRadius.circular(18),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: AppColors.gradient(AppTheme.seed),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(color: AppTheme.seed.withValues(alpha: 0.28), blurRadius: 16, offset: const Offset(0, 7)),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), shape: BoxShape.circle),
                    child: Center(
                      child: Icon(improved ? Icons.trending_up_rounded : Icons.insights_rounded,
                          color: Colors.white, size: 22),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Your progress',
                            style: TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(line, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white),
                ],
              ),
            ),
          ),
        );
      },
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

  /// Whole days remaining until [iso] (a UTC ISO timestamp), or null if unknown.
  int? _trialDaysLeft(dynamic iso) {
    if (iso == null) return null;
    final end = DateTime.tryParse(iso.toString());
    if (end == null) return null;
    final diff = end.difference(DateTime.now());
    if (diff.isNegative) return 0;
    return diff.inHours ~/ 24 + (diff.inHours % 24 == 0 ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<Map<String, dynamic>>(
      future: access,
      builder: (context, snap) {
        final d = snap.data ?? {};
        final plan = (d['planType'] ?? 'free').toString();
        final isPremium = plan == 'premium';
        final isTrial = plan == 'trial';
        String title;
        String subtitle;
        if (isPremium) {
          title = 'Premium 💜';
          subtitle = 'Unlimited conversations. Thank you!';
        } else if (isTrial) {
          title = 'Free trial ✨';
          final days = _trialDaysLeft(d['trialEndsAtUtc']);
          subtitle = days != null
              ? (days <= 1 ? 'Unlimited today — last day of your free trial' : 'Unlimited practice · $days days left')
              : 'Unlimited practice during your free trial';
        } else {
          final used = (d['dailyUsed'] ?? 0) as num;
          final limit = (d['dailyLimit'] ?? 10) as num;
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
  /// Destructive action — tints the row so it never reads as a neutral setting.
  final bool danger;
  const _InfoRow({required this.icon, required this.label, required this.value, this.onTap, this.trailingArrow = false, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = danger ? scheme.error : scheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: tint),
            const SizedBox(width: 14),
            Text(label, style: TextStyle(fontSize: 14.5, color: danger ? scheme.error : null)),
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
