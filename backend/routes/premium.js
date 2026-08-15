const express = require('express');
const { activatePremium } = require('../controllers/premiumController');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();

// Called by the app after a confirmed Google Play subscription purchase.
// The purchase token is verified against the Play API (premiumController); the
// uid it's granted to comes from the verified sign-in, not from the client.
router.post('/activate', requireAuth, async (req, res) => {
  const data = await activatePremium(req.uid, req.body);
  res.json({ success: true, data });
});

module.exports = router;
