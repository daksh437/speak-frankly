/**
 * Metering tests — the rules that decide what an AI call costs.
 *
 * These exist because the expensive bugs in this service have all been the same
 * shape: an endpoint that calls Gemini but never claims anything, so a loop
 * against it is free for the caller and unbounded for us. /translate was one.
 * /tutor/feedback was another (it checked the plan, then charged nothing, so a
 * learner sitting at 0 used messages could call it forever).
 *
 * Hermetic: no Firebase creds, no Gemini key, DEV_SKIP_LIMITS off — so nothing
 * here touches production Firestore or spends AI quota. Without Firestore the
 * budget itself is in degraded allow-through mode by design, so these tests
 * cover the parts that hold regardless: the auth gate, the reserve/refund
 * bookkeeping, and the per-IP ceiling on the tutor routes.
 *
 * Usage: node tests/metering.test.js
 */
Object.assign(process.env, {
  DEV_SKIP_LIMITS: 'false',
  REQUIRE_AUTH_TOKEN: '',
  GEMINI_API_KEY: '',
  FIREBASE_SERVICE_ACCOUNT_JSON: '',
  GOOGLE_APPLICATION_CREDENTIALS: '',
});

const axios = require('axios');
const { app } = require('../app');
const { reserveAuxUsage, releaseAuxUsage, refundAuxIfFallback } = require('../middleware/aiAccess');

let failures = 0;
const check = (name, cond) => {
  if (cond) console.log(`  ✅ ${name}`);
  else {
    console.error(`  ❌ ${name}`);
    failures++;
  }
};

(async () => {
  const server = app.listen(0);
  const base = `http://127.0.0.1:${server.address().port}`;
  const any = { validateStatus: () => true };
  const signedIn = { headers: { 'x-user-uid': 'test-learner' }, ...any };

  try {
    console.log('\n— /tutor/feedback is no longer a free AI endpoint —');

    const anon = await axios.post(`${base}/tutor/feedback`, { messages: [] }, any);
    check('POST /tutor/feedback with no credentials → 401', anon.status === 401);

    // Signed in it still works (this is a real feature, not a blocked one) —
    // the point is that it now goes through the aux budget on the way.
    const ok = await axios.post(
      `${base}/tutor/feedback`,
      { messages: [{ role: 'user', text: 'i go to shop yesterday' }] },
      signedIn,
    );
    check('POST /tutor/feedback signed in → 200', ok.status === 200);
    check('POST /tutor/feedback returns a report', !!(ok.data && ok.data.data && ok.data.data.encouragement));

    console.log('\n— which budget each tutor route spends —');

    // Read the actual middleware chain, because the bug this guards against is
    // invisible without Firestore: /tutor/feedback was mounted under a
    // router-wide requireAiAccess, which rejects a free learner as soon as
    // their daily MESSAGES run out — i.e. exactly when the session they want a
    // report for has just ended. The report is metered by the AUX budget and
    // must not be gated on the chat allowance as well.
    const chain = (path) => {
      const layer = require('../routes/tutor').stack.find((l) => l.route && l.route.path === path);
      return layer ? layer.route.stack.map((s) => s.name) : [];
    };
    const feedbackChain = chain('/feedback');
    const chatChain = chain('/chat');
    check('/tutor/feedback is metered by the aux budget', feedbackChain.includes('requireAuxAccess'));
    check('/tutor/feedback is NOT gated on the daily chat allowance', !feedbackChain.includes('requireAiAccess'));
    check('/tutor/feedback never claims a chat message', !feedbackChain.includes('requireMessageSlot'));
    check('/tutor/chat still checks the plan', chatChain.includes('requireAiAccess'));
    check('/tutor/chat still claims a message', chatChain.includes('requireMessageSlot'));

    console.log('\n— reserve / refund bookkeeping —');

    // No Firestore configured → every claim is a no-op that must still report
    // success, because a database outage must not break a learner's session.
    const claim = await reserveAuxUsage('test-learner');
    check('reserveAuxUsage without Firestore → allowed (degraded, not blocked)', claim.ok === true);
    check('reserveAuxUsage without Firestore → nothing actually reserved', claim.reserved !== true);
    let threw = false;
    try {
      await releaseAuxUsage('test-learner');
    } catch (_) {
      threw = true;
    }
    check('releaseAuxUsage without Firestore → no throw', threw === false);

    // The refund decision itself is pure, so it can be checked exactly.
    const fellBack = { _auxReserved: true, uid: 'u' };
    refundAuxIfFallback(fellBack, { phrases: [], fallback: true });
    check('a fallback response clears the reservation (refund issued)', fellBack._auxReserved === false);

    const mocked = { _auxReserved: true, uid: 'u' };
    refundAuxIfFallback(mocked, { phrases: [], mock: true });
    check('a mock response clears the reservation (refund issued)', mocked._auxReserved === false);

    const realAi = { _auxReserved: true, uid: 'u' };
    refundAuxIfFallback(realAi, { phrases: ['Good morning.'] });
    check('a real AI response keeps the reservation (learner is charged)', realAi._auxReserved === true);

    const never = { _auxReserved: false, uid: 'u' };
    refundAuxIfFallback(never, { fallback: true });
    check('nothing reserved → no double refund', never._auxReserved === false);

    console.log('\n— per-IP ceiling on the tutor routes —');

    // Well above a real conversation's pace; a caller this fast is a script.
    let sawRateLimit = false;
    for (let i = 0; i < 40; i++) {
      const r = await axios.post(`${base}/tutor/feedback`, { messages: [] }, signedIn);
      if (r.status === 429) {
        sawRateLimit = true;
        break;
      }
    }
    check('a burst of tutor calls from one client → 429', sawRateLimit);
  } finally {
    server.close();
  }

  if (failures) {
    console.error(`\n❌ ${failures} metering check(s) failed.`);
    process.exit(1);
  }
  console.log('\n✅ All metering checks passed.');
})();
