import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'analytics_service.dart';
import 'api_service.dart';
import 'plan_status.dart';

/// Buying Premium through Razorpay, from inside the app.
///
/// EVERY PRICE COMES FROM THE SERVER. `/checkout/plans` returns the same list
/// the web checkout page prints, so a price change is a Render env edit rather
/// than an app release. Nothing on the paywall is hardcoded, and when the list
/// cannot be fetched the paywall says so instead of showing a number the
/// checkout would not honour.
///
/// ENTITLEMENT COMES FROM THE WEBHOOK, NOT FROM THIS CLASS. Razorpay's success
/// callback here is a UI hint — premium is written server-side when Razorpay
/// reports the payment with a valid signature. So after a successful payment
/// this polls `/access` and waits for the server to agree, rather than
/// unlocking the app on the client's say-so.
class RazorpayCheckout extends ChangeNotifier {
  static final RazorpayCheckout instance = RazorpayCheckout._();
  RazorpayCheckout._();

  // ------------------------------------------------------------- price list

  String keyId = '';
  List<CheckoutPlan> plans = const [];
  TrialTerms? trial;

  /// A load has finished, successfully or not.
  bool loaded = false;
  bool loading = false;

  /// True when there is something buyable: Razorpay keys are set on the server
  /// AND at least one plan id is configured.
  bool configured = false;

  Future<void> load() async {
    if (loading) return;
    loading = true;
    notifyListeners();
    try {
      final d = await ApiService.instance.fetchCheckoutPlans();
      keyId = (d['keyId'] ?? '').toString();
      configured = d['configured'] == true && keyId.isNotEmpty;
      plans = ((d['plans'] as List?) ?? const [])
          .whereType<Map>()
          .map(CheckoutPlan.fromJson)
          .where((p) => p.price.isNotEmpty)
          .toList();
      final t = d['trial'];
      final parsed = t is Map ? TrialTerms.fromJson(t) : null;
      // A trial we cannot print is not a trial we can sell.
      trial = (parsed != null && parsed.days > 0 && parsed.price.isNotEmpty) ? parsed : null;
      // A plan with no price label is not sellable: the paywall would have to
      // show a blank where the amount goes.
      if (plans.isEmpty) configured = false;
    } catch (_) {
      configured = false;
      plans = const [];
    } finally {
      loading = false;
      loaded = true;
      notifyListeners();
    }
  }

  // ----------------------------------------------------------------- buying

  bool busy = false;

  Razorpay? _rzp;
  Completer<_PaymentSignal>? _pending;

  void _wire() {
    if (_rzp != null) return;
    final r = Razorpay();
    r.on(Razorpay.EVENT_PAYMENT_SUCCESS, (_) => _settle(_PaymentSignal.paid));
    r.on(Razorpay.EVENT_PAYMENT_ERROR, (dynamic e) {
      // Razorpay reports a learner closing the sheet as an error too. It is
      // not one, and it must not be shown to them as a failed payment.
      final code = (e is PaymentFailureResponse) ? e.code : null;
      _settle(code == Razorpay.PAYMENT_CANCELLED
          ? _PaymentSignal.cancelled
          : _PaymentSignal.failed);
    });
    r.on(Razorpay.EVENT_EXTERNAL_WALLET, (_) => _settle(_PaymentSignal.cancelled));
    _rzp = r;
  }

  void _settle(_PaymentSignal s) {
    final p = _pending;
    _pending = null;
    if (p != null && !p.isCompleted) p.complete(s);
  }

  /// Run the whole purchase: create the subscription, open Razorpay, then wait
  /// for the server to confirm the entitlement.
  Future<CheckoutResult> buy(String planKey) async {
    if (busy) return CheckoutResult.failed;
    busy = true;
    notifyListeners();
    try {
      final created = await ApiService.instance.createSubscription(planKey);
      final subId = (created?['subscriptionId'] ?? '').toString();
      final key = (created?['keyId'] ?? keyId).toString();
      if (subId.isEmpty || key.isEmpty) return CheckoutResult.failed;

      _wire();
      final signal = Completer<_PaymentSignal>();
      _pending = signal;

      final user = FirebaseAuth.instance.currentUser;
      final email = user?.email ?? '';
      try {
        _rzp!.open(<String, dynamic>{
          'key': key,
          'subscription_id': subId,
          'name': 'Speak Frankly',
          'description': 'Premium',
          'recurring': 1,
          'theme': <String, dynamic>{'color': '#6C5CE7'},
          if (email.isNotEmpty) 'prefill': <String, dynamic>{'email': email},
        });
      } catch (_) {
        _settle(_PaymentSignal.failed);
      }

      final result = await signal.future;
      if (result == _PaymentSignal.cancelled) return CheckoutResult.cancelled;
      if (result == _PaymentSignal.failed) return CheckoutResult.failed;

      AnalyticsService.log('purchase', {
        'plan': planKey,
        'trial': created?['trial'] == true,
        'method': 'razorpay',
      });

      return await _awaitEntitlement()
          ? CheckoutResult.active
          : CheckoutResult.pending;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Wait for the webhook to land.
  ///
  /// Razorpay calls us server-to-server, which usually beats the learner back
  /// to the app — but not always. Giving up returns `pending`, not `failed`:
  /// their money has left their account, and telling them the payment failed
  /// would be a lie that earns a support ticket and a refund request.
  Future<bool> _awaitEntitlement() async {
    for (var i = 0; i < 10; i++) {
      await PlanStatus.instance.refresh();
      if (PlanStatus.instance.hasPremiumAccess) return true;
      await Future<void>.delayed(Duration(milliseconds: i < 3 ? 1200 : 2500));
    }
    return false;
  }

  @override
  void dispose() {
    _rzp?.clear();
    _rzp = null;
    super.dispose();
  }
}

enum CheckoutResult {
  /// Paid, and the server has confirmed premium.
  active,

  /// Paid, but the entitlement has not arrived yet. Not an error.
  pending,

  /// The learner closed the sheet.
  cancelled,

  /// Could not create the subscription, or Razorpay reported a real failure.
  failed,
}

enum _PaymentSignal { paid, cancelled, failed }

/// One purchasable plan, exactly as the server described it.
class CheckoutPlan {
  const CheckoutPlan({
    required this.key,
    required this.name,
    required this.per,
    required this.price,
    this.badge,
  });

  /// 'monthly' | 'quarterly' | 'halfyearly' | 'annual' — the id sent back.
  final String key;

  /// 'Monthly', '3 months', … as shown on the card.
  final String name;

  /// 'per month', 'every 3 months', … the period the price repeats on.
  final String per;

  /// The formatted amount, e.g. Rs 199. Never built in the app.
  final String price;

  /// 'Best value', or null.
  final String? badge;

  static CheckoutPlan fromJson(Map<dynamic, dynamic> j) => CheckoutPlan(
        key: (j['key'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        per: (j['per'] ?? '').toString(),
        price: (j['price'] ?? '').toString(),
        badge: j['badge']?.toString(),
      );
}

/// The intro offer for new subscribers: [price] for [days] days.
class TrialTerms {
  const TrialTerms({required this.days, required this.amount, required this.price});

  /// How long the intro amount covers.
  final int days;

  /// The raw amount, for anything that needs to compare rather than print.
  final num amount;

  /// The formatted amount the paywall prints, built server-side alongside the
  /// plan prices so the app never assembles a currency string.
  final String price;

  static TrialTerms fromJson(Map<dynamic, dynamic> j) => TrialTerms(
        days: (j['days'] as num?)?.toInt() ?? 0,
        amount: (j['amount'] as num?) ?? 0,
        price: (j['price'] ?? '').toString(),
      );
}
