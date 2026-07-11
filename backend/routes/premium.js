const express = require('express');
const { activatePremium } = require('../controllers/premiumController');

const router = express.Router();

function uidOf(req) {
  return (req.headers['x-user-uid'] || req.headers['x-user-id'] || '').toString().trim();
}

// Called by the app after a confirmed Google Play subscription purchase.
router.post('/activate', async (req, res) => {
  const uid = uidOf(req);
  if (!uid) return res.status(401).json({ success: false, error: 'UNAUTHORIZED' });
  const data = await activatePremium(uid, req.body);
  res.json({ success: true, data });
});

module.exports = router;
