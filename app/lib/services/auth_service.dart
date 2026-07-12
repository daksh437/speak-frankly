import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'account_service.dart';
import 'user_session.dart';

/// Google Sign-In → Firebase. The Firebase UID becomes UserSession.uid (sent to
/// the backend as x-user-uid), which keys the Firestore user doc, progress, and
/// server-side usage limits — so the learner's data follows their Google account
/// across devices.
class AuthService {
  /// Launches the Google sign-in flow. Returns the signed-in [User], or null if
  /// the user cancelled. Throws on real errors (the caller shows a message).
  static Future<User?> signInWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return null; // user cancelled

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final result = await FirebaseAuth.instance.signInWithCredential(credential);
    final user = result.user;
    if (user != null) await UserSession.instance.setUid(user.uid);
    return user;
  }

  static Future<void> signOut() async {
    // Sign out of Firebase FIRST so authStateChanges fires and AuthGate routes
    // to the login screen immediately — a slow/hanging Google plugin must never
    // block the actual sign-out.
    await FirebaseAuth.instance.signOut();
    await AccountService.onSignedOut(); // clear this device's local data
    try {
      await GoogleSignIn().signOut().timeout(const Duration(seconds: 4));
    } catch (_) {/* best-effort; Firebase is already signed out */}
  }
}
