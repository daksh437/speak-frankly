/**
 * Grants premium after a Google Play subscription purchase. The app calls this
 * once the purchase is confirmed by the Play billing client. We set premiumExpiry
 * ~31 days out (a monthly period); the app re-activates on each renewal it sees.
 *
 * NOTE (production hardening): for full trust, verify `purchaseToken` server-side
 * via the Google Play Developer API before granting. This MVP trusts the client.
 */
const { getDb } = require('../utils/firestoreAdmin');

const USERS = 'users';
const PREMIUM_DAYS = 31;

async function activatePremium(uid, body) {
  const db = getDb();
  if (!db || !uid) return { ok: false };
  const now = new Date();
  const premiumExpiry = new Date(now.getTime() + PREMIUM_DAYS * 24 * 60 * 60 * 1000);
  try {
    await db.collection(USERS).doc(uid).set(
      {
        planType: 'premium',
        premiumExpiry,
        lastPurchaseAt: now,
        lastPurchaseToken: body && body.purchaseToken ? String(body.purchaseToken).slice(0, 4096) : null,
      },
      { merge: true },
    );
    return { ok: true, premiumExpiry: premiumExpiry.toISOString() };
  } catch (e) {
    console.warn('[premium] activate error:', e.message);
    return { ok: false };
  }
}

module.exports = { activatePremium };
