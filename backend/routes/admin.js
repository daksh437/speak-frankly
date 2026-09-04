/**
 * Admin panel API. `GET /admin/me` is callable by anyone (the app uses it to
 * decide whether to show the Admin entry). Everything else requires admin.
 *
 * Everything here is computed from live Firestore documents plus the running
 * process's own counters — there are no placeholder or sample numbers. When a
 * value cannot be read we say so (`degraded: true`) instead of returning zeros
 * that look like real data.
 */
const express = require('express');
const { getDb, getAdmin } = require('../utils/firestoreAdmin');
const { requireAdmin, adminEmailOf, isAdminEmail, OWNER_EMAILS, ADMINS } = require('../middleware/adminAuth');
const {
  resolvePlan,
  DAILY_MESSAGES_FREE,
  DAILY_AUX_FREE,
  TRIAL_DAYS,
  REQUIRE_PREMIUM,
} = require('../middleware/aiAccess');
const { toDate, dayStr } = require('../utils/dates');
const { getAiStats, MODEL, MODELS, hasKey } = require('../utils/geminiClient');
const { getAuthStats } = require('../middleware/auth');

const router = express.Router();

const USERS = 'users';
const REPORTS = 'ai_reports';
const DEVICES = 'trial_devices';

const iso = (v) => {
  const d = toDate(v);
  return d ? d.toISOString() : null;
};

/**
 * Collection size via the aggregate API, with a bounded fallback.
 *
 * Returns null when the real count is unknown — including when the fallback
 * scan hits its own cap. Returning the cap would show "1000" as though it were
 * the true total; null renders as a dash, which is the honest answer.
 */
const COUNT_SCAN_CAP = 1000;

// How many user documents the dashboard will read to build its breakdowns.
// Well past the point where the panel stops being read one row at a time, and
// low enough that a refresh can never turn into an unbounded bill.
const USER_SCAN_CAP = 5000;

async function countOf(db, name, filter) {
  try {
    let q = db.collection(name);
    if (filter) q = q.where(filter[0], filter[1], filter[2]);
    const agg = await q.count().get();
    return agg.data().count;
  } catch (_) {
    try {
      let q = db.collection(name);
      if (filter) q = q.where(filter[0], filter[1], filter[2]);
      const snap = await q.limit(COUNT_SCAN_CAP).get();
      return snap.size >= COUNT_SCAN_CAP ? null : snap.size;
    } catch (_e) {
      return null;
    }
  }
}

/**
 * Whether the caller is an admin (app shows/hides the Admin entry from this).
 * Only answers for a verified sign-in — it used to hand back the email behind
 * any claimed uid, which leaked account emails to anyone who had a uid.
 */
router.get('/me', async (req, res) => {
  const email = await adminEmailOf(req);
  if (!email) return res.json({ success: true, data: { isAdmin: false, isOwner: false, email: null } });
  const { isAdmin, isOwner } = await isAdminEmail(email);
  res.json({ success: true, data: { isAdmin, isOwner, email } });
});

// ---- everything below requires admin ----
router.use(requireAdmin);

/** List admins (owners + Firestore admins). */
router.get('/admins', async (req, res) => {
  const out = OWNER_EMAILS.map((e) => ({ email: e, role: 'owner' }));
  const db = getDb();
  if (db) {
    try {
      const snap = await db.collection(ADMINS).get();
      snap.forEach((d) => {
        if (!OWNER_EMAILS.includes(d.id)) {
          out.push({ email: d.id, role: 'admin', addedBy: d.data().addedBy || null });
        }
      });
    } catch (e) {
      console.warn('[admin] list error:', e.message);
    }
  }
  res.json({ success: true, data: { admins: out, you: req.adminEmail, isOwner: req.isOwner } });
});

/** Grant admin to a Gmail/email. */
router.post('/admins', async (req, res) => {
  const email = (req.body && req.body.email ? String(req.body.email) : '').trim().toLowerCase();
  if (!email || !email.includes('@')) return res.status(400).json({ success: false, error: 'INVALID_EMAIL' });
  const db = getDb();
  if (!db) return res.status(503).json({ success: false, error: 'NO_DB' });
  try {
    await db.collection(ADMINS).doc(email).set({ email, addedBy: req.adminEmail, addedAt: new Date() }, { merge: true });
    res.json({ success: true, data: { email } });
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

/** Revoke admin. Owners (from env) cannot be removed here. */
router.delete('/admins/:email', async (req, res) => {
  const email = (req.params.email || '').trim().toLowerCase();
  if (OWNER_EMAILS.includes(email)) return res.status(400).json({ success: false, error: 'CANNOT_REMOVE_OWNER' });
  const db = getDb();
  if (!db) return res.status(503).json({ success: false, error: 'NO_DB' });
  try {
    await db.collection(ADMINS).doc(email).delete();
    res.json({ success: true, data: { email } });
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

/**
 * Dashboard numbers. One pass over the users collection produces the plan mix,
 * signups, active learners and today's AI usage; the rest comes from the
 * reports/devices collections and this process's own AI + auth counters.
 */
router.get('/stats', async (req, res) => {
  const db = getDb();
  const config = {
    dailyMessagesFree: DAILY_MESSAGES_FREE,
    dailyAuxFree: DAILY_AUX_FREE,
    trialDays: TRIAL_DAYS,
    requirePremium: REQUIRE_PREMIUM,
    geminiModel: MODEL,
    geminiModels: MODELS,
    geminiLive: hasKey(),
  };
  if (!db) {
    return res.json({ success: true, data: { degraded: true, config, ai: getAiStats(), auth: getAuthStats() } });
  }

  try {
    const now = new Date();
    const today = dayStr(now);
    const since7 = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    const since30 = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);

    // Every figure below except `total` has to be derived per document, because
    // a plan is resolved from dates rather than stored - so this reads user
    // documents, and it used to read ALL of them, unbounded, on every refresh.
    // That is a full collection transfer billed per document, and it grows with
    // the thing it is measuring. Capped now, with the truth about the cap
    // reported alongside (see `partial`) rather than a smaller number passed
    // off as the whole picture.
    const snap = await db.collection(USERS).limit(USER_SCAN_CAP).get();
    const scanned = snap.size;
    const partial = scanned >= USER_SCAN_CAP;
    const s = {
      total: 0, premium: 0, trial: 0, free: 0,
      premiumVerified: 0, premiumGranted: 0,
      newToday: 0, new7d: 0, new30d: 0,
      activeToday: 0, active7d: 0,
      messagesToday: 0, auxToday: 0, adRewardsToday: 0,
      messagesAllTime: 0, atLimitToday: 0, withEmail: 0,
    };

    snap.forEach((doc) => {
      const u = doc.data();
      s.total++;

      const plan = resolvePlan(u, now);
      if (plan === 'premium') {
        s.premium++;
        if (u.premiumVerified === true) s.premiumVerified++;
        else s.premiumGranted++;
      } else if (plan === 'trial') s.trial++;
      else s.free++;

      const created = toDate(u.createdAt);
      if (created) {
        if (dayStr(created) === today) s.newToday++;
        if (created >= since7) s.new7d++;
        if (created >= since30) s.new30d++;
      }

      const usedToday = u.dailyAiDate === today ? Number(u.dailyAiUsed) || 0 : 0;
      if (usedToday > 0) s.activeToday++;
      s.messagesToday += usedToday;
      // A learner who watched a rewarded ad has a HIGHER cap today, so compare
      // against their effective limit — measuring everyone against the base
      // free limit counted ad-watchers as blocked while they still had messages
      // left, inflating the "hit daily limit" (i.e. upgrade prompt) number.
      const bonusToday = (u.bonusDate === today && typeof u.bonusMessages === 'number')
        ? Math.max(0, u.bonusMessages)
        : 0;
      if (plan === 'free' && usedToday >= DAILY_MESSAGES_FREE + bonusToday) s.atLimitToday++;

      // lastActive is written by the app's progress sync as YYYY-MM-DD.
      const last = toDate(u.lastSeenAt) || toDate(u.lastActive) || toDate(u.dailyAiDate);
      if (last && last >= since7) s.active7d++;

      s.auxToday += u.dailyAuxDate === today ? Number(u.dailyAuxUsed) || 0 : 0;
      s.adRewardsToday += u.bonusDate === today ? Number(u.adRewardsToday) || 0 : 0;
      s.messagesAllTime += Number(u.totalAiUsed) || 0;
      if (u.email) s.withEmail++;
    });

    const [reportsTotal, reportsNew, trialDevices, userTotal] = await Promise.all([
      countOf(db, REPORTS),
      countOf(db, REPORTS, ['status', '==', 'new']),
      countOf(db, DEVICES),
      // The aggregate count is the real total even when the scan was capped -
      // it is answered server-side without shipping the documents.
      countOf(db, USERS),
    ]);
    if (typeof userTotal === 'number') s.total = userTotal;

    res.json({
      success: true,
      data: {
        ...s,
        scanned,
        partial,
        reportsTotal,
        reportsNew,
        trialDevices,
        ai: getAiStats(),
        auth: getAuthStats(),
        config,
        generatedAt: now.toISOString(),
      },
    });
  } catch (e) {
    console.warn('[admin] stats error:', e.message);
    res.status(500).json({ success: false, error: e.message });
  }
});

/**
 * Recent learners, newest first. Emails come from Firebase Auth (batched, max
 * 100 per call) so the list shows real accounts even for docs written before we
 * started storing the email alongside the usage counters.
 */
router.get('/users', async (req, res) => {
  const db = getDb();
  const a = getAdmin();
  if (!db) return res.json({ success: true, data: { users: [], degraded: true } });

  const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 50, 1), 100);
  try {
    let docs = [];
    try {
      const snap = await db.collection(USERS).orderBy('createdAt', 'desc').limit(limit).get();
      docs = snap.docs;
    } catch (_) {
      docs = [];
    }
    if (docs.length < limit) {
      // Docs written before we started stamping createdAt (progress sync used to
      // create them) are invisible to orderBy — top the page up so the list
      // shows every real learner, not just the recently provisioned ones.
      const seen = new Set(docs.map((d) => d.id));
      const extra = await db.collection(USERS).limit(limit).get();
      extra.docs.forEach((d) => {
        if (!seen.has(d.id) && docs.length < limit) docs.push(d);
      });
    }

    // Batch-resolve emails for docs that do not carry one yet. A uid with no
    // Firebase Auth account is not a learner at all — it is a leftover doc from
    // a curl/smoke check, so we flag it instead of showing it as a real user.
    const missing = docs.filter((d) => !d.data().email).map((d) => ({ uid: d.id }));
    const emails = new Map();
    const known = new Set();
    if (a && missing.length) {
      try {
        const result = await a.auth().getUsers(missing.slice(0, 100));
        result.users.forEach((u) => {
          known.add(u.uid);
          emails.set(u.uid, (u.email || '').toLowerCase() || null);
        });
      } catch (e) {
        console.warn('[admin] getUsers error:', e.message);
      }
    }

    const now = new Date();
    const today = dayStr(now);
    const users = docs.map((d) => {
      const u = d.data();
      return {
        uid: d.id,
        email: u.email || emails.get(d.id) || null,
        displayName: u.displayName || null,
        // No email on the doc AND no Auth account behind the uid → leftover
        // test document, not a person.
        hasAccount: !!(u.email || known.has(d.id)),
        plan: resolvePlan(u, now),
        premiumVerified: u.premiumVerified === true,
        level: u.level || null,
        streak: Number(u.streak) || 0,
        xp: Number(u.xp) || 0,
        savedWords: Array.isArray(u.savedWords) ? u.savedWords.length : 0,
        messagesToday: u.dailyAiDate === today ? Number(u.dailyAiUsed) || 0 : 0,
        messagesAllTime: Number(u.totalAiUsed) || 0,
        createdAt: iso(u.createdAt),
        lastSeenAt: iso(u.lastSeenAt) || iso(u.lastActive),
        trialEndsAt: iso(u.trialEndsAt),
        premiumExpiry: iso(u.premiumExpiry),
      };
    });

    res.json({ success: true, data: { users, count: users.length } });
  } catch (e) {
    console.warn('[admin] users error:', e.message);
    res.status(500).json({ success: false, error: e.message });
  }
});

/**
 * Reported AI replies (Play's generative-AI policy expects us to act on these).
 * Newest first; `status` flips to 'reviewed' via POST /admin/reports/:id/review.
 */
router.get('/reports', async (req, res) => {
  const db = getDb();
  if (!db) return res.json({ success: true, data: { reports: [], degraded: true } });
  try {
    const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 50, 1), 200);
    const snap = await db.collection(REPORTS).orderBy('createdAt', 'desc').limit(limit).get();
    const reports = snap.docs.map((d) => {
      const r = d.data();
      return {
        id: d.id,
        text: r.text || '',
        reason: r.reason || 'other',
        note: r.note || '',
        scenarioId: r.scenarioId || '',
        email: r.email || null,
        status: r.status || 'new',
        createdAt: iso(r.createdAt),
      };
    });
    res.json({ success: true, data: { reports, newCount: reports.filter((r) => r.status === 'new').length } });
  } catch (e) {
    console.warn('[admin] reports error:', e.message);
    res.status(500).json({ success: false, error: e.message });
  }
});

/** Mark a report reviewed (so the queue shows what still needs attention). */
router.post('/reports/:id/review', async (req, res) => {
  const db = getDb();
  if (!db) return res.status(503).json({ success: false, error: 'NO_DB' });
  try {
    await db.collection(REPORTS).doc(req.params.id).set(
      { status: 'reviewed', reviewedBy: req.adminEmail, reviewedAt: new Date() },
      { merge: true },
    );
    res.json({ success: true, data: { id: req.params.id, status: 'reviewed' } });
  } catch (e) {
    res.status(500).json({ success: false, error: e.message });
  }
});

/** Support tool: grant premium to a user by email for N days (default 31). */
router.post('/grant-premium', async (req, res) => {
  const email = (req.body && req.body.email ? String(req.body.email) : '').trim().toLowerCase();
  const days = Math.min(Math.max(parseInt(req.body && req.body.days, 10) || 31, 1), 3650);
  if (!email || !email.includes('@')) return res.status(400).json({ success: false, error: 'INVALID_EMAIL' });
  const a = getAdmin();
  const db = getDb();
  if (!a || !db) return res.status(503).json({ success: false, error: 'NO_DB' });
  try {
    const user = await a.auth().getUserByEmail(email);
    const premiumExpiry = new Date(Date.now() + days * 24 * 60 * 60 * 1000);
    await db.collection(USERS).doc(user.uid).set(
      { planType: 'premium', premiumExpiry, premiumVerified: false, grantedByAdmin: req.adminEmail, grantedAt: new Date() },
      { merge: true },
    );
    res.json({ success: true, data: { email, uid: user.uid, premiumExpiry: premiumExpiry.toISOString(), days } });
  } catch (e) {
    res.status(404).json({ success: false, error: 'USER_NOT_FOUND', message: e.message });
  }
});

module.exports = router;
