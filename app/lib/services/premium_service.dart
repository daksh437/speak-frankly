import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'api_service.dart';

/// Google Play subscriptions for Premium. Two plans (create both in Play Console):
///  - [monthlyId] `premium_monthly` — ₹199/month, with a ₹10 first-month intro offer.
///  - [annualId]  `premium_annual`  — ₹999/year (best value; ~58% off monthly).
/// On a confirmed purchase we grant premium on the backend, which VERIFIES the
/// purchase token with the Play Developer API (server-authoritative).
class PremiumService extends ChangeNotifier {
  static final PremiumService instance = PremiumService._();
  PremiumService._();

  /// Must match the subscription product IDs created in Play Console.
  static const String monthlyId = 'premium_monthly';
  static const String annualId = 'premium_annual';
  static const Set<String> _ids = {monthlyId, annualId};

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  bool available = false;
  final Map<String, ProductDetails> _products = {};
  bool purchasePending = false;
  bool justActivated = false;

  ProductDetails? get monthly => _products[monthlyId];
  ProductDetails? get annual => _products[annualId];

  /// Whether the annual plan is offered (only if the Play product exists).
  bool get hasAnnual => _products.containsKey(annualId);

  Future<void> init() async {
    try {
      available = await _iap.isAvailable();
    } catch (_) {
      available = false;
    }
    if (!available) {
      notifyListeners();
      return;
    }
    _sub ??= _iap.purchaseStream.listen(_onPurchases, onError: (_) {});
    await _loadProducts();
    try {
      await _iap.restorePurchases(); // re-grant an active subscription on this account
    } catch (_) {}
  }

  Future<void> _loadProducts() async {
    try {
      final resp = await _iap.queryProductDetails(_ids);
      for (final p in resp.productDetails) {
        _products[p.id] = p;
      }
      notifyListeners();
    } catch (_) {}
  }

  /// Launch the Play purchase flow for [productId] (defaults to monthly).
  /// Returns false if that product is unavailable.
  Future<bool> buy(String productId) async {
    final product = _products[productId];
    if (product == null) return false;
    purchasePending = true;
    justActivated = false;
    notifyListeners();
    try {
      return await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));
    } catch (_) {
      purchasePending = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored) {
        try {
          await ApiService.instance.activatePremium(purchaseToken: p.verificationData.serverVerificationData);
          justActivated = true;
        } catch (_) {}
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
