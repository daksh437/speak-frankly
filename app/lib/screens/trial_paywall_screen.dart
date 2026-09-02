import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/plan_status.dart';
import '../services/premium_service.dart';
import '../theme/app_theme.dart';

/// The hard paywall shown straight after onboarding: one plan, one price, one
/// button. There is no way past it except subscribing, restoring an existing
/// subscription, or signing out.
///
/// EVERY NUMBER ON THIS SCREEN COMES FROM PLAY.
/// The headline price is the opening pricing phase of the offer Play returned
/// (e.g. ₹5 for 3 days), and the struck-through price next to it is that same
/// offer's renewal phase (₹199/month) — both already formatted for the buyer's
/// country. Nothing is hardcoded, so changing the price or the trial length is
/// a Play Console edit and no app release.
///
/// When Play returns no intro phase — because this account already used its
/// trial, or no offer is configured — the screen quietly becomes a plain
/// subscribe page at the normal price. It never promises a trial Play will not
/// honour.
class TrialPaywallScreen extends StatefulWidget {
  const TrialPaywallScreen({super.key, this.onSubscribed});

  /// Called once the purchase is confirmed AND the server has been re-checked,
  /// so the caller can reveal the app.
  final VoidCallback? onSubscribed;

  @override
  State<TrialPaywallScreen> createState() => _TrialPaywallScreenState();
}

class _TrialPaywallScreenState extends State<TrialPaywallScreen> {
  bool _restoring = false;
  bool _handled = false; // guards against the purchase stream firing twice

  @override
  void initState() {
    super.initState();
    PremiumService.instance.addListener(_onPurchaseState);
    PremiumService.instance.init();
  }

  @override
  void dispose() {
    PremiumService.instance.removeListener(_onPurchaseState);
    super.dispose();
  }

  Future<void> _onPurchaseState() async {
    if (_handled || !PremiumService.instance.justActivated) return;
    _handled = true;
    // The server is the authority on entitlement, not the purchase stream —
    // re-read it before letting anyone in.
    await PlanStatus.instance.refresh();
    if (mounted) widget.onSubscribed?.call();
  }

  Future<void> _subscribe() async {
    final offer = PremiumService.instance.trialOffer;
    if (offer == null) return;
    final ok = await PremiumService.instance.buy(offer);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.subsUnavailable)),
      );
    }
  }

  Future<void> _restore() async {
    setState(() => _restoring = true);
    await PremiumService.instance.restore();
    await PlanStatus.instance.refresh();
    if (!mounted) return;
    setState(() => _restoring = false);
    if (PlanStatus.instance.hasPremiumAccess) {
      widget.onSubscribed?.call();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.subsUnavailable)),
      );
    }
  }

  /// How long the opening phase lasts, in days — or null when it is measured in
  /// months or years, which is not a trial and must not be sold as one.
  static int? _introDays(PlanPhase phase) {
    final units = phase.totalUnits;
    if (units <= 0) return null;
    switch (phase.periodUnit) {
      case 'D':
        return units;
      case 'W':
        return units * 7;
      default:
        return null;
    }
  }

  /// "₹199 per month" — the price plus the period it repeats on.
  String _renewalLabel(AppLocalizations loc, PlanPhase renewal) {
    switch (renewal.periodUnit) {
      case 'Y':
        return '${renewal.price} ${loc.perYear}';
      case 'M':
        return '${renewal.price} ${loc.perMonth}';
      default:
        return renewal.price;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: PremiumService.instance,
          builder: (context, _) {
            final svc = PremiumService.instance;
            final offer = svc.trialOffer;
            final intro = (offer != null && offer.hasIntro) ? offer.opening : null;
            final days = intro != null ? _introDays(intro) : null;
            final renewal = offer != null ? _renewalLabel(loc, offer.renewal) : '';

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => AuthService.signOut(),
                        child: Text(loc.signOut),
                      ),
                      TextButton(
                        onPressed: _restoring ? null : _restore,
                        child: _restoring
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(loc.restorePurchase),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                    children: [
                      Center(
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            gradient: AppColors.gradient(AppTheme.seed),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.seed.withValues(alpha: 0.35),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: const Center(child: Text('👑', style: TextStyle(fontSize: 42))),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Center(
                        child: Text(
                          days != null ? loc.trialPaywallTitle(days) : loc.goPremium,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: Text(
                          loc.trialPaywallSubtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14.5),
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (offer == null)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              svc.hasAnyPlan ? loc.subsUnavailable : '…',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        )
                      else ...[
                        // The struck-through price is the real renewal price of
                        // this same offer, not an invented "was" number.
                        if (intro != null)
                          Center(
                            child: Text(
                              offer.renewal.price,
                              style: TextStyle(
                                fontSize: 22,
                                color: scheme.onSurfaceVariant,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ),
                        const SizedBox(height: 4),
                        Center(
                          child: Text(
                            (intro ?? offer.renewal).price,
                            style: TextStyle(
                              fontSize: 76,
                              fontWeight: FontWeight.w900,
                              color: scheme.primary,
                              height: 1.1,
                            ),
                          ),
                        ),
                        if (days != null) ...[
                          const SizedBox(height: 4),
                          Center(
                            child: Text(
                              loc.trialPaywallFor(days).toUpperCase(),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                        if (intro != null) ...[
                          const SizedBox(height: 10),
                          Center(
                            child: Text(
                              loc.trialPaywallThen(renewal),
                              style: TextStyle(fontSize: 14.5, color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ],
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _feature(context, Icons.forum_rounded, loc.featAiChats),
                          _feature(context, Icons.mic_rounded, loc.featSpeaking),
                          _feature(context, Icons.download_rounded, loc.featOffline),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton(
                          // Nothing purchasable → no live button. Play returns
                          // no offers while they load and in any country the
                          // subscription isn't sold in; a live button there
                          // just walks the learner into a failed checkout.
                          onPressed: (svc.purchasePending || offer == null) ? null : _subscribe,
                          child: svc.purchasePending
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(
                                  days != null ? loc.trialPaywallCta(days) : loc.trialPaywallSubscribe,
                                  style: const TextStyle(
                                      fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 0.3),
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Auto-renewal, the amount and how to cancel, stated
                      // before the learner pays — Play requires it, and a
                      // subscription nobody understood is a refund anyway.
                      Text(
                        offer == null
                            ? loc.subsUnavailable
                            : intro != null
                                ? loc.trialPaywallDisclosure(intro.price, renewal)
                                : loc.trialPaywallRenewNote(renewal),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5, height: 1.4),
                      ),
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

  Widget _feature(BuildContext context, IconData icon, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.55),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: scheme.primary, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
