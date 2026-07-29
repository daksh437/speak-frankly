import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/premium_service.dart';
import '../theme/app_theme.dart';

/// Premium upgrade screen. Learners start with a free in-app trial; this screen
/// is the paid upgrade — monthly (₹199/mo, ₹10 first-month intro) or annual
/// (₹999/yr, best value). The actual prices come from the Play Console products.
///
/// When [blocking] is true the screen acts as a hard paywall: no back button,
/// a sign-out escape hatch, and on success [onSubscribed] is invoked (instead of
/// popping) so a gate can reveal the app.
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key, this.blocking = false, this.onSubscribed});
  final bool blocking;
  final VoidCallback? onSubscribed;
  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  // Which plan the learner has selected. Defaults to annual (best value) when
  // it's offered, otherwise monthly.
  String _selected = PremiumService.annualId;

  @override
  void initState() {
    super.initState();
    PremiumService.instance.init();
    // If annual isn't available (product not created yet), fall back to monthly.
    if (!PremiumService.instance.hasAnnual) _selected = PremiumService.monthlyId;
  }

  Future<void> _subscribe() async {
    final svc = PremiumService.instance;
    // Guard: if the selected plan isn't available, use whatever is.
    var plan = _selected;
    if (plan == PremiumService.annualId && !svc.hasAnnual) plan = PremiumService.monthlyId;
    final ok = await svc.buy(plan);
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
      appBar: AppBar(
        title: const Text('Speak Frankly Premium'),
        automaticallyImplyLeading: !widget.blocking,
        actions: widget.blocking
            ? [
                TextButton(
                  onPressed: () => AuthService.signOut(),
                  child: const Text('Sign out'),
                ),
              ]
            : null,
      ),
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
                        child: Text('Your 3-day free trial keeps everything unlocked.\nKeep it going with Premium.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14.5)),
                      ),
                      const SizedBox(height: 26),
                      _benefit(context, '💬', 'Unlimited AI conversations', 'No daily message cap — talk as much as you want.'),
                      _benefit(context, '🎙️', 'Unlimited speaking practice', 'Practise pronunciation without limits.'),
                      _benefit(context, '🔓', 'Everything unlocked', 'All scenarios, games and daily challenges.'),
                      _benefit(context, '🚀', 'Faster progress', 'The best way to become fluent quickly.'),
                      const SizedBox(height: 20),
                      // Plan selector
                      if (svc.hasAnnual)
                        _planTile(
                          context,
                          id: PremiumService.annualId,
                          title: 'Annual',
                          price: svc.annual?.price ?? '₹999',
                          per: 'per year',
                          note: 'Best value · save ~58%',
                          highlight: true,
                        ),
                      if (svc.hasAnnual) const SizedBox(height: 12),
                      _planTile(
                        context,
                        id: PremiumService.monthlyId,
                        title: 'Monthly',
                        price: svc.monthly?.price ?? '₹199',
                        per: 'per month',
                        note: 'Just ₹10 for your first month',
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
                              : Text(_selected == PremiumService.annualId ? 'Continue · Annual' : 'Continue · ₹10 first month',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('Billed via Google Play. Cancel anytime. Renews automatically until cancelled.',
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

  Widget _planTile(
    BuildContext context, {
    required String id,
    required String title,
    required String price,
    required String per,
    required String note,
    bool highlight = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _selected == id;
    return InkWell(
      onTap: () => setState(() => _selected = id),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                color: selected ? scheme.primary : scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      if (highlight) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(20)),
                          child: Text('POPULAR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: scheme.onPrimary)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(note, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(price, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                Text(per, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            ),
          ],
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
            child: FilledButton(
              onPressed: () {
                if (widget.onSubscribed != null) {
                  widget.onSubscribed!();
                } else {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }
}
