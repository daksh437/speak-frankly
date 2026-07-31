const express = require('express');
const { getAiAccess, grantAdReward } = require('../middleware/aiAccess');

const router = express.Router();

function uidOf(req) {
  return (req.headers['x-user-uid'] || req.headers['x-user-id'] || '').toString().trim();
}

/**
 * GET /access — the client reads this to show the learner their plan, remaining
 * daily messages, and reset time. Server is authoritative; client counters are advisory.
 */
router.get('/', async (req, res) => {
  const uid = (req.headers['x-user-uid'] || req.headers['x-user-id'] || '').toString().trim();
  if (!uid) return res.status(401).json({ success: false, error: 'UNAUTHORIZED', message: 'Missing x-user-uid' });
  const deviceId = (req.headers['x-device-id'] || '').toString().trim();
  const access = await getAiAccess(uid, deviceId);
  const { user, ...safe } = access; // never leak the full user doc
  return res.json({ success: true, data: safe });
});

/**
 * POST /access/reward-ad — grant bonus messages after a rewarded ad completes.
 * Server-authoritative + daily-capped so it can't be farmed.
 */
router.post('/reward-ad', async (req, res) => {
  const uid = uidOf(req);
  if (!uid) return res.status(401).json({ success: false, error: 'UNAUTHORIZED' });
  const result = await grantAdReward(uid);
  return res.status(result.ok ? 200 : 400).json({ success: result.ok, data: result });
});

module.exports = router;
