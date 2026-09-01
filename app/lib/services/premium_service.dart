import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'analytics_service.dart';
import 'api_service.dart';

/// One pricing phase of an offer, already formatted by Play for the buyer's
/// own country and currency.
///
/// A plain base plan has exactly one phase (₹200 / month, forever). A base plan
/// with an introductory offer has two: the opening phase (₹4 for 3 days, one
/// cycle) followed by the open-ended renewal phase.
class PlanPhase {
  const PlanPhase({
    required this.price,
    required this.rawPrice,
    required this.period,
    required this.cycles,
  });

  /// Play's formatted price string — render this, never a hardcoded amount.
  final String price;
  final double rawPrice;

  /// ISO-8601 billing period: `P3D`, `P1W`, `P1M`, `P1Y`.
  final String period;

  /// How many times this phase repeats. 0 means the open-ended renewal phase.
  final int cycles;

  bool get isFree => rawPrice <= 0;

  /// `3` out of `P3D`. 0 when Play gave us no period (non-Play platforms).
  int get periodCount => int.tryParse(RegExp(r'\d+').firstMatch(period)?.group(0) ?? '') ?? 0;

  /// `D`, `W`, `M` or `Y` out of `P3D`. Empty when there is no period.
  String get periodUnit => period.isEmpty ? '' : period.substring(period.length - 1);

  /// Total length of this phase, e.g. 3 days billed once = 3 days;
  /// 1 month billed twice = 2 months. Used to say "3 days" on the button.
  int get totalUnits => periodCount * (cycles > 0 ? cycles : 1);
}

/// A purchasable subscription offer: a base plan on its own, or a base plan
/// with an introductory / free-trial phase in front of it.
///
/// Play returns one of these per base plan AND per offer, all sharing the same
/// product id — which is why they cannot be stored in a map keyed by id.
class PlanOffer {
  const PlanOffer({
    required this.productId,
    required this.details,
    required this.phases,
    required this.basePlanId,
    required this.offerId,
  });

  final String productId;

  /// Hand this straight back to [PremiumService.buy]. For Play it carries the
  /// offerToken that decides WHICH offer is actually purchased.
  final ProductDetails details;

  final List<PlanPhase> phases;
  final String basePlanId;
  final String? offerId;

  /// What the buyer pays first — the intro/trial phase when there is one.
  PlanPhase get opening => phases.first;

  /// What they pay every cycle once any intro phase is over.
  PlanPhase get renewal => phases.last;

  /// Is there a cheaper opening phase in front of the normal price?
  bool get hasIntro => phases.length > 1;
}

/// Google Play subscriptions for Premium. Two products (create both in Play
/// Console):
///  - [monthlyId] `premium_monthly` — billed monthly.
///  - [annualId]  `premium_annual`  — billed yearly (best value).
///
/// THE PAID TRIAL LIVES IN PLAY, NOT HERE.
/// "₹4 for 3 days, then ₹200/month" is a Play *offer* on the monthly base plan
/// (Play Console → the subscription → base plan → Add offer → a single
/// introductory phase, 3 days, ₹4, new-subscriber eligibility). Play charges
/// the ₹4, waits 3 days, then auto-debits ₹200 unless the learner cancelled —
/// so the whole renew/cancel/refund flow is Google's, and this app only has to
/// ask for the right offer and react to the result.
///
/// Prices are NOT defined here. Play returns them for the buyer's own country
/// and currency, already formatted, in [PlanPhase.price] — so the UI must
/// render that string and never a hardcoded one. A learner in Brazil sees R$,
/// one in India sees ₹.
///
/// A product only comes back for countries the subscription is actually
/// available and priced in, and an offer only comes back while this account is
/// still ELIGIBLE for it. So an intro offer that is missing is not an error:
/// it means this learner already used their trial, and they must be shown the
/// normal price instead of a promise Play will not honour.
///
/// On a confirmed purchase we grant premium on the backend, which VERIFIES the
/// purchase token with the Play Developer API (server-authoritative).
class PremiumService extends ChangeNotifier {
  static final PremiumService instance = PremiumService._();
  PremiumService._();

  /// Must match the subscription product IDs created in Play Console.
  static const String monthlyId = 'premium_monthly';
  static const String annualId = 'premium_annual';
  static const Set<String> _ids = {monthlyId, annualId};

  // Lazy: touching InAppPurchase.instance spins up the platform billing
  // client, which needs a Flutter binding. Keeping it late means the price
  // logic below can be unit-tested without one.
  late final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  bool available = false;

  /// True once [init] has finished — products queried and past purchases
  /// restored. The paywall gate waits for this so a subscriber whose
  /// renewal has not been reported to our server yet is never shown a
  /// sales page they already paid for.
  bool ready = false;

  bool purchasePending = false;
  bool justActivated = false;

  /// Every offer Play returned, flattened. One product id can appear more than
  /// once (base plan + each eligible offer).
  final List<PlanOffer> _offers = [];

  List<PlanOffer> offersFor(String productId) =>
      _offers.where((o) => o.productId == productId).toList();

  /// The offer a buyer should be shown for [productId].
  ///
  /// Play only returns an intro or free-trial offer while the account is still
  /// eligible for it, so when one comes back it is always the better deal:
  /// pick the cheapest opening phase, and on a tie prefer the one that has an
  /// intro at all.
  PlanOffer? bestOffer(String productId) {
    final list = offersFor(productId);
    if (list.isEmpty) return null;
    list.sort((a, b) {
      final byPrice = a.opening.rawPrice.compareTo(b.opening.rawPrice);
      if (byPrice != 0) return byPrice;
      return (b.hasIntro ? 1 : 0).compareTo(a.hasIntro ? 1 : 0);
    });
    return list.first;
  }

  /// The headline offer for the hard paywall: monthly, with its intro phase if
  /// this learner is still eligible for one. Null when Play has nothing to
  /// sell here (still loading, or not available in this country).
  PlanOffer? get trialOffer => bestOffer(monthlyId);

  /// Whether the annual plan is offered (only if the Play product exists).
  bool get hasAnnual => offersFor(annualId).isNotEmpty;

  /// Whether Play returned ANY purchasable plan for this buyer.
  ///
  /// False means either the products are still loading, or the subscription
  /// isn't available in this country — in both cases there is no real price to
  /// show and nothing to buy, so the paywall must not present one.
  bool get hasAnyPlan => _offers.isNotEmpty;

  /// Is [productId] actually purchasable right now?
  bool canBuy(String productId) => offersFor(productId).isNotEmpty;

  Future<void> init() async {
    try {
      available = await _iap.isAvailable();
    } catch (_) {
      available = false;
    }
    if (!available) {
      ready = true; // nothing to wait for — no billing on this device
      notifyListeners();
      return;
    }
    _sub ??= _iap.purchaseStream.listen(_onPurchases, onError: (_) {});
    await _loadProducts();
    try {
      await _iap.restorePurchases(); // re-grant an active subscription on this account
    } catch (_) {}
    ready = true;
    notifyListeners();
  }

  Future<void> _loadProducts() async {
    try {
      final resp = await _iap.queryProductDetails(_ids);
      _offers
        ..clear()
        ..addAll(resp.productDetails.map(toOffer).whereType<PlanOffer>());
      notifyListeners();
    } catch (_) {}
  }

  /// Flatten one [ProductDetails] into our offer model.
  ///
  /// On Play each entry already points at a single base plan or offer via
  /// `subscriptionIndex`; everywhere else there are no phases to read, so the
  /// product's own price becomes a single-phase offer.
  @visibleForTesting
  static PlanOffer? toOffer(ProductDetails d) {
    PlanOffer flat() => PlanOffer(
          productId: d.id,
          details: d,
          phases: [PlanPhase(price: d.price, rawPrice: d.rawPrice, period: '', cycles: 0)],
          basePlanId: '',
          offerId: null,
        );

    if (d is! GooglePlayProductDetails) return flat();
    final index = d.subscriptionIndex;
    final offers = d.productDetails.subscriptionOfferDetails;
    if (index == null || offers == null || index >= offers.length) return flat();

    final offer = offers[index];
    if (offer.pricingPhases.isEmpty) return flat();

    return PlanOffer(
      productId: d.id,
      details: d,
      basePlanId: offer.basePlanId,
      offerId: offer.offerId,
      phases: offer.pricingPhases
          .map((p) => PlanPhase(
                price: p.formattedPrice,
                rawPrice: p.priceAmountMicros / 1000000.0,
                period: p.billingPeriod,
                cycles: p.billingCycleCount,
              ))
          .toList(),
    );
  }

  /// Load offers directly, without Play. Tests only.
  @visibleForTesting
  void debugSetOffers(List<PlanOffer> offers) {
    _offers
      ..clear()
      ..addAll(offers);
    notifyListeners();
  }

  /// Launch the Play purchase flow for [offer].
  ///
  /// The offer's own [ProductDetails] must be the one handed to Play: it
  /// carries the offerToken, and that token — not the product id — is what
  /// decides whether the learner is charged ₹4 or ₹200.
  Future<bool> buy(PlanOffer offer) async {
    purchasePending = true;
    justActivated = false;
    notifyListeners();
    try {
      return await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: offer.details),
      );
    } catch (_) {
      purchasePending = false;
      notifyListeners();
      return false;
    }
  }

  /// Convenience for the upgrade screen: buy the best offer for a product id.
  Future<bool> buyProduct(String productId) async {
    final offer = bestOffer(productId);
    if (offer == null) return false;
    return buy(offer);
  }

  /// Re-ask Play for anything this account already owns. The hard paywall
  /// offers this so a reinstalling subscriber is never asked to pay twice.
  Future<void> restore() async {
    if (!available) return;
    try {
      await _iap.restorePurchases();
    } catch (_) {}
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored) {
        try {
          await ApiService.instance.activatePremium(purchaseToken: p.verificationData.serverVerificationData);
          justActivated = true;
        } catch (_) {}

        // Firebase's standard `purchase` event, which Google Ads reads natively
        // for value-based bidding. Without it a paying learner is invisible to
        // the ad platform and campaigns can only ever optimise for installs.
        //
        // Only a genuine `purchased` counts. `restored` is the same
        // subscription being re-applied on a reinstall or another device —
        // counting it would inflate revenue with money nobody paid again.
        if (p.status == PurchaseStatus.purchased) {
          final product = _products[p.productID];
          AnalyticsService.log('purchase', {
            'transaction_id': p.purchaseID ?? '',
            'value': product?.rawPrice ?? 0,
            'currency': product?.currencyCode ?? 'INR',
            'item_id': p.productID,
          });
        }
      }
      if (p.pendingCompletePurchase) {
        try {
          await _iap.completePurchase(p);
        } catch (_) {}
      }
    }
    purchasePending = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
