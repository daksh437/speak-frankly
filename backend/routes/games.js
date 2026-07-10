const express = require('express');
const { pictureMatch } = require('../controllers/tutorController');

const router = express.Router();

// Not metered: the client caches one set of items per day (~1 Gemini call/day).
router.post('/picture-match', async (req, res) => {
  try {
    const data = await pictureMatch(req);
    res.json({ success: true, data });
  } catch (e) {
    console.warn('[games] route error:', e.message);
    res.json({ success: true, data: { items: [] }, fallback: true });
  }
});

module.exports = router;
