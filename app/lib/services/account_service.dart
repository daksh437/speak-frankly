import 'package:shared_preferences/shared_preferences.dart';

import 'gamification_service.dart';
import 'locale_controller.dart';
import 'premium_service.dart';
import 'sync_service.dart';
import 'user_session.dart';
import 'vocabulary_service.dart';

/// Keeps on-device data tied to the signed-in Google account. On sign-in, if a
/// *different* account is now active, local data is cleared before loading that
/// account's cloud copy — so two Google accounts on one device never share data.
class AccountService {
  static const _kSyncedUid = 'sf_synced_uid';

  /// Prepare the session for [uid]. Call after Google sign-in, before showing
  /// the app. Safe to call repeatedly for the same account.
  static Future<void> switchTo(String uid) async {
    final p = await SharedPreferences.getInstance();
    final last = p.getString(_kSyncedUid);
    await UserSession.instance.setUid(uid);

    if (last != uid) {
      // A DIFFERENT account signed in on this device → wipe local first, then we
      // MUST wait for the cloud pull, because routing (onboarding vs app) and the
      // UI language depend on this account's profile. This path is rare (first
      // sign-in / new device), and the backend was warmed on the login screen.
      await GamificationService.instance.reset();
      await VocabularyService.instance.reset();
      await UserSession.instance.resetProfile();
      await p.setString(_kSyncedUid, uid);
      await SyncService.pullAndApply();
      LocaleController.setFromLanguage(UserSession.instance.nativeLanguage);
    } else {
      // SAME account reopening the app (the common case) — local data is already
      // correct, so open INSTANTLY and refresh from cloud in the background. This
      // is the key fix: a sleeping (cold) backend no longer delays app startup.
      SyncService.pullAndApply().then((_) {
        LocaleController.setFromLanguage(UserSession.instance.nativeLanguage);
      });
    }

    // Persist merged state / create the doc — fire-and-forget so it doesn't block
    // the login → app transition (esp. on a cold backend).
    SyncService.push();

    // Restore any active Google Play subscription for this account (re-grants premium).
    PremiumService.instance.init();
  }

  /// On sign-out, clear local data so the next account starts clean.
  static Future<void> onSignedOut() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kSyncedUid);
    await GamificationService.instance.reset();
    await VocabularyService.instance.reset();
    await UserSession.instance.resetProfile();
  }

  /// After the server confirms the account is deleted: wipe every local trace.
  ///
  /// Sign-out only clears the per-account data, because the account still
  /// exists and will sync back. Deletion has nothing to come back to, so this
  /// clears prefs wholesale — cached offline packs, streaks, saved words, the
  /// daily-phrase cache, rate-prompt state, all of it.
  ///
  /// The ONE key that survives is the device id. It is what the backend uses to
  /// grant a single free trial per device; dropping it here would quietly turn
  /// "delete my account" into "restart my free trial", forever.
  static Future<void> wipeAfterDeletion() async {
    final deviceId = UserSession.instance.deviceId;
    final p = await SharedPreferences.getInstance();
    await p.clear();
    if (deviceId.isNotEmpty) await p.setString('sf_device_id', deviceId);
    await GamificationService.instance.reset();
    await VocabularyService.instance.reset();
    await UserSession.instance.resetProfile();
    await UserSession.instance.load(); // regenerate the placeholder uid
  }
}
