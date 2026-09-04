/**
 * Reporting offensive / inappropriate AI output.
 *
 * Google Play's generative-AI policy requires an in-app way for users to report
 * AI-generated content they find offensive, and for the developer to act on it.
 * The app shows a "Report" action under every tutor reply; this endpoint stores
 * the report in Firestore (`ai_reports`) where the owner reviews it from the
 * in-app admin panel (GET /admin/reports).
 *
 * Reporting must never feel broken: if Firestore is unavailable we still answer
 * ok so the learner gets their "thanks, we'll review it" confirmation.
 */
const express = require('express');
const { getDb } = require('../utils/firestoreAdmin');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();
const REPORTS = 'ai_reports';

// Cheap in-memory spam guard (per instance): a real learner reports a handful of
// lines, not hundreds. Keeps a flood from writing unbounded documents.
const MAX_PER_HOUR = 20;
const WINDOW_MS = 60 * 60 * 1000;
const hits = new Map(); // uid -> { count, windowStart }

// Expired windows are dropped on a timer, because nothing else ever removed
// them: an entry was added for every uid that ever reported and kept for the
// life of the process, so the guard against unbounded documents was itself an
// unbounded map. unref() keeps it from holding the process (or a test run) open.
const sweep = setInterval(() => {
  const cutoff = Date.now() - WINDOW_MS;
  for (const [uid, h] of hits) {
    if (h.windowStart < cutoff) hits.delete(uid);
  }
}, WINDOW_MS);
if (typeof sweep.unref === 'function') sweep.unref();

function overLimit(uid) {
  const now = Date.now();
  const h = hits.get(uid);
  if (!h || now - h.windowStart > WINDOW_MS) {
    hits.set(uid, { count: 1, windowStart: now });
    return false;
  }
  h.count++;
  return h.count > MAX_PER_HOUR;
}

const REASONS = ['offensive', 'wrong', 'unsafe', 'other'];

router.post('/', requireAuth, async (req, res) => {
  const body = req.body || {};
  const text = String(body.text || '').trim().slice(0, 2000);
  if (!text) return res.status(400).json({ success: false, error: 'TEXT_REQUIRED' });

  const reasonRaw = String(body.reason || 'other').toLowerCase().trim();
  const reason = REASONS.includes(reasonRaw) ? reasonRaw : 'other';

  if (overLimit(req.uid)) {
    return res.status(429).json({ success: false, error: 'TOO_MANY_REPORTS' });
  }

  const db = getDb();
  if (!db) return res.json({ success: true, data: { ok: true, stored: false } });

  try {
    await db.collection(REPORTS).add({
      uid: req.uid,
      email: req.authEmail || null,
      text,
      reason,
      note: String(body.note || '').trim().slice(0, 500),
      scenarioId: String(body.scenarioId || '').slice(0, 60),
      level: String(body.level || '').slice(0, 8),
      status: 'new',
      createdAt: new Date(),
    });
    console.warn(`[report] AI content reported (${reason}) by ${req.uid}`);
    return res.json({ success: true, data: { ok: true, stored: true } });
  } catch (e) {
    console.warn('[report] store error:', e.message);
    return res.json({ success: true, data: { ok: true, stored: false } });
  }
});

module.exports = router;
