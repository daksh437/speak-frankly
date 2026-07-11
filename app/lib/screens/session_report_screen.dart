import 'package:flutter/material.dart';

import '../services/sync_service.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';

/// End-of-conversation report (from backend /tutor/feedback): phrases the learner
/// practiced, a couple of gentle grammar tips, and encouragement — plus the XP
/// earned for finishing. Closes the practice loop on a positive note.
class SessionReportScreen extends StatelessWidget {
  final Map<String, dynamic> feedback;
  final int xpEarned;

  /// Optional adaptive-difficulty nudge: (suggested level, isLevelUp, reason).
  final (String, bool, String)? levelSuggestion;
  const SessionReportScreen({super.key, required this.feedback, required this.xpEarned, this.levelSuggestion});

  List<String> get _phrases =>
      (feedback['phrases_learned'] as List?)?.map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList() ?? [];

  List<Map<String, dynamic>> get _notes =>
      (feedback['grammar_notes'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? [];

  String get _encouragement => (feedback['encouragement'] ?? 'Great effort — keep practicing!').toString();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                children: [
                  // Celebratory header
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(gradient: AppColors.gradient(AppTheme.seed), shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: AppTheme.seed.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10))]),
                          child: const Center(child: Text('🎉', style: TextStyle(fontSize: 46))),
                        ),
                        const SizedBox(height: 18),
                        const Text('Great session!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                          child: Text('+$xpEarned XP  ⭐', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFB45309))),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (_phrases.isNotEmpty) ...[
                    _sectionTitle(context, 'Phrases you practiced'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _phrases
                          .map((p) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
                                child: Text(p, style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 13.5, fontWeight: FontWeight.w500)),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 24),
                  ],
                  if (_notes.isNotEmpty) ...[
                    _sectionTitle(context, 'Quick tips'),
                    const SizedBox(height: 10),
                    ..._notes.map((n) => _TipCard(point: (n['point'] ?? '').toString(), tip: (n['tip'] ?? '').toString())),
                    const SizedBox(height: 12),
                  ],
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
                    child: Row(
                      children: [
                        const Text('💪', style: TextStyle(fontSize: 22)),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_encouragement, style: const TextStyle(fontSize: 14.5, height: 1.35))),
                      ],
                    ),
                  ),
                  if (levelSuggestion != null) ...[
                    const SizedBox(height: 16),
                    _LevelSuggestionCard(suggestion: levelSuggestion!),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                  child: const Text('Done'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String t) =>
      Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700));
}

class _TipCard extends StatelessWidget {
  final String point;
  final String tip;
  const _TipCard({required this.point, required this.tip});

  @override
  Widget build(BuildContext context) {
    const amber = AppColors.correction;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: amber.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (point.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb_rounded, size: 17, color: amber),
                const SizedBox(width: 8),
                Expanded(child: Text(point, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFFB45309)))),
              ],
            ),
          if (tip.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 25),
              child: Text(tip, style: TextStyle(fontSize: 13.5, color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.3)),
            ),
        ],
      ),
    );
  }
}

class _LevelSuggestionCard extends StatefulWidget {
  final (String, bool, String) suggestion;
  const _LevelSuggestionCard({required this.suggestion});
  @override
  State<_LevelSuggestionCard> createState() => _LevelSuggestionCardState();
}

class _LevelSuggestionCardState extends State<_LevelSuggestionCard> {
  bool _applied = false;

  @override
  Widget build(BuildContext context) {
    final (level, up, reason) = widget.suggestion;
    final scheme = Theme.of(context).colorScheme;
    final color = up ? AppColors.success : const Color(0xFF4C9AFF);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded, color: color, size: 20),
              const SizedBox(width: 8),
              Text(up ? 'Level up?' : 'Adjust level?', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
            ],
          ),
          const SizedBox(height: 6),
          Text(reason, style: TextStyle(fontSize: 13.5, color: scheme.onSurface)),
          const SizedBox(height: 12),
          if (_applied)
            Row(
              children: [
                Icon(Icons.check_circle_rounded, color: color, size: 18),
                const SizedBox(width: 6),
                Text('Level set to $level', style: TextStyle(color: color, fontWeight: FontWeight.w600)),
              ],
            )
          else
            FilledButton(
              onPressed: () async {
                await UserSession.instance.setLevel(level);
                SyncService.push(); // adaptive level follows the account across devices
                if (mounted) setState(() => _applied = true);
              },
              style: FilledButton.styleFrom(backgroundColor: color),
              child: Text('Switch to $level'),
            ),
        ],
      ),
    );
  }
}
