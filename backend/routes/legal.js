const express = require('express');

const router = express.Router();

const CONTACT = 'instaflow38@gmail.com';
const APP = 'Speak Frankly';
const UPDATED = 'August 2026';

function page(title, bodyHtml) {
  return `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title} — ${APP}</title>
<style>
  :root { color-scheme: light dark; }
  body { font-family: -apple-system, Segoe UI, Roboto, sans-serif; line-height: 1.65; max-width: 760px;
    margin: 0 auto; padding: 28px 20px 64px; color: #1a1a1a; background: #fff; }
  @media (prefers-color-scheme: dark) { body { color: #e6e6e6; background: #121016; } a { color: #9b8cff; } }
  h1 { font-size: 26px; margin: 0 0 4px; }
  h2 { font-size: 18px; margin: 28px 0 8px; }
  .muted { color: #888; font-size: 14px; margin-bottom: 24px; }
  ul { padding-left: 20px; }
  li { margin: 4px 0; }
  a { color: #6c5ce7; }
  .box { background: rgba(108,92,231,0.08); border-radius: 12px; padding: 14px 16px; margin: 20px 0; }
</style></head>
<body>${bodyHtml}
<p class="muted" style="margin-top:40px">Contact: <a href="mailto:${CONTACT}">${CONTACT}</a></p>
</body></html>`;
}

router.get('/privacy', (_req, res) => {
  res.set('Content-Type', 'text/html; charset=utf-8').send(page('Privacy Policy', `
<h1>Privacy Policy</h1>
<p class="muted">${APP} · Last updated: ${UPDATED}</p>

<p>${APP} ("we", "us") helps you learn English through conversation, speaking practice, and vocabulary. This policy explains what we collect and how we use it.</p>

<h2>Information we collect</h2>
<ul>
  <li><b>Account information</b> — when you sign in with Google, we receive your name, email address, and a Google account ID to create your account.</li>
  <li><b>Learning data</b> — your progress (streak, XP, completed scenarios), saved words, chosen level, goal, and language, so your learning is saved and syncs across devices.</li>
  <li><b>Content you provide</b> — messages you type or speak to the AI tutor and any text you paste for vocabulary extraction, used only to generate a response for you.</li>
  <li><b>Microphone / audio</b> — for speaking practice, your speech is processed by your device's on-device speech recognition to produce text. We do <b>not</b> store audio recordings.</li>
  <li><b>Usage analytics</b> — anonymous events (e.g. features used) to improve the app.</li>
  <li><b>Advertising identifier</b> — if you are on the free plan, Google AdMob may access your device's advertising ID and standard ad-request data (approximate location derived from IP, device type) to select and measure ads. Premium subscribers see no ads.</li>
</ul>

<h2>How we use it</h2>
<ul>
  <li>To provide and personalize the tutor, exercises, and progress tracking.</li>
  <li>To save and sync your progress to your account.</li>
  <li>To maintain fair-usage limits and offer premium features.</li>
  <li>To fix bugs and improve the experience.</li>
</ul>

<h2>Third-party services</h2>
<p>We use trusted providers to run the app:</p>
<ul>
  <li><b>Google Firebase</b> (authentication, database, analytics) — stores your account and learning data.</li>
  <li><b>Google Gemini</b> — generates AI tutor responses from your messages.</li>
  <li><b>Free Dictionary API</b> — word definitions and pronunciation.</li>
  <li><b>Render</b> — hosts our backend server.</li>
  <li><b>Google AdMob</b> — shows ads to free-plan users. See <a href="https://policies.google.com/technologies/partner-sites">how Google uses data from apps that use its services</a>.</li>
</ul>

<div class="box">We do <b>not</b> sell your personal data, and we never share your conversations, learning data or account details with advertisers.</div>

<h2>Advertising</h2>
<p>The free plan is supported by ads served through Google AdMob: a banner on some screens, an ad at the end of a practice session, and an optional rewarded ad you can choose to watch to earn extra daily messages. AdMob may use your device's advertising ID to select and measure those ads.</p>
<p>Your tutor conversations, saved words, progress and email are <b>never</b> sent to AdMob or to any advertiser — ads are chosen by Google, not by anything you say to the tutor.</p>
<p>You can reset or delete your advertising ID at any time in <b>Android Settings → Privacy → Ads</b>. Subscribing to Premium removes ads entirely.</p>

<h2>Data retention & deletion</h2>
<p>We keep your data while your account is active.</p>
<p>You can delete your account and all associated data yourself, at any time, from inside the app: <b>Profile → Delete account</b>. Deletion is immediate and cannot be undone.</p>
<p>You can also email us at <a href="mailto:${CONTACT}">${CONTACT}</a>, or see our <a href="/delete-account">account deletion page</a> for exactly what is removed.</p>

<h2>Children</h2>
<p>${APP} is not directed to children under 13. If you believe a child has provided us data, contact us and we will delete it.</p>

<h2>Changes</h2>
<p>We may update this policy; the "Last updated" date will change accordingly.</p>
`));
});

router.get('/terms', (_req, res) => {
  res.set('Content-Type', 'text/html; charset=utf-8').send(page('Terms of Service', `
<h1>Terms of Service</h1>
<p class="muted">${APP} · Last updated: ${UPDATED}</p>

<p>By using ${APP}, you agree to these terms.</p>

<h2>The service</h2>
<p>${APP} provides AI-assisted English learning — conversation practice, speaking exercises, a dictionary, and vocabulary tools. Content is for educational purposes and may not always be perfectly accurate.</p>

<h2>Your account</h2>
<ul>
  <li>You sign in with a Google account and are responsible for activity under it.</li>
  <li>Use the app lawfully and do not attempt to disrupt, abuse, or reverse-engineer it.</li>
</ul>

<h2>Free &amp; premium</h2>
<p>The app is free to use with a daily limit. Premium is an optional paid subscription that removes the limit and unlocks every practice scenario. Who handles the money depends on where and when you subscribed:</p>
<ul>
  <li><b>Inside the Android app, and on this website</b> — billed by Razorpay Software Private Limited on our behalf.</li>
  <li><b>Through Google Play, in an earlier version of the app</b> — billed by Google Play and subject to Google Play's terms. Those subscriptions keep running and are still managed in Play; nothing about them changes.</li>
</ul>
<p>Premium plans are offered monthly, three-monthly, six-monthly and yearly. Prices are shown before you pay and may change; a change never affects a period you have already paid for.</p>

<h2 id="refunds">Subscriptions, cancellation and refunds</h2>

<h3>How billing works</h3>
<ul>
  <li>Premium <b>renews automatically</b> at the end of each period until you cancel. This is how it is described at checkout before you pay.</li>
  <li>New subscribers may be charged a small introductory amount for the first day, after which the plan price applies from the next billing date. The introductory amount is shown at checkout before you pay.</li>
  <li>Renewals are charged to the payment method you authorised. Where the law requires it, your bank or UPI provider notifies you before a recurring debit.</li>
</ul>

<h3>Cancelling</h3>
<ul>
  <li>You may cancel at any time. Cancelling stops future renewals; it does not end the period you have already paid for, and you keep Premium until that period ends.</li>
  <li>Billed by Razorpay (in the app or on this website): email <a href="mailto:${CONTACT}">${CONTACT}</a> from your account address, or use the cancellation link in your Razorpay subscription email. We stop the mandate, so no further amount is debited.</li>
  <li>An older subscription billed by Google Play: cancel through Google Play &rarr; Subscriptions.</li>
</ul>

<h3>Refunds</h3>
<ul>
  <li>If you are charged in error — a duplicate charge, or a renewal after you asked us to cancel — tell us and we will refund it in full.</li>
  <li>For a first-time subscription billed by Razorpay, you may request a refund within <b>7 days</b> of the charge by emailing <a href="mailto:${CONTACT}">${CONTACT}</a>.</li>
  <li>We do not refund part-used periods after that window, because the service is delivered as soon as the subscription starts.</li>
  <li>Approved refunds are returned to the original payment method. Razorpay typically takes 5&ndash;7 working days to settle a refund; the timing after that is your bank's.</li>
  <li>An older subscription billed by Google Play is refunded under Google Play's refund policy, not this one, because Google is the merchant for those.</li>
</ul>
<p>Write to <a href="mailto:${CONTACT}">${CONTACT}</a> for anything to do with a payment. We aim to reply within two working days.</p>

<h2>Acceptable use</h2>
<p>Do not submit unlawful, harmful, or abusive content to the AI tutor. We may limit or suspend access for misuse.</p>

<h2>Disclaimer</h2>
<p>The service is provided "as is", without warranties. ${APP} is a learning aid and does not guarantee any specific outcome or fluency level.</p>

<h2>Limitation of liability</h2>
<p>To the extent permitted by law, ${APP} and its developer are not liable for any indirect or incidental damages arising from use of the app.</p>

<h2>Termination</h2>
<p>You may stop using the app at any time. We may suspend accounts that violate these terms.</p>

<h2>Governing law</h2>
<p>These terms are governed by the laws of India.</p>

<h2>Contact</h2>
<p>Questions? Email <a href="mailto:${CONTACT}">${CONTACT}</a>.</p>
`));
});

router.get('/delete-account', (_req, res) => {
  res.set('Content-Type', 'text/html; charset=utf-8').send(page('Delete your account', `
<h1>Delete your ${APP} account</h1>
<p class="muted">${APP} · Account &amp; data deletion · Last updated: ${UPDATED}</p>

<p>You can delete your ${APP} account and all associated data at any time.</p>

<h2>Delete it yourself, in the app (fastest)</h2>
<ol>
  <li>Open ${APP} and go to the <b>Profile</b> tab.</li>
  <li>Tap <b>Delete account</b> at the bottom.</li>
  <li>Confirm. Your account and data are erased immediately and you are signed out.</li>
</ol>

<div class="box">This is immediate and <b>cannot be undone</b> — there is no recovery window and no way for us to restore a deleted account.</div>

<h2>Or ask us to do it</h2>
<ol>
  <li>Email <a href="mailto:${CONTACT}?subject=Delete%20my%20account">${CONTACT}</a> from the email address linked to your Google account.</li>
  <li>Use the subject line <b>"Delete my account"</b>.</li>
  <li>We will verify and process your request.</li>
</ol>

<h2>What is deleted</h2>
<ul>
  <li>Your account: Google name, email address, and account ID.</li>
  <li>Your learning data: progress (streak, XP, completed scenarios), saved words, level, goal, and chosen language.</li>
  <li>Your subscription record on our side. <b>Note:</b> an active Google Play subscription is billed by Google and is not cancelled by deleting your account — cancel it in <b>Play Store → Subscriptions</b>.</li>
</ul>

<h2>What is kept, and why</h2>
<ul>
  <li>If you reported an AI reply as offensive, the report itself is kept as a safety record — but your account ID and email are stripped from it, so it is no longer linked to you.</li>
  <li>A record that your device has already used its one free trial is kept, with your account ID removed. Without it, deleting an account would work as a way to restart the free trial forever.</li>
</ul>

<h2>Retention</h2>
<p>In-app deletion removes your data straight away. An emailed request is processed and permanently completed within <b>30 days</b>. No additional data is retained after deletion.</p>
`));
});

module.exports = router;
