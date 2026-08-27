const express = require('express');
const { pictureMatch } = require('../controllers/tutorController');
const { requireAuxAccess, refundAuxIfFallback } = require('../middleware/aiAccess');

const router = express.Router();

// Metered against the daily AUX budget (claimed up front, refunded when the
// learner gets the bundled item set instead of AI). The client caches one set
// per day.
router.post('/picture-match', requireAuxAccess, async (req, res) => {
  try {
    const data = refundAuxIfFallback(req, await pictureMatch(req));
    res.json({ success: true, data });
  } catch (e) {
    console.warn('[games] route error:', e.message);
    refundAuxIfFallback(req, { fallback: true });
    res.json({ success: true, data: { items: [] }, fallback: true });
  }
});

module.exports = router;
