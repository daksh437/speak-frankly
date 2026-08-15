const express = require('express');
const { define } = require('../controllers/dictionaryController');
const { authenticate } = require('../middleware/auth');

const router = express.Router();

// The dictionary card is public (cheap, cached, free upstream API). We still
// resolve the caller so the optional ?target= translation — which IS a Gemini
// call — can be budgeted per learner; anonymous callers just get no translation.
router.get('/:word', async (req, _res, next) => {
  await authenticate(req);
  next();
}, define);

module.exports = router;
