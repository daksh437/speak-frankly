import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/plan_status.dart';
import '../services/premium_service.dart';
import '../services/razorpay_checkout.dart';
import '../theme/app_theme.dart';

/// The hard paywall shown straight after onboarding: one plan, one price, one
/// button. There is no way past it except subscribing, restoring an existing
/// subscription, or signing out.
///
/// EVERY NUMBER ON THIS SCREEN COMES FROM THE SERVER. The headline price is the
/// intro amount from `/checkout/plans` and the struck-through price is that
/// plan's real recurring price — both already formatted server-side. Changing a
/// price is a Render env edit, not an app release and a Play review.
///
/// It sells the MONTHLY plan and nothing else. A first paywall with four
/// choices on it is a decision, and a decision is a place to leave. The longer
/// plans stay on the web checkout page for learners who go looking.
///
/// When the price list cannot be loaded — server down, Razorpay not configured
/// — the button stays dead and the screen says so, rather than showing a price
/// the checkout would not honour.
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

  @override
  void initState() {
    super.initState();
    RazorpayCheckout.instance.load();
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
    );
  }

  Future<void> _subscribe(CheckoutPlan plan) async {
    final loc = AppLocalizations.of(context)!;
    final result = await RazorpayCheckout.instance.buy(plan.key);
    if (!mounted) return;
    switch (result) {
      case CheckoutResult.active:
        widget.onSubscribed?.call();
      case CheckoutResult.pending:
        // Paid, but the webhook has not landed. Never call this a failure —
        // the money has left their account.
        _say(loc.checkoutPending);
      case CheckoutResult.cancelled:
        break; // they closed the sheet; nothing to announce
      case CheckoutResult.failed:
        _say(loc.checkoutFailed);
    }
  }

  /// Ask both storefronts again.
  ///
  /// Play is still asked because a learner who subscribed through Play before
  /// this screen moved to Razorpay must not be walled out of what they are
  /// still paying for. The /access refresh covers the Razorpay side, including
  /// a webhook that arrived while they were staring at this screen.
  Future<void> _restore() async {
    setState(() => _restoring = true);
    await PremiumService.instance.restore();
    await PlanStatus.instance.refresh();
    if (!mounted) return;
    setState(() => _restoring = false);
    if (PlanStatus.instance.hasPremiumAccess) {
      widget.onSubscribed?.call();
    } else {
      _say(AppLocalizations.of(context)!.subsUnavailable);
    }
  }

  /// "₹199 per month" — the price plus the period it repeats on, in the
  /// learner's language where there is a word for it, and in the server's
  /// wording ('every 3 months') where there is not.
  String _renewalLabel(AppLocalizations loc, CheckoutPlan plan) {
    switch (plan.key) {
      case 'monthly':
        return '${plan.price} ${loc.perMonth}';
      case 'annual':
        return '${plan.price} ${loc.perYear}';
      default:
        return plan.per.isEmpty ? plan.price : '${plan.price} ${plan.per}';
    }
  }

  /// The plan this screen sells. Monthly by definition; the first available
  /// plan only as a fallback, so a misconfigured server shows something
  /// buyable instead of nothing.
  CheckoutPlan? _headline(List<CheckoutPlan> plans) {
    if (plans.isEmpty) return null;
    for (final p in plans) {
      if (p.key == 'monthly') return p;
    }
    return plans.first;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: RazorpayCheckout.instance,
          builder: (context, _) {
            final svc = RazorpayCheckout.instance;
            final plan = svc.configured ? _headline(svc.plans) : null;
            final trial = plan == null ? null : svc.trial;
            final days = trial?.days ?? 0;
            final renewal = plan == null ? '' : _renewalLabel(loc, plan);
            final headlinePrice = trial?.price ?? plan?.price ?? '';

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
                          days > 0 ? loc.trialPaywallTitle(days) : loc.goPremium,
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
                      if (plan == null)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              svc.loaded ? loc.subsUnavailable : '…',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        )
                      else ...[
                        // The struck-through price is this plan's real
                        // recurring price, not an invented "was" number.
                        if (trial != null)
                          Center(
                            child: Text(
                              plan.price,
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
                            headlinePrice,
                            style: TextStyle(
                              fontSize: 76,
                              fontWeight: FontWeight.w900,
                              color: scheme.primary,
                              height: 1.1,
                            ),
                          ),
                        ),
                        if (days > 0) ...[
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
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 62,
                        child: FilledButton(
                          // Nothing purchasable → no live button. A live button
                          // while the price list is still loading, or on a
                          // server with no Razorpay keys, just walks the
                          // learner into a failed checkout.
                          onPressed: (svc.busy || plan == null) ? null : () => _subscribe(plan),
                          child: svc.busy
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(
                                  days > 0 ? loc.trialPaywallCta(days) : loc.trialPaywallSubscribe,
                                  style: const TextStyle(
                                      fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 0.3),
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Auto-renewal, the amount, that the intro is not
                      // refundable, and how to cancel — all stated before the
                      // learner pays. A subscription nobody understood is a
                      // chargeback with extra steps.
                      Text(
                        plan == null
                            ? loc.subsUnavailable
                            : trial != null
                                ? loc.trialPaywallDisclosure(headlinePrice, renewal)
                                : loc.trialPaywallRenewNote(renewal),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5, height: 1.4),
                      ),
                      const SizedBox(height: 2),
                      // The full terms have to be reachable from the screen
                      // that takes the money, not only from a settings page
                      // this learner has never seen.
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _legalLink(context, 'Terms', AppConfig.termsUrl),
                          Text(' · ', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5)),
                          _legalLink(context, 'Privacy', AppConfig.privacyUrl),
                        ],
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

  Widget _legalLink(BuildContext context, String label, String url) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      style: TextButton.styleFrom(
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          color: scheme.onSurfaceVariant,
          decoration: TextDecoration.underline,
          decorationColor: scheme.onSurfaceVariant,
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
