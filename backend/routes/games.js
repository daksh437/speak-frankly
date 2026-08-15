const express = require('express');
const { pictureMatch } = require('../controllers/tutorController');
const { requireAuxAccess, recordAuxUsage } = require('../middleware/aiAccess');

const router = express.Router();

// Metered against the daily AUX budget. The client caches one set per day.
router.post('/picture-match', requireAuxAccess, async (req, res) => {
  try {
    const data = await pictureMatch(req);
    if (!data.fallback && !data.mock) recordAuxUsage(req.uid).catch(() => {});
    res.json({ success: true, data });
  } catch (e) {
    console.warn('[games] route error:', e.message);
    res.json({ success: true, data: { items: [] }, fallback: true });
  }
});

module.exports = router;
