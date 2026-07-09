const express = require('express');
const { requireAiAccess, wrapAiHandler } = require('../middleware/aiAccess');
const { buildAiFallback } = require('../utils/aiFallback');
const { chat, feedback } = require('../controllers/tutorController');

const router = express.Router();

// Every tutor AI call is metered by the plan (trial/free/premium).
router.use((req, res, next) => {
  req._aiEndpoint = `/tutor${req.path}`;
  requireAiAccess(req, res, next);
});

router.post('/chat', wrapAiHandler(chat, (req) => buildAiFallback('/tutor/chat', req.body)));
router.post('/feedback', wrapAiHandler(feedback, (req) => buildAiFallback('/tutor/feedback', req.body)));

module.exports = router;
