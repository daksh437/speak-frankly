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
const FALLBACK_DAYS = 31; // used only when unverified grants are explicitly allowed
const GRACE_DAYS = 3;     // short window granted on a transient (non-strict) API error
// SAFE DEFAULT: when Play verification isn't configured we do NOT grant premium
// (so a restored/leftover purchase can't hand out free premium). Set
// PLAY_ALLOW_UNVERIFIED=true ONLY for local/testing before Play API is wired.
const ALLOW_UNVERIFIED = process.env.PLAY_ALLOW_UNVERIFIED === 'true' || process.env.PLAY_ALLOW_UNVERIFIED === '1';

const TOKENS = 'purchase_tokens'; // purchaseToken -> the uid it was first granted to

const daysFromNow = (n) => new Date(Date.now() + n * 24 * 60 * 60 * 1000);

/** Has this account ever had a purchase Google actually confirmed? */
async function hasVerifiedPurchase(db, uid) {
  try {
    const snap = await db.collection(USERS).doc(uid).get();
    return snap.exists && snap.data().premiumVerified === true;
  } catch (e) {
    console.warn('[premium] verified-history lookup failed:', e.message);
    return false; // can't prove they paid → don't hand out grace
  }
}

/**
 * Bind a purchase token to the first account that redeems it.
 *
 * Play verifies that a token is a real, paid, active subscription — it does not
 * say whose it is. So one subscriber could pass their token to any number of
 * friends and every one of them would verify as valid and get premium. Claiming
 * the token on first use makes it worth exactly one account.
 *
 * Returns true if this uid owns the token (first claim, or re-activating their
 * own subscription — which the app does on every renewal and restore).
 */
async function claimToken(db, purchaseToken, uid) {
  if (!purchaseToken) return true;
  // Firestore document ids cap at 1500 bytes and can't contain '/'.
  const id = Buffer.from(purchaseToken).toString('base64url').slice(0, 300);
  const ref = db.collection(TOKENS).doc(id);
  try {
    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (snap.exists) return snap.data().uid === uid;
      tx.set(ref, { uid, claimedAt: new Date() });
      return true;
    });
  } catch (e) {
    // Infrastructure trouble must not block a real buyer at the moment they pay.
    console.warn('[premium] token claim failed (allowing):', e.message);
    return true;
  }
}

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
      //
      // But ONLY to someone who has actually paid before. A 401/403 from the
      // Play API — exactly what you get before Play Console → API access is
      // granted — is reported as transient, so without this check any signed-in
      // caller could POST a junk token and collect a rolling 3-day premium, for
      // ever, for free. Grace is there to protect existing subscribers through
      // an outage, not to admit strangers.
      const everVerified = await hasVerifiedPurchase(db, uid);
      if (!everVerified) {
        console.warn(`[premium] grace refused for ${uid} — no previously verified purchase (${v.reason}).`);
        return { ok: false, error: 'verification_failed', reason: v.reason };
      }
      premiumExpiry = daysFromNow(GRACE_DAYS);
    } else {
      // Definitively invalid token, or STRICT mode on a transient error → deny.
      return { ok: false, error: 'verification_failed', reason: v.reason };
    }
  } else if (ALLOW_UNVERIFIED) {
    // Explicit opt-in for testing before Play API access is set up.
    premiumExpiry = daysFromNow(FALLBACK_DAYS);
  } else {
    // Safe default: never grant premium we can't verify. This stops a restored
    // or leftover purchase from silently activating premium on sign-in.
    console.warn('[premium] grant refused — Play verification not configured. Set PLAY_PACKAGE_NAME (or PLAY_ALLOW_UNVERIFIED=true for testing).');
    return { ok: false, error: 'verification_not_configured' };
  }

  // One paid token, one account. Checked after verification so we never claim a
  // token that turned out to be junk.
  if (!(await claimToken(db, purchaseToken, uid))) {
    console.warn(`[premium] token already belongs to another account — refused for ${uid}.`);
    return { ok: false, error: 'token_already_claimed' };
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
