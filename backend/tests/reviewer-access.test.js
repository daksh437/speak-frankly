/**
 * The app-store review bypass.
 *
 * Google Play rejected a submission because the reviewer could not reach the
 * full experience without paying — the trial had run out (or the device had
 * already used one), leaving them on 8 messages a day and then a paywall. The
 * policy accepts either a test account with an active subscription or a way to
 * bypass every payment gate; REVIEWER_EMAILS is that way.
 *
 * What must hold, and what these lock in:
 *   - a listed address is recognised, case- and whitespace-insensitively;
 *   - an unlisted one is not, so this is never a general free-premium hole;
 *   - it is keyed on the VERIFIED token's email, so a claimed header cannot
 *     assert it;
 *   - it is OFF unless the owner sets the variable.
 *
 * Hermetic: no Firebase creds, no Gemini key. Without Firestore the write in
 * ensureReviewerPremium is a no-op that still reports success, which is the
 * degraded behaviour the rest of the service is built on.
 *
 * Usage: node tests/reviewer-access.test.js
 */
Object.assign(process.env, {
  DEV_SKIP_LIMITS: 'false',
  REQUIRE_AUTH_TOKEN: '',
  GEMINI_API_KEY: '',
  FIREBASE_SERVICE_ACCOUNT_JSON: '',
  GOOGLE_APPLICATION_CREDENTIALS: '',
  REVIEWER_EMAILS: ' Play.Reviewer@example.com , second-reviewer@example.com ',
});

const { isReviewerEmail, ensureReviewerPremium, REVIEWER_EMAILS } = require('../middleware/aiAccess');

let failures = 0;
const check = (name, cond) => {
  if (cond) console.log(`  ✅ ${name}`);
  else {
    console.error(`  ❌ ${name}`);
    failures++;
  }
};

(async () => {
  console.log('\n— who counts as a review account —');

  check('the configured addresses are parsed', REVIEWER_EMAILS.length === 2);
  check('surrounding whitespace is trimmed', REVIEWER_EMAILS[0] === 'play.reviewer@example.com');
  check('a listed address is recognised', isReviewerEmail('play.reviewer@example.com'));
  check('matching ignores case', isReviewerEmail('PLAY.REVIEWER@EXAMPLE.COM'));
  check('matching ignores stray whitespace', isReviewerEmail('  play.reviewer@example.com  '));
  check('the second address is recognised too', isReviewerEmail('second-reviewer@example.com'));

  console.log('\n— who does not —');

  check('an unlisted address is not a reviewer', !isReviewerEmail('someone@example.com'));
  check('no email is not a reviewer', !isReviewerEmail(''));
  check('null is not a reviewer', !isReviewerEmail(null));
  check('undefined is not a reviewer', !isReviewerEmail(undefined));
  // The soft auth path leaves authEmail null for a caller who only sent the
  // legacy uid header, so an unverified caller can never reach the bypass.
  check('an unverified caller (no token email) is not a reviewer', !isReviewerEmail(null));
  // Substring and domain lookalikes must not pass.
  check('a lookalike domain is rejected', !isReviewerEmail('play.reviewer@example.com.evil.com'));
  check('a prefix of a listed address is rejected', !isReviewerEmail('play.reviewer@example.co'));

  console.log('\n— granting is safe when it cannot write —');

  const granted = await ensureReviewerPremium('reviewer-uid', 'play.reviewer@example.com');
  check('a reviewer is admitted even with no Firestore (degraded)', granted === true);
  const notReviewer = await ensureReviewerPremium('someone-uid', 'someone@example.com');
  check('a non-reviewer is not granted anything', notReviewer === false);
  const noUid = await ensureReviewerPremium('', 'play.reviewer@example.com');
  check('no uid → nothing granted', noUid === false);

  console.log('\n— it is off unless configured —');

  // A fresh module registry with the variable unset, so the default really is
  // "nobody" rather than whatever this process happens to have set.
  delete require.cache[require.resolve('../middleware/aiAccess')];
  const savedEnv = process.env.REVIEWER_EMAILS;
  delete process.env.REVIEWER_EMAILS;
  const fresh = require('../middleware/aiAccess');
  check('unset REVIEWER_EMAILS means no review accounts', fresh.REVIEWER_EMAILS.length === 0);
  check('and nobody is recognised', !fresh.isReviewerEmail('play.reviewer@example.com'));
  process.env.REVIEWER_EMAILS = savedEnv;

  if (failures) {
    console.error(`\n❌ ${failures} reviewer-access check(s) failed.`);
    process.exit(1);
  }
  console.log('\n✅ All reviewer-access checks passed.');
})();
