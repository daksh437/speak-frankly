/**
 * The paid trial, and the four billing plans behind it.
 *
 * Razorpay has no "trial" field. A trial is a subscription whose first billing
 * date is pushed into the future (`start_at`) with an up-front amount taken
 * during the authorisation transaction (`addons`). If either half is missing
 * the learner is either charged the full plan price on day one, or gets the
 * trial for nothing — so both are asserted here.
 *
 * Razorpay also has no equivalent of Play's "new customer acquisition"
 * eligibility, so the same account could take the Rs 2 trial on every new
 * subscription forever. The route decides eligibility and passes it in; these
 * tests pin the wiring on the service side.
 *
 * Hermetic: axios is stubbed before the service loads, so nothing leaves the
 * machine and no Razorpay credentials are needed.
 *
 * Usage: node tests/subscription-trial.test.js
 */
Object.assign(process.env, {
  RAZORPAY_KEY_ID: 'rzp_test_fake',
  RAZORPAY_KEY_SECRET: 'fake-secret',
  RAZORPAY_PLAN_MONTHLY: 'plan_fake_monthly',
  RAZORPAY_PLAN_QUARTERLY: 'plan_fake_quarterly',
  RAZORPAY_PLAN_HALFYEARLY: 'plan_fake_halfyearly',
  RAZORPAY_PLAN_ANNUAL: 'plan_fake_annual',
  RAZORPAY_TRIAL_DAYS: '1',
  RAZORPAY_TRIAL_AMOUNT_PAISE: '200',
});

const axios = require('axios');

// Capture what would have been sent to Razorpay. Patch before the service is
// required: it destructures nothing, but this keeps the stub unambiguous.
let sent = null;
axios.post = async (url, body) => {
  sent = { url, body };
  return { data: { id: 'sub_fake_123', status: 'created', short_url: 'https://rzp.io/fake' } };
};

const rzp = require('../services/razorpay');

let failures = 0;
const check = (name, cond) => {
  if (cond) console.log(`  ✅ ${name}`);
  else {
    console.error(`  ❌ ${name}`);
    failures++;
  }
};

const DAY = 24 * 60 * 60;

(async () => {
  console.log('\n🧪 paid trial + billing plans\n');

  // ---- all four plans are purchasable ------------------------------------
  const plans = rzp.availablePlans();
  check('all four plans are offered', plans.length === 4);
  for (const k of ['monthly', 'quarterly', 'halfyearly', 'annual']) {
    check(`  ${k} is configured`, plans.includes(k));
  }
  check('yearly is listed first (the page pre-selects it)', plans[0] === 'annual');

  // ---- the trial is described consistently -------------------------------
  const info = rzp.trialInfo();
  check('trial is enabled', rzp.trialEnabled() === true);
  check('trial lasts 1 day', info && info.days === 1);
  check('trial costs Rs 2 (200 paise)', info && info.amountPaise === 200 && info.amount === 2);

  // ---- with a trial ------------------------------------------------------
  sent = null;
  const before = Math.floor(Date.now() / 1000);
  const withTrial = await rzp.createSubscription('uid-new', 'monthly', { withTrial: true });
  const after = Math.floor(Date.now() / 1000);

  check('subscription is created', withTrial.ok === true && withTrial.id === 'sub_fake_123');
  check('it uses the monthly plan id', sent.body.plan_id === 'plan_fake_monthly');
  check('the uid travels in notes (renewals months later still match)',
    sent.body.notes && sent.body.notes.uid === 'uid-new');

  const start = sent.body.start_at;
  check('first billing is pushed one day out',
    start >= before + DAY && start <= after + DAY + 5);
  check('an up-front amount is attached',
    Array.isArray(sent.body.addons) && sent.body.addons.length === 1);
  check('the up-front amount is Rs 2 in paise',
    sent.body.addons[0].item.amount === 200 && sent.body.addons[0].item.currency === 'INR');

  // ---- without a trial ---------------------------------------------------
  sent = null;
  await rzp.createSubscription('uid-returning', 'monthly', { withTrial: false });
  check('a returning buyer gets no deferred start', sent.body.start_at === undefined);
  check('a returning buyer gets no up-front add-on', sent.body.addons === undefined);
  check('...and is billed on the same plan', sent.body.plan_id === 'plan_fake_monthly');

  // The default matters: an accidental call without options must not hand out
  // a trial, because that is the expensive direction to be wrong in.
  sent = null;
  await rzp.createSubscription('uid-default', 'annual');
  check('no trial unless it is asked for',
    sent.body.start_at === undefined && sent.body.addons === undefined);

  // ---- longer plans still bill for a sane number of cycles ---------------
  for (const [plan, id] of [['quarterly', 'plan_fake_quarterly'],
                            ['halfyearly', 'plan_fake_halfyearly'],
                            ['annual', 'plan_fake_annual']]) {
    sent = null;
    await rzp.createSubscription('uid-x', plan);
    check(`${plan} maps to its own plan id`, sent.body.plan_id === id);
    check(`${plan} has a finite billing count`, Number.isInteger(sent.body.total_count) && sent.body.total_count > 0);
  }

  // ---- an unknown plan is refused ---------------------------------------
  const bad = await rzp.createSubscription('uid-x', 'weekly');
  check('an unknown plan is rejected', bad.ok === false && bad.error === 'UNKNOWN_PLAN');

  console.log(failures === 0 ? '\n✅ trial and plan checks passed\n'
                             : `\n❌ ${failures} check(s) failed\n`);
  process.exit(failures === 0 ? 0 : 1);
})();
