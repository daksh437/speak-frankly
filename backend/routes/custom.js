const express = require('express');
const { customScenario } = require('../controllers/tutorController');
const { requireAiAccess } = require('../middleware/aiAccess');

const router = express.Router();

// Premium-gated AI: build a scenario from the learner's topic.
router.post('/scenario', requireAiAccess, async (req, res) => {
  try {
    const data = await customScenario(req);
    if (data.error) return res.status(400).json({ success: false, error: data.error });
    res.json({ success: true, data });
  } catch (e) {
    console.warn('[custom] route error:', e.message);
    res.status(500).json({ success: false, error: 'GENERATION_FAILED' });
  }
});

module.exports = router;
