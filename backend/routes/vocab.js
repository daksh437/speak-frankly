const express = require('express');
const { extractVocab } = require('../controllers/tutorController');
const { requireAiAccess } = require('../middleware/aiAccess');

const router = express.Router();

// Premium-gated AI: pull vocabulary out of pasted text.
router.post('/extract', requireAiAccess, async (req, res) => {
  try {
    const data = await extractVocab(req);
    res.json({ success: true, data });
  } catch (e) {
    console.warn('[vocab] route error:', e.message);
    res.json({ success: true, data: { words: [] }, fallback: true });
  }
});

module.exports = router;
