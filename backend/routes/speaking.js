const express = require('express');
const { speakingPhrases } = require('../controllers/tutorController');
const { requireAuxAccess, recordAuxUsage } = require('../middleware/aiAccess');

const router = express.Router();

// Metered against the daily AUX budget. The client caches one set per day, so
// a normal learner spends 1 — but the budget stops a scripted caller.
router.post('/phrases', requireAuxAccess, async (req, res) => {
  try {
    const data = await speakingPhrases(req);
    if (!data.fallback && !data.mock) recordAuxUsage(req.uid).catch(() => {});
    res.json({ success: true, data });
  } catch (e) {
    console.warn('[speaking] route error:', e.message);
    res.json({ success: true, data: { phrases: [] }, fallback: true });
  }
});

module.exports = router;
