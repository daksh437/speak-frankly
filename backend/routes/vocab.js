const express = require('express');
const { extractVocab } = require('../controllers/tutorController');
const { requireAuxAccess, recordAuxUsage } = require('../middleware/aiAccess');

const router = express.Router();

// Metered against the daily AUX budget: pull vocabulary out of pasted text.
router.post('/extract', requireAuxAccess, async (req, res) => {
  try {
    const data = await extractVocab(req);
    if (data.words && data.words.length) recordAuxUsage(req.uid).catch(() => {});
    res.json({ success: true, data });
  } catch (e) {
    console.warn('[vocab] route error:', e.message);
    res.json({ success: true, data: { words: [] }, fallback: true });
  }
});

module.exports = router;
