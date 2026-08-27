/**
 * Account & data deletion.
 *
 * Google Play requires any app that lets users create an account to offer
 * deletion BOTH from inside the app and from a web page. The web page has
 * existed (GET /delete-account) but it only told people to send an email, and
 * nothing in the app linked to it — so in practice neither half was there.
 * This endpoint is the in-app half: Profile → Delete account calls it and the
 * data is gone immediately, no email round-trip.
 *
 * Always requires a VERIFIED Firebase ID token, never the soft `x-user-uid`
 * header. Deletion is irreversible, so "this caller says they are uid X" is not
 * good enough — knowing someone's uid string must not be enough to erase their
 * account.
 */
const express = require('express');
const { getDb, getAdmin } = require('../utils/firestoreAdmin');
const { requireVerifiedAuth } = require('../middleware/auth');

const router = express.Router();

const USERS = 'users';
const REPORTS = 'ai_reports';
const DEVICES = 'trial_devices';

/**
 * Detach this uid from the device's trial record WITHOUT deleting the record.
 *
 * The document exists to stop one device farming endless free trials; dropping
 * it would turn "delete my account" into a trial reset. Keeping it while
 * scrubbing the uid preserves the anti-abuse signal and holds on to no personal
 * identifier.
 */
async function scrubTrialDevices(db, uid) {
  try {
    const snap = await db.collection(DEVICES).where('firstUid', '==', uid).limit(50).get();
    await Promise.all(snap.docs.map((d) => d.ref.set({ firstUid: null, uidDeleted: true }, { merge: true })));
    return snap.size;
  } catch (e) {
    console.warn('[account] device scrub error:', e.message);
    return 0;
  }
}

/**
 * Strip the reporter's identity from their AI-content reports, keeping the
 * report itself. The reports are a moderation record Play expects us to act on,
 * so deleting them would destroy safety history — but nothing in that history
 * needs to say who filed it.
 */
async function anonymizeReports(db, uid) {
  try {
    const snap = await db.collection(REPORTS).where('uid', '==', uid).limit(500).get();
    await Promise.all(snap.docs.map((d) => d.ref.set({ uid: null, email: null, reporterDeleted: true }, { merge: true })));
    return snap.size;
  } catch (e) {
    console.warn('[account] report scrub error:', e.message);
    return 0;
  }
}

/**
 * DELETE /account — erase the caller's own account and learning data.
 *
 * Firestore first, Firebase Auth last: if the Auth delete fails the learner's
 * data is already gone and they can safely retry, whereas the reverse order
 * would leave orphaned data behind a uid nobody can sign in as any more.
 */
router.delete('/', requireVerifiedAuth, async (req, res) => {
  const uid = req.uid;
  const db = getDb();
  const admin = getAdmin();
  if (!db || !admin) {
    return res.status(503).json({
      success: false,
      error: 'NO_DB',
      message: 'Account deletion is unavailable right now — please try again shortly.',
    });
  }

  try {
    const [devices, reports] = await Promise.all([
      scrubTrialDevices(db, uid),
      anonymizeReports(db, uid),
    ]);
    await db.collection(USERS).doc(uid).delete();

    let authDeleted = false;
    try {
      await admin.auth().deleteUser(uid);
      authDeleted = true;
    } catch (e) {
      // The learning data is already gone; the sign-in record lingering is
      // recoverable (a retry, or the manual email path) and must not read as a
      // total failure to the person waiting on the confirmation screen.
      console.warn('[account] auth delete error:', e.message);
    }

    console.warn(`[account] deleted ${uid} (auth: ${authDeleted ? 'yes' : 'pending'})`);
    return res.json({ success: true, data: { ok: true, authDeleted, devicesScrubbed: devices, reportsAnonymized: reports } });
  } catch (e) {
    console.error('[account] delete error:', e.message);
    return res.status(500).json({
      success: false,
      error: 'DELETE_FAILED',
      message: 'We could not delete your account. Please try again or email support.',
    });
  }
});

module.exports = router;
