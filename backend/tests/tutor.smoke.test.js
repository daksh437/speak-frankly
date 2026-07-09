/**
 * Smoke test: boots the app on a random port and hits the core endpoints.
 * Runs with no keys (MOCK tutor + degraded Firestore + DEV_SKIP_LIMITS).
 * Usage: node tests/tutor.smoke.test.js
 */
process.env.DEV_SKIP_LIMITS = 'true';
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
