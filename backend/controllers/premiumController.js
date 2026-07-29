/**
 * Grants premium after a Google Play subscription purchase.
 *
 * The app calls this once the Play billing client confirms a purchase, sending
 * the `purchaseToken`. We VERIFY that token server-side against the Google Play
 * Developer API (services/playVerify.js) before granting — so a forged call
 * can't hand out premium. On success we set premiumExpiry to the REAL expiry
 * Google reports; the app re-activates on each renewal it observes.
 *
 * If verification isn't configured yet (PLAY_PACKAGE_NAME unset), we fall back
 * to trusting the client with a fixed 31-day window so the app still works
 * before Play API access is wired — see playVerify.js for setup steps.
 */
const { getDb } = require('../utils/firestoreAdmin');
const { verifySubscription, isConfigured, STRICT } = require('../services/playVerify');

const USERS = 'users';
const FALLBACK_DAYS = 31; // used only when verification is not configured
const GRACE_DAYS = 3;     // short window granted on a transient (non-strict) API error

const daysFromNow = (n) => new Date(Date.now() + n * 24 * 60 * 60 * 1000);

async function activatePremium(uid, body) {
  const db = getDb();
  if (!db || !uid) return { ok: false, error: 'no_db' };

  const purchaseToken = body && body.purchaseToken ? String(body.purchaseToken) : '';

  let premiumExpiry;
  let verified = false;

  if (isConfigured()) {
    const v = await verifySubscription(purchaseToken);
    if (v.valid) {
      verified = true;
      premiumExpiry = new Date(v.expiryMs);
    } else if (v.transient && !STRICT) {
      // Couldn't reach Play (our creds/network), not a bad token → grant a short
      // grace window rather than locking out a paying user. Client re-activates.
      premiumExpiry = daysFromNow(GRACE_DAYS);
    } else {
      // Definitively invalid token, or STRICT mode on a transient error → deny.
      return { ok: false, error: 'verification_failed', reason: v.reason };
    }
  } else {
    // Verification not set up yet → trust the client (pre-launch behaviour).
    premiumExpiry = daysFromNow(FALLBACK_DAYS);
  }

  try {
    await db.collection(USERS).doc(uid).set(
      {
        planType: 'premium',
        premiumExpiry,
        premiumVerified: verified,
        lastPurchaseAt: new Date(),
        lastPurchaseToken: purchaseToken ? purchaseToken.slice(0, 4096) : null,
      },
      { merge: true },
    );
    return { ok: true, verified, premiumExpiry: premiumExpiry.toISOString() };
  } catch (e) {
    console.warn('[premium] activate error:', e.message);
    return { ok: false, error: 'write_failed' };
  }
}

module.exports = { activatePremium };
