const express = require('express');
const { requireAiAccess, requireMessageSlot, wrapAiHandler } = require('../middleware/aiAccess');
const { buildAiFallback } = require('../utils/aiFallback');
const { chat, feedback } = require('../controllers/tutorController');

const router = express.Router();

// Every tutor AI call is metered by the plan (trial/free/premium).
router.use((req, res, next) => {
  req._aiEndpoint = `/tutor${req.path}`;
  requireAiAccess(req, res, next);
});

// /chat additionally CLAIMS one of today's messages before the AI runs, in a
// transaction — see requireMessageSlot. /feedback stays free: the end-of-session
// report shouldn't cost a learner one of their daily messages.
router.post('/chat', requireMessageSlot, wrapAiHandler(chat, (req) => buildAiFallback('/tutor/chat', req.body)));
router.post('/feedback', wrapAiHandler(feedback, (req) => buildAiFallback('/tutor/feedback', req.body)));

module.exports = router;
