/**
 * Who is calling? — Firebase ID token verification.
 *
 * The app signs in with Google (Firebase Auth) and sends the resulting ID token
 * as `Authorization: Bearer <token>`. We verify it server-side with the Admin
 * SDK, so the uid is PROVEN rather than claimed. Before this, every route read
 * `x-user-uid` straight off the request, which meant anyone could send any uid:
 * farm endless free trials, read/overwrite another learner's progress, or hit
 * the admin panel with the owner's uid.
 *
 * ROLLOUT (important): app versions already installed on phones only send the
 * old header. Rejecting them would break live users mid-session, so the default
 * is SOFT mode — a verified token wins; a bare header still works and is
 * counted. Once /health shows legacyHeaderAuth ≈ 0 (i.e. almost everyone is on
 * a build that sends the token), set REQUIRE_AUTH_TOKEN=true on Render to make
 * verification mandatory. Admin routes are always hard-verified regardless.
 */
const { getAdmin } = require('../utils/firestoreAdmin');

const REQUIRE_AUTH_TOKEN =
  process.env.REQUIRE_AUTH_TOKEN === 'true' || process.env.REQUIRE_AUTH_TOKEN === '1';
const DEV_SKIP_LIMITS =
  process.env.DEV_SKIP_LIMITS === 'true' || process.env.DEV_SKIP_LIMITS === '1';

// Rollout telemetry (in-memory, per instance) — surfaced on /health so we can
// see when it's safe to flip REQUIRE_AUTH_TOKEN on.
const stats = { verified: 0, legacyHeader: 0, invalidToken: 0 };

function headerUid(req) {
  return (req.headers['x-user-uid'] || req.headers['x-user-id'] || '').toString().trim();
}

function bearerToken(req) {
  const raw = (req.headers.authorization || req.headers.Authorization || '').toString().trim();
  const m = /^Bearer\s+(.+)$/i.exec(raw);
  return m ? m[1].trim() : '';
}

/** Verify the bearer token. Returns { uid, email } or null. */
async function verifyToken(token) {
  if (!token) return null;
  const a = getAdmin();
  if (!a) return null; // degraded (no Firebase creds) — soft mode handles it
  try {
    const decoded = await a.auth().verifyIdToken(token);
    return { uid: decoded.uid, email: (decoded.email || '').toLowerCase() || null };
  } catch (e) {
    stats.invalidToken++;
    console.warn('[auth] invalid ID token:', e.message);
    return null;
  }
}

/**
 * Populate req.uid / req.uidVerified / req.authEmail. Never rejects — callers
 * decide what an unauthenticated request means for them.
 */
async function authenticate(req) {
  if (req.uid !== undefined) return req; // already resolved on this request

  const verified = await verifyToken(bearerToken(req));
  if (verified) {
    stats.verified++;
    req.uid = verified.uid;
    req.uidVerified = true;
    req.authEmail = verified.email;
    return req;
  }

  const claimed = headerUid(req);
  if (claimed && !REQUIRE_AUTH_TOKEN) {
    stats.legacyHeader++;
    req.uid = claimed; // legacy client (or local dev) — trusted only in soft mode
    req.uidVerified = false;
    req.authEmail = null;
    return req;
  }

  req.uid = '';
  req.uidVerified = false;
  req.authEmail = null;
  return req;
}

/** Express middleware: 401 unless we could resolve a uid. */
async function requireAuth(req, res, next) {
  if (DEV_SKIP_LIMITS) {
    req.uid = req.uid || headerUid(req) || 'dev-skip';
    req.uidVerified = true;
    return next();
  }
  await authenticate(req);
  if (!req.uid) {
    return res.status(401).json({
      success: false,
      error: 'UNAUTHORIZED',
      code: REQUIRE_AUTH_TOKEN ? 'AUTH_TOKEN_REQUIRED' : 'UNAUTHORIZED',
      message: REQUIRE_AUTH_TOKEN
        ? 'Sign in again — this app version is out of date.'
        : 'Missing credentials',
    });
  }
  next();
}

/** Express middleware: 401 unless the uid came from a VERIFIED token. */
async function requireVerifiedAuth(req, res, next) {
  await authenticate(req);
  if (!req.uidVerified || !req.uid) {
    return res.status(401).json({
      success: false,
      error: 'UNAUTHORIZED',
      code: 'AUTH_TOKEN_REQUIRED',
      message: 'A verified sign-in is required for this action.',
    });
  }
  next();
}

function getAuthStats() {
  return { ...stats, requireAuthToken: REQUIRE_AUTH_TOKEN };
}

module.exports = {
  authenticate,
  requireAuth,
  requireVerifiedAuth,
  verifyToken,
  getAuthStats,
  REQUIRE_AUTH_TOKEN,
};
