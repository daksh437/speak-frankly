const express = require('express');
const { translate } = require('../controllers/tutorController');
const { requireAiAccess } = require('../middleware/aiAccess');

const router = express.Router();

// Premium-gated AI: translate a tutor line into the learner's native language.
router.post('/', requireAiAccess, async (req, res) => {
  try {
    const data = await translate(req);
    res.json({ success: true, data });
  } catch (e) {
    console.warn('[translate] route error:', e.message);
    res.json({ success: true, data: { translation: '' }, fallback: true });
  }
});

module.exports = router;
