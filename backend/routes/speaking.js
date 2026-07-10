const express = require('express');
const { speakingPhrases } = require('../controllers/tutorController');

const router = express.Router();

// Not metered: the client caches one set of phrases per day, so this is ~1
// Gemini call/day/device. Always returns usable phrases (graceful fallback).
router.post('/phrases', async (req, res) => {
  try {
    const data = await speakingPhrases(req);
    res.json({ success: true, data });
  } catch (e) {
    console.warn('[speaking] route error:', e.message);
    res.json({ success: true, data: { phrases: [] }, fallback: true });
  }
});

module.exports = router;
