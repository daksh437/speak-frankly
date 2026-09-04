/**
 * Give an app-review account a password, so it can sign in without Google.
 *
 * WHY THIS SCRIPT EXISTS
 * Play rejected this app twice for a paywall the reviewer could not get past,
 * and the server showed why: the reviewer never signed in at all. Google
 * Sign-In asks them to add a Google ACCOUNT to a shared test device, and
 * Google's own security regularly refuses that from review infrastructure. So
 * the app now also accepts email + password, which needs no account on the
 * device — and this is how that password gets set.
 *
 * The Firebase Console cannot do it: the reviewer address already exists as a
 * Google-provider user, and the console offers no way to add a password to one.
 * The Admin SDK can, and doing so ADDS the password provider rather than
 * replacing Google — the same account, reachable two ways, with the premium it
 * already has in Firestore untouched.
 *
 * THE PASSWORD IS YOURS. It is read from the environment and never written to
 * disk, never logged, and never echoed back. Choose it, use it here, and paste
 * the same one into Play Console -> App content -> Sign in details.
 *
 * BEFORE RUNNING: enable the provider once, in Firebase Console ->
 * Authentication -> Sign-in method -> Email/Password -> Enable. Without it the
 * password is set but the app is refused at sign-in with
 * `operation-not-allowed`.
 *
 * Usage (from backend/):
 *   REVIEWER_PASSWORD='the-one-you-chose' node scripts/set-reviewer-password.js
 *
 * Optional: pass an address to target one explicitly. With no argument it uses
 * REVIEWER_EMAILS from .env, which is the list the server already grants
 * premium to — so the account you set up here is the account that gets in.
 *   REVIEWER_PASSWORD='...' node scripts/set-reviewer-password.js someone@x.com
 */
require('dotenv').config();
const { getAdmin } = require('../utils/firestoreAdmin');

const password = process.env.REVIEWER_PASSWORD || '';
const argEmail = (process.argv[2] || '').trim().toLowerCase();

const emails = argEmail
  ? [argEmail]
  : (process.env.REVIEWER_EMAILS || '')
      .split(',')
      .map((e) => e.trim().toLowerCase())
      .filter(Boolean);

function fail(message) {
  console.error(`\n  ${message}\n`);
  process.exit(1);
}

if (!password) {
  fail(
    'Set REVIEWER_PASSWORD first — this script will not invent one for you.\n' +
    "    REVIEWER_PASSWORD='your-choice' node scripts/set-reviewer-password.js",
  );
}
// Firebase's own minimum. Checked here so the failure is a sentence rather than
// an SDK error code.
if (password.length < 6) fail('Firebase requires a password of at least 6 characters.');
if (!emails.length) {
  fail(
    'No address to set up. Either pass one as an argument, or set REVIEWER_EMAILS\n' +
    '    in backend/.env to the same value the server uses.',
  );
}

(async () => {
  const admin = getAdmin();
  if (!admin) {
    fail(
      'No Firebase credentials. This must run where the service account is\n' +
      '    configured — FIREBASE_SERVICE_ACCOUNT_JSON in backend/.env.',
    );
  }
  const auth = admin.auth();

  for (const email of emails) {
    let user = null;
    try {
      user = await auth.getUserByEmail(email);
    } catch (e) {
      if (e.code !== 'auth/user-not-found') {
        console.error(`  ${email}: lookup failed — ${e.message}`);
        continue;
      }
    }

    try {
      if (user) {
        // Adds the password provider to the existing account. Google sign-in
        // keeps working, and the uid does not change — so the premium already
        // written against it in Firestore stays exactly where it is.
        await auth.updateUser(user.uid, { password });
        const providers = user.providerData.map((p) => p.providerId).join(', ') || 'none';
        console.log(`  ${email}: password set (uid ${user.uid})`);
        console.log(`    providers before: ${providers} — password is now added alongside`);
      } else {
        const created = await auth.createUser({ email, password, emailVerified: true });
        console.log(`  ${email}: account created with a password (uid ${created.uid})`);
      }
    } catch (e) {
      console.error(`  ${email}: could not set the password — ${e.message}`);
    }
  }

  console.log('\n  Next:');
  console.log('   1. Firebase Console -> Authentication -> Sign-in method -> enable Email/Password');
  console.log('   2. Play Console -> App content -> Sign in details: the same address and password');
  console.log('   3. In the app, the reviewer taps "Sign in with email" under the Google button');
  console.log('   4. Make sure the address is in REVIEWER_EMAILS on Render, or it signs in with no premium\n');
  process.exit(0);
})().catch((e) => fail(`Unexpected failure — ${e.message}`));
