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
// /chat is metered by the plan (trial/free/premium) and CLAIMS one of today's
// messages before the AI runs, in a transaction — see requireMessageSlot.
router.post(
  '/chat',
  requireAiAccess,
  requireMessageSlot,
  wrapAiHandler(chat, (req) => buildAiFallback('/tutor/chat', req.body)),
);

// /feedback is metered against the AUX budget: an end-of-session report should
// not cost one of the daily messages, but it cannot be free either — it is an
// unbounded Gemini endpoint (6k chars in, 600 tokens out, per call). A real
// learner spends one per session; a script runs out. A report served from the
// canned fallback refunds the slot.
//
// requireAiAccess deliberately does NOT run here. It used to, mounted on the
// whole router, and it rejects a free learner the moment their daily MESSAGES
// are gone — which is exactly when a session ends and the report is asked for.
// Every learner who used their full allowance got an empty report; the ones who
// practised most never saw one at all.
router.post('/feedback', requireAuxAccess, wrapAiHandler(feedback, (req) => buildAiFallback('/tutor/feedback', req.body)));

module.exports = router;
