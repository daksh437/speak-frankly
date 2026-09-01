/**
 * The public landing page at `/`.
 *
 * WHY THIS EXISTS
 * `/` used to return `{"success":true,"message":"Speak Frankly Backend API"}`.
 * That is fine for a machine and useless to a person — and it is what a payment
 * gateway's reviewer sees first. Razorpay declined the domain with "the website
 * must be live with the services/products offered", because a JSON string is
 * not a shop. This page is that shop: what the product is, what the plans cost,
 * what the trial charges, and where the policies are.
 *
 * Prices are read from the SAME env vars the checkout page uses, so the two can
 * never quote different numbers. Blank shows a dash rather than a guess.
 */
const express = require('express');
const rzp = require('../services/razorpay');

const router = express.Router();

const APP = 'Speak Frankly';
const CONTACT = 'instaflow38@gmail.com';
const PLAY_URL = 'https://play.google.com/store/apps/details?id=com.speakfrankly';

const PRICES = {
  monthly: (process.env.RAZORPAY_PRICE_MONTHLY || '').trim(),
  quarterly: (process.env.RAZORPAY_PRICE_QUARTERLY || '').trim(),
  halfyearly: (process.env.RAZORPAY_PRICE_HALFYEARLY || '').trim(),
  annual: (process.env.RAZORPAY_PRICE_ANNUAL || '').trim(),
};

const PLAN_ROWS = [
  ['annual', 'Yearly', 'per year'],
  ['halfyearly', '6 months', 'every 6 months'],
  ['quarterly', '3 months', 'every 3 months'],
  ['monthly', 'Monthly', 'per month'],
];

const STYLES = [
  ':root{color-scheme:light dark;--fg:#1a1a1a;--bg:#fff;--muted:#6b6b6b;--seed:#6C5CE7;--card:#f6f5fb;--line:#e3e0f0}',
  '@media(prefers-color-scheme:dark){:root{--fg:#e9e7ef;--bg:#121016;--muted:#9d99ab;--card:#1d1a25;--line:#2e2a3a}}',
  '*{box-sizing:border-box}',
  'body{font-family:-apple-system,"Segoe UI",Roboto,sans-serif;line-height:1.65;margin:0;background:var(--bg);color:var(--fg);padding:36px 20px 64px}',
  '.wrap{max-width:760px;margin:0 auto}',
  '.crown{width:76px;height:76px;border-radius:22px;display:grid;place-items:center;font-size:38px;margin:0 auto 14px;background:linear-gradient(135deg,#6C5CE7,#8b7cf0)}',
  'h1{font-size:30px;text-align:center;margin:0 0 6px}',
  '.tag{text-align:center;color:var(--muted);margin:0 0 30px}',
  'h2{font-size:20px;margin:34px 0 10px}',
  'ul{padding-left:20px}li{margin:5px 0}',
  'table{width:100%;border-collapse:collapse;margin:14px 0}',
  'th,td{text-align:left;padding:11px 12px;border-bottom:1px solid var(--line)}',
  'th{font-size:13px;color:var(--muted);font-weight:600}',
  '.price{font-weight:800;font-size:17px}',
  '.box{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:16px 18px;margin:20px 0}',
  '.cta{display:block;text-align:center;background:var(--seed);color:#fff;text-decoration:none;font-weight:700;padding:15px;border-radius:14px;margin:26px 0 10px}',
  'a{color:var(--seed)}',
  '.foot{text-align:center;color:var(--muted);font-size:14px;margin-top:34px}',
].join('');

function planTable() {
  const rows = PLAN_ROWS
    .filter(([key]) => rzp.availablePlans().includes(key))
    .map(([key, name, per]) => {
      const p = PRICES[key] || '&mdash;';
      return `<tr><td><b>${name}</b></td><td class="price">${p}</td><td>${per}</td></tr>`;
    })
    .join('');
  if (!rows) return '<p>Plans are being updated. Please check back shortly.</p>';
  return `<table><tr><th>Plan</th><th>Price</th><th>Billed</th></tr>${rows}</table>`;
}

function trialNote() {
  const t = rzp.trialInfo();
  if (!t) return '';
  const days = t.days === 1 ? '1 day' : `${t.days} days`;
  return `<div class="box"><b>New subscribers pay &#8377;${t.amount} for the first ${days}</b>,
    then the plan price above. The subscription renews automatically until you cancel.</div>`;
}

router.get('/', (_req, res) => {
  res.set('Content-Type', 'text/html; charset=utf-8').send(`<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${APP} — Practise real English conversations</title>
<meta name="description" content="${APP} is an English speaking-practice app. Talk to an AI tutor in real-life scenarios and get gentle corrections as you go.">
<style>${STYLES}</style>
</head><body><div class="wrap">

<div class="crown">🗣️</div>
<h1>${APP}</h1>
<p class="tag">Practise real English conversations, and get corrected as you go.</p>

<h2>What it is</h2>
<p>${APP} is an English speaking-practice app for Android. You hold a conversation
with an AI tutor in a real-life situation — a job interview, ordering food, a visit
to the doctor — and it replies in character, corrects the most useful mistake in what
you said, and keeps the conversation going. It is built for learners who read and
understand English but freeze when they have to speak it.</p>

<h2>What you get</h2>
<ul>
  <li>AI conversation practice across real-life scenarios, with gentle corrections</li>
  <li>Suggested replies for when you are not sure what to say</li>
  <li>Speaking practice — listen to a phrase, then say it out loud</li>
  <li>Story mode role-plays, a word of the day, and a saved-words review list</li>
  <li>Streaks, XP and levels to keep a daily habit going</li>
</ul>

<h2>Premium</h2>
<p>The app is free to download and use with a daily limit. Premium removes that
limit and unlocks every scenario. It is a subscription that renews automatically
until cancelled.</p>

${planTable()}
${trialNote()}

<a class="cta" href="/checkout">Subscribe to Premium</a>
<p style="text-align:center;color:var(--muted);font-size:14px">
  Payments are processed by Razorpay. You sign in with the same Google account you
  use in the app.
</p>

<h2>Cancellation and refunds</h2>
<p>You can cancel at any time and keep access until the end of the period you have
already paid for. Refund terms are set out in full in our
<a href="/terms#refunds">Terms of Service</a>.</p>

<h2>Get the app</h2>
<p><a href="${PLAY_URL}">Speak Frankly on Google Play</a></p>

<p class="foot">
  <a href="/privacy">Privacy Policy</a> &middot;
  <a href="/terms">Terms of Service</a> &middot;
  <a href="/terms#refunds">Refunds</a> &middot;
  <a href="/delete-account">Delete your account</a><br>
  Contact: <a href="mailto:${CONTACT}">${CONTACT}</a>
</p>

</div></body></html>`);
});

module.exports = router;
