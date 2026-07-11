const express = require('express');

const router = express.Router();

const CONTACT = 'instaflow38@gmail.com';
const APP = 'Speak Frankly';
const UPDATED = 'July 2026';

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
</ul>

<div class="box">We do <b>not</b> sell your personal data or share it for advertising.</div>

<h2>Data retention & deletion</h2>
<p>We keep your data while your account is active. To delete your account and associated data, email us at <a href="mailto:${CONTACT}">${CONTACT}</a> and we will remove it.</p>

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

<h2>Free & premium</h2>
<p>The app offers a free tier with daily limits and may offer optional paid premium features (unlimited practice). Purchases, if any, are handled by Google Play and subject to its terms.</p>

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

<p>You can request deletion of your ${APP} account and all associated data at any time.</p>

<h2>How to request deletion</h2>
<ol>
  <li>Email <a href="mailto:${CONTACT}?subject=Delete%20my%20account">${CONTACT}</a> from the email address linked to your Google account.</li>
  <li>Use the subject line <b>"Delete my account"</b>.</li>
  <li>We will verify and process your request.</li>
</ol>

<div class="box">You can also open the app → <b>Profile → Sign out</b> at any time; to permanently delete your data, use the email request above.</div>

<h2>What is deleted</h2>
<ul>
  <li>Your account: Google name, email address, and account ID.</li>
  <li>Your learning data: progress (streak, XP, completed scenarios), saved words, level, goal, and chosen language.</li>
</ul>

<h2>Retention</h2>
<p>Your account and associated data are permanently deleted within <b>30 days</b> of your request. No additional data is retained after deletion.</p>
`));
});

module.exports = router;
