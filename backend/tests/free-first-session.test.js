/**
 * The one free conversation a new account gets before the paywall.
 *
 * This decides who is asked to pay and who is not, so it is the last place in
 * the service that should be reasoned about by reading it and hoping. Two
 * things have to hold at once:
 *
 *   - with the flag OFF, absolutely nothing changes. It ships off, so a deploy
 *     that merges this must not quietly start giving the product away.
 *   - with it ON, a brand-new account can hold exactly one conversation and
 *     then meets the paywall — once, for good, not once a day.
 *
 * Everything here is pure: isPaywalled/inIntro/introRemaining take a user
 * document and return an answer, so the rules can be checked exactly rather
 * than inferred from an HTTP round trip.
 *
 * Usage: node tests/free-first-session.test.js
 */
let failures = 0;
const check = (name, cond) => {
  if (cond) console.log(`  OK   ${name}`);
  else {
    console.error(`  FAIL ${name}`);
    failures++;
  }
};

/** Load aiAccess with a specific environment, fresh each time. */
function withEnv(env) {
  for (const k of Object.keys(require.cache)) {
    if (k.includes('aiAccess') || k.includes('firestoreAdmin') || k.includes('utils\\dates') || k.includes('utils/dates')) {
      delete require.cache[k];
    }
  }
  Object.assign(process.env, {
    DEV_SKIP_LIMITS: 'false',
    GEMINI_API_KEY: '',
    FIREBASE_SERVICE_ACCOUNT_JSON: '',
    GOOGLE_APPLICATION_CREDENTIALS: '',
    REQUIRE_PREMIUM: '',
    PAYWALL_FROM: '',
    FREE_FIRST_SESSION: '',
    FREE_FIRST_SESSION_MESSAGES: '',
    ...env,
  });
  return require('../middleware/aiAccess');
}

const NEW_USER = { createdAt: new Date('2026-09-01T00:00:00Z') };
const OLD_USER = { createdAt: new Date('2025-01-01T00:00:00Z') };

console.log('\n--- the flag is off by default ---');
{
  const m = withEnv({ REQUIRE_PREMIUM: 'true' });
  check('FREE_FIRST_SESSION defaults to off', m.FREE_FIRST_SESSION === false);
  check('a new account is paywalled exactly as before', m.isPaywalled(NEW_USER) === true);
  check('nobody is in an intro', m.inIntro(NEW_USER) === false);
  check('and nobody has messages to spend', m.introRemaining(NEW_USER) === 0);
}

console.log('\n--- switched on, a new account gets one conversation ---');
{
  const m = withEnv({ REQUIRE_PREMIUM: 'true', FREE_FIRST_SESSION: 'true', FREE_FIRST_SESSION_MESSAGES: '10' });
  check('a brand-new account is NOT paywalled', m.isPaywalled(NEW_USER) === false);
  check('it is in the intro', m.inIntro(NEW_USER) === true);
  check('with the full allowance', m.introRemaining(NEW_USER) === 10);

  const partway = { ...NEW_USER, introMessagesUsed: 4 };
  check('part-way through, still free', m.isPaywalled(partway) === false);
  check('and the remainder is right', m.introRemaining(partway) === 6);

  const spent = { ...NEW_USER, introMessagesUsed: 10 };
  check('once spent, the paywall applies', m.isPaywalled(spent) === true);
  check('and the intro is over', m.inIntro(spent) === false);

  // A lifetime allowance, not a daily one - the whole point is that it does
  // not come back tomorrow.
  const overspent = { ...NEW_USER, introMessagesUsed: 25 };
  check('an overspent counter cannot go negative', m.introRemaining(overspent) === 0);
  check('and stays paywalled', m.isPaywalled(overspent) === true);
}

console.log('\n--- it never touches anyone it should not ---');
{
  const m = withEnv({
    REQUIRE_PREMIUM: 'true',
    FREE_FIRST_SESSION: 'true',
    PAYWALL_FROM: '2026-06-01T00:00:00Z',
  });
  // Grandfathered accounts already have a free tier; there is nothing to
  // introduce them to, and spending an intro on them would be meaningless.
  check('a grandfathered account is not paywalled (as before)', m.isPaywalled(OLD_USER) === false);
  check('and is not put into an intro', m.inIntro(OLD_USER) === false);
  check('a post-cutoff account does get the intro', m.inIntro(NEW_USER) === true);

  // An account with no createdAt predates that field, so it is old by
  // definition - the existing rule, unchanged.
  check('an undated account stays un-paywalled', m.isPaywalled({}) === false);
  check('and is not given an intro either', m.inIntro({}) === false);
}

console.log('\n--- freemium mode is untouched ---');
{
  // With REQUIRE_PREMIUM off there is no paywall to be introduced past, so the
  // intro must not quietly cap a free learner's daily messages.
  const m = withEnv({ REQUIRE_PREMIUM: '', FREE_FIRST_SESSION: 'true' });
  check('nobody is paywalled', m.isPaywalled(NEW_USER) === false);
  check('and nobody is in an intro', m.inIntro(NEW_USER) === false);
}

console.log('\n--- the size of the giveaway is configurable ---');
{
  const m = withEnv({ REQUIRE_PREMIUM: 'true', FREE_FIRST_SESSION: 'true', FREE_FIRST_SESSION_MESSAGES: '3' });
  check('the cap is read from the environment', m.FREE_FIRST_SESSION_MESSAGES === 3);
  check('two messages in, still free', m.isPaywalled({ ...NEW_USER, introMessagesUsed: 2 }) === false);
  check('three messages in, paywalled', m.isPaywalled({ ...NEW_USER, introMessagesUsed: 3 }) === true);
}

if (failures) {
  console.error(`\nFAILED: ${failures} free-first-session check(s).`);
  process.exit(1);
}
console.log('\nAll free-first-session checks passed.');
