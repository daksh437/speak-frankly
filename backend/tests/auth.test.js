/**
 * Auth + metering tests. These cover the money/identity rules, so they run with
 * DEV_SKIP_LIMITS OFF (the smoke test runs with it on, which bypasses everything).
 *
 * Hermetic by design: Firebase creds, Gemini key and DEV_SKIP_LIMITS are blanked
 * before the app is required, so nothing here touches production Firestore or
 * spends AI quota.
 *
 * Two modes, each in its own process because the env is read at module load:
 *   soft — REQUIRE_AUTH_TOKEN off: verified token preferred, legacy header still works
 *   hard — REQUIRE_AUTH_TOKEN on:  a bare x-user-uid header is rejected
 *
 * Usage: node tests/auth.test.js
 */
const path = require('path');
const { fork } = require('child_process');

const MODE = process.argv[2];

const HERMETIC = {
  DEV_SKIP_LIMITS: 'false',
  GEMINI_API_KEY: '',
  FIREBASE_SERVICE_ACCOUNT_JSON: '',
  GOOGLE_APPLICATION_CREDENTIALS: '',
};

function runMode(mode) {
  Object.assign(process.env, HERMETIC);
  if (mode === 'hard') process.env.REQUIRE_AUTH_TOKEN = 'true';

  const axios = require('axios');
  const { app } = require('../app');

  let failures = 0;
  const check = (name, cond) => {
    if (cond) console.log(`  ✅ ${name}`);
    else {
      console.error(`  ❌ ${name}`);
      failures++;
    }
  };

  return (async () => {
    const server = app.listen(0);
    const base = `http://127.0.0.1:${server.address().port}`;
    const any = { validateStatus: () => true };
    const claimed = { headers: { 'x-user-uid': 'someone-elses-uid' }, ...any };

    try {
      if (mode === 'soft') {
        console.log('\n— soft mode (REQUIRE_AUTH_TOKEN off) —');

        const noCreds = await axios.get(`${base}/progress`, any);
        check('GET /progress with no credentials → 401', noCreds.status === 401);

        const badToken = await axios.get(`${base}/progress`, {
          headers: { Authorization: 'Bearer not-a-real-token' },
          ...any,
        });
        check('GET /progress with an invalid token → 401', badToken.status === 401);

        const legacy = await axios.get(`${base}/progress`, claimed);
        check('GET /progress with legacy header → 200 (rollout grace)', legacy.status === 200);

        const auxNoCreds = await axios.post(`${base}/translate`, { text: 'hi', target: 'Hindi' }, any);
        check('POST /translate with no credentials → 401', auxNoCreds.status === 401);

        const rewardNoCreds = await axios.post(`${base}/access/reward-ad`, {}, any);
        check('POST /access/reward-ad with no credentials → 401', rewardNoCreds.status === 401);

        const premiumNoCreds = await axios.post(`${base}/premium/activate`, { purchaseToken: 'x' }, any);
        check('POST /premium/activate with no credentials → 401', premiumNoCreds.status === 401);

        const reportNoCreds = await axios.post(`${base}/report`, { text: 'bad reply' }, any);
        check('POST /report with no credentials → 401', reportNoCreds.status === 401);

        const reportOk = await axios.post(`${base}/report`, { text: 'bad reply', reason: 'offensive' }, claimed);
        check('POST /report signed in → accepted', reportOk.status === 200 && reportOk.data?.data?.ok === true);

        const reportEmpty = await axios.post(`${base}/report`, { text: '   ' }, claimed);
        check('POST /report with empty text → 400', reportEmpty.status === 400);

        const me = await axios.get(`${base}/admin/me`, claimed);
        check('GET /admin/me with a claimed uid → not admin', me.data?.data?.isAdmin === false);
        check('GET /admin/me with a claimed uid → leaks no email', me.data?.data?.email === null);

        const adminAction = await axios.get(`${base}/admin/stats`, claimed);
        check('GET /admin/stats with a claimed uid → 401 (verified token required)', adminAction.status === 401);

        const health = await axios.get(`${base}/health`);
        check('GET /health → reports auth mode', health.data?.auth?.requireAuthToken === false);
        check('GET /health → reports the model chain', Array.isArray(health.data?.ai?.models) && health.data.ai.models.length > 1);
      } else {
        console.log('\n— hard mode (REQUIRE_AUTH_TOKEN on) —');

        const legacy = await axios.get(`${base}/progress`, claimed);
        check('GET /progress with legacy header → 401', legacy.status === 401);

        const aux = await axios.post(`${base}/translate`, { text: 'hi', target: 'Hindi' }, claimed);
        check('POST /translate with legacy header → 401', aux.status === 401);

        const chat = await axios.post(`${base}/tutor/chat`, { messages: [{ role: 'user', text: 'hi' }] }, claimed);
        check('POST /tutor/chat with legacy header → 401', chat.status === 401);

        const health = await axios.get(`${base}/health`);
        check('GET /health → reports token required', health.data?.auth?.requireAuthToken === true);
      }
    } catch (e) {
      console.error('  ❌ threw:', e.message);
      failures++;
    } finally {
      server.close();
    }

    process.exit(failures === 0 ? 0 : 1);
  })();
}

if (MODE) {
  runMode(MODE);
} else {
  // Parent: run each mode in a fresh process (env is read at module load).
  const modes = ['soft', 'hard'];
  let failed = 0;
  (async () => {
    for (const mode of modes) {
      const code = await new Promise((resolve) => {
        fork(path.join(__dirname, 'auth.test.js'), [mode], { stdio: 'inherit' }).on('exit', resolve);
      });
      if (code !== 0) failed++;
    }
    if (failed === 0) {
      console.log('\n✅ All auth checks passed.');
      process.exit(0);
    }
    console.error(`\n❌ ${failed} auth mode(s) failed.`);
    process.exit(1);
  })();
}
