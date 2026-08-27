const express = require('express');
const { customScenario } = require('../controllers/tutorController');
const { requireAuxAccess, refundAuxIfFallback } = require('../middleware/aiAccess');

const router = express.Router();

// Metered against the daily AUX budget: build a scenario from the learner's
// topic. The chat that follows is metered normally (chat messages). A rejected
// request or a template-only scenario refunds the claimed slot.
router.post('/scenario', requireAuxAccess, async (req, res) => {
  try {
    const data = await customScenario(req);
    if (data.error) {
      refundAuxIfFallback(req, { fallback: true });
      return res.status(400).json({ success: false, error: data.error });
    }
    res.json({ success: true, data: refundAuxIfFallback(req, data) });
  } catch (e) {
    console.warn('[custom] route error:', e.message);
    refundAuxIfFallback(req, { fallback: true });
    res.status(500).json({ success: false, error: 'GENERATION_FAILED' });
  }
});

module.exports = router;
