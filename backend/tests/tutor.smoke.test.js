/**
 * Smoke test: boots the app on a random port and hits the core endpoints.
 * Runs with no keys (MOCK tutor + degraded Firestore + DEV_SKIP_LIMITS).
 * Usage: node tests/tutor.smoke.test.js
 */
process.env.DEV_SKIP_LIMITS = 'true';
// Hermetic: without these blanked, dotenv hands the test the REAL service
// account and Gemini key — so every `npm test` used to write junk user docs
// (test-user-1, deploy-smoke-test-…) into production Firestore and spend AI
// quota on a canned chat turn.
process.env.FIREBASE_SERVICE_ACCOUNT_JSON = '';
process.env.GOOGLE_APPLICATION_CREDENTIALS = '';
process.env.GEMINI_API_KEY = '';
const axios = require('axios');
const { app } = require('../app');

let failures = 0;
function check(name, cond) {
  if (cond) {
    console.log(`  ✅ ${name}`);
  } else {
    console.error(`  ❌ ${name}`);
    failures++;
  }
}

(async () => {
  const server = app.listen(0);
  const port = server.address().port;
  const base = `http://127.0.0.1:${port}`;
  const H = { 'x-user-uid': 'test-user-1' };

  try {
    const health = await axios.get(`${base}/health`);
    check('GET /health → ok', health.data.success === true);

    const scenarios = await axios.get(`${base}/scenarios`);
    check('GET /scenarios → non-empty array', Array.isArray(scenarios.data.data) && scenarios.data.data.length > 0);
    check('GET /scenarios → hides internal setup', scenarios.data.data.every((s) => s.setup === undefined));

    const one = await axios.get(`${base}/scenarios/job-interview`);
    check('GET /scenarios/:id → title present', one.data.data.title === 'Job Interview');

    const chat = await axios.post(`${base}/tutor/chat`, {
      scenarioId: 'ordering-food',
      level: 'A1',
      nativeLanguage: 'Hindi',
      messages: [{ role: 'user', text: 'I want one coffee please' }],
    }, { headers: H });
    check('POST /tutor/chat → returns reply', typeof chat.data.data.reply === 'string' && chat.data.data.reply.length > 0);
    check('POST /tutor/chat → corrections array', Array.isArray(chat.data.data.corrections));

    const dict = await axios.get(`${base}/dictionary/delicious`, { validateStatus: () => true });
    // Network may be offline in CI; accept either a card or a clean 404/handled error.
    check('GET /dictionary/:word → responds', dict.status === 200 || dict.status === 404);

    const access = await axios.get(`${base}/access`, { headers: H, validateStatus: () => true });
    check('GET /access → responds', access.status === 200);

    // The public endpoints take no account, so the per-learner AI budget can't
    // protect them — the rate limiter has to. /scenarios is served from memory,
    // so this stays fast and hits no third party.
    let limited = 0;
    for (let i = 0; i < 65; i++) {
      const r = await axios.get(`${base}/scenarios`, { validateStatus: () => true });
      if (r.status === 429) limited++;
    }
    check('GET /scenarios → rate limited past the window cap', limited > 0);

    // A conversation turn is billed as one message however long the transcript
    // is, so the server must clamp the history the client sends.
    const { trimHistory, MAX_CHAT_TURNS } = require('../controllers/tutorController');
    const long = Array.from({ length: 200 }, (_, i) => ({ role: i % 2 ? 'model' : 'user', text: `turn ${i}` }));
    const trimmed = trimHistory(long, MAX_CHAT_TURNS);
    check('trimHistory → keeps only the most recent turns', trimmed.length === MAX_CHAT_TURNS);
    check('trimHistory → keeps the NEWEST turns', trimmed[trimmed.length - 1].text === 'turn 199');
    check('trimHistory → clips an oversized message', trimHistory([{ role: 'user', text: 'x'.repeat(50000) }], 5)[0].text.length <= 2000);
    check('trimHistory → drops empty/malformed turns', trimHistory([{ role: 'user', text: '  ' }, null, { role: 'user', text: 'ok' }], 5).length === 1);
  } catch (e) {
    console.error('  ❌ threw:', e.message);
    failures++;
  } finally {
    server.close();
  }

  if (failures === 0) {
    console.log('\n✅ All smoke checks passed.');
    process.exit(0);
  } else {
    console.error(`\n❌ ${failures} check(s) failed.`);
    process.exit(1);
  }
})();
