import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../services/gamification_service.dart';
import '../services/vocabulary_service.dart';
import '../theme/app_theme.dart';

/// Flashcard review of saved words. Tap a card to flip (word → meaning), then
/// self-rate "Still learning" / "Got it". Each review earns XP and counts as
/// practice (advances the daily streak). Groundwork for full spaced repetition.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late final List<SavedWord> _cards;
  final _player = AudioPlayer();
  int _index = 0;
  bool _showBack = false;
  int _known = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _cards = List.of(VocabularyService.instance.words)..shuffle();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  void _rate(bool known) {
    if (known) _known++;
    GamificationService.instance.recordActivity(xpGain: 2);
    if (_index + 1 >= _cards.length) {
      setState(() => _done = true);
    } else {
      setState(() {
        _index++;
        _showBack = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review')),
      body: SafeArea(
        child: _done ? _buildSummary(context) : _buildCard(context),
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final card = _cards[_index];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (_index + 1) / _cards.length,
                    minHeight: 7,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text('${_index + 1}/${_cards.length}', style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: GestureDetector(
              onTap: () => setState(() => _showBack = !_showBack),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(anim), child: child),
                ),
                child: _showBack ? _back(context, card) : _front(context, card),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: _showBack
              ? Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _rate(false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('Still learning'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _rate(true),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.success,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Got it 👍'),
                      ),
                    ),
                  ],
                )
              : Text('Tap the card to reveal the meaning',
                  textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
      ],
    );
  }

  Widget _front(BuildContext context, SavedWord card) {
    return _cardBox(
      context,
      key: const ValueKey('front'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(card.word, textAlign: TextAlign.center, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
          if (card.phonetic != null) ...[
            const SizedBox(height: 8),
            Text(card.phonetic!, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 16)),
          ],
          if (card.audio != null) ...[
            const SizedBox(height: 18),
            GestureDetector(
              onTap: () => _player.play(UrlSource(card.audio!)),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(gradient: AppColors.gradient(AppTheme.seed), shape: BoxShape.circle),
                child: const Icon(Icons.volume_up_rounded, color: Colors.white),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _back(BuildContext context, SavedWord card) {
    final scheme = Theme.of(context).colorScheme;
    return _cardBox(
      context,
      key: const ValueKey('back'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(card.word, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: scheme.primary)),
          const SizedBox(height: 14),
          Text(card.definition, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, height: 1.35)),
          if (card.translation != null && card.translation!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
              child: Text(card.translation!, textAlign: TextAlign.center, style: TextStyle(color: scheme.onPrimaryContainer)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cardBox(BuildContext context, {required Widget child, required Key key}) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xFF1E1B26),
        borderRadius: BorderRadius.circular(24),
        boxShadow: isLight ? [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 24, offset: const Offset(0, 12))] : null,
      ),
      child: Center(child: child),
    );
  }

  Widget _buildSummary(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🎯', style: TextStyle(fontSize: 60)),
          const SizedBox(height: 16),
          const Text('Review complete!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('You knew $_known of ${_cards.length} words.',
              style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
            child: Text('+${_cards.length * 2} XP  ⭐', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFB45309))),
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
