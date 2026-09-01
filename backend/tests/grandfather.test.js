/**
 * The paywall is for NEW accounts only.
 *
 * Turning REQUIRE_PREMIUM on without this would wall off everyone already using
 * the app for free — people who installed under a promise of a free tier and
 * would open the app one morning to find it gone. PAYWALL_FROM draws the line
 * by account creation date.
 *
 * These run in separate processes because the env is read once at module load,
 * and the whole point is how the module behaves under different env.
 *
 * Usage: node tests/grandfather.test.js
 */
const path = require('path');
const { fork } = require('child_process');

const MODE = process.argv[2];

const HERMETIC = {
  GEMINI_API_KEY: '',
  FIREBASE_SERVICE_ACCOUNT_JSON: '',
  GOOGLE_APPLICATION_CREDENTIALS: '',
  DEV_SKIP_LIMITS: 'false',
};

const CUTOFF = '2026-09-01T00:00:00Z';
const before = { createdAt: new Date('2026-08-15T10:00:00Z') };  // already a user
const after = { createdAt: new Date('2026-09-10T10:00:00Z') };   // arrived later
const onTheLine = { createdAt: new Date(CUTOFF) };               // exactly at it
const ancient = {};                                              // predates the field

function run(mode) {
  Object.assign(process.env, HERMETIC);
  if (mode === 'paywall-new') {
    process.env.REQUIRE_PREMIUM = 'true';
    process.env.PAYWALL_FROM = CUTOFF;
  } else if (mode === 'paywall-all') {
    process.env.REQUIRE_PREMIUM = 'true';
    process.env.PAYWALL_FROM = '';
  } else if (mode === 'off') {
    process.env.REQUIRE_PREMIUM = 'false';
    process.env.PAYWALL_FROM = CUTOFF;
  } else if (mode === 'bad-date') {
    process.env.REQUIRE_PREMIUM = 'true';
    process.env.PAYWALL_FROM = 'not a date';
  }

  const { isPaywalled } = require('../middleware/aiAccess');
  let failures = 0;
  const check = (name, cond) => {
    if (cond) console.log(`  ✅ ${name}`);
    else {
      console.error(`  ❌ ${name}`);
      failures++;
    }
  };

  if (mode === 'paywall-new') {
    console.log('\n— paywall on, cutoff set: only new accounts pay —');
    check('an account from before the cutoff keeps its free tier', isPaywalled(before) === false);
    check('an account created after the cutoff is paywalled', isPaywalled(after) === true);
    check('an account created exactly on the cutoff is paywalled', isPaywalled(onTheLine) === true);
    check('an account with no createdAt is treated as old, not new', isPaywalled(ancient) === false);
    check('a missing user object does not wall anyone out', isPaywalled(null) === false);
    check('snake_case created_at is read too', isPaywalled({ created_at: before.createdAt }) === false);
    // Firestore hands back Timestamps, not Dates. If toDate() were not applied
    // every existing user would read as "no date" or throw.
    const asTimestamp = { createdAt: { toDate: () => before.createdAt } };
    check('a Firestore Timestamp is understood', isPaywalled(asTimestamp) === false);
    const newTimestamp = { createdAt: { toDate: () => after.createdAt } };
    check('...in both directions', isPaywalled(newTimestamp) === true);
  }

  if (mode === 'paywall-all') {
    console.log('\n— paywall on, no cutoff: everyone pays —');
    check('an old account is paywalled when no line is drawn', isPaywalled(before) === true);
    check('a new account is paywalled', isPaywalled(after) === true);
    check('even an account with no createdAt is paywalled', isPaywalled(ancient) === true);
  }

  if (mode === 'off') {
    console.log('\n— paywall off: the cutoff is irrelevant —');
    check('nobody is paywalled, however new', isPaywalled(after) === false);
    check('nobody is paywalled, however old', isPaywalled(before) === false);
  }

  if (mode === 'bad-date') {
    console.log('\n— PAYWALL_FROM is unparseable —');
    // Failing open here would silently un-paywall the whole app, and the only
    // symptom would be revenue that never arrives. Fail closed, and warn.
    check('an unparseable cutoff paywalls everyone rather than nobody',
      isPaywalled(after) === true && isPaywalled(before) === true);
  }

  process.exit(failures === 0 ? 0 : 1);
}

if (MODE) {
  run(MODE);
} else {
  const modes = ['paywall-new', 'paywall-all', 'off', 'bad-date'];
  let failed = 0;
  (function next(i) {
    if (i >= modes.length) {
      console.log(failed === 0 ? '\n✅ grandfathering checks passed\n'
                               : `\n❌ ${failed} mode(s) failed\n`);
      process.exit(failed === 0 ? 0 : 1);
    }
    fork(path.join(__dirname, 'grandfather.test.js'), [modes[i]], { stdio: 'inherit' })
      .on('exit', (code) => {
        if (code !== 0) failed++;
        next(i + 1);
      });
  })(0);
}
