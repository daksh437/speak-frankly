/**
 * Web checkout (Razorpay) tests.
 *
 * The whole design rests on one rule: the webhook signature is the only thing
 * that can turn a stranger's HTTP request into premium. So these tests attack
 * that boundary — forged signatures, a missing one, a body altered after
 * signing, and the browser trying to grant itself premium directly.
 *
 * Hermetic: real Razorpay keys are blanked, a throwaway webhook secret is set,
 * and there is no Firebase, so nothing here reaches Razorpay or Firestore.
 *
 * Usage: node tests/checkout.test.js
 */
const WEBHOOK_SECRET = 'test-webhook-secret-do-not-use';

Object.assign(process.env, {
  DEV_SKIP_LIMITS: 'false',
  REQUIRE_AUTH_TOKEN: '',
  GEMINI_API_KEY: '',
  FIREBASE_SERVICE_ACCOUNT_JSON: '',
  GOOGLE_APPLICATION_CREDENTIALS: '',
  RAZORPAY_KEY_ID: 'rzp_test_fake',
  RAZORPAY_KEY_SECRET: 'fake-secret',
  RAZORPAY_WEBHOOK_SECRET: WEBHOOK_SECRET,
  RAZORPAY_PLAN_MONTHLY: 'plan_fake_monthly',
  RAZORPAY_PLAN_ANNUAL: 'plan_fake_annual',
});

const crypto = require('crypto');
const axios = require('axios');
const { app } = require('../app');
const { verifyWebhookSignature, availablePlans } = require('../services/razorpay');

let failures = 0;
const check = (name, cond) => {
  if (cond) console.log(`  ✅ ${name}`);
  else {
    console.error(`  ❌ ${name}`);
    failures++;
  }
};

const sign = (raw) => crypto.createHmac('sha256', WEBHOOK_SECRET).update(raw).digest('hex');

function chargedEvent(uid, endSec) {
  return JSON.stringify({
    event: 'subscription.charged',
    payload: {
      subscription: {
        entity: {
          id: 'sub_test_123',
          status: 'active',
          current_end: endSec,
          notes: { uid, plan: 'monthly' },
        },
      },
    },
  });
}

(async () => {
  const server = app.listen(0);
  const base = `http://127.0.0.1:${server.address().port}`;
  const any = { validateStatus: () => true };
  const raw = (sig) => ({
    headers: { 'Content-Type': 'application/json', ...(sig ? { 'x-razorpay-signature': sig } : {}) },
    ...any,
  });

  try {
    console.log('\n— signature verification (pure) —');

    const body = chargedEvent('learner-1', Math.floor(Date.now() / 1000) + 2592000);
    check('a correctly signed body verifies', verifyWebhookSignature(Buffer.from(body), sign(body)) === true);
    check('a wrong signature is refused', verifyWebhookSignature(Buffer.from(body), sign(body + 'x')) === false);
    check('no signature is refused', verifyWebhookSignature(Buffer.from(body), '') === false);
    check('no body is refused', verifyWebhookSignature(null, sign(body)) === false);
    check(
      'a body altered after signing is refused',
      verifyWebhookSignature(Buffer.from(body.replace('learner-1', 'attacker')), sign(body)) === false,
    );
    check(
      'a signature of the right length but wrong bytes is refused',
      verifyWebhookSignature(Buffer.from(body), 'a'.repeat(64)) === false,
    );

    console.log('\n— the webhook endpoint —');

    const forged = await axios.post(`${base}/checkout/webhook`, body, raw('deadbeef'));
    check('POST /checkout/webhook with a forged signature → 400', forged.status === 400);

    const unsigned = await axios.post(`${base}/checkout/webhook`, body, raw());
    check('POST /checkout/webhook with no signature → 400', unsigned.status === 400);

    // Correctly signed but no Firestore behind it: the grant can't be written,
    // and it must still answer 200 so Razorpay doesn't retry for hours.
    const good = await axios.post(`${base}/checkout/webhook`, body, raw(sign(body)));
    check('POST /checkout/webhook correctly signed → 200', good.status === 200);

    // A real Razorpay event for a subscription that isn't ours must be shrugged
    // off, not treated as an error.
    const noUid = JSON.stringify({
      event: 'subscription.charged',
      payload: { subscription: { entity: { id: 'sub_other', current_end: 1, notes: {} } } },
    });
    const other = await axios.post(`${base}/checkout/webhook`, noUid, raw(sign(noUid)));
    check('a signed event with no uid in notes → 200, ignored', other.status === 200 && other.data.data.ignored === true);

    console.log('\n— the browser cannot grant itself premium —');

    const anon = await axios.post(`${base}/checkout/subscription`, { plan: 'monthly' }, any);
    check('POST /checkout/subscription with no credentials → 401', anon.status === 401);

    const claimed = await axios.post(
      `${base}/checkout/subscription`,
      { plan: 'monthly' },
      { headers: { 'x-user-uid': 'someone-elses-uid' }, ...any },
    );
    check('POST /checkout/subscription with a claimed uid → 401 (verified token required)', claimed.status === 401);

    console.log('\n— the page —');

    const page = await axios.get(`${base}/checkout`, any);
    check('GET /checkout → 200 HTML', page.status === 200 && String(page.data).includes('<!doctype html>'));
    check('GET /checkout never leaks the key secret', !String(page.data).includes('fake-secret'));
    check(
      'GET /checkout says it is unavailable when Firebase web config is missing',
      String(page.data).includes("isn't set up yet"),
    );
    // Annual first, so the page pre-selects it — same default as the in-app paywall.
    check('both plans offered, annual first', availablePlans().join(',') === 'annual,monthly');
  } finally {
    server.close();
  }

  if (failures) {
    console.error(`\n❌ ${failures} checkout check(s) failed.`);
    process.exit(1);
  }
  console.log('\n✅ All checkout checks passed.');
})();
