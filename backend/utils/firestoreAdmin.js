/**
 * Firestore Admin (adapted from InstaFlow). Backend is the source of truth for
 * usage limits. Uses a NEW Firebase project — no hardcoded Insta Flow default.
 *
 * Auth (one of):
 * - FIREBASE_SERVICE_ACCOUNT_JSON — stringified service-account JSON in .env
 * - GOOGLE_APPLICATION_CREDENTIALS — path to service-account JSON file
 * Project id: FIREBASE_PROJECT_ID / GCLOUD_PROJECT (from the service account if present).
 *
 * If no credentials are set, getDb() returns null and callers run in a degraded
 * (allow-through) mode — fine for local development before Firebase is wired.
 */
let admin;
let db;
let initError = null;

function resolveProjectId(cred) {
  return (
    cred?.project_id ||
    process.env.FIREBASE_PROJECT_ID ||
    process.env.GCLOUD_PROJECT ||
    process.env.GOOGLE_CLOUD_PROJECT ||
    null
  );
}

function normalizeServiceAccount(raw) {
  const parsed = JSON.parse(raw);
  if (!parsed || typeof parsed !== 'object') throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON must be valid JSON');
  for (const field of ['project_id', 'client_email', 'private_key']) {
    if (!parsed[field]) throw new Error(`Service account missing ${field}`);
  }
  if (typeof parsed.private_key === 'string') {
    parsed.private_key = parsed.private_key.replace(/\\n/g, '\n');
  }
  return parsed;
}

function getAdmin() {
  if (admin) return admin;
  try {
    // NOTE: only cache the namespace once an app is actually initialized.
    // Caching it before the credential check meant the first (degraded) call
    // returned null but every later call handed back an UNinitialized
    // namespace — and `a.firestore()` on that throws app/no-app, crashing the
    // process on the second request instead of staying degraded.
    const a = require('firebase-admin');
    if (!a.apps.length) {
      const key = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
      if (key && key.trim()) {
        const cred = normalizeServiceAccount(key);
        a.initializeApp({
          credential: a.credential.cert(cred),
          projectId: resolveProjectId(cred),
        });
      } else if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
        a.initializeApp({ projectId: resolveProjectId() });
      } else {
        // No credentials — degraded mode. Not fatal in development.
        initError = new Error('No Firebase credentials set (degraded mode)');
        return null;
      }
    }
    admin = a;
    initError = null;
    return admin;
  } catch (e) {
    initError = e;
    console.warn('[FirestoreAdmin] init failed:', e.message);
    return null;
  }
}

function getDb() {
  if (db) return db;
  const a = getAdmin();
  if (!a) return null;
  try {
    db = a.firestore();
    return db;
  } catch (e) {
    initError = e;
    console.warn('[FirestoreAdmin] firestore() failed:', e.message);
    return null;
  }
}

function getInitStatus() {
  return {
    firestoreReady: !!getDb(),
    projectId: resolveProjectId(),
    initError: initError ? String(initError.message || initError) : null,
  };
}

module.exports = { getAdmin, getDb, getInitStatus };
