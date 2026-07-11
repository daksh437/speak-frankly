import 'package:flutter/material.dart';

import '../services/premium_service.dart';
import '../theme/app_theme.dart';

/// Premium upgrade screen — introductory ₹10 for 7 days, then ₹199/month.
/// The actual price/offer comes from the Play Console subscription; the text
/// below mirrors it as the marketing copy.
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});
  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  @override
  void initState() {
    super.initState();
    PremiumService.instance.init();
  }

  Future<void> _subscribe() async {
    final ok = await PremiumService.instance.buy();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subscriptions are not available yet. Please try again later.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Speak Frankly Premium')),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: PremiumService.instance,
          builder: (context, _) {
            final svc = PremiumService.instance;
            if (svc.justActivated) return _success(context);
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                    children: [
                      Center(
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(gradient: AppColors.gradient(AppTheme.seed), shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: AppTheme.seed.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10))]),
                          child: const Center(child: Text('👑', style: TextStyle(fontSize: 46))),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Center(child: Text('Go Premium', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),
                      const SizedBox(height: 8),
                      Center(
                        child: Text('Unlimited practice, no daily limits.',
                            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14.5)),
                      ),
                      const SizedBox(height: 26),
                      _benefit(context, '💬', 'Unlimited AI conversations', 'No daily message cap — talk as much as you want.'),
                      _benefit(context, '🎙️', 'Unlimited speaking practice', 'Practise pronunciation without limits.'),
                      _benefit(context, '🔓', 'Everything unlocked', 'All scenarios, games and daily challenges.'),
                      _benefit(context, '🚀', 'Faster progress', 'The best way to become fluent quickly.'),
                      const SizedBox(height: 20),
                      // Offer card
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: scheme.primary.withValues(alpha: 0.3), width: 1.5),
                        ),
                        child: Column(
                          children: [
                            Text('₹10 for your first 7 days',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: scheme.onPrimaryContainer)),
                            const SizedBox(height: 4),
                            Text('then ₹199/month · cancel anytime',
                                style: TextStyle(fontSize: 13.5, color: scheme.onPrimaryContainer.withValues(alpha: 0.85))),
                            if (svc.product != null) ...[
                              const SizedBox(height: 6),
                              Text('Billed via Google Play (${svc.product!.price})',
                                  style: TextStyle(fontSize: 11.5, color: scheme.onPrimaryContainer.withValues(alpha: 0.7))),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton(
                          onPressed: svc.purchasePending ? null : _subscribe,
                          child: svc.purchasePending
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Start for ₹10', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('Payment charged to your Google Play account. Renews monthly at ₹199 until cancelled.',
                          textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _benefit(BuildContext context, String emoji, String title, String sub) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                Text(sub, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _success(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🎉', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          const Text("You're Premium!", style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('Enjoy unlimited practice. Happy learning!',
              textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
