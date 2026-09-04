/**
 * The guard that stops a sync push from erasing a learner's progress.
 *
 * The app clears its local stores on sign-out and on an account switch, and
 * clearing them notifies the sync listeners, which push the emptied state back
 * to the server under the uid the client is still sending. Every counter
 * arrives as 0 and the word list as [], and the learner's history is gone.
 *
 * The client fix only reaches builds people have installed. This guard protects
 * every install that already exists, so it is the one that actually has to be
 * right — and it is pure, so it can be checked exactly.
 *
 * The rule is the one the client already believes (GamificationService.mergeFrom
 * takes the higher of each counter): these numbers only rise. Saved words are
 * allowed to shrink, because words get deleted on purpose — but not to vanish
 * in a single write, which is a wipe rather than an edit.
 *
 * Usage: node tests/progress-guard.test.js
 */
const { guardProgress } = require('../controllers/progressController');

let failures = 0;
const check = (name, cond) => {
  if (cond) console.log(`  ✅ ${name}`);
  else {
    console.error(`  ❌ ${name}`);
    failures++;
  }
};

const wipe = () => ({
  streak: 0, xp: 0, scenariosCompleted: 0, speakingReps: 0,
  lastActive: '', savedWords: [],
});

const established = {
  streak: 12, xp: 840, scenariosCompleted: 9, speakingReps: 31,
  lastActive: '2026-09-03', savedWords: [{ word: 'appreciate' }, { word: 'fluent' }],
};

console.log('\n— a sign-out wipe must not land —');

{
  const { update, dropped } = guardProgress(wipe(), established);
  check('the streak is kept', update.streak === undefined);
  check('the XP is kept', update.xp === undefined);
  check('completed scenarios are kept', update.scenariosCompleted === undefined);
  check('speaking reps are kept', update.speakingReps === undefined);
  check('the saved words are kept', update.savedWords === undefined);
  check('every field is reported as refused', dropped.length === 5);
}

console.log('\n— real progress still writes —');

{
  const higher = { ...wipe(), streak: 13, xp: 900, scenariosCompleted: 10, speakingReps: 35, savedWords: [{ word: 'a' }] };
  const { update, dropped } = guardProgress(higher, established);
  check('a higher streak is written', update.streak === 13);
  check('higher XP is written', update.xp === 900);
  check('more completed scenarios are written', update.scenariosCompleted === 10);
  check('more speaking reps are written', update.speakingReps === 35);
  check('nothing is refused', dropped.length === 0);
}

{
  // The same numbers again — an idle push. Equal is not lower, so it passes.
  const { update, dropped } = guardProgress({ ...established }, established);
  check('an unchanged push is not treated as a wipe', dropped.length === 0);
  check('and it still writes', update.xp === 840);
}

console.log('\n— deleting words on purpose still works —');

{
  const fewer = { ...wipe(), streak: 12, xp: 840, scenariosCompleted: 9, speakingReps: 31, savedWords: [{ word: 'fluent' }] };
  const { update, dropped } = guardProgress(fewer, established);
  check('a shorter word list is allowed through', Array.isArray(update.savedWords) && update.savedWords.length === 1);
  check('nothing is refused', dropped.length === 0);
}

console.log('\n— partial damage is caught field by field —');

{
  // XP lost but the streak advanced: keep the stored XP, take the new streak.
  const mixed = { ...wipe(), streak: 13, xp: 0, scenariosCompleted: 9, speakingReps: 31, savedWords: established.savedWords };
  const { update, dropped } = guardProgress(mixed, established);
  check('the lost XP is refused', update.xp === undefined);
  check('the advanced streak is accepted', update.streak === 13);
  check('only the damaged field is reported', dropped.length === 1 && dropped[0] === 'xp');
}

console.log('\n— a genuinely new account is not blocked —');

{
  const { update, dropped } = guardProgress(wipe(), null);
  check('no stored document → nothing to protect', dropped.length === 0);
  check('the write goes through untouched', update.xp === 0 && Array.isArray(update.savedWords));
}

{
  const empty = {};
  const { dropped } = guardProgress({ ...wipe(), xp: 5 }, empty);
  check('an empty stored document blocks nothing', dropped.length === 0);
}

console.log('\n— the profile fields are never touched —');

{
  const withProfile = { ...wipe(), level: 'B1', displayName: 'Daksh', onboarded: true };
  const { update } = guardProgress(withProfile, established);
  check('level survives the guard', update.level === 'B1');
  check('display name survives the guard', update.displayName === 'Daksh');
  check('onboarded survives the guard', update.onboarded === true);
}

if (failures) {
  console.error(`\n❌ ${failures} progress-guard check(s) failed.`);
  process.exit(1);
}
console.log('\n✅ All progress-guard checks passed.');
