/**
 * Admin gate. A request is admin if the signed-in user's Firebase email is
 * either an OWNER (env allowlist, always admin) or listed in the Firestore
 * `admins` collection (added from the in-app admin panel).
 *
 * The email is resolved SERVER-SIDE from the VERIFIED ID token (or from the uid
 * via the Firebase Admin SDK) — never trusted from a client header.
 *
 * Admin is the one place that never runs in legacy header mode: resolving an
 * email from a claimed uid still trusts the caller's uid, so knowing the
 * owner's uid string would have been enough to grant premium or add admins.
 * requireAdmin therefore demands a verified token even while REQUIRE_AUTH_TOKEN
 * is off for the rest of the API.
 *
 * Bootstrap: OWNER emails come from ADMIN_OWNER_EMAILS (comma-separated). A
 * default owner is baked in so the app owner is admin out of the box.
 */
const { getAdmin, getDb } = require('../utils/firestoreAdmin');
const { authenticate } = require('./auth');

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

/**
 * Resolve the caller's admin email from a VERIFIED sign-in only.
 * Returns null for anonymous/legacy-header callers.
 */
async function adminEmailOf(req) {
  await authenticate(req);
  if (!req.uidVerified || !req.uid) return null;
  return req.authEmail || (await emailForUid(req.uid));
}

/** Express middleware — 403 unless the caller is an admin. Sets req.adminEmail/isOwner. */
async function requireAdmin(req, res, next) {
  const email = await adminEmailOf(req);
  if (!email) {
    return res.status(401).json({
      success: false,
      error: 'UNAUTHORIZED',
      code: 'AUTH_TOKEN_REQUIRED',
      message: 'Admin actions require a verified sign-in (update the app).',
    });
  }
  const { isAdmin, isOwner } = await isAdminEmail(email);
  if (!isAdmin) return res.status(403).json({ success: false, error: 'NOT_ADMIN' });
  req.adminEmail = email;
  req.isOwner = isOwner;
  next();
}

module.exports = { requireAdmin, adminEmailOf, isAdminEmail, emailForUid, OWNER_EMAILS, ADMINS };
