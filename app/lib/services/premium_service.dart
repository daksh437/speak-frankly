import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'api_service.dart';

/// Google Play subscription for Premium. The Play Console product (base plan
/// ₹199/month + a 7-day intro offer at ₹10) is referenced by [productId].
/// On a confirmed purchase we grant premium on the backend (server-authoritative).
class PremiumService extends ChangeNotifier {
  static final PremiumService instance = PremiumService._();
  PremiumService._();

  /// Must match the subscription product ID created in Play Console.
  static const String productId = 'premium_monthly';

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  bool available = false;
  ProductDetails? product;
  bool purchasePending = false;
  bool justActivated = false;

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
    await _loadProduct();
    try {
      await _iap.restorePurchases(); // re-grant an active subscription on this account
    } catch (_) {}
  }

  Future<void> _loadProduct() async {
    try {
      final resp = await _iap.queryProductDetails({productId});
      if (resp.productDetails.isNotEmpty) {
        product = resp.productDetails.first;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Launch the Play purchase flow. Returns false if unavailable.
  Future<bool> buy() async {
    if (product == null) return false;
    purchasePending = true;
    justActivated = false;
    notifyListeners();
    try {
      return await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product!));
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
