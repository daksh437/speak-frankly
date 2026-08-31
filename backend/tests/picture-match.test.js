/**
 * Picture Match must never mark a learner wrong for being right.
 *
 * Found on a real device: the green bicycle emoji came back with "He is riding
 * a blue bicycle" as the CORRECT answer — twice, across a refresh. A learner
 * looking at a green bicycle picks the sentence that does not say blue, and is
 * told they are wrong.
 *
 * The root cause is not the model being careless. Emoji are drawn differently
 * on every platform: Samsung's bicycle is green, Apple's is grey. So a colour
 * claim about an emoji cannot be true for all learners, whatever the model
 * intended. The prompt now says so, and this filter enforces it, because a
 * prompt is a request and a filter is a rule.
 *
 * Usage: node tests/picture-match.test.js
 */
process.env.GEMINI_API_KEY = '';
process.env.FIREBASE_SERVICE_ACCOUNT_JSON = '';

const { mentionsAColour } = require('../controllers/tutorController');

let failures = 0;
const check = (name, cond) => {
  if (cond) console.log(`  ✅ ${name}`);
  else {
    console.error(`  ❌ ${name}`);
    failures++;
  }
};

console.log('\n🧪 picture match: no unverifiable colour claims\n');

// ---- the exact item that was wrong on the device --------------------------
check('the reported item is rejected',
  mentionsAColour('He is riding a blue bicycle.') === true);
check('...and the same sentence without the colour is kept',
  mentionsAColour('He is riding a bicycle.') === false);

// ---- every colour, used attributively -------------------------------------
for (const c of ['red', 'yellow', 'green', 'blue', 'purple', 'pink',
                 'brown', 'black', 'white', 'grey', 'gray', 'golden']) {
  check(`  "${c}" as a colour is rejected`,
    mentionsAColour(`She is holding a ${c} bag.`) === true);
}

// ---- things that only look like colour claims ------------------------------
// "orange" is a fruit far more often than a colour in a beginner sentence, so
// the rule is attributive use only: a colour word followed by another word.
check('"eating an orange" is a fruit, not a colour', mentionsAColour('She is eating an orange.') === false);
check('"an orange bag" is a colour', mentionsAColour('She is carrying an orange bag.') === true);
check('a sentence ending in a colour word is not a claim about an object',
  mentionsAColour('The sky is blue') === false);

// ---- ordinary items survive ------------------------------------------------
for (const s of ['They are eating pizza.',
                 'The dog is running in the park.',
                 'She is waiting for the bus.',
                 'He is drinking a cup of coffee.',
                 'It is raining outside.',
                 'The plane is taking off.']) {
  check(`kept: "${s}"`, mentionsAColour(s) === false);
}

// ---- the curated fallback set must itself pass the rule --------------------
// If it did not, every AI failure would serve exactly the bug this fixes.
const { FALLBACK_PICTURE_MATCH } = require('../controllers/tutorController');
if (Array.isArray(FALLBACK_PICTURE_MATCH)) {
  const bad = FALLBACK_PICTURE_MATCH.filter((i) => mentionsAColour(i.correct));
  check(`the ${FALLBACK_PICTURE_MATCH.length} fallback items make no colour claims`, bad.length === 0);
  if (bad.length) console.error('    offending:', bad.map((b) => b.correct));
}

// ---- empty / odd input -----------------------------------------------------
check('empty string is fine', mentionsAColour('') === false);
check('null is fine', mentionsAColour(null) === false);

console.log(failures === 0 ? '\n✅ picture match checks passed\n'
                           : `\n❌ ${failures} check(s) failed\n`);
process.exit(failures === 0 ? 0 : 1);
