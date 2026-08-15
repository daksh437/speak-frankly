const express = require('express');
const { getProgress, saveProgress } = require('../controllers/progressController');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();

// requireAuth resolves the uid from the verified ID token (falling back to the
// legacy header only while REQUIRE_AUTH_TOKEN is off). Never take the uid from
// the request body/params here: that would let anyone read or overwrite another
// learner's vocabulary, XP and profile.
router.get('/', requireAuth, async (req, res) => {
  const data = await getProgress(req.uid);
  res.json({ success: true, data });
});

router.post('/', requireAuth, async (req, res) => {
  const result = await saveProgress(req.uid, req.body);
  res.json({ success: true, data: result });
});

module.exports = router;
