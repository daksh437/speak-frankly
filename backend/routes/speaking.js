const express = require('express');
const { speakingPhrases } = require('../controllers/tutorController');
const { requireAiAccess } = require('../middleware/aiAccess');

const router = express.Router();

// Premium-gated AI. The client caches one set of phrases per day (~1 call/day).
router.post('/phrases', requireAiAccess, async (req, res) => {
  try {
    const data = await speakingPhrases(req);
    res.json({ success: true, data });
  } catch (e) {
    console.warn('[speaking] route error:', e.message);
    res.json({ success: true, data: { phrases: [] }, fallback: true });
  }
});

module.exports = router;
