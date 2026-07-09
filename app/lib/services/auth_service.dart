import 'package:firebase_auth/firebase_auth.dart';

import 'user_session.dart';

/// Signs the learner in anonymously so every device gets a stable Firebase UID.
/// That UID becomes UserSession.uid (sent to the backend as x-user-uid), which
/// keys the Firestore user doc and server-side usage limits.
///
/// Later this can be upgraded to email/password or Google sign-in by *linking*
/// the anonymous account, so progress is preserved.
class AuthService {
  static Future<void> ensureSignedIn() async {
    final auth = FirebaseAuth.instance;
    var user = auth.currentUser;
    user ??= (await auth.signInAnonymously()).user;
    if (user != null) {
      await UserSession.instance.setUid(user.uid);
    }
  }
}
