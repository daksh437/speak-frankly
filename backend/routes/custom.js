const express = require('express');
const { customScenario } = require('../controllers/tutorController');

const router = express.Router();

// Not metered: one AI call to build a scenario from the learner's topic. The
// conversation that follows (/tutor/chat) is metered normally.
router.post('/scenario', async (req, res) => {
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
