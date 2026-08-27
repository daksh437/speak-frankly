# Speak Frankly — AI English Tutor

Learn English by *talking* — real-life scenarios, an AI conversation partner that
matches your level, gentle in-context corrections, and tap-any-word dictionary
help. Built to reuse the InstaFlow architecture (Gemini, graceful AI fallbacks,
Firestore-authoritative usage limits) as a **separate service + separate Firebase
project**, so the live InstaFlow app is never touched.

> Name: "Speak Frankly". Android package id: `com.speakfrankly`. Firebase project: `speakfrankly-cdddf`.

## Structure

```
english_tutor_ai/
  backend/   Node/Express API  (tutor chat, dictionary, scenarios, plan limits)
  app/       Flutter app        (onboarding → scenarios → chat + dictionary)
```

## Built

- **Scenario library** — Ordering Food, Job Interview, Shopping, Doctor, Small Talk, Airport, plus AI-generated scenarios from any topic the learner types.
- **AI conversation** — level-matched replies, answers meaning-first, ≤2 gentle corrections/turn, quick-reply suggestions. Runs in **MOCK mode** with no API key.
- **Dictionary** — tap any word → meaning, phonetics, audio, + L1 translation. Real data from dictionaryapi.dev (free), cached.
- **Speaking practice** — listen-and-imitate phrases with on-device speech recognition + TTS.
- **Games & review** — cloze, word match, picture match, word guess, spaced-repetition review, stories.
- **Accounts** — Google sign-in (Firebase Auth); the backend verifies the ID token, so a uid is proven rather than claimed. Progress syncs to the account.
- **Monetization** — trial (`TRIAL_DAYS`, unlimited-feeling with a daily soft cap) → free (`DAILY_MESSAGES_FREE`/day + rewarded-ad bonus) → premium (unlimited). Enforced server-side; Play purchases verified against the Play Developer API.
- **Admin panel** — in-app, owner/admin only: live stats, learners, and the AI-content report queue.
- **Account deletion** — Profile → Delete account erases the account and its data immediately (`DELETE /account`, verified token only), with a public page at `/delete-account`. Play requires both halves.
- **Web checkout** — `/checkout` sells the same Premium through Razorpay at ~2.36% instead of Play's 15%. Web-only by design; the app never links to it. See [Web checkout](#web-checkout-razorpay--the-second-storefront).
- **Onboarding** — native language, goal, level, biggest speaking struggle. Localized shell (en/hi/es/fr/pt).

## Run it locally (2 terminals)

**1. Backend** (works with zero keys — MOCK tutor + degraded limits):
```bash
cd backend && npm install && npm start      # http://localhost:10000
```

**2. App** (Android emulator — 10.0.2.2 is the emulator's alias for your PC):
```bash
cd app && flutter pub get
flutter run --dart-define=SPEAKFLOW_API=http://10.0.2.2:10000
```
On a **physical phone**, replace with your PC's LAN IP, e.g. `http://192.168.1.20:10000`.

## Wiring the real services (when ready)

1. **Gemini** — get a key at https://aistudio.google.com/apikey → set `GEMINI_API_KEY` in `backend/.env`. The tutor immediately upgrades from MOCK to real AI.
2. **Firebase (NEW project)** — create a fresh project, download a service-account JSON (Project Settings → Service accounts), and set `FIREBASE_SERVICE_ACCOUNT_JSON` + `FIREBASE_PROJECT_ID`. Limits then enforce for real.
3. **Deploy backend** — push to GitHub, use `backend/render.yaml` as a Render Blueprint, fill the secret env vars, then point `AppConfig.baseUrl` (app default) at the new Render URL.

## Known limits (built, but only goes so far)

- **Pronunciation scoring measures intelligibility, not accent.** `assessPronunciation`
  aligns the speech-recogniser's transcript against the target with Needleman–Wunsch
  and gives partial credit for near-misses, then nudges the result with the
  recogniser's own confidence. So it answers "how much of that did the recogniser
  catch, in order?" — a real signal, and the per-word breakdown is honest. It does
  **not** grade phonemes, stress or intonation: a heavy accent the recogniser still
  parses cleanly can score 100. Real accent scoring needs a speech-assessment API.

## What's next (not built yet)

- Any real imagery. Scenarios and the picture-match game are carried entirely by emoji; `assets/` holds only the logo and icon.
- iOS build (Android only today — the iOS AdMob unit is still a placeholder; the Android banner, interstitial and rewarded units are the real ones).

## Operational checklist

Things that are configured outside this repo and are easy to forget:

1. **Push before assuming it's live.** Render auto-deploys from `origin/main`. Confirm what's actually running: `GET /health` reports the AI model chain and the auth mode.
2. **`REQUIRE_AUTH_TOKEN`.** While it is `false`, any caller can claim any uid (the rollout grace for old app builds). Watch `auth.legacyHeader` on `/health`; once it's ≈0, set it to `true` in the Render dashboard.
3. **Play Developer API access.** Without it `PLAY_PACKAGE_NAME` is set but verification fails as *transient*, and paying subscribers only get a rolling 3-day grace window. Play Console → Setup → API access → link the GCP project that owns the service account, then grant it order/financial read access. Grace is only ever granted to an account that has had a **verified** purchase before — otherwise a 403 from the Play API (exactly what an unconfigured project returns) would have let any signed-in caller collect rolling free premium with a junk token.

4. **`PREMIUM_DAILY_CAP`.** Premium is unlimited in the literal sense — a premium uid is never counted and never blocked — so one subscription authorises unbounded AI spend. Default `0` keeps that. Set it to `500` for a fair-use ceiling no real learner reaches (a heavy user does 30–50 messages/day).

## Unit economics

Measured, not estimated — the token counts come from the real prompts and the limits from this repo:

| | cost |
|---|---|
| One chat message (typical session) | ~$0.0006 · **₹0.06** |
| One chat message (most the server's caps allow) | ~$0.0063 · ₹0.60 |
| One aux call (translate / phrases / picture match / vocab) | ~$0.0007 · ₹0.07 |
| A free user maxing out a day (23 msg + 30 aux) | ~₹3.38 |
| A trial user maxing out a day (50 msg + 80 aux) | ~₹8.34 |

Two plans, no intro offer: monthly and annual. (A ₹10 first-month offer was removed — it went underwater at ~4 messages/day, and invited a pay-₹10, use-a-month-unlimited, cancel loop.)

At Google Play India's 15% subscription fee you keep **₹169.15/month** on the ₹199 plan and **₹849.15/year** (₹70.76/month) on the ₹999 plan. So a subscriber turns unprofitable at roughly:

- **monthly plan** — ~95 messages/day
- **annual plan** — ~39 messages/day

The annual plan is the thin one: a committed daily learner is close to its break-even on AI cost alone, before Firestore, Render or support.

**Prices live in Play Console, not in this repo.** The app renders `ProductDetails.price`, which Play localises to the buyer's country and currency; the ₹199/₹999 figures above are the Indian prices and are only used for this analysis. A subscription is purchasable exactly where you have made it available and priced it — anywhere else Play returns no product and the paywall says so rather than offering a dead button.

Pricing basis: [Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing) (`gemini-3-flash-preview`, $0.50/1M in, $3.00/1M out), [Play service fees](https://support.google.com/googleplay/android-developer/answer/112622), ₹95.9/USD. Re-run the numbers when any of those move.

## Web checkout (Razorpay) — the second storefront

Play's Payments policy governs purchases made **inside** the Android app; it does not govern our own website. So `GET /checkout` sells the same Premium through Razorpay, where the only fee is ~2.36% instead of Play's 15%:

| ₹199/month | you keep |
|---|---|
| In-app (Play Billing) | ₹169.15 |
| **Web (Razorpay)** | **₹194.30** |

**+₹25.15 per subscriber — about 15% more.**

Two rules this design does not bend:

1. **The app never links here.** That is Play's anti-steering rule. Play Billing stays the only in-app purchase path; traffic to `/checkout` comes from marketing, email and social, never from a button in the app.
2. **Only the webhook grants premium.** The browser's "payment succeeded" callback is a UI hint that anyone can forge. `POST /checkout/webhook` verifies an HMAC-SHA256 signature over the **raw** request body before writing anything — which is why `app.js` stashes `req.rawBody` for that one path.

The learner signs in on the page with the same Google account they use in the app, so the uid comes from a verified Firebase ID token and rides along in the subscription's `notes` — that is how a renewal ten months later still finds the right account. `premiumExpiry` is shared with the Play path and only ever moves **later**, so holding both subscriptions can never shorten either.

Setup (all outside this repo — until it's done, `/checkout` just says it isn't available):

1. **Razorpay** → Subscriptions → Plans: create a monthly and an annual plan → `RAZORPAY_PLAN_MONTHLY` / `RAZORPAY_PLAN_ANNUAL`.
2. **Razorpay** → Settings → API Keys → `RAZORPAY_KEY_ID` / `RAZORPAY_KEY_SECRET`.
3. **Razorpay** → Settings → Webhooks → `https://<host>/checkout/webhook`, subscribe to `subscription.charged`, `.cancelled`, `.halted`, `.completed` → `RAZORPAY_WEBHOOK_SECRET`. **Without this secret nothing can ever be granted.**
4. **Firebase** → Project settings → Your apps → **Web** (a separate registration from the Android app) → `FIREBASE_WEB_API_KEY`, `FIREBASE_WEB_AUTH_DOMAIN`, `FIREBASE_WEB_APP_ID`. Add the backend's domain under Authentication → Settings → Authorized domains, or the Google popup is refused.
5. Optional display labels: `RAZORPAY_PRICE_MONTHLY` / `RAZORPAY_PRICE_ANNUAL` (e.g. `₹199`). Blank shows a dash — the page never guesses an amount.

Recurring charges ride UPI AutoPay / e-NACH / card mandates, which fail more often than Play's billing does. Watch `subscription.halted` in the logs; unlike Play, nobody else is retrying those for you.

*Not chosen: Razorpay via Play's in-app alternative billing (allowed in India). It reduces Google's cut 15% → 11%, so after Razorpay's 2.36% the gain is ₹3.26/subscriber/month — 1.64% — in exchange for keeping both billing paths alive, PCI DSS certification, and reporting every transaction to Google within 24 hours. Revisit past ~3,000 paying subscribers.*

## Renaming

- App display name: `app/android/app/src/main/AndroidManifest.xml` (`android:label`).
- Dart package name: `app/pubspec.yaml` (`name:`) — then update imports `package:speakflow/...`.
- Backend service name: `backend/package.json` + `backend/render.yaml`.
