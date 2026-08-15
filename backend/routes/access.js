const express = require('express');
const { getAiAccess, grantAdReward } = require('../middleware/aiAccess');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();

/**
 * GET /access — the client reads this to show the learner their plan, remaining
 * daily messages, and reset time. Server is authoritative; client counters are advisory.
 */
router.get('/', requireAuth, async (req, res) => {
  const deviceId = (req.headers['x-device-id'] || '').toString().trim();
  const access = await getAiAccess(req.uid, deviceId);
  const { user, ...safe } = access; // never leak the full user doc
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
