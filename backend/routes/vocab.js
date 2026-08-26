const express = require('express');
const { extractVocab } = require('../controllers/tutorController');
const { requireAuxAccess, refundAuxIfFallback } = require('../middleware/aiAccess');

const router = express.Router();

// Metered against the daily AUX budget: pull vocabulary out of pasted text.
// Claimed up front; refunded when we fall back to the local keyword extractor.
router.post('/extract', requireAuxAccess, async (req, res) => {
  try {
    const data = refundAuxIfFallback(req, await extractVocab(req));
    res.json({ success: true, data });
  } catch (e) {
    console.warn('[vocab] route error:', e.message);
    refundAuxIfFallback(req, { fallback: true });
    res.json({ success: true, data: { words: [] }, fallback: true });
  }
});

module.exports = router;
