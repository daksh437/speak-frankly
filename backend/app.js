/**
 * Speak Frankly backend — AI English tutor.
 * Entry point (mirrors InstaFlow: app.js, not index.js). Mounts:
 *   GET  /health            liveness
 *   GET  /scenarios         scenario library (public)
 *   GET  /scenarios/:id     one scenario (public)
 *   GET  /dictionary/:word  dictionary card (+ optional ?target= translation)
 *   GET  /access            learner's plan + remaining messages
 *   POST /tutor/chat        AI conversation turn (metered: daily messages)
 *   POST /tutor/feedback    end-of-session report (metered: daily aux budget)
 *   POST /report            report offensive AI output (Play GenAI policy)
 *   DELETE /account         erase your own account + data (Play deletion policy)
 *
 * Runs with zero external services: no GEMINI_API_KEY → MOCK tutor; no Firebase
 * → degraded (allow-through) mode. Wire keys via .env when ready.
 */
require('dotenv').config();
const express = require('express');
const cors = require('cors');

const tutorRoutes = require('./routes/tutor');
const dictionaryRoutes = require('./routes/dictionary');
const scenarioRoutes = require('./routes/scenarios');
const accessRoutes = require('./routes/access');
const speakingRoutes = require('./routes/speaking');
const customRoutes = require('./routes/custom');
const progressRoutes = require('./routes/progress');
const gamesRoutes = require('./routes/games');
const vocabRoutes = require('./routes/vocab');
const { hasKey, MODEL, MODELS, getAiStats } = require('./utils/geminiClient');
const { getInitStatus } = require('./utils/firestoreAdmin');
const { getAuthStats, REQUIRE_AUTH_TOKEN } = require('./middleware/auth');
const { DEV_SKIP_LIMITS, DAILY_MESSAGES_FREE, REQUIRE_PREMIUM } = require('./middleware/aiAccess');
const { rateLimit } = require('./middleware/rateLimit');

const app = express();
const PORT = process.env.PORT || 10000;
const NODE_ENV = process.env.NODE_ENV || 'development';
const IS_PROD = NODE_ENV === 'production';

// Render terminates TLS in front of us, so the client's real address is only in
// X-Forwarded-For — without this req.ip is the proxy for every caller, which
// would make the rate limiter treat all traffic as one client.
app.set('trust proxy', 1);

app.use(express.json({ limit: '2mb' }));
app.use(express.urlencoded({ extended: true, limit: '2mb' }));

const corsOrigins = (process.env.CORS_ORIGINS || '')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);
app.use(cors(corsOrigins.length ? { origin: corsOrigins } : {}));

if (!IS_PROD) {
  app.use((req, _res, next) => {
    console.log(`[${new Date().toISOString()}] ${req.method} ${req.path}`);
    next();
  });
}

app.get('/', (_req, res) => res.json({ success: true, message: 'Speak Frankly Backend API' }));

// WHICH BUILD IS THIS? Render sets RENDER_GIT_COMMIT on every deploy. Without
// it there is no way to tell a deployed change from an undeployed one from
// outside — this service once ran commits behind main for days because /health
// looked identical either way. `startedAt` separates "my push went live" from
// "the free instance just woke up from a spin-down".
const COMMIT = (process.env.RENDER_GIT_COMMIT || process.env.GIT_COMMIT || '').slice(0, 7) || 'unknown';
const STARTED_AT = new Date().toISOString();

/**
 * Liveness + operational truth. `ai` shows whether the model chain is actually
 * serving (fallbacks/failed > 0 means learners are getting canned replies), and
 * `auth.legacyHeader` shows how many callers are still on an app build that
 * doesn't send an ID token — flip REQUIRE_AUTH_TOKEN=true once that flatlines.
 */
app.get('/health', (_req, res) =>
  res.json({
    status: 'ok',
    success: true,
    commit: COMMIT,
    startedAt: STARTED_AT,
    ai: getAiStats(),
    auth: getAuthStats(),
  }));

app.use('/', require('./routes/legal')); // GET /privacy, /terms (public HTML)

// The public endpoints take no account, so per-learner budgets don't apply —
// cap them per client instead. /dictionary is the tighter of the two: it
// proxies a free third-party API we don't want to get throttled out of.
app.use('/scenarios', rateLimit({ windowMs: 60_000, max: 60, name: 'scenarios' }), scenarioRoutes);
app.use('/dictionary', rateLimit({ windowMs: 60_000, max: 30, name: 'dictionary' }), dictionaryRoutes);
app.use('/access', accessRoutes);
app.use('/account', require('./routes/account')); // DELETE /account (in-app deletion)
app.use('/speaking', speakingRoutes);
app.use('/custom', customRoutes);
app.use('/progress', progressRoutes);
app.use('/games', gamesRoutes);
app.use('/vocab', vocabRoutes);
app.use('/report', require('./routes/report'));
app.use('/premium', require('./routes/premium'));
app.use('/translate', require('./routes/translate'));
app.use('/admin', require('./routes/admin'));
app.use('/tutor', tutorRoutes);

// Graceful catch-all for AI paths so a learner never sees a raw 500 mid-chat.
// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  console.error('[ERROR]', req.method, req.path, err?.message || err);
  if (!res.headersSent && req.path.startsWith('/tutor/')) {
    return res.json({
      success: true,
      data: { reply: "Sorry, something went wrong — let's try that again. 🙂", corrections: [], suggestions: [], translation: null },
      fallback: true,
    });
  }
  if (!res.headersSent) res.status(500).json({ success: false, error: 'INTERNAL_SERVER_ERROR' });
});

function startServer() {
  if (IS_PROD && DEV_SKIP_LIMITS) {
    throw new Error('DEV_SKIP_LIMITS must NOT be enabled in production.');
  }
  const fb = getInitStatus();
  return app.listen(PORT, '0.0.0.0', () => {
    console.log(`🚀 Speak Frankly backend on port ${PORT} (${NODE_ENV})`);
    console.log(`🤖 Gemini: ${hasKey() ? `REAL (${MODEL}) → fallbacks: ${MODELS.slice(1).join(', ') || 'none'}` : 'MOCK MODE (no GEMINI_API_KEY)'}`);
    console.log(`🔥 Firestore: ${fb.firestoreReady ? `ready (${fb.projectId})` : 'degraded / not configured'}`);
    console.log(`🔐 Auth: ${REQUIRE_AUTH_TOKEN ? 'ID token REQUIRED' : 'ID token preferred, legacy x-user-uid still accepted'}`);
    console.log(`🎫 Plan: ${REQUIRE_PREMIUM ? 'premium required for AI (no free tier)' : `free ${DAILY_MESSAGES_FREE} msg/day`} → premium unlimited`);
    if (DEV_SKIP_LIMITS) console.log('⚠️  DEV_SKIP_LIMITS on — limits bypassed.');
    console.log(`📊 Health: http://localhost:${PORT}/health`);
  });
}

if (require.main === module) startServer();

module.exports = { app, startServer };
