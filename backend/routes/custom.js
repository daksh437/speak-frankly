const express = require('express');
const { customScenario } = require('../controllers/tutorController');
const { requireAuxAccess, recordAuxUsage } = require('../middleware/aiAccess');

const router = express.Router();

// Metered against the daily AUX budget: build a scenario from the learner's
// topic. The chat that follows is metered normally (chat messages).
router.post('/scenario', requireAuxAccess, async (req, res) => {
  try {
    const data = await customScenario(req);
    if (data.error) return res.status(400).json({ success: false, error: data.error });
    recordAuxUsage(req.uid).catch(() => {});
    res.json({ success: true, data });
  } catch (e) {
    console.warn('[custom] route error:', e.message);
    res.status(500).json({ success: false, error: 'GENERATION_FAILED' });
  }
});

module.exports = router;
