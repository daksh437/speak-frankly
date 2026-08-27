// Tests for the paywall's price logic.
//
// This is the code that decides which number the learner sees and which offer
// Play actually charges them for, so a bug here is a bug about money.
//
// The trap it guards: when a subscription has an introductory offer, Play
// returns MORE THAN ONE ProductDetails for the SAME product id — one per base
// plan and offer. Anything that stores them in a map keyed by product id keeps
// whichever arrived last, so the ₹5 trial offer silently disappears (or the
// ₹199 base plan does) and the paywall quotes a price the buyer will not be
// charged.

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:speakflow/services/premium_service.dart';

/// A pricing phase as Play reports it.
PricingPhaseWrapper _phase({
  required String price,
  required int micros,
  required String period,
  required int cycles,
  RecurrenceMode mode = RecurrenceMode.infiniteRecurring,
}) =>
    PricingPhaseWrapper(
      billingCycleCount: cycles,
      billingPeriod: period,
      formattedPrice: price,
      priceAmountMicros: micros,
      priceCurrencyCode: 'INR',
      recurrenceMode: mode,
    );

/// One `premium_monthly` product carrying [offers] — the shape Play hands back.
List<ProductDetails> _monthly(List<SubscriptionOfferDetailsWrapper> offers) =>
    GooglePlayProductDetails.fromProductDetails(
      ProductDetailsWrapper(
        description: 'Premium',
        name: 'Premium',
        productId: PremiumService.monthlyId,
        productType: ProductType.subs,
        title: 'Premium',
        subscriptionOfferDetails: offers,
      ),
    );

/// The plain ₹199/month base plan.
final _basePlan = SubscriptionOfferDetailsWrapper(
  basePlanId: 'monthly',
  offerIdToken: 'token-base',
  offerTags: const <String>[],
  pricingPhases: <PricingPhaseWrapper>[
    _phase(price: '₹199.00', micros: 199000000, period: 'P1M', cycles: 0),
  ],
);

/// The paid trial: ₹5 for 3 days, then the base plan's ₹199/month.
final _introOffer = SubscriptionOfferDetailsWrapper(
  basePlanId: 'monthly',
  offerId: 'intro-3day',
  offerIdToken: 'token-intro',
  offerTags: const <String>[],
  pricingPhases: <PricingPhaseWrapper>[
    _phase(price: '₹5.00', micros: 5000000, period: 'P3D', cycles: 1, mode: RecurrenceMode.finiteRecurring),
    _phase(price: '₹199.00', micros: 199000000, period: 'P1M', cycles: 0),
  ],
);

void main() {
  final svc = PremiumService.instance;

  List<PlanOffer> load(List<ProductDetails> products) {
    final offers = products.map(PremiumService.toOffer).whereType<PlanOffer>().toList();
    svc.debugSetOffers(offers);
    return offers;
  }

  group('a subscription with an intro offer', () {
    setUp(() => load(_monthly(<SubscriptionOfferDetailsWrapper>[_basePlan, _introOffer])));

    test('both offers survive — they share a product id and must not collapse', () {
      expect(svc.offersFor(PremiumService.monthlyId).length, 2);
    });

    test('the cheapest opening phase wins', () {
      expect(svc.trialOffer!.opening.price, '₹5.00');
      expect(svc.trialOffer!.hasIntro, isTrue);
    });

    test('the renewal price is the real one, not the intro repeated', () {
      expect(svc.trialOffer!.renewal.price, '₹199.00');
      expect(svc.trialOffer!.renewal.periodUnit, 'M');
    });

    test('the winning offer carries the offerToken Play charges against', () {
      final details = svc.trialOffer!.details as GooglePlayProductDetails;
      expect(details.offerToken, 'token-intro');
    });

    test('the intro phase reads as 3 days', () {
      final opening = svc.trialOffer!.opening;
      expect(opening.periodCount, 3);
      expect(opening.periodUnit, 'D');
      expect(opening.totalUnits, 3);
    });
  });

  group('a learner who already used their trial', () {
    setUp(() => load(_monthly(<SubscriptionOfferDetailsWrapper>[_basePlan])));

    test('Play returns only the base plan, so no trial is promised', () {
      expect(svc.trialOffer!.hasIntro, isFalse);
    });

    test('the headline price is the price they will actually pay', () {
      expect(svc.trialOffer!.opening.price, '₹199.00');
      expect(svc.trialOffer!.renewal.price, '₹199.00');
    });
  });

  group('nothing to sell', () {
    test('no products → no offer, so the paywall shows no price and no button', () {
      load(<ProductDetails>[]);
      expect(svc.trialOffer, isNull);
      expect(svc.hasAnyPlan, isFalse);
      expect(svc.canBuy(PremiumService.monthlyId), isFalse);
    });
  });

  group('a free trial offer', () {
    test('a ₹0 opening phase is recognised as free', () {
      load(_monthly(<SubscriptionOfferDetailsWrapper>[
        _basePlan,
        SubscriptionOfferDetailsWrapper(
          basePlanId: 'monthly',
          offerId: 'free-3day',
          offerIdToken: 'token-free',
          offerTags: const <String>[],
          pricingPhases: <PricingPhaseWrapper>[
            _phase(price: 'Free', micros: 0, period: 'P3D', cycles: 1, mode: RecurrenceMode.finiteRecurring),
            _phase(price: '₹199.00', micros: 199000000, period: 'P1M', cycles: 0),
          ],
        ),
      ]));
      expect(svc.trialOffer!.opening.isFree, isTrue);
      expect(svc.trialOffer!.renewal.price, '₹199.00');
    });
  });

  group('an offer with several intro cycles', () {
    test('totalUnits multiplies the period by the cycle count', () {
      load(_monthly(<SubscriptionOfferDetailsWrapper>[
        SubscriptionOfferDetailsWrapper(
          basePlanId: 'monthly',
          offerId: 'two-weeks',
          offerIdToken: 'token-2w',
          offerTags: const <String>[],
          pricingPhases: <PricingPhaseWrapper>[
            _phase(price: '₹5.00', micros: 5000000, period: 'P1W', cycles: 2, mode: RecurrenceMode.finiteRecurring),
            _phase(price: '₹199.00', micros: 199000000, period: 'P1M', cycles: 0),
          ],
        ),
      ]));
      expect(svc.trialOffer!.opening.totalUnits, 2); // 2 × 1 week
      expect(svc.trialOffer!.opening.periodUnit, 'W');
    });
  });
}
