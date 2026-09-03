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
  halfyearly: (process.env.RAZORPAY_PLAN_HALFYEARLY || '').trim(),
  quarterly: (process.env.RAZORPAY_PLAN_QUARTERLY || '').trim(),
  monthly: (process.env.RAZORPAY_PLAN_MONTHLY || '').trim(),
};

// Display prices, as written on the shop windows. Both the landing page and
// the checkout page render these, and they used to declare their own identical
// copy of this map — two places to edit for one price change, and a silent
// mismatch between the price a visitor is quoted and the one they are shown at
// checkout if only one got updated. The AMOUNT CHARGED is never from here: that
// is whatever the Razorpay plan says. Blank stays blank so a page shows a dash
// rather than a guess.
const PRICE_LABELS = {
  monthly: (process.env.RAZORPAY_PRICE_MONTHLY || '').trim(),
  quarterly: (process.env.RAZORPAY_PRICE_QUARTERLY || '').trim(),
  halfyearly: (process.env.RAZORPAY_PRICE_HALFYEARLY || '').trim(),
  annual: (process.env.RAZORPAY_PRICE_ANNUAL || '').trim(),
};

// Razorpay requires a finite billing-cycle count. These are just "keep renewing
// for a very long time" — the learner cancels when they want, and each renewal
// extends premiumExpiry by one more cycle via the webhook.
const TOTAL_COUNT = { monthly: 120, quarterly: 40, halfyearly: 20, annual: 10 };

// The paid trial. Razorpay has no "trial" field: a trial is a subscription
// whose first billing date is pushed into the future (`start_at`) with an
// up-front amount collected during the authorisation transaction (`addons`).
// So the learner pays TRIAL_AMOUNT today, the mandate is registered, and the
// first full cycle is charged TRIAL_DAYS later unless they cancel.
//
// Keep TRIAL_DAYS small. At the measured ~Rs 0.06 per message, Rs 2 buys about
// 32 messages, so a longer window is a straight loss on anyone who actually
// uses the app. Set RAZORPAY_TRIAL_AMOUNT_PAISE=0 to sell without a trial.
const TRIAL_DAYS = parseInt(process.env.RAZORPAY_TRIAL_DAYS || '1', 10);
const TRIAL_AMOUNT_PAISE = parseInt(process.env.RAZORPAY_TRIAL_AMOUNT_PAISE || '200', 10);

/** Is a paid trial configured at all? */
function trialEnabled() {
  return TRIAL_DAYS > 0 && TRIAL_AMOUNT_PAISE > 0;
}

/** What the trial costs, in rupees, for display. */
function trialInfo() {
  return trialEnabled()
    ? { days: TRIAL_DAYS, amountPaise: TRIAL_AMOUNT_PAISE, amount: TRIAL_AMOUNT_PAISE / 100 }
    : null;
}

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
/**
 * Create a subscription for `uid` on `planKey`.
 *
 * `withTrial` is decided by the caller, not here: Razorpay has no equivalent of
 * Play's "new customer acquisition" eligibility, so nothing stops the same
 * person taking the Rs 2 trial again and again. The route checks whether this
 * account has ever completed a purchase and passes the answer in.
 */
async function createSubscription(uid, planKey, { withTrial = false } = {}) {
  if (!isConfigured()) return { ok: false, error: 'NOT_CONFIGURED' };
  const planId = PLANS[planKey];
  if (!planId) return { ok: false, error: 'UNKNOWN_PLAN' };

  const body = {
    plan_id: planId,
    total_count: TOTAL_COUNT[planKey] || 12,
    quantity: 1,
    customer_notify: 1,
    notes: { uid, plan: planKey, app: 'speak-frankly' },
  };
  if (withTrial && trialEnabled()) {
    body.start_at = Math.floor(Date.now() / 1000) + TRIAL_DAYS * 24 * 60 * 60;
    body.addons = [{
      item: {
        name: `${TRIAL_DAYS}-day trial`,
        amount: TRIAL_AMOUNT_PAISE,
        currency: 'INR',
      },
    }];
    body.notes.trial = `${TRIAL_DAYS}d`;
  }

  try {
    const resp = await axios.post(
      `${API}/subscriptions`,
      body,
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
  trialEnabled,
  trialInfo,
  fetchSubscription,
  verifyWebhookSignature,
  KEY_ID,
  PLANS,
  PRICE_LABELS,
  hasWebhookSecret: () => !!WEBHOOK_SECRET,
};
