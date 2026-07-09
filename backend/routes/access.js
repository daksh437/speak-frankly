const express = require('express');
const { getAiAccess } = require('../middleware/aiAccess');

const router = express.Router();

/**
 * GET /access — the client reads this to show the learner their plan, remaining
 * daily messages, and reset time. Server is authoritative; client counters are advisory.
 */
router.get('/', async (req, res) => {
  const uid = (req.headers['x-user-uid'] || req.headers['x-user-id'] || '').toString().trim();
  if (!uid) return res.status(401).json({ success: false, error: 'UNAUTHORIZED', message: 'Missing x-user-uid' });
  const access = await getAiAccess(uid);
  const { user, ...safe } = access; // never leak the full user doc
  return res.json({ success: true, data: safe });
});

module.exports = router;
