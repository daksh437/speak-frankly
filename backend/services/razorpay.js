/**
 * Razorpay subscriptions — for selling Premium on our OWN website.
 *
 * WHY THIS EXISTS, AND WHERE IT MAY BE USED
 * Google Play's Payments policy requires Play Billing for digital goods bought
 * INSIDE the Android app, so this is deliberately NOT wired into the app. It
 * backs a web checkout page instead, where Play's policy does not apply: there
 * the only fee is Razorpay's ~2.36%, versus Play's 15%.
 *
 * The Android app must never link to that page (Play's anti-steering rule), and
 * nothing here is reachable from it. Play Billing remains the only in-app path.
 *
 * TRUST MODEL
 * The browser is never trusted with entitlement. Creating a subscription only
 * records who it is for; premium is granted exclusively by the webhook, whose
 * signature we verify against the raw request body. A visitor who forges a
 * "payment succeeded" callback gets nothing.
 *
 * SETUP (one-time, all outside this repo):
 *   1. Razorpay Dashboard → Subscriptions → Plans: create a monthly and an
 *      annual plan, then set RAZORPAY_PLAN_MONTHLY / RAZORPAY_PLAN_ANNUAL.
 *   2. Settings → API Keys: set RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET.
 *   3. Settings → Webhooks: point at https://<host>/checkout/webhook, subscribe
 *      to subscription.charged / .cancelled / .halted / .completed, and set the
 *      secret as RAZORPAY_WEBHOOK_SECRET.
 */
const crypto = require('crypto');
const axios = require('axios');

const API = 'https://api.razorpay.com/v1';

const KEY_ID = (process.env.RAZORPAY_KEY_ID || '').trim();
const KEY_SECRET = (process.env.RAZORPAY_KEY_SECRET || '').trim();
const WEBHOOK_SECRET = (process.env.RAZORPAY_WEBHOOK_SECRET || '').trim();

// Annual first: availablePlans() preserves this order and the checkout page
// pre-selects the first one, so the web page defaults to annual exactly like
// the in-app paywall does. Same plan highlighted in both storefronts.
const PLANS = {
  annual: (process.env.RAZORPAY_PLAN_ANNUAL || '').trim(),
  monthly: (process.env.RAZORPAY_PLAN_MONTHLY || '').trim(),
};

// Razorpay requires a finite billing-cycle count. These are just "keep renewing
// for a very long time" — the learner cancels when they want, and each renewal
// extends premiumExpiry by one more cycle via the webhook.
const TOTAL_COUNT = { monthly: 120, annual: 10 };

/** Is the web checkout wired up at all? */
function isConfigured() {
  return !!(KEY_ID && KEY_SECRET);
}

/** Which plans are actually purchasable (a plan id has been configured). */
function availablePlans() {
  return Object.keys(PLANS).filter((k) => !!PLANS[k]);
}

function authHeader() {
  return 'Basic ' + Buffer.from(`${KEY_ID}:${KEY_SECRET}`).toString('base64');
}

/**
 * Create a subscription for `uid` on `planKey` ('monthly' | 'annual').
 *
 * The uid rides along in `notes` because that is what comes back on every
 * webhook for this subscription — it is how a renewal two months from now is
 * still matched to the right learner.
 */
async function createSubscription(uid, planKey) {
  if (!isConfigured()) return { ok: false, error: 'NOT_CONFIGURED' };
  const planId = PLANS[planKey];
  if (!planId) return { ok: false, error: 'UNKNOWN_PLAN' };

  try {
    const resp = await axios.post(
      `${API}/subscriptions`,
      {
        plan_id: planId,
        total_count: TOTAL_COUNT[planKey] || 12,
        quantity: 1,
        customer_notify: 1,
        notes: { uid, plan: planKey, app: 'speak-frankly' },
      },
      {
        headers: { Authorization: authHeader(), 'Content-Type': 'application/json' },
        timeout: 15000,
      },
    );
    const d = resp.data || {};
    return { ok: true, id: d.id, status: d.status, shortUrl: d.short_url };
  } catch (e) {
    const msg = e.response?.data?.error?.description || e.message;
    console.warn('[razorpay] createSubscription failed:', msg);
    return { ok: false, error: 'CREATE_FAILED', reason: msg };
  }
}

/** Read a subscription back from Razorpay (authoritative; used for reconciliation). */
async function fetchSubscription(subscriptionId) {
  if (!isConfigured() || !subscriptionId) return null;
  try {
    const resp = await axios.get(`${API}/subscriptions/${encodeURIComponent(subscriptionId)}`, {
      headers: { Authorization: authHeader() },
      timeout: 15000,
    });
    return resp.data || null;
  } catch (e) {
    console.warn('[razorpay] fetchSubscription failed:', e.response?.data?.error?.description || e.message);
    return null;
  }
}

/**
 * Verify a webhook came from Razorpay.
 *
 * HMAC-SHA256 of the RAW body with the webhook secret, compared to the
 * X-Razorpay-Signature header. The raw bytes matter: re-serialising the parsed
 * JSON reorders keys and changes whitespace, which produces a different hash and
 * would reject every genuine webhook (see the rawBody capture in app.js).
 *
 * Compared in constant time — a plain === leaks how much of the signature
 * matched, which is enough to forge one byte at a time.
 */
function verifyWebhookSignature(rawBody, signature) {
  if (!WEBHOOK_SECRET || !rawBody || !signature) return false;
  try {
    const expected = crypto.createHmac('sha256', WEBHOOK_SECRET).update(rawBody).digest('hex');
    const a = Buffer.from(expected, 'utf8');
    const b = Buffer.from(String(signature), 'utf8');
    return a.length === b.length && crypto.timingSafeEqual(a, b);
  } catch (e) {
    console.warn('[razorpay] signature check error:', e.message);
    return false;
  }
}

module.exports = {
  isConfigured,
  availablePlans,
  createSubscription,
  fetchSubscription,
  verifyWebhookSignature,
  KEY_ID,
  PLANS,
  hasWebhookSecret: () => !!WEBHOOK_SECRET,
};
