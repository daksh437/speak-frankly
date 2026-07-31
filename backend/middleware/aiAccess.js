/**
 * AI usage control for Speak Frankly (adapted from InstaFlow's aiAccess).
 * Backend is the source of truth — never trust client counters.
 *
 * Plans (resolved from Firestore user doc dates, not a stored string):
 * - trial:   new users get TRIAL_DAYS days of UNLIMITED AI (no card, no paywall).
 * - free:    after the trial ends → DAILY_MESSAGES_FREE messages/day (resets midnight UTC).
 *            (Set REQUIRE_PREMIUM=true to instead hard-gate free users behind premium.)
 * - premium: unlimited (Google Play in_app_purchase; premiumExpiry in the future).
 *
 * DEV_SKIP_LIMITS=true bypasses all checks for local testing.
 */
const { getDb } = require('../utils/firestoreAdmin');

const USERS = 'users';
const DEVICES = 'trial_devices'; // device-level anti-abuse: one trial per device
const DAILY_MESSAGES_FREE = parseInt(process.env.DAILY_MESSAGES_FREE || '10', 10);
const TRIAL_DAYS = parseInt(process.env.TRIAL_DAYS || '3', 10);
// Soft cap during the trial — high enough to feel unlimited, low enough to stop
// abuse (a bot chatting thousands of times and running up the AI bill).
const TRIAL_DAILY_CAP = parseInt(process.env.TRIAL_DAILY_CAP || '50', 10);
// Default = freemium (trial → free daily limit). Set REQUIRE_PREMIUM=true to
// instead hard-gate free users (post-trial) behind a paywall.
const REQUIRE_PREMIUM = process.env.REQUIRE_PREMIUM === 'true' || process.env.REQUIRE_PREMIUM === '1';
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

/** Resolve plan from dates. premium (paid) > trial (time-limited) > free. */
function resolvePlan(user, now = new Date()) {
  const premiumExpiry = toDate(user.premiumExpiry || user.premium_expiry);
  if (premiumExpiry && premiumExpiry > now) return 'premium';
  const trialEndsAt = toDate(user.trialEndsAt || user.trial_ends_at);
  if (trialEndsAt && trialEndsAt > now) return 'trial';
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
 * First time we see a signed-in learner, create their user doc and start their
 * free TRIAL_DAYS trial (unlimited AI). After it ends they drop to the free
 * daily limit. Premium is granted only via a paid subscription.
 * Returns the created user object, or null if the write failed.
 */
async function createTrialUser(uid, deviceId) {
  const db = getDb();
  if (!db) return null;
  const now = new Date();

  // Device-level anti-abuse: only the FIRST account on a device gets a trial;
  // signing in with a fresh Google account on the same device won't farm another.
  let deviceAlreadyTrialed = false;
  const did = (deviceId || '').toString().trim();
  if (did) {
    try {
      const dref = db.collection(DEVICES).doc(did);
      const dsnap = await dref.get();
      if (dsnap.exists) deviceAlreadyTrialed = true;
      else await dref.set({ firstUid: uid, trialUsedAt: now });
    } catch (e) {
      console.warn('[aiAccess] device check error:', e.message);
    }
  }

  const base = { createdAt: now, dailyAiUsed: 0, dailyAiDate: todayDateStr(), totalAiUsed: 0 };
  const doc = deviceAlreadyTrialed
    ? { ...base, planType: 'free' } // trial already consumed on this device
    : {
        ...base,
        planType: 'trial',
        trialStartedAt: now,
        trialEndsAt: new Date(now.getTime() + TRIAL_DAYS * 24 * 60 * 60 * 1000),
      };
  try {
    await db.collection(USERS).doc(uid).set(doc, { merge: true });
    return { id: uid, ...doc };
  } catch (e) {
    console.warn('[aiAccess] createTrialUser error:', e.message);
    return null;
  }
}

/** Compute access state for a uid. */
async function getAiAccess(uid, deviceId) {
  const resetAtUtc = getNextMidnightUtc();
  const { user, firestoreOk } = await loadUser(uid);

  // Degraded mode (no Firestore) — allow through so dev/testing isn't blocked.
  if (!firestoreOk) {
    return { allowed: true, planType: 'free', dailyUsed: 0, dailyLimit: DAILY_MESSAGES_FREE, resetAtUtc, trialEndsAtUtc: null, user: null, degraded: true };
  }
  let currentUser = user;
  if (!currentUser) {
    // New signed-in learner → start their free trial (unless this device already used one).
    currentUser = await createTrialUser(uid, deviceId);
    if (!currentUser) {
      return { allowed: true, planType: 'free', dailyUsed: 0, dailyLimit: DAILY_MESSAGES_FREE, resetAtUtc, trialEndsAtUtc: null, user: null, degraded: true };
    }
  }

  const now = new Date();
  const planType = resolvePlan(currentUser, now);
  const trialEndsAt = toDate(currentUser.trialEndsAt || currentUser.trial_ends_at);
  const trialEndsAtUtc = trialEndsAt ? trialEndsAt.toISOString() : null;
  const today = todayDateStr();
  let usedToday = typeof currentUser.dailyAiUsed === 'number' ? currentUser.dailyAiUsed : 0;
  if ((currentUser.dailyAiDate || '') !== today) usedToday = 0;

  if (planType === 'premium') {
    return { allowed: true, planType: 'premium', dailyUsed: null, dailyLimit: null, resetAtUtc: null, trialEndsAtUtc: null, user: currentUser };
  }

  // trial — effectively unlimited, but a daily soft cap stops abuse/cost blowups.
  if (planType === 'trial') {
    const used = Math.max(0, Math.min(TRIAL_DAILY_CAP, Math.floor(usedToday)));
    return {
      allowed: used < TRIAL_DAILY_CAP,
      planType: 'trial',
      dailyUsed: used,
      dailyLimit: TRIAL_DAILY_CAP,
      resetAtUtc,
      trialEndsAtUtc,
      user: currentUser,
      error: used < TRIAL_DAILY_CAP ? null : 'DAILY_LIMIT_REACHED',
    };
  }

  // free + optional hard paywall: no AI access at all.
  if (REQUIRE_PREMIUM) {
    return {
      allowed: false,
      planType: 'free',
      dailyUsed: 0,
      dailyLimit: 0,
      resetAtUtc: null,
      trialEndsAtUtc,
      user: currentUser,
      error: 'PREMIUM_REQUIRED',
    };
  }

  // free (default) — daily message cap. Reuses usedToday computed above.
  const dailyUsed = Math.max(0, Math.min(DAILY_MESSAGES_FREE, Math.floor(usedToday)));

  return {
    allowed: dailyUsed < DAILY_MESSAGES_FREE,
    planType: 'free',
    dailyUsed,
    dailyLimit: DAILY_MESSAGES_FREE,
    resetAtUtc,
    trialEndsAtUtc,
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

  const deviceId = (req.headers['x-device-id'] || '').toString().trim();
  const access = await getAiAccess(uid, deviceId);
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
      if (resolvePlan(data) === 'premium') return; // premium: no metering (free + trial both count)
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
