/**
 * Web checkout for Premium (Razorpay).
 *
 *   GET  /checkout                the page a learner buys from (public)
 *   POST /checkout/subscription   create a subscription (verified sign-in only)
 *   POST /checkout/webhook        Razorpay tells us it was paid (signature-verified)
 *
 * This exists because Google Play takes 15% of an in-app subscription while
 * Razorpay takes ~2.36% of a web one. Play's Payments policy governs purchases
 * made INSIDE the Android app, not on our own site — so this page is a
 * legitimate second storefront, and the app keeps Play Billing untouched and
 * never links here (Play's anti-steering rule).
 *
 * ENTITLEMENT COMES FROM THE WEBHOOK, NOTHING ELSE.
 * The browser's "payment succeeded" callback is a UI hint; anyone can POST it.
 * Premium is written only when Razorpay tells us server-to-server with a valid
 * signature. That is the same rule the Play path follows: never trust the
 * client with the thing it is trying to buy.
 */
const express = require('express');
const { getDb } = require('../utils/firestoreAdmin');
const { requireVerifiedAuth } = require('../middleware/auth');
const { rateLimit } = require('../middleware/rateLimit');
const rzp = require('../services/razorpay');

const router = express.Router();
const USERS = 'users';

// Firebase Web SDK config for the Google sign-in on the page. Separate from the
// Android app's google-services.json — register a WEB app in the same Firebase
// project (Project settings → Your apps → Web) and copy these values in.
const WEB = {
  apiKey: (process.env.FIREBASE_WEB_API_KEY || '').trim(),
  authDomain: (process.env.FIREBASE_WEB_AUTH_DOMAIN || '').trim(),
  projectId: (process.env.FIREBASE_PROJECT_ID || '').trim(),
  appId: (process.env.FIREBASE_WEB_APP_ID || '').trim(),
};
const webReady = () => !!(WEB.apiKey && WEB.authDomain && WEB.appId);

const PLAN_LABELS = {
  monthly: { name: 'Monthly', per: 'per month', badge: '' },
  annual: { name: 'Annual', per: 'per year', badge: 'Best value' },
};

// Display only. The real amount is whatever the Razorpay plan says; this is a
// label, so it is left blank rather than guessed when unset.
const PRICES = {
  monthly: (process.env.RAZORPAY_PRICE_MONTHLY || '').trim(),
  annual: (process.env.RAZORPAY_PRICE_ANNUAL || '').trim(),
};

// ------------------------------------------------------------------- page

function planCardsHtml(plans) {
  return plans
    .map((key, i) => {
      const l = PLAN_LABELS[key] || { name: key, per: '', badge: '' };
      const price = PRICES[key] || '&mdash;';
      const badge = l.badge ? '<span class="badge">' + l.badge + '</span>' : '';
      const checked = i === 0 ? 'checked' : '';
      return [
        '<label class="plan">',
        '  <input type="radio" name="plan" value="' + key + '" ' + checked + '>',
        '  <span class="plan-body">',
        '    <span class="plan-head"><b>' + l.name + '</b>' + badge + '</span>',
        '    <span class="plan-price">' + price + ' <span class="per">' + l.per + '</span></span>',
        '  </span>',
        '</label>',
      ].join('\n');
    })
    .join('\n');
}

const STYLES = [
  ':root{color-scheme:light dark;--bg:#fff;--fg:#1a1a1a;--muted:#6b6b6b;--seed:#5B4BD6;--card:#f6f5fb;--line:#e3e0f0}',
  '@media(prefers-color-scheme:dark){:root{--bg:#121016;--fg:#e9e7ef;--muted:#9d99ab;--card:#1d1a25;--line:#2e2a3a}}',
  '*{box-sizing:border-box}',
  'body{font-family:-apple-system,"Segoe UI",Roboto,sans-serif;line-height:1.6;margin:0;background:var(--bg);color:var(--fg);padding:32px 20px 64px}',
  '.wrap{max-width:460px;margin:0 auto}',
  '.crown{width:76px;height:76px;border-radius:50%;display:grid;place-items:center;font-size:36px;margin:0 auto 16px;background:linear-gradient(135deg,#5B4BD6,#8b7cf0)}',
  'h1{font-size:26px;text-align:center;margin:0 0 6px}',
  '.sub{text-align:center;color:var(--muted);margin:0 0 24px;font-size:15px}',
  '.plan{display:flex;align-items:center;gap:10px;border:2px solid var(--line);border-radius:14px;padding:14px 16px;margin-bottom:12px;cursor:pointer;background:var(--card)}',
  '.plan:has(input:checked){border-color:var(--seed)}',
  '.plan input{accent-color:var(--seed);flex:0 0 auto}',
  '.plan-body{display:block;flex:1 1 auto}',
  '.plan-head{display:flex;align-items:center;gap:8px}',
  '.badge{font-size:11px;font-weight:700;color:#fff;background:var(--seed);padding:2px 8px;border-radius:99px}',
  '.plan-price{display:block;font-size:20px;font-weight:800}',
  '.per{font-size:13px;font-weight:500;color:var(--muted)}',
  'button{width:100%;height:52px;border:0;border-radius:14px;background:var(--seed);color:#fff;font-size:16px;font-weight:700;cursor:pointer;margin-top:8px}',
  'button:disabled{opacity:.5;cursor:not-allowed}',
  '.note{font-size:12px;color:var(--muted);text-align:center;margin-top:12px}',
  '.who{font-size:13px;color:var(--muted);text-align:center;margin-bottom:14px;min-height:20px}',
  '.msg{border-radius:12px;padding:12px 14px;margin:16px 0;font-size:14px;display:none}',
  '.msg.err{display:block;background:rgba(220,60,60,.12);color:#d33}',
  '.msg.ok{display:block;background:rgba(60,180,120,.14);color:#1a8f5a}',
  'a{color:var(--seed)}',
].join('');

function browserScript() {
  const cfg = JSON.stringify({
    apiKey: WEB.apiKey,
    authDomain: WEB.authDomain,
    projectId: WEB.projectId,
    appId: WEB.appId,
  });
  const keyId = JSON.stringify(rzp.KEY_ID);

  return [
    '<script src="https://checkout.razorpay.com/v1/checkout.js"></script>',
    '<script type="module">',
    "import { initializeApp } from 'https://www.gstatic.com/firebasejs/10.12.2/firebase-app.js';",
    "import { getAuth, GoogleAuthProvider, signInWithPopup, onAuthStateChanged } from 'https://www.gstatic.com/firebasejs/10.12.2/firebase-auth.js';",
    'const auth = getAuth(initializeApp(' + cfg + '));',
    "const who = document.getElementById('who');",
    "const pay = document.getElementById('pay');",
    "const msg = document.getElementById('msg');",
    'let user = null;',
    "const show = (t, k) => { msg.textContent = t; msg.className = 'msg ' + k; };",
    "const reset = (t) => { pay.disabled = false; pay.textContent = t; };",
    'onAuthStateChanged(auth, (u) => {',
    '  user = u;',
    "  if (u) { who.textContent = 'Signed in as ' + u.email; reset('Continue to payment'); }",
    "  else { who.textContent = 'Sign in with the same Google account you use in the app.'; reset('Sign in with Google'); }",
    '});',
    "document.getElementById('form').addEventListener('submit', async (e) => {",
    '  e.preventDefault();',
    "  msg.className = 'msg';",
    '  if (!user) {',
    '    try { await signInWithPopup(auth, new GoogleAuthProvider()); }',
    "    catch (err) { show('Sign-in failed. Please try again.', 'err'); }",
    '    return;',
    '  }',
    '  pay.disabled = true;',
    "  pay.textContent = 'Starting\\u2026';",
    '  try {',
    '    const token = await user.getIdToken();',
    "    const plan = document.querySelector('input[name=plan]:checked').value;",
    "    const res = await fetch('/checkout/subscription', {",
    "      method: 'POST',",
    "      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + token },",
    '      body: JSON.stringify({ plan }),',
    '    });',
    '    const body = await res.json();',
    "    if (!res.ok || !body.success) throw new Error(body.message || 'Could not start checkout.');",
    '    // Razorpay\'s handler is a UI signal only — the server grants premium',
    '    // from the webhook, so we say it may take a moment to appear.',
    '    new Razorpay({',
    '      key: ' + keyId + ',',
    '      subscription_id: body.data.subscriptionId,',
    "      name: 'Speak Frankly',",
    "      description: 'Premium subscription',",
    '      prefill: { email: user.email },',
    "      theme: { color: '#5B4BD6' },",
    "      handler: () => show('Payment received. Premium unlocks in the app within a minute \\u2014 reopen the app to see it.', 'ok'),",
    "      modal: { ondismiss: () => reset('Continue to payment') },",
    '    }).open();',
    '  } catch (err) {',
    "    show(err.message || 'Something went wrong. Please try again.', 'err');",
    '  } finally {',
    "    reset('Continue to payment');",
    '  }',
    '});',
    '</script>',
  ].join('\n');
}

function checkoutPage() {
  const plans = rzp.availablePlans();
  const ready = rzp.isConfigured() && webReady() && plans.length > 0;

  const body = ready
    ? [
        '<div class="who" id="who">Checking your account&hellip;</div>',
        '<div id="msg" class="msg"></div>',
        '<form id="form">',
        planCardsHtml(plans),
        '  <button type="submit" id="pay" disabled>Sign in to continue</button>',
        '</form>',
        '<p class="note">Billed by Razorpay. Cancel anytime. Renews automatically until cancelled.<br>',
        'Use the same Google account you sign in to the app with.</p>',
      ].join('\n')
    : '<div class="msg err">Web checkout isn\'t set up yet. Please use the app to subscribe.</div>';

  return [
    '<!doctype html>',
    '<html lang="en"><head>',
    '<meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width, initial-scale=1">',
    '<title>Get Premium — Speak Frankly</title>',
    '<style>' + STYLES + '</style>',
    '</head><body><div class="wrap">',
    '<div class="crown">👑</div>',
    '<h1>Speak Frankly Premium</h1>',
    '<p class="sub">Unlimited conversation practice, no ads.</p>',
    body,
    '<p class="note"><a href="/privacy">Privacy</a> &middot; <a href="/terms">Terms</a></p>',
    '</div>',
    ready ? browserScript() : '',
    '</body></html>',
  ].join('\n');
}

router.get('/', (_req, res) => {
  res.set('Content-Type', 'text/html; charset=utf-8').send(checkoutPage());
});

// ------------------------------------------------------- create subscription

/**
 * Start a subscription for the signed-in learner.
 *
 * requireVerifiedAuth, not requireAuth: this decides whose account a payment
 * will unlock, so "I claim to be uid X" is not good enough — the same rule the
 * Play activation path follows. The uid goes into the subscription's notes,
 * which is how a renewal months from now is still matched to this learner.
 */
router.post(
  '/subscription',
  rateLimit({ windowMs: 60_000, max: 10, name: 'checkout' }),
  requireVerifiedAuth,
  async (req, res) => {
    if (!rzp.isConfigured()) {
      return res.status(503).json({ success: false, error: 'NOT_CONFIGURED', message: 'Checkout is not available yet.' });
    }
    const plan = String((req.body && req.body.plan) || '').trim();
    if (!rzp.availablePlans().includes(plan)) {
      return res.status(400).json({ success: false, error: 'UNKNOWN_PLAN', message: 'Pick a plan.' });
    }

    const result = await rzp.createSubscription(req.uid, plan);
    if (!result.ok) {
      return res.status(502).json({ success: false, error: result.error, message: 'Could not start checkout. Please try again.' });
    }
    console.log(`[checkout] subscription ${result.id} created for ${req.uid} (${plan})`);
    return res.json({ success: true, data: { subscriptionId: result.id, plan } });
  },
);

// ------------------------------------------------------------------ webhook

/** Grant/extend premium. Never shortens an expiry that is already further out. */
async function grantPremium(uid, expiryMs, subscriptionId) {
  const db = getDb();
  if (!db || !uid) return false;
  const ref = db.collection(USERS).doc(uid);
  try {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const existing = snap.exists ? snap.data().premiumExpiry : null;
      let existingMs = 0;
      if (existing) {
        const d = typeof existing.toDate === 'function' ? existing.toDate() : new Date(existing);
        existingMs = Number.isNaN(d.getTime()) ? 0 : d.getTime();
      }
      // A learner may also hold a Play subscription. Taking the later of the two
      // means a web renewal can never cut short something already paid for.
      const best = Math.max(expiryMs, existingMs);
      tx.set(
        ref,
        {
          planType: 'premium',
          premiumExpiry: new Date(best),
          premiumVerified: true,
          premiumSource: 'razorpay',
          razorpaySubscriptionId: subscriptionId || null,
          lastPurchaseAt: new Date(),
        },
        { merge: true },
      );
    });
    return true;
  } catch (e) {
    console.warn('[checkout] grant error:', e.message);
    return false;
  }
}

/**
 * Razorpay → us. The ONLY place premium is granted on the web path.
 *
 * Answers 200 once the signature checks out, even if our own write failed: a
 * non-2xx makes Razorpay retry the same event for hours, and a genuine event we
 * mishandled is our bug to fix from the logs, not something to have hammered
 * back at us. A BAD signature still gets 400 — that is a forgery, and it must
 * never look accepted.
 */
router.post('/webhook', async (req, res) => {
  const signature = req.headers['x-razorpay-signature'];
  if (!rzp.hasWebhookSecret()) {
    console.warn('[checkout] webhook received but RAZORPAY_WEBHOOK_SECRET is unset — ignoring');
    return res.status(503).json({ success: false, error: 'NOT_CONFIGURED' });
  }
  if (!rzp.verifyWebhookSignature(req.rawBody, signature)) {
    console.warn('[checkout] REJECTED a webhook with a bad signature');
    return res.status(400).json({ success: false, error: 'BAD_SIGNATURE' });
  }

  const body = req.body || {};
  const event = String(body.event || '');
  const sub = (body.payload && body.payload.subscription && body.payload.subscription.entity) || null;
  const uid = (sub && sub.notes && sub.notes.uid) || null;
  const subId = (sub && sub.id) || null;

  if (!uid) {
    // The signature was valid, so this really is from Razorpay — it just isn't
    // one of our subscriptions (or predates the notes). Nothing to do.
    console.warn(`[checkout] ${event}: no uid in notes (sub ${subId}) — ignored`);
    return res.json({ success: true, data: { ignored: true } });
  }

  if (event === 'subscription.charged') {
    // current_end is the end of the cycle this payment just covered.
    const endSec = Number(sub.current_end) || 0;
    if (endSec) {
      const ok = await grantPremium(uid, endSec * 1000, subId);
      console.log(`[checkout] ${uid} premium ${ok ? 'granted' : 'FAILED'} until ${new Date(endSec * 1000).toISOString()} (${subId})`);
    } else {
      console.warn(`[checkout] subscription.charged without current_end (sub ${subId})`);
    }
  } else if (event === 'subscription.cancelled' || event === 'subscription.halted' || event === 'subscription.completed') {
    // Deliberately does NOT revoke. They paid for the cycle they are in, so
    // premiumExpiry is allowed to run out on its own — cutting access the
    // moment someone cancels would take away time they already bought.
    console.log(`[checkout] ${event} for ${uid} (${subId}) — access runs to premiumExpiry`);
  }

  return res.json({ success: true, data: { handled: event } });
});

module.exports = router;
