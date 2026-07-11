/**
 * AI usage control for Speak Frankly (adapted from InstaFlow's aiAccess).
 * Backend is the source of truth — never trust client counters.
 *
 * Plans (resolved from Firestore user doc dates, not a stored string):
 * - free:    NO AI access — premium is required to use the tutor (hard paywall).
 *            (If REQUIRE_PREMIUM=false, free instead gets DAILY_MESSAGES_FREE/day.)
 * - premium: unlimited (Google Play in_app_purchase; premiumExpiry in the future).
 *
 * There is no free trial. DEV_SKIP_LIMITS=true bypasses all checks for local testing.
 */
const { getDb } = require('../utils/firestoreAdmin');

const USERS = 'users';
const DAILY_MESSAGES_FREE = parseInt(process.env.DAILY_MESSAGES_FREE || '25', 10);
const TRIAL_DAYS = parseInt(process.env.TRIAL_DAYS || '7', 10);
// Premium required for ALL AI (default). Set REQUIRE_PREMIUM=false to instead
// give free users DAILY_MESSAGES_FREE messages/day.
const REQUIRE_PREMIUM = process.env.REQUIRE_PREMIUM !== 'false' && process.env.REQUIRE_PREMIUM !== '0';
const DEV_SKIP_LIMITS = process.env.DEV_SKIP_LIMITS === 'true' || process.env.DEV_SKIP_LIMITS === '1';

if (DEV_SKIP_LIMITS) {
  console.warn('[aiAccess] ⚠️ DEV_SKIP_LIMITS enabled — usage limits bypassed. Do NOT use in production.');
}

function todayDateStr() {
  return new Date().toISOString().slice(0, 10); // YYYY-MM-DD (UTC)
}

function getNextMidnightUtc() {
  const now = new Date();
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1)).toISOString();
}

function toDate(v) {
  if (v == null) return null;
  if (typeof v.toDate === 'function') return v.toDate();
  if (v instanceof Date) return v;
  if (typeof v._seconds === 'number') return new Date(v._seconds * 1000);
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? null : d;
}

/** Resolve plan from dates. premium (paid subscription) > free. No free trial. */
function resolvePlan(user, now = new Date()) {
  const premiumExpiry = toDate(user.premiumExpiry || user.premium_expiry);
  if (premiumExpiry && premiumExpiry > now) return 'premium';
  return 'free';
}

async function loadUser(uid) {
  const db = getDb();
  if (!db) return { user: null, firestoreOk: false };
  try {
    const snap = await db.collection(USERS).doc(uid).get();
    if (!snap.exists) return { user: null, firestoreOk: true };
    return { user: { id: snap.id, ...snap.data() }, firestoreOk: true };
  } catch (e) {
    console.warn('[aiAccess] loadUser error:', e.message);
    return { user: null, firestoreOk: false };
  }
}

/**
 * First time we see a signed-in learner, create their user doc on the free plan
 * (daily limits). Premium is granted only via a paid subscription. No free trial.
 * Returns the created user object, or null if the write failed.
 */
async function createFreeUser(uid) {
  const db = getDb();
  if (!db) return null;
  const now = new Date();
  const doc = {
    createdAt: now,
    planType: 'free',
    dailyAiUsed: 0,
    dailyAiDate: todayDateStr(),
    totalAiUsed: 0,
  };
  try {
    await db.collection(USERS).doc(uid).set(doc, { merge: true });
    return { id: uid, ...doc };
  } catch (e) {
    console.warn('[aiAccess] createFreeUser error:', e.message);
    return null;
  }
}

/** Compute access state for a uid. */
async function getAiAccess(uid) {
  const resetAtUtc = getNextMidnightUtc();
  const { user, firestoreOk } = await loadUser(uid);

  // Degraded mode (no Firestore) — allow through so dev/testing isn't blocked.
  if (!firestoreOk) {
    return { allowed: true, planType: 'free', dailyUsed: 0, dailyLimit: DAILY_MESSAGES_FREE, resetAtUtc, user: null, degraded: true };
  }
  let currentUser = user;
  if (!currentUser) {
    // New signed-in learner → create on the free plan (daily limits apply).
    currentUser = await createFreeUser(uid);
    if (!currentUser) {
      return { allowed: true, planType: 'free', dailyUsed: 0, dailyLimit: DAILY_MESSAGES_FREE, resetAtUtc, user: null, degraded: true };
    }
  }

  const now = new Date();
  const planType = resolvePlan(currentUser, now);

  if (planType === 'premium') {
    return { allowed: true, planType: 'premium', dailyUsed: null, dailyLimit: null, resetAtUtc: null, user: currentUser };
  }

  // free — premium required: no AI access at all (hard paywall).
  if (REQUIRE_PREMIUM) {
    return {
      allowed: false,
      planType: 'free',
      dailyUsed: 0,
      dailyLimit: 0,
      resetAtUtc: null,
      user: currentUser,
      error: 'PREMIUM_REQUIRED',
    };
  }

  // free (only when REQUIRE_PREMIUM=false) — daily message cap.
  const today = todayDateStr();
  let dailyUsed = typeof currentUser.dailyAiUsed === 'number' ? currentUser.dailyAiUsed : 0;
  if ((currentUser.dailyAiDate || '') !== today) dailyUsed = 0;
  dailyUsed = Math.max(0, Math.min(DAILY_MESSAGES_FREE, Math.floor(dailyUsed)));

  return {
    allowed: dailyUsed < DAILY_MESSAGES_FREE,
    planType: 'free',
    dailyUsed,
    dailyLimit: DAILY_MESSAGES_FREE,
    resetAtUtc,
    user: currentUser,
    error: dailyUsed < DAILY_MESSAGES_FREE ? null : 'DAILY_LIMIT_REACHED',
  };
}

/** Express middleware: require x-user-uid, enforce plan. Sets req.uid, req.aiAccessAllowed. */
async function requireAiAccess(req, res, next) {
  const uid = (req.headers['x-user-uid'] || req.headers['x-user-id'] || req.body?.uid || '').toString().trim();

  if (DEV_SKIP_LIMITS) {
    req.uid = uid || 'dev-skip';
    req.aiAccess = { allowed: true, planType: 'premium' };
    req.aiAccessAllowed = true;
    return next();
  }

  if (!uid) {
    return res.status(401).json({ success: false, error: 'UNAUTHORIZED', message: 'Missing x-user-uid header' });
  }

  const access = await getAiAccess(uid);
  req.uid = uid;
  req.aiAccess = access;

  if (access.planType === 'premium') {
    req.aiAccessAllowed = true;
    return next();
  }

  if (!access.allowed) {
    const premiumRequired = access.error === 'PREMIUM_REQUIRED';
    return res.status(403).json({
      success: false,
      error: access.error || 'DAILY_LIMIT_REACHED',
      code: access.error || 'DAILY_LIMIT_REACHED',
      message: premiumRequired
        ? 'Premium required. Subscribe to use the AI tutor.'
        : 'Daily free limit reached. Upgrade to Premium for unlimited practice.',
      dailyLimit: access.dailyLimit,
      resetAtUtc: access.resetAtUtc,
    });
  }

  req.aiAccessAllowed = true;
  next();
}

/**
 * Wrap an AI controller: assert access, auto-envelope the returned value,
 * and never leak a hard error to the learner (returns graceful fallback).
 */
function wrapAiHandler(handler, buildFallback) {
  return function wrapped(req, res, next) {
    if (req.aiAccessAllowed !== true) {
      const code = req.aiAccess?.error || 'PREMIUM_REQUIRED';
      return res.status(403).json({ success: false, error: code, code });
    }
    return Promise.resolve(handler(req, res, next))
      .then((value) => {
        if (!res.headersSent && value !== undefined) {
          return res.json({ success: true, data: value });
        }
        return value;
      })
      .catch((error) => {
        if (res.headersSent) return;
        console.error('[AI Controller Error]', req.path, error?.message || error);
        const fallback = typeof buildFallback === 'function' ? buildFallback(req) : { message: 'Service busy, try again.' };
        return res.json({ success: true, data: fallback, fallback: true, meta: { errorCode: String(error?.code || 'AI_FALLBACK') } });
      });
  };
}

/** After a confirmed successful tutor message: increment daily counter (free only). */
async function recordAiUsage(uid) {
  if (DEV_SKIP_LIMITS || !uid) return;
  const db = getDb();
  if (!db) return;
  const ref = db.collection(USERS).doc(uid);
  const today = todayDateStr();
  try {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return;
      const data = snap.data();
      if (resolvePlan(data) !== 'free') return; // trial/premium: no decrement
      const rollover = (data.dailyAiDate || '') !== today;
      const used = rollover ? 0 : (typeof data.dailyAiUsed === 'number' ? data.dailyAiUsed : 0);
      tx.update(ref, {
        dailyAiUsed: used + 1,
        dailyAiDate: today,
        totalAiUsed: (typeof data.totalAiUsed === 'number' ? data.totalAiUsed : 0) + 1,
      });
    });
  } catch (e) {
    console.warn('[aiAccess] recordAiUsage error:', e.message);
  }
}

module.exports = {
  requireAiAccess,
  wrapAiHandler,
  recordAiUsage,
  getAiAccess,
  resolvePlan,
  DAILY_MESSAGES_FREE,
  TRIAL_DAYS,
  REQUIRE_PREMIUM,
  DEV_SKIP_LIMITS,
};
