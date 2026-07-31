import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Rewarded ads: free learners can watch a short ad for bonus daily messages.
/// Only rewarded ads are used (opt-in) — no banners/interstitials.
///
/// Android uses the real "Bonus messages" rewarded unit. (iOS is not shipped;
/// its id stays a Google TEST unit as a harmless placeholder.)
class AdService {
  static final AdService instance = AdService._();
  AdService._();

  // Real AdMob rewarded unit (Speak Frankly · Android). App ID is in AndroidManifest.xml.
  static const String _androidTestUnit = 'ca-app-pub-6637437102244163/2959275179';
  static const String _iosTestUnit = 'ca-app-pub-3940256099942544/1712485313';

  // Banner + interstitial — TEST units for now. REPLACE with real AdMob units
  // (create a Banner + an Interstitial ad unit for Speak Frankly, then swap).
  static const String _bannerTestUnit = 'ca-app-pub-3940256099942544/6300978111';
  static const String _interstitialTestUnit = 'ca-app-pub-3940256099942544/1033173712';

  // Don't show interstitials more often than this (protects UX + retention).
  static const int _minInterstitialGapMs = 180 * 1000; // 3 minutes

  bool _sdkReady = false;
  RewardedAd? _ad;
  bool _loading = false;
  InterstitialAd? _interstitial;
  int _lastInterstitialMs = 0;

  String get _unitId => Platform.isIOS ? _iosTestUnit : _androidTestUnit;
  bool get sdkReady => _sdkReady;
  String get bannerUnitId => _bannerTestUnit;

  /// Initialize the Mobile Ads SDK (call once at startup, non-blocking).
  Future<void> init() async {
    try {
      await MobileAds.instance.initialize();
      _sdkReady = true;
      _preload();
      _loadInterstitial();
    } catch (e) {
      debugPrint('[Ads] init failed: $e');
    }
  }

  void _loadInterstitial() {
    if (!_sdkReady || _interstitial != null) return;
    InterstitialAd.load(
      adUnitId: _interstitialTestUnit,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (err) {
          _interstitial = null;
          debugPrint('[Ads] interstitial load failed: $err');
        },
      ),
    );
  }

  /// Show an interstitial at a natural break (e.g. session end) — frequency
  /// capped. Returns false (and does nothing) if too soon or none loaded.
  /// The CALLER gates this to free users only.
  Future<bool> maybeShowInterstitial() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastInterstitialMs < _minInterstitialGapMs) return false;
    final ad = _interstitial;
    if (ad == null) {
      _loadInterstitial();
      return false;
    }
    _interstitial = null;
    _lastInterstitialMs = now;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        ad.dispose();
        _loadInterstitial();
      },
    );
    await ad.show();
    return true;
  }

  void _preload() {
    if (!_sdkReady || _loading || _ad != null) return;
    _loading = true;
    RewardedAd.load(
      adUnitId: _unitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loading = false;
        },
        onAdFailedToLoad: (err) {
          _ad = null;
          _loading = false;
          debugPrint('[Ads] load failed: $err');
        },
      ),
    );
  }

  /// Whether a rewarded ad is loaded and ready to show right now.
  bool get isReady => _ad != null;

  /// Show the rewarded ad. Calls [onReward] only if the user earns the reward
  /// (watches enough). Returns false if no ad was available. Preloads the next.
  Future<bool> showRewarded({required VoidCallback onReward}) async {
    final ad = _ad;
    if (ad == null) {
      _preload();
      return false;
    }
    _ad = null; // consumed
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _preload(); // ready for next time
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        ad.dispose();
        _preload();
      },
    );
    await ad.show(onUserEarnedReward: (_, __) {
      earned = true;
      onReward();
    });
    return earned;
  }
}
