/**
 * Cloud sync for a learner's gamification + saved vocabulary. Stored on the
 * user's Firestore doc so progress survives reinstalls and follows the account
 * across devices. Best-effort: if Firestore is unavailable, returns empty / no-op.
 */
const { getDb } = require('../utils/firestoreAdmin');

const USERS = 'users';

async function getProgress(uid) {
  const db = getDb();
  if (!db || !uid) return {};
  try {
    const snap = await db.collection(USERS).doc(uid).get();
    if (!snap.exists) return {};
    const d = snap.data();
    return {
      streak: d.streak || 0,
      xp: d.xp || 0,
      scenariosCompleted: d.scenariosCompleted || 0,
      speakingReps: d.speakingReps || 0,
      lastActive: d.lastActive || '',
      savedWords: Array.isArray(d.savedWords) ? d.savedWords : [],
      // Per-account profile so onboarding/level follow the Google account.
      onboarded: d.onboarded === true,
      level: d.level || '',
      goal: d.goal || '',
      nativeLanguage: d.nativeLanguage || '',
      displayName: d.displayName || '',
    };
  } catch (e) {
    console.warn('[progress] get error:', e.message);
    return {};
  }
}

// Counters that only ever go up. The app merges cloud state by taking the
// higher of each (GamificationService.mergeFrom), so a lower number arriving
// here is not a correction — it is a client that has lost its local copy.
const MONOTONIC = ['streak', 'xp', 'scenariosCompleted', 'speakingReps'];

/**
 * Refuse a write that would destroy progress, and keep the rest of it.
 *
 * The app clears its local stores on sign-out and on an account switch, and
 * clearing them notifies the sync listeners — which then push the emptied state
 * back here under the uid the client is still sending. Every counter goes to
 * zero and the word list to empty, and the learner's history is gone. The fix
 * on the client is to suspend syncing around the wipe, but that only helps
 * builds people have actually installed; this guard protects every existing
 * install, today, and stays as the backstop afterwards.
 *
 * The rule is the one the client already believes: these counters only rise.
 * A saved-word list is allowed to shrink (words get deleted on purpose) but not
 * to vanish in one write, which is the signature of a wipe rather than an edit.
 */
function guardProgress(update, existing) {
  if (!existing) return { update, dropped: [] };
  const dropped = [];
  for (const key of MONOTONIC) {
    const was = Number(existing[key]) || 0;
    if (was > (Number(update[key]) || 0)) {
      delete update[key];
      dropped.push(key);
    }
  }
  const hadWords = Array.isArray(existing.savedWords) ? existing.savedWords.length : 0;
  const nowWords = Array.isArray(update.savedWords) ? update.savedWords.length : 0;
  if (hadWords > 0 && nowWords === 0) {
    delete update.savedWords;
    dropped.push('savedWords');
  }
  return { update, dropped };
}

async function saveProgress(uid, body) {
  const db = getDb();
  if (!db || !uid) return { ok: false };
  const data = body || {};
  const update = {
    streak: Number(data.streak) || 0,
    xp: Number(data.xp) || 0,
    scenariosCompleted: Number(data.scenariosCompleted) || 0,
    speakingReps: Number(data.speakingReps) || 0,
    lastActive: String(data.lastActive || ''),
    savedWords: Array.isArray(data.savedWords) ? data.savedWords.slice(0, 500) : [],
  };
  if (typeof data.onboarded === 'boolean') update.onboarded = data.onboarded;
  if (data.level != null) update.level = String(data.level);
  if (data.goal != null) update.goal = String(data.goal);
  if (data.nativeLanguage != null) update.nativeLanguage = String(data.nativeLanguage);
  if (data.displayName != null) update.displayName = String(data.displayName);
  const ref = db.collection(USERS).doc(uid);
  try {
    // Read-then-write in a transaction: two pushes racing must not let the
    // second one through on a stale view of what the learner had.
    const dropped = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const guarded = guardProgress(update, snap.exists ? snap.data() : null);
      tx.set(ref, guarded.update, { merge: true });
      return guarded.dropped;
    });
    if (dropped.length) {
      console.warn(`[progress] refused to lower ${dropped.join(', ')} for ${uid} (kept the stored values)`);
    }
    return { ok: true, guarded: dropped.length > 0 };
  } catch (e) {
    console.warn('[progress] save error:', e.message);
    return { ok: false };
  }
}

module.exports = { getProgress, saveProgress, guardProgress };
