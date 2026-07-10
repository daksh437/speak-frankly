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
  try {
    await db.collection(USERS).doc(uid).set(update, { merge: true });
    return { ok: true };
  } catch (e) {
    console.warn('[progress] save error:', e.message);
    return { ok: false };
  }
}

module.exports = { getProgress, saveProgress };
