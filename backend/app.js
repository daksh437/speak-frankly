/**
 * Speak Frankly backend — AI English tutor.
 * Entry point (mirrors InstaFlow: app.js, not index.js). Mounts:
 *   GET  /health            liveness
 *   GET  /scenarios         scenario library (public)
 *   GET  /scenarios/:id     one scenario (public)
 *   GET  /dictionary/:word  dictionary card (+ optional ?target= translation)
 *   GET  /access            learner's plan + remaining messages
 *   POST /tutor/chat        AI conversation turn (metered)
 *   POST /tutor/feedback    end-of-session report (metered)
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
const { hasKey, MODEL } = require('./utils/geminiClient');
const { getInitStatus } = require('./utils/firestoreAdmin');
const { DEV_SKIP_LIMITS, DAILY_MESSAGES_FREE, TRIAL_DAYS } = require('./middleware/aiAccess');

const app = express();
const PORT = process.env.PORT || 10000;
const NODE_ENV = process.env.NODE_ENV || 'development';
const IS_PROD = NODE_ENV === 'production';

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
app.get('/health', (_req, res) => res.json({ status: 'ok', success: true }));

app.use('/scenarios', scenarioRoutes);
app.use('/dictionary', dictionaryRoutes);
app.use('/access', accessRoutes);
app.use('/speaking', speakingRoutes);
app.use('/custom', customRoutes);
app.use('/progress', progressRoutes);
app.use('/games', gamesRoutes);
app.use('/vocab', vocabRoutes);
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
    console.log(`🤖 Gemini: ${hasKey() ? `REAL (${MODEL})` : 'MOCK MODE (no GEMINI_API_KEY)'}`);
    console.log(`🔥 Firestore: ${fb.firestoreReady ? `ready (${fb.projectId})` : 'degraded / not configured'}`);
    console.log(`🎫 Plan: trial ${TRIAL_DAYS}d unlimited → free ${DAILY_MESSAGES_FREE} msg/day → premium unlimited`);
    if (DEV_SKIP_LIMITS) console.log('⚠️  DEV_SKIP_LIMITS on — limits bypassed.');
    console.log(`📊 Health: http://localhost:${PORT}/health`);
  });
}

if (require.main === module) startServer();

module.exports = { app, startServer };
