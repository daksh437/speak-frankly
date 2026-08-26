const express = require('express');
const { speakingPhrases } = require('../controllers/tutorController');
const { requireAuxAccess, refundAuxIfFallback } = require('../middleware/aiAccess');

const router = express.Router();

// Metered against the daily AUX budget. The client caches one set per day, so a
// normal learner spends 1 — but the budget stops a scripted caller. The slot is
// CLAIMED by requireAuxAccess before the handler runs (so a burst of concurrent
// requests can't all pass the same check) and refunded if we end up serving the
// canned phrase list instead of AI.
router.post('/phrases', requireAuxAccess, async (req, res) => {
  try {
    const data = refundAuxIfFallback(req, await speakingPhrases(req));
    res.json({ success: true, data });
  } catch (e) {
    console.warn('[speaking] route error:', e.message);
    refundAuxIfFallback(req, { fallback: true });
    res.json({ success: true, data: { phrases: [] }, fallback: true });
  }
});

module.exports = router;
