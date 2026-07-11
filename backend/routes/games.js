const express = require('express');
const { pictureMatch } = require('../controllers/tutorController');
const { requireAiAccess } = require('../middleware/aiAccess');

const router = express.Router();

// Premium-gated AI. The client caches one set of items per day (~1 call/day).
router.post('/picture-match', requireAiAccess, async (req, res) => {
  try {
    const data = await pictureMatch(req);
    res.json({ success: true, data });
  } catch (e) {
    console.warn('[games] route error:', e.message);
    res.json({ success: true, data: { items: [] }, fallback: true });
  }
});

module.exports = router;
