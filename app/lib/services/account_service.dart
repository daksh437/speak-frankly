import 'package:shared_preferences/shared_preferences.dart';

import 'gamification_service.dart';
import 'locale_controller.dart';
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
      // A different account signed in on this device → wipe local first.
      await GamificationService.instance.reset();
      await VocabularyService.instance.reset();
      await UserSession.instance.resetProfile();
      await p.setString(_kSyncedUid, uid);
    }

    // Load this account's cloud data (after a reset, this is a clean load).
    await SyncService.pullAndApply();
    LocaleController.setFromLanguage(UserSession.instance.nativeLanguage);
    await SyncService.push(); // persist merged state / create the doc
  }

  /// On sign-out, clear local data so the next account starts clean.
  static Future<void> onSignedOut() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kSyncedUid);
    await GamificationService.instance.reset();
    await VocabularyService.instance.reset();
    await UserSession.instance.resetProfile();
  }
}
