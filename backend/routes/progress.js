const express = require('express');
const { getProgress, saveProgress } = require('../controllers/progressController');

const router = express.Router();

function uidOf(req) {
  return (req.headers['x-user-uid'] || req.headers['x-user-id'] || '').toString().trim();
}

router.get('/', async (req, res) => {
  const uid = uidOf(req);
  if (!uid) return res.status(401).json({ success: false, error: 'UNAUTHORIZED' });
  const data = await getProgress(uid);
  res.json({ success: true, data });
});

router.post('/', async (req, res) => {
  const uid = uidOf(req);
  if (!uid) return res.status(401).json({ success: false, error: 'UNAUTHORIZED' });
  const result = await saveProgress(uid, req.body);
  res.json({ success: true, data: result });
});

module.exports = router;
