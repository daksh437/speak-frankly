const express = require('express');
const { translate } = require('../controllers/tutorController');
const { requireAuxAccess, recordAuxUsage } = require('../middleware/aiAccess');

const router = express.Router();

// Metered against the daily AUX budget (not the learner's chat messages).
// Previously this only checked plan access and never counted, so a free user —
// or anyone with a uid — could call it in a loop for unlimited Gemini calls.
router.post('/', requireAuxAccess, async (req, res) => {
  try {
    const data = await translate(req);
    if (data.translation) recordAuxUsage(req.uid).catch(() => {});
    res.json({ success: true, data });
  } catch (e) {
    console.warn('[translate] route error:', e.message);
    res.json({ success: true, data: { translation: '' }, fallback: true });
  }
});

module.exports = router;
