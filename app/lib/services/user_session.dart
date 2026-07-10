import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

/// Local learner session. For the MVP we identify the user with a locally
/// generated id stored in prefs; once Firebase Auth is wired this `uid` becomes
/// the Firebase UID (the backend already trusts the `x-user-uid` header, so the
/// swap is transparent to the API layer).
class UserSession {
  static const _kUid = 'sf_uid';
  static const _kNativeLang = 'sf_native_language';
  static const _kGoal = 'sf_goal';
  static const _kLevel = 'sf_level';
  static const _kOnboarded = 'sf_onboarded';
  static const _kName = 'sf_display_name';

  String uid = '';
  String nativeLanguage = '';
  String goal = '';
  String level = 'A2';
  String displayName = 'Learner';
  bool onboarded = false;

  static final UserSession instance = UserSession._();
  UserSession._();

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    uid = p.getString(_kUid) ?? '';
    if (uid.isEmpty) {
      uid = _generateUid();
      await p.setString(_kUid, uid);
    }
    nativeLanguage = p.getString(_kNativeLang) ?? '';
    goal = p.getString(_kGoal) ?? '';
    level = p.getString(_kLevel) ?? 'A2';
    displayName = p.getString(_kName) ?? 'Learner';
    onboarded = p.getBool(_kOnboarded) ?? false;
  }

  Future<void> setDisplayName(String name) async {
    final trimmed = name.trim();
    displayName = trimmed.isEmpty ? 'Learner' : trimmed;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kName, displayName);
  }

  Future<void> setLevel(String newLevel) async {
    level = newLevel;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLevel, newLevel);
  }

  /// Adopt the Firebase UID as the authoritative id once anonymous auth resolves.
  /// The backend keys the user doc + usage limits on this uid (x-user-uid header).
  Future<void> setUid(String firebaseUid) async {
    if (firebaseUid.isEmpty || firebaseUid == uid) return;
    uid = firebaseUid;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUid, firebaseUid);
  }

  Future<void> completeOnboarding({
    required String nativeLanguage,
    required String goal,
    required String level,
  }) async {
    final p = await SharedPreferences.getInstance();
    this.nativeLanguage = nativeLanguage;
    this.goal = goal;
    this.level = level;
    onboarded = true;
    await p.setString(_kNativeLang, nativeLanguage);
    await p.setString(_kGoal, goal);
    await p.setString(_kLevel, level);
    await p.setBool(_kOnboarded, true);
  }

  /// Clear the per-account profile (when a different account signs in). Keeps uid.
  Future<void> resetProfile() async {
    nativeLanguage = '';
    goal = '';
    level = 'A2';
    displayName = 'Learner';
    onboarded = false;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kNativeLang);
    await p.remove(_kGoal);
    await p.remove(_kLevel);
    await p.remove(_kName);
    await p.remove(_kOnboarded);
  }

  /// Profile snapshot for cloud sync (so onboarding/level follow the account).
  Map<String, dynamic> profileToCloud() => {
        'onboarded': onboarded,
        'level': level,
        'goal': goal,
        'nativeLanguage': nativeLanguage,
        'displayName': displayName,
      };

  /// Apply a cloud profile (only if that account has completed onboarding).
  Future<void> applyCloudProfile(Map<String, dynamic> m) async {
    if (m['onboarded'] != true) return;
    onboarded = true;
    level = (m['level'] ?? level).toString();
    goal = (m['goal'] ?? goal).toString();
    nativeLanguage = (m['nativeLanguage'] ?? nativeLanguage).toString();
    displayName = (m['displayName'] ?? displayName).toString();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kOnboarded, true);
    await p.setString(_kLevel, level);
    await p.setString(_kGoal, goal);
    await p.setString(_kNativeLang, nativeLanguage);
    await p.setString(_kName, displayName);
  }

  String _generateUid() {
    final r = Random.secure();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = List.generate(8, (_) => r.nextInt(16).toRadixString(16)).join();
    return 'local-$ts-$rand';
  }
}
