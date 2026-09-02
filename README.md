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

Two plans, monthly and annual, plus a short paid intro offer (₹4 for the first 3 days, India only). An earlier ₹10 FIRST-MONTH offer was removed because it went underwater at ~4 messages/day and invited a pay-₹10, use-a-month-unlimited, cancel loop. Three days is a far smaller exposure than a month, but it is not zero: a paid intro user resolves to `premium`, so `PREMIUM_DAILY_CAP` (0 = unlimited today) is the only thing bounding them. Set it before running paid acquisition.

At Google Play India's 15% subscription fee you keep **₹170.00/month** on the ₹200 plan and **₹850.00/year** (₹70.83/month) on the ₹1,000 plan. So a subscriber turns unprofitable at roughly:

- **monthly plan** — ~94 messages/day
- **annual plan** — ~39 messages/day

The annual plan is the thin one: a committed daily learner is close to its break-even on AI cost alone, before Firestore, Render or support.

**Prices live in Play Console, not in this repo.** The app renders `ProductDetails.price`, which Play localises to the buyer's country and currency; the ₹200/₹1,000 figures above are the Indian prices and are only used for this analysis. A subscription is purchasable exactly where you have made it available and priced it — anywhere else Play returns no product and the paywall says so rather than offering a dead button.

Pricing basis: [Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing) (`gemini-3-flash-preview`, $0.50/1M in, $3.00/1M out), [Play service fees](https://support.google.com/googleplay/android-developer/answer/112622), ₹95.9/USD. Re-run the numbers when any of those move.

## The hard paywall

Sign in → onboarding → paywall → app. Nothing else gets through: `PaywallGate`
(`app/lib/screens/auth_gate.dart`) asks `/access` what this account is entitled
to and only reveals `MainShell` for a premium answer. The server enforces the
same rule independently — `REQUIRE_PREMIUM=true` with `TRIAL_DAYS=0` makes every
AI call from a free account fail with `PREMIUM_REQUIRED` — so a patched client
that skips the screen still gets nothing.

**The trial is a Play offer, not app logic.** In Play Console → the
`premium_monthly` subscription → the monthly base plan → **Add offer**:

| Setting | Value |
|---|---|
| Eligibility | New subscribers only (single use) |
| Phase 1 | 3 days, ₹4, one billing cycle |
| Phase 2 | the base plan — ₹200/month, until cancelled |

**Set the offer's availability to India only.** ₹4 is below Play's minimum
offer price in roughly three dozen countries once it is converted — A$0.09
against an A$0.10 floor, ฿1.00 against ฿2.00, and so on — and it is *above* the
allowed ceiling in Georgia and Singapore, where Play caps an intro at a fraction
of the base price. Pricing it per country would mean 38 manual edits and a
different discount in every market. India is the primary market and the only one
where ₹4 is a sensible number, so the offer lives there; everywhere else Play
simply returns no intro and the paywall shows the normal price with a Subscribe
button. That path is covered by `app/test/premium_offers_test.dart`.

Play charges the ₹4, waits out the phase, then auto-debits ₹200 unless the
learner cancelled. Renewals, cancellations, refunds, dunning and the
legally-required renewal reminders are all Google's. The app only asks for the
right offer and reacts to the answer.

Two things this shape buys: the flow is Play-policy-clean (no third-party
billing inside the app), and the price and trial length become Console edits
rather than app releases.

If Play won't accept a 3-day *paid* phase on your base plan, the alternatives are
a 1-week ₹4 phase, or a free 3-day trial followed by ₹200. The app renders
whatever phases Play returns, so either works with no code change.

**Why the paywall reads pricing phases.** With an offer attached, Play returns
*two* `ProductDetails` for the same product id — one for the base plan, one for
the offer — and the offer's token, not the product id, decides whether the buyer
is charged ₹4 or ₹200. `PremiumService` therefore keeps a list, never a map
keyed by product id, and picks the cheapest opening phase.
`app/test/premium_offers_test.dart` locks that down.

An intro offer only comes back while the account is still **eligible** for it. A
learner who already used their trial sees the plain ₹200 price and a Subscribe
button — the screen never promises a trial Play will not honour.

Two deliberate softenings in the gate, both about not accusing a paying learner
of not paying: the paywall waits for Play's `restorePurchases()` as well as the
server's answer (so a renewal we haven't recorded yet doesn't flash a sales page
at a subscriber), and if `/access` cannot be reached at all the app opens
normally — the server refuses the actual work anyway.

## Renaming

- App display name: `app/android/app/src/main/AndroidManifest.xml` (`android:label`).
- Dart package name: `app/pubspec.yaml` (`name:`) — then update imports `package:speakflow/...`.
- Backend service name: `backend/package.json` + `backend/render.yaml`.
