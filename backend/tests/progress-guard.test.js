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
const { guardProgress, mergeProgressDays, clampProgressDays } = require('../controllers/progressController');

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

console.log('\n- the day-by-day outcome history -');

{
  const c = clampProgressDays({
    '2026-09-04': { s: 1, t: 8, c: 2, ps: 80, pc: 1, wm: 5 },
    'not-a-date': { s: 9 },
    '2026-9-4': { s: 9 },
    '2026-09-03': { s: '2', t: -4, c: null, ps: 1.9, pc: 1, wm: 0 },
  });
  check('a malformed key is dropped', c['not-a-date'] === undefined);
  check('an unpadded date is dropped', c['2026-9-4'] === undefined);
  check('a numeric string is coerced', c['2026-09-03'].s === 2);
  check('a negative count becomes 0', c['2026-09-03'].t === 0);
  check('a null count becomes 0', c['2026-09-03'].c === 0);
  check('a fraction is floored', c['2026-09-03'].ps === 1);
  check('a good day survives intact', c['2026-09-04'].t === 8 && c['2026-09-04'].wm === 5);
}

{
  // A reinstalled client knows only today, and knows less of it than the
  // server does. Neither the missing days nor the fuller day may be lost.
  const incoming = { '2026-09-04': { s: 1, t: 8, c: 2, ps: 0, pc: 0, wm: 0 } };
  const existing = {
    '2026-09-04': { s: 3, t: 20, c: 2, ps: 170, pc: 2, wm: 9 },
    '2026-09-01': { s: 2, t: 10, c: 5, ps: 0, pc: 0, wm: 3 },
  };
  const m = mergeProgressDays(incoming, existing);
  check('a day the client never had is kept', m['2026-09-01'].t === 10);
  check('the fuller reading of a shared day wins', m['2026-09-04'].t === 20);
  check('sessions take the higher count', m['2026-09-04'].s === 3);
  check('mastered words take the higher count', m['2026-09-04'].wm === 9);
}

{
  // Pronunciation is a sum over a count. Taking each field's max separately
  // would pair a big sum with a small count and invent an average.
  const m = mergeProgressDays(
    { '2026-09-04': { s: 1, t: 5, c: 1, ps: 95, pc: 1, wm: 0 } },
    { '2026-09-04': { s: 1, t: 5, c: 1, ps: 120, pc: 3, wm: 0 } },
  );
  check('the reading with more attempts wins the sum', m['2026-09-04'].ps === 120);
  check('...and its count comes with it', m['2026-09-04'].pc === 3);
  check('so the average stays real', m['2026-09-04'].ps / m['2026-09-04'].pc === 40);
}

{
  const m = mergeProgressDays({ '2026-09-04': { s: 1, t: 9, c: 1, ps: 0, pc: 0, wm: 0 } }, null);
  check('no stored history means the incoming one stands', m['2026-09-04'].t === 9);
}

{
  // Re-sending the same day changes nothing, which is what lets this sync
  // without any de-duplication.
  const day = { '2026-09-04': { s: 2, t: 12, c: 3, ps: 150, pc: 2, wm: 4 } };
  const once = mergeProgressDays(day, day);
  const twice = mergeProgressDays(once, once);
  check('re-sending a day is a no-op', JSON.stringify(twice) === JSON.stringify(day));
}

{
  const many = {};
  for (let i = 1; i <= 260; i++) {
    const d = new Date(Date.UTC(2026, 0, i));
    many[d.toISOString().slice(0, 10)] = { s: 1, t: 1, c: 0, ps: 0, pc: 0, wm: 0 };
  }
  const c = clampProgressDays(many);
  check('the history is capped', Object.keys(c).length === 200);
  check('and it is the NEWEST days that are kept', c[Object.keys(many).sort().pop()] !== undefined);
}

{
  const guarded = guardProgress({ ...wipe(), progressDays: {} }, { ...established, progressDays: { '2026-09-01': { s: 2, t: 10, c: 5, ps: 0, pc: 0, wm: 3 } } });
  check('a wipe cannot empty the history either', guarded.update.progressDays['2026-09-01'].t === 10);
}

if (failures) {
  console.error(`\n❌ ${failures} progress-guard check(s) failed.`);
  process.exit(1);
}
console.log('\n✅ All progress-guard checks passed.');
