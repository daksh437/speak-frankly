const express = require('express');
const { getAiAccess, grantAdReward } = require('../middleware/aiAccess');
const { requireAuth } = require('../middleware/auth');
const { getDb } = require('../utils/firestoreAdmin');

const router = express.Router();

/**
 * Stamp the account's email and a daily "last seen" on the user doc.
 *
 * The doc is keyed by uid and never carried an email, so the admin panel had no
 * way to show who a learner actually is without a lookup per row. The email
 * comes from the VERIFIED token (never the client), and we write at most once
 * per day per learner — /access is called on app open, so this stays cheap.
 */
async function touchProfile(req, user) {
  const db = getDb();
  if (!db || !req.uid || !user) return;
  const today = new Date().toISOString().slice(0, 10);
  const patch = {};
  if (req.authEmail && user.email !== req.authEmail) patch.email = req.authEmail;
  if ((user.lastSeenDay || '') !== today) {
    patch.lastSeenDay = today;
    patch.lastSeenAt = new Date();
  }
  if (Object.keys(patch).length === 0) return;
  try {
    await db.collection('users').doc(req.uid).set(patch, { merge: true });
  } catch (e) {
    console.warn('[access] touchProfile error:', e.message);
  }
}

/**
 * GET /access — the client reads this to show the learner their plan, remaining
 * daily messages, and reset time. Server is authoritative; client counters are advisory.
 */
router.get('/', requireAuth, async (req, res) => {
  const deviceId = (req.headers['x-device-id'] || '').toString().trim();
  const access = await getAiAccess(req.uid, deviceId);
  const { user, ...safe } = access; // never leak the full user doc
  touchProfile(req, user).catch(() => {}); // fire-and-forget, never blocks the plan check
  return res.json({ success: true, data: safe });
});

/**
 * POST /access/reward-ad — grant bonus messages after a rewarded ad completes.
 * Server-authoritative + daily-capped so it can't be farmed.
 */
router.post('/reward-ad', requireAuth, async (req, res) => {
  const result = await grantAdReward(req.uid);
  return res.status(result.ok ? 200 : 400).json({ success: result.ok, data: result });
});

module.exports = router;
