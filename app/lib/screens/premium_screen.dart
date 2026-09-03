import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/plan_status.dart';
import '../services/premium_service.dart';
import '../theme/app_theme.dart';

/// Premium upgrade screen. Learners start with a free in-app trial; this screen
/// is the paid upgrade — monthly or annual (best value).
///
/// Every price shown comes from Play, localised to the buyer's own country and
/// currency. Nothing here hardcodes an amount: the tiles used to fall back to
/// '₹999'/'₹199' while the products loaded, which quoted Indian rupees to a
/// learner anywhere in the world and then failed at checkout. If Play returns
/// no plans at all — still loading, or the subscription is not available in
/// this country — the screen says so instead of inventing a price.
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});
  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  /// Shown in a plan tile until Play hands us the real, localised price. A
  /// neutral dash, never a currency — we don't know the buyer's until Play
  /// tells us, and guessing quotes them a price they will not be charged.
  static const String _pricePlaceholder = '—';

  /// The plan the learner has TAPPED, or null while they haven't chosen yet.
  ///
  /// Null rather than a default, because the default depends on what Play
  /// returns and Play answers asynchronously. This used to be initialised to
  /// annual and then corrected in initState by reading `hasAnnual` on the line
  /// after firing the async load — which is always false that early, so the
  /// screen fell back to monthly every time and the annual plan, the one badged
  /// "best value", was never the one preselected.
  String? _picked;

  /// Annual when Play sells it, monthly otherwise — re-evaluated on every build
  /// so it settles as soon as the products arrive.
  String get _selected {
    final picked = _picked;
    if (picked != null && PremiumService.instance.canBuy(picked)) return picked;
    return PremiumService.instance.hasAnnual ? PremiumService.annualId : PremiumService.monthlyId;
  }

  @override
  void initState() {
    super.initState();
    PremiumService.instance.init();
    PlanStatus.instance.refresh(); // know if already premium / on trial
  }

  Future<void> _subscribe() async {
    // _selected only ever names a plan Play is actually selling.
    final ok = await PremiumService.instance.buy(_selected);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.subsUnavailable)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.premiumTitle),
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([PremiumService.instance, PlanStatus.instance]),
          builder: (context, _) {
            final svc = PremiumService.instance;
            if (svc.justActivated) return _success(context);
            // Already subscribed → show a status screen, not a sales pitch.
            if (PlanStatus.instance.isPremium) return _premiumStatus(context);
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
                      Center(child: Text(loc.goPremium, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(loc.premiumSubtitle,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14.5)),
                      ),
                      const SizedBox(height: 22),
                      _comparisonTable(context),
                      const SizedBox(height: 20),
                      // Plan selector
                      if (svc.hasAnnual)
                        _planTile(
                          context,
                          id: PremiumService.annualId,
                          title: loc.planAnnual,
                          price: svc.annual?.price ?? _pricePlaceholder,
                          per: loc.perYear,
                          note: loc.planBestValue,
                          highlight: true,
                        ),
                      if (svc.hasAnnual) const SizedBox(height: 12),
                      _planTile(
                        context,
                        id: PremiumService.monthlyId,
                        title: loc.planMonthly,
                        price: svc.monthly?.price ?? _pricePlaceholder,
                        per: loc.perMonth,
                        note: loc.planMonthlyNote,
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
                          // Nothing purchasable → no live button. Play returns
                          // no products while they load and in any country the
                          // subscription isn't sold in; offering Continue there
                          // just walks the learner into a failed checkout.
                          onPressed: (svc.purchasePending || !svc.hasAnyPlan) ? null : _subscribe,
                          child: svc.purchasePending
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(_selected == PremiumService.annualId ? loc.continueAnnual : loc.continueMonthly,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(svc.hasAnyPlan ? loc.billingNote : loc.subsUnavailable,
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
      onTap: () => setState(() => _picked = id),
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
                          child: Text(AppLocalizations.of(context)!.planPopular, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: scheme.onPrimary)),
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

  /// A clear Free vs Premium comparison so learners see exactly what they get.
  Widget _comparisonTable(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final loc = AppLocalizations.of(context)!;
    // rows: (label, free value, premium value). A bool → tick/cross; a String → text.
    final rows = <(String, Object, Object)>[
      (loc.featAiChats, loc.valLimited, loc.valUnlimited),
      (loc.featSpeaking, true, true),
      (loc.featScenarios, true, true),
      (loc.featOffline, false, true),
      (loc.featAdFree, false, true),
      (loc.featNoLimits, false, true),
    ];
    return Container(
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xFF1E1B26),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                Expanded(child: Text(loc.compareWhatYouGet, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))),
                SizedBox(width: 64, child: Text(loc.compareFree, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: scheme.onSurfaceVariant))),
                SizedBox(width: 74, child: Text(loc.comparePremium, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: scheme.primary))),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
          for (int i = 0; i < rows.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(
                children: [
                  Expanded(child: Text(rows[i].$1, style: const TextStyle(fontSize: 13.5))),
                  SizedBox(width: 64, child: Center(child: _cell(context, rows[i].$2, premium: false))),
                  SizedBox(width: 74, child: Center(child: _cell(context, rows[i].$3, premium: true))),
                ],
              ),
            ),
            if (i < rows.length - 1) Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.3)),
          ],
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, Object v, {required bool premium}) {
    final scheme = Theme.of(context).colorScheme;
    if (v is bool) {
      return v
          ? Icon(Icons.check_circle_rounded, size: 20, color: premium ? scheme.primary : AppColors.success)
          : Icon(Icons.remove_rounded, size: 18, color: scheme.onSurfaceVariant.withValues(alpha: 0.5));
    }
    return Text(
      v.toString(),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: premium ? FontWeight.w800 : FontWeight.w500,
        color: premium ? scheme.primary : scheme.onSurfaceVariant,
      ),
    );
  }

  /// Shown when the learner is already Premium — a thank-you status, not a pitch.
  Widget _premiumStatus(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(gradient: AppColors.gradient(AppTheme.seed), shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: AppTheme.seed.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10))]),
            child: const Center(child: Text('👑', style: TextStyle(fontSize: 46))),
          ),
          const SizedBox(height: 18),
          Text(loc.youArePremium, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(loc.premiumStatusBody,
              textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14.5, height: 1.4)),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(14)),
            child: Text(loc.manageInPlay,
                textAlign: TextAlign.center, style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  Widget _success(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🎉', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          Text(loc.youArePremiumExcl, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(loc.enjoyUnlimited,
              textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: () async {
                // Refresh FIRST, so clearing the flag reveals the "you are
                // Premium" status rather than flashing the sales pitch at
                // someone who just paid.
                await PlanStatus.instance.refresh();
                // Leave the celebration behind whether or not there is a route
                // to pop: on the Premium TAB there isn't one, and without this
                // the screen stayed on 🎉 for the rest of the session.
                PremiumService.instance.clearJustActivated();
                if (context.mounted && Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
              child: Text(loc.done),
            ),
          ),
        ],
      ),
    );
  }
}
