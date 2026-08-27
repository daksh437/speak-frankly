const express = require('express');
const { translate } = require('../controllers/tutorController');
const { requireAuxAccess, refundAuxIfFallback } = require('../middleware/aiAccess');

const router = express.Router();

// Metered against the daily AUX budget (not the learner's chat messages).
// Previously this only checked plan access and never counted, so a free user —
// or anyone with a uid — could call it in a loop for unlimited Gemini calls.
// The slot is now claimed BEFORE the call (so concurrent requests can't all
// pass one stale check) and refunded when no translation comes back.
router.post('/', requireAuxAccess, async (req, res) => {
  try {
    const data = refundAuxIfFallback(req, await translate(req));
    res.json({ success: true, data });
  } catch (e) {
    console.warn('[translate] route error:', e.message);
    refundAuxIfFallback(req, { fallback: true });
    res.json({ success: true, data: { translation: '' }, fallback: true });
  }
});

module.exports = router;
