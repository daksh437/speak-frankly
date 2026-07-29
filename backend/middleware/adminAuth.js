/**
 * Admin gate. A request is admin if the signed-in user's Firebase email is
 * either an OWNER (env allowlist, always admin) or listed in the Firestore
 * `admins` collection (added from the in-app admin panel).
 *
 * The email is resolved SERVER-SIDE from the uid via the Firebase Admin SDK —
 * never trusted from a client header — so admin access can't be spoofed.
 *
 * Bootstrap: OWNER emails come from ADMIN_OWNER_EMAILS (comma-separated). A
 * default owner is baked in so the app owner is admin out of the box.
 */
const { getAdmin, getDb } = require('../utils/firestoreAdmin');

const ADMINS = 'admins';

const OWNER_EMAILS = (process.env.ADMIN_OWNER_EMAILS || 'dakshjangir44@gmail.com')
  .split(',')
  .map((s) => s.trim().toLowerCase())
  .filter(Boolean);

/** Resolve the Firebase email for a uid (server-side, authoritative). */
async function emailForUid(uid) {
  if (!uid) return null;
  try {
    const a = getAdmin();
    if (!a) return null;
    const user = await a.auth().getUser(uid);
    return (user.email || '').toLowerCase() || null;
  } catch (_) {
    return null;
  }
}

/** Is this email an admin? Returns { isAdmin, isOwner }. */
async function isAdminEmail(email) {
  if (!email) return { isAdmin: false, isOwner: false };
  const e = email.toLowerCase();
  if (OWNER_EMAILS.includes(e)) return { isAdmin: true, isOwner: true };
  const db = getDb();
  if (!db) return { isAdmin: false, isOwner: false };
  try {
    const snap = await db.collection(ADMINS).doc(e).get();
    return { isAdmin: snap.exists, isOwner: false };
  } catch (_) {
    return { isAdmin: false, isOwner: false };
  }
}

/** Express middleware — 403 unless the caller is an admin. Sets req.adminEmail/isOwner. */
async function requireAdmin(req, res, next) {
  const uid = (req.headers['x-user-uid'] || req.headers['x-user-id'] || '').toString().trim();
  if (!uid) return res.status(401).json({ success: false, error: 'UNAUTHORIZED' });
  const email = await emailForUid(uid);
  const { isAdmin, isOwner } = await isAdminEmail(email);
  if (!isAdmin) return res.status(403).json({ success: false, error: 'NOT_ADMIN' });
  req.adminEmail = email;
  req.isOwner = isOwner;
  next();
}

module.exports = { requireAdmin, isAdminEmail, emailForUid, OWNER_EMAILS, ADMINS };
