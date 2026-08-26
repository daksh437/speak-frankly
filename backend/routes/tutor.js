const express = require('express');
const { requireAiAccess, requireAuxAccess, requireMessageSlot, wrapAiHandler } = require('../middleware/aiAccess');
const { buildAiFallback } = require('../utils/aiFallback');
const { rateLimit } = require('../middleware/rateLimit');
const { chat, feedback } = require('../controllers/tutorController');

const router = express.Router();

// Belt-and-braces on top of the per-learner budgets below: a burst this far
// past a real conversation's pace is a script, not a learner, and it should
// cost us nothing to say no. Keyed per client IP, well above human usage.
router.use(rateLimit({ windowMs: 60_000, max: 30, name: 'tutor' }));

// Every tutor AI call is metered by the plan (trial/free/premium).
router.use((req, res, next) => {
  req._aiEndpoint = `/tutor${req.path}`;
  requireAiAccess(req, res, next);
});

// /chat CLAIMS one of today's messages before the AI runs, in a transaction —
// see requireMessageSlot.
router.post('/chat', requireMessageSlot, wrapAiHandler(chat, (req) => buildAiFallback('/tutor/chat', req.body)));

// /feedback used to be free: requireAiAccess checked the plan but nothing was
// ever claimed or counted, so a signed-in learner who never chatted sat at
// dailyUsed = 0 forever and could call this in a loop — an unbounded Gemini
// endpoint (6k chars in, 600 tokens out, per call) on our bill.
//
// It is now metered against the AUX budget rather than chat messages: an
// end-of-session report still shouldn't cost one of the 8 daily messages, but
// it can't be free either. A real learner spends one per session; a script runs
// out. A report served from the canned fallback refunds the slot.
router.post('/feedback', requireAuxAccess, wrapAiHandler(feedback, (req) => buildAiFallback('/tutor/feedback', req.body)));

module.exports = router;
