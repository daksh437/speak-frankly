/**
 * Admin panel API. `GET /admin/me` is callable by anyone (the app uses it to
 * decide whether to show the Admin entry). Everything else requires admin.
 */
const express = require('express');
const { getDb, getAdmin } = require('../utils/firestoreAdmin');
const { requireAdmin, adminEmailOf, isAdminEmail, OWNER_EMAILS, ADMINS } = require('../middleware/adminAuth');
const { resolvePlan } = require('../middleware/aiAccess');

const router = express.Router();

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

/** Revoke admin. Owners (from env) can't be removed here. */
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

/** Basic stats for the dashboard. */
router.get('/stats', async (req, res) => {
  const db = getDb();
  if (!db) return res.json({ success: true, data: { total: 0, premium: 0, trial: 0, free: 0, degraded: true } });
  try {
    const snap = await db.collection('users').get();
    let total = 0, premium = 0, trial = 0, free = 0;
    const now = new Date();
    snap.forEach((d) => {
      total++;
      const p = resolvePlan(d.data(), now);
      if (p === 'premium') premium++;
      else if (p === 'trial') trial++;
      else free++;
    });
    res.json({ success: true, data: { total, premium, trial, free } });
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
    await db.collection('users').doc(user.uid).set(
      { planType: 'premium', premiumExpiry, premiumVerified: false, grantedByAdmin: req.adminEmail, grantedAt: new Date() },
      { merge: true },
    );
    res.json({ success: true, data: { email, uid: user.uid, premiumExpiry: premiumExpiry.toISOString(), days } });
  } catch (e) {
    res.status(404).json({ success: false, error: 'USER_NOT_FOUND', message: e.message });
  }
});

module.exports = router;
