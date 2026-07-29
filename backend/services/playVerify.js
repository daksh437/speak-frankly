/**
 * Google Play subscription verification.
 *
 * Verifies the `purchaseToken` the app receives from the Play billing client
 * against the Google Play Developer API before we grant premium — so a forged
 * /premium/activate call can't hand out free premium.
 *
 * Reuses the SAME service-account credentials as firebase-admin
 * (FIREBASE_SERVICE_ACCOUNT_JSON, or GOOGLE_APPLICATION_CREDENTIALS file), just
 * with the androidpublisher scope. No extra npm package: google-auth-library
 * ships with firebase-admin, and axios is already a dependency.
 *
 * REQUIRED EXTERNAL SETUP (one-time) for verification to work:
 *   1. In Play Console → Setup → API access, link the same Google Cloud project
 *      that owns this service account.
 *   2. Grant that service account the "View financial data / Manage orders"
 *      permission (enough for read-only purchase verification).
 *   3. Set env: PLAY_PACKAGE_NAME=com.speakfrankly  (the app's real package id)
 *      Optional: PLAY_SUBSCRIPTION_ID (default premium_monthly),
 *                PLAY_VERIFY_STRICT=true to reject on transient API errors too.
 *
 * If PLAY_PACKAGE_NAME is unset, verification is DISABLED and the caller falls
 * back to trusting the client (so you can deploy before finishing Play setup).
 */
const axios = require('axios');
const { GoogleAuth } = require('google-auth-library');

const PACKAGE_NAME = (process.env.PLAY_PACKAGE_NAME || '').trim();
const SUBSCRIPTION_ID = (process.env.PLAY_SUBSCRIPTION_ID || 'premium_monthly').trim();
const STRICT = process.env.PLAY_VERIFY_STRICT === 'true' || process.env.PLAY_VERIFY_STRICT === '1';
const SCOPE = 'https://www.googleapis.com/auth/androidpublisher';

// Play subscription states we treat as "entitled" (CANCELED can still be within
// the already-paid period — we additionally require expiryTime in the future).
const ENTITLED_STATES = new Set([
  'SUBSCRIPTION_STATE_ACTIVE',
  'SUBSCRIPTION_STATE_IN_GRACE_PERIOD',
  'SUBSCRIPTION_STATE_CANCELED',
]);

let _auth;
function getAuth() {
  if (_auth) return _auth;
  const opts = { scopes: [SCOPE] };
  const saJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (saJson && saJson.trim()) {
    const creds = JSON.parse(saJson);
    if (typeof creds.private_key === 'string') creds.private_key = creds.private_key.replace(/\\n/g, '\n');
    opts.credentials = creds;
  }
  // else: GOOGLE_APPLICATION_CREDENTIALS (file path) is picked up automatically.
  _auth = new GoogleAuth(opts);
  return _auth;
}

/** Whether server-side verification is configured (a package name is set). */
function isConfigured() {
  return !!PACKAGE_NAME;
}

/**
 * Verify a subscription purchase token.
 * Returns:
 *   { configured:false }                        — verification disabled
 *   { valid:true,  expiryMs }                    — entitled, use expiryMs as premiumExpiry
 *   { valid:false, transient:true,  reason }     — couldn't reach Play (retry-able)
 *   { valid:false, transient:false, reason }     — definitively not entitled / bad token
 */
async function verifySubscription(purchaseToken) {
  if (!PACKAGE_NAME) return { configured: false, valid: false, reason: 'NOT_CONFIGURED' };
  if (!purchaseToken) return { configured: true, valid: false, transient: false, reason: 'NO_TOKEN' };

  const url =
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
    `${encodeURIComponent(PACKAGE_NAME)}/purchases/subscriptionsv2/tokens/` +
    `${encodeURIComponent(purchaseToken)}`;

  try {
    const client = await getAuth().getClient();
    const { token } = await client.getAccessToken();
    const resp = await axios.get(url, {
      headers: { Authorization: `Bearer ${token}` },
      timeout: 15000,
    });
    const data = resp.data || {};
    const state = data.subscriptionState;

    let expiryMs = 0;
    for (const li of Array.isArray(data.lineItems) ? data.lineItems : []) {
      const t = li && li.expiryTime ? Date.parse(li.expiryTime) : 0;
      if (t > expiryMs) expiryMs = t;
    }

    const valid = ENTITLED_STATES.has(state) && expiryMs > Date.now();
    return {
      configured: true,
      valid,
      expiryMs: valid ? expiryMs : 0,
      state: state || null,
      transient: false,
      reason: valid ? 'OK' : (state || 'INVALID'),
    };
  } catch (e) {
    const status = e.response && e.response.status;
    // 400/404/410 → the token is genuinely invalid/expired/not found.
    // 401/403 → OUR credentials/permission are wrong (treat as transient so we
    //           don't reject paying users while setup is being fixed).
    // 5xx / network → transient.
    const definitivelyInvalid = status === 400 || status === 404 || status === 410;
    const apiMsg = (e.response && e.response.data && e.response.data.error && e.response.data.error.message) || e.message;
    console.warn('[playVerify] error', status || 'NET', '-', apiMsg);
    return {
      configured: true,
      valid: false,
      transient: !definitivelyInvalid,
      reason: definitivelyInvalid ? 'INVALID_TOKEN' : `API_ERROR_${status || 'NET'}`,
    };
  }
}

module.exports = { verifySubscription, isConfigured, STRICT, SUBSCRIPTION_ID, PACKAGE_NAME };
