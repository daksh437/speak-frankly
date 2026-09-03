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
const { toDate, todayDateStr, getNextMidnightUtc } = require('../utils/dates');
const { authenticate } = require('./auth');

const USERS = 'users';
const DEVICES = 'trial_devices'; // device-level anti-abuse: one trial per device
const DAILY_MESSAGES_FREE = parseInt(process.env.DAILY_MESSAGES_FREE || '10', 10);
// "Aux" AI = the small helper calls around the conversation (translate a line,
// daily speaking phrases, picture-match items, vocab extraction, custom
// scenario). They're cheap individually but they ALL hit Gemini, so they get
// their own daily budget: metering them against chat messages would eat a free
// learner's 8 messages, but leaving them uncounted (as they were) let anyone
// spam /translate for unlimited AI calls on our bill.
const DAILY_AUX_FREE = parseInt(process.env.DAILY_AUX_FREE || '30', 10);
const DAILY_AUX_TRIAL = parseInt(process.env.DAILY_AUX_TRIAL || '80', 10);
const TRIAL_DAYS = parseInt(process.env.TRIAL_DAYS || '3', 10);
// Soft cap during the trial — high enough to feel unlimited, low enough to stop
// abuse (a bot chatting thousands of times and running up the AI bill).
const TRIAL_DAILY_CAP = parseInt(process.env.TRIAL_DAILY_CAP || '50', 10);
// Rewarded ads: a free user can watch an ad for REWARD_MESSAGES more messages,
// up to MAX_AD_REWARDS_PER_DAY times/day (server-authoritative — client can't fake).
const REWARD_MESSAGES = parseInt(process.env.REWARD_MESSAGES || '5', 10);
const MAX_AD_REWARDS_PER_DAY = parseInt(process.env.MAX_AD_REWARDS_PER_DAY || '3', 10);
// FAIR-USE CEILING FOR PREMIUM. Premium is sold as unlimited and the code means
// it literally: a premium uid is never counted and never blocked, so one ₹199
// subscription authorises unbounded spend. At the measured ~₹0.06 per message,
// a single account left running flat out against the /tutor rate limit costs
// more in a day than it pays in a year — and that account may be stolen rather
// than abusive.
//
// 0 = off, i.e. genuinely unlimited (the behaviour shipped today, so this
// changes nothing until you choose a number). 500/day is the suggested value:
// a heavy real learner does 30–50 messages a day, so nobody legitimate is ever
// near it, and it turns the worst case from ~₹2,560/day into ~₹30/day. Enforced
// in reserveAiUsage only — /access still reports premium as unlimited, so the
// app's UI is unchanged.
const PREMIUM_DAILY_CAP = parseInt(process.env.PREMIUM_DAILY_CAP || '0', 10);
// Default = freemium (trial → free daily limit). Set REQUIRE_PREMIUM=true to
// instead hard-gate free users (post-trial) behind a paywall.
const REQUIRE_PREMIUM = process.env.REQUIRE_PREMIUM === 'true' || process.env.REQUIRE_PREMIUM === '1';
const DEV_SKIP_LIMITS = process.env.DEV_SKIP_LIMITS === 'true' || process.env.DEV_SKIP_LIMITS === '1';

if (DEV_SKIP_LIMITS) {
  console.warn('[aiAccess] ⚠️ DEV_SKIP_LIMITS enabled — usage limits bypassed. Do NOT use in production.');
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

  // free (default) — daily message cap + any ad-earned bonus for today.
  const bonusToday = (currentUser.bonusDate === today && typeof currentUser.bonusMessages === 'number')
    ? Math.max(0, currentUser.bonusMessages)
    : 0;
  const effectiveLimit = DAILY_MESSAGES_FREE + bonusToday;
  const dailyUsed = Math.max(0, Math.floor(usedToday));

  return {
    allowed: dailyUsed < effectiveLimit,
    planType: 'free',
    dailyUsed,
    dailyLimit: effectiveLimit,
    bonusMessages: bonusToday,
    resetAtUtc,
    trialEndsAtUtc,
    user: currentUser,
    error: dailyUsed < effectiveLimit ? null : 'DAILY_LIMIT_REACHED',
  };
}

/**
 * Grant ad-reward bonus messages for today (server-authoritative). Free plan
 * only; capped at MAX_AD_REWARDS_PER_DAY. Returns { ok, bonusMessages, rewardsUsed }.
 */
async function grantAdReward(uid) {
  const db = getDb();
  if (!db || !uid) return { ok: false, error: 'no_db' };
  const ref = db.collection(USERS).doc(uid);
  const today = todayDateStr();
  try {
    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return { ok: false, error: 'no_user' };
      const data = snap.data();
      if (resolvePlan(data) !== 'free') return { ok: false, error: 'not_free' }; // trial/premium don't need it
      const rollover = data.bonusDate !== today;
      const rewardsUsed = rollover ? 0 : (typeof data.adRewardsToday === 'number' ? data.adRewardsToday : 0);
      if (rewardsUsed >= MAX_AD_REWARDS_PER_DAY) {
        return { ok: false, error: 'daily_reward_limit', rewardsUsed, maxPerDay: MAX_AD_REWARDS_PER_DAY };
      }
      const bonus = (rollover ? 0 : (typeof data.bonusMessages === 'number' ? data.bonusMessages : 0)) + REWARD_MESSAGES;
      tx.update(ref, { bonusMessages: bonus, bonusDate: today, adRewardsToday: rewardsUsed + 1 });
      return { ok: true, bonusMessages: bonus, rewardsUsed: rewardsUsed + 1, maxPerDay: MAX_AD_REWARDS_PER_DAY, added: REWARD_MESSAGES };
    });
  } catch (e) {
    console.warn('[aiAccess] grantAdReward error:', e.message);
    return { ok: false, error: 'tx_failed' };
  }
}

/**
 * Daily budget for the aux AI helpers (see DAILY_AUX_FREE above). Separate
 * counter (dailyAuxUsed) so these never eat the learner's chat messages —
 * and never run unbounded either.
 */
async function getAuxAccess(uid, deviceId) {
  const base = await getAiAccess(uid, deviceId);
  if (base.degraded || !base.user) {
    return { allowed: true, planType: base.planType, auxUsed: 0, auxLimit: DAILY_AUX_FREE, degraded: true };
  }
  if (base.planType === 'premium') {
    return { allowed: true, planType: 'premium', auxUsed: null, auxLimit: null };
  }
  if (base.planType === 'free' && REQUIRE_PREMIUM) {
    return { allowed: false, planType: 'free', auxUsed: 0, auxLimit: 0, error: 'PREMIUM_REQUIRED' };
  }

  const limit = base.planType === 'trial' ? DAILY_AUX_TRIAL : DAILY_AUX_FREE;
  const today = todayDateStr();
  const u = base.user;
  const used = (u.dailyAuxDate === today && typeof u.dailyAuxUsed === 'number') ? Math.max(0, Math.floor(u.dailyAuxUsed)) : 0;
  return {
    allowed: used < limit,
    planType: base.planType,
    auxUsed: used,
    auxLimit: limit,
    resetAtUtc: base.resetAtUtc,
    error: used < limit ? null : 'DAILY_LIMIT_REACHED',
  };
}

/**
 * Atomically claim ONE aux call from today's budget, re-checking the limit
 * inside the transaction — the aux twin of reserveAiUsage.
 *
 * This used to be `recordAuxUsage`, called AFTER the reply came back, with the
 * limit checked separately beforehand. Nothing was reserved in between, so N
 * concurrent /translate (or /speaking/phrases, …) requests all read the same
 * "used" value and every one of them passed — the same burst hole that was
 * closed for chat messages. Claiming up front closes it; releaseAuxUsage hands
 * the slot back when the learner ends up getting canned text instead of AI.
 *
 * Never blocks on infrastructure trouble: an unreachable Firestore lets the
 * call through rather than breaking a feature mid-session.
 */
async function reserveAuxUsage(uid) {
  if (DEV_SKIP_LIMITS || !uid) return { ok: true, skipped: true };
  const db = getDb();
  if (!db) return { ok: true, skipped: true };
  const ref = db.collection(USERS).doc(uid);
  const today = todayDateStr();
  try {
    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return { ok: true, skipped: true };
      const data = snap.data();
      const plan = resolvePlan(data);
      if (plan === 'premium') return { ok: true, skipped: true }; // unmetered
      if (plan === 'free' && REQUIRE_PREMIUM) return { ok: false, error: 'PREMIUM_REQUIRED', auxLimit: 0 };

      const limit = plan === 'trial' ? DAILY_AUX_TRIAL : DAILY_AUX_FREE;
      const rollover = (data.dailyAuxDate || '') !== today;
      const used = rollover ? 0 : (typeof data.dailyAuxUsed === 'number' ? Math.max(0, Math.floor(data.dailyAuxUsed)) : 0);
      if (used >= limit) return { ok: false, error: 'DAILY_LIMIT_REACHED', auxLimit: limit, auxUsed: used };

      tx.update(ref, { dailyAuxUsed: used + 1, dailyAuxDate: today });
      return { ok: true, reserved: true, auxUsed: used + 1, auxLimit: limit };
    });
  } catch (e) {
    console.warn('[aiAccess] reserveAuxUsage error:', e.message);
    return { ok: true, skipped: true, degraded: true };
  }
}

/**
 * Hand a reserved aux call back — the learner got a fallback/mock, not AI, so
 * it shouldn't cost them anything.
 */
async function releaseAuxUsage(uid) {
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
      // A rollover since the reserve means today's counter is already 0 — a
      // refund would push it negative, so there is nothing to give back.
      if ((data.dailyAuxDate || '') !== today) return;
      const used = typeof data.dailyAuxUsed === 'number' ? data.dailyAuxUsed : 0;
      tx.update(ref, { dailyAuxUsed: Math.max(0, used - 1) });
    });
  } catch (e) {
    console.warn('[aiAccess] releaseAuxUsage error:', e.message);
  }
}

/**
 * Refund a reserved aux call when the handler produced canned text. Routes call
 * this instead of hand-rolling the `req._auxReserved` check.
 */
function refundAuxIfFallback(req, data) {
  if (req._auxReserved && data && (data.fallback === true || data.mock === true)) {
    releaseAuxUsage(req.uid).catch(() => {});
    req._auxReserved = false;
  }
  return data;
}

/**
 * Express middleware for the aux AI helpers. Sets req.uid + req.auxAccess, and
 * CLAIMS one aux call before the handler runs (see reserveAuxUsage).
 *
 * Two steps on purpose: getAuxAccess provisions the user doc for a first-time
 * learner (and gives the 403 body its real numbers), then reserveAuxUsage makes
 * the authoritative claim inside a transaction. Handlers that end up returning
 * canned text refund the slot via refundAuxIfFallback.
 */
async function requireAuxAccess(req, res, next) {
  await authenticate(req);
  const uid = req.uid;

  if (DEV_SKIP_LIMITS) {
    req.uid = uid || 'dev-skip';
    req.auxAccess = { allowed: true, planType: 'premium' };
    return next();
  }
  if (!uid) {
    return res.status(401).json({ success: false, error: 'UNAUTHORIZED', message: 'Sign in to use this feature' });
  }

  const deviceId = (req.headers['x-device-id'] || '').toString().trim();
  const access = await getAuxAccess(uid, deviceId);
  req.auxAccess = access;

  const deny = (code, dailyLimit) => res.status(403).json({
    success: false,
    error: code,
    code,
    message: code === 'PREMIUM_REQUIRED'
      ? 'Premium required. Subscribe to use this feature.'
      : 'Daily limit reached for this feature. Upgrade to Premium for unlimited practice.',
    dailyLimit,
    resetAtUtc: getNextMidnightUtc(),
  });

  if (!access.allowed) return deny(access.error || 'DAILY_LIMIT_REACHED', access.auxLimit);

  const claim = await reserveAuxUsage(uid);
  if (!claim.ok) return deny(claim.error || 'DAILY_LIMIT_REACHED', claim.auxLimit);

  req._auxReserved = claim.reserved === true; // only a real reservation is refundable
  // The aux budget IS this endpoint's authorisation, so say so — wrapAiHandler
  // refuses to run a handler that nothing has cleared, and an aux route may be
  // the only gate a request passed through.
  req.aiAccessAllowed = true;
  next();
}

/** Express middleware: authenticate the learner, enforce plan. Sets req.uid, req.aiAccessAllowed. */
async function requireAiAccess(req, res, next) {
  await authenticate(req);
  const uid = req.uid;

  if (DEV_SKIP_LIMITS) {
    req.uid = uid || 'dev-skip';
    req.aiAccess = { allowed: true, planType: 'premium' };
    req.aiAccessAllowed = true;
    return next();
  }

  if (!uid) {
    return res.status(401).json({ success: false, error: 'UNAUTHORIZED', message: 'Sign in to use the AI tutor' });
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
          // A handler that returned canned text (mock/fallback) never reached
          // the model, so it shouldn't cost the learner a reserved aux call.
          return res.json({ success: true, data: refundAuxIfFallback(req, value) });
        }
        return value;
      })
      .catch((error) => {
        if (res.headersSent) return;
        console.error('[AI Controller Error]', req.path, error?.message || error);
        // The learner is getting canned text, not a real tutor reply — give the
        // reserved message back so a bad AI day doesn't eat their daily quota.
        if (req._aiReserved) releaseAiUsage(req.uid).catch(() => {});
        if (req._auxReserved) releaseAuxUsage(req.uid).catch(() => {});
        const fallback = typeof buildFallback === 'function' ? buildFallback(req) : { message: 'Service busy, try again.' };
        return res.json({ success: true, data: fallback, fallback: true, meta: { errorCode: String(error?.code || 'AI_FALLBACK') } });
      });
  };
}

/**
 * Atomically claim ONE message from today's allowance, re-checking the limit
 * inside the transaction.
 *
 * Why this exists: requireAiAccess reads the counter, and the increment used to
 * happen (fire-and-forget) only after the reply came back. Between those two
 * points nothing was reserved, so N requests fired at once all saw the same
 * "used" value and every one of them passed — a free learner could burst well
 * past their daily cap and run up the AI bill. Reserving up front closes that
 * window; releaseAiUsage refunds the slot if the AI call ends up failing.
 *
 * Never blocks on infrastructure trouble: if Firestore is unreachable we let
 * the learner through rather than breaking a conversation mid-session.
 */
async function reserveAiUsage(uid) {
  if (DEV_SKIP_LIMITS || !uid) return { ok: true, skipped: true };
  const db = getDb();
  if (!db) return { ok: true, skipped: true };
  const ref = db.collection(USERS).doc(uid);
  const today = todayDateStr();
  try {
    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return { ok: true, skipped: true };
      const data = snap.data();
      const plan = resolvePlan(data);

      const rollover = (data.dailyAiDate || '') !== today;
      const used = rollover ? 0 : (typeof data.dailyAiUsed === 'number' ? Math.max(0, Math.floor(data.dailyAiUsed)) : 0);

      if (plan === 'premium') {
        if (PREMIUM_DAILY_CAP <= 0) return { ok: true, skipped: true }; // truly unmetered
        if (used >= PREMIUM_DAILY_CAP) {
          return { ok: false, error: 'FAIR_USE_LIMIT', dailyLimit: PREMIUM_DAILY_CAP, dailyUsed: used };
        }
        // Count premium too, so the ceiling has something to measure. Kept out
        // of totalAiUsed so the admin panel's "messages" figure keeps meaning
        // the same thing it always has.
        tx.update(ref, { dailyAiUsed: used + 1, dailyAiDate: today });
        return { ok: true, reserved: true, dailyUsed: used + 1, dailyLimit: PREMIUM_DAILY_CAP };
      }

      let limit;
      if (plan === 'trial') {
        limit = TRIAL_DAILY_CAP;
      } else if (REQUIRE_PREMIUM) {
        return { ok: false, error: 'PREMIUM_REQUIRED', dailyLimit: 0 };
      } else {
        const bonus = (data.bonusDate === today && typeof data.bonusMessages === 'number')
          ? Math.max(0, data.bonusMessages)
          : 0;
        limit = DAILY_MESSAGES_FREE + bonus;
      }

      if (used >= limit) return { ok: false, error: 'DAILY_LIMIT_REACHED', dailyLimit: limit, dailyUsed: used };

      tx.update(ref, {
        dailyAiUsed: used + 1,
        dailyAiDate: today,
        totalAiUsed: (typeof data.totalAiUsed === 'number' ? data.totalAiUsed : 0) + 1,
      });
      return { ok: true, reserved: true, dailyUsed: used + 1, dailyLimit: limit };
    });
  } catch (e) {
    console.warn('[aiAccess] reserveAiUsage error:', e.message);
    return { ok: true, skipped: true, degraded: true };
  }
}

/** Hand a reserved message back after the AI call failed (learner got nothing). */
async function releaseAiUsage(uid) {
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
      // A rollover since the reserve means today's counter is already 0 — a
      // refund would push it negative, so there is nothing to give back.
      if ((data.dailyAiDate || '') !== today) return;
      const used = typeof data.dailyAiUsed === 'number' ? data.dailyAiUsed : 0;
      const patch = { dailyAiUsed: Math.max(0, used - 1) };
      // A premium reservation under the fair-use ceiling only touches the daily
      // counter, so refunding totalAiUsed here would walk the all-time figure
      // downwards for messages it never counted.
      if (resolvePlan(data) !== 'premium') {
        const total = typeof data.totalAiUsed === 'number' ? data.totalAiUsed : 0;
        patch.totalAiUsed = Math.max(0, total - 1);
      }
      tx.update(ref, patch);
    });
  } catch (e) {
    console.warn('[aiAccess] releaseAiUsage error:', e.message);
  }
}

/**
 * Express middleware for endpoints that spend one of the learner's daily
 * messages (i.e. /tutor/chat). Mount AFTER requireAiAccess. The end-of-session
 * feedback report deliberately does NOT use this — it stays free, as before.
 */
async function requireMessageSlot(req, res, next) {
  const result = await reserveAiUsage(req.uid);
  if (!result.ok) {
    const code = result.error || 'DAILY_LIMIT_REACHED';
    const messages = {
      PREMIUM_REQUIRED: 'Premium required. Subscribe to use the AI tutor.',
      // Never tell a paying subscriber to "upgrade to Premium".
      FAIR_USE_LIMIT: "You've hit today's fair-use limit for Premium — that's a lot of practice! It resets at midnight UTC.",
      DAILY_LIMIT_REACHED: 'Daily free limit reached. Upgrade to Premium for unlimited practice.',
    };
    return res.status(403).json({
      success: false,
      error: code,
      code,
      message: messages[code] || messages.DAILY_LIMIT_REACHED,
      dailyLimit: result.dailyLimit,
      resetAtUtc: getNextMidnightUtc(),
    });
  }
  req._aiReserved = result.reserved === true; // only a real reservation is refundable
  next();
}

module.exports = {
  requireAiAccess,
  requireAuxAccess,
  requireMessageSlot,
  wrapAiHandler,
  reserveAiUsage,
  releaseAiUsage,
  reserveAuxUsage,
  releaseAuxUsage,
  refundAuxIfFallback,
  getAiAccess,
  getAuxAccess,
  grantAdReward,
  resolvePlan,
  DAILY_MESSAGES_FREE,
  DAILY_AUX_FREE,
  PREMIUM_DAILY_CAP,
  DAILY_AUX_TRIAL,
  TRIAL_DAYS,
  REQUIRE_PREMIUM,
  DEV_SKIP_LIMITS,
};
