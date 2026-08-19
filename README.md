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

## What's next (not built yet)

- Pronunciation *scoring* (speech-to-text exists; grading what was said does not).
- iOS build (Android only today — the iOS AdMob unit is still a placeholder).
- Real AdMob banner + interstitial units (see `app/lib/services/ad_service.dart` — these are still Google TEST units, so they earn nothing).

## Operational checklist

Things that are configured outside this repo and are easy to forget:

1. **Push before assuming it's live.** Render auto-deploys from `origin/main`. Confirm what's actually running: `GET /health` reports the AI model chain and the auth mode.
2. **`REQUIRE_AUTH_TOKEN`.** While it is `false`, any caller can claim any uid (the rollout grace for old app builds). Watch `auth.legacyHeader` on `/health`; once it's ≈0, set it to `true` in the Render dashboard.
3. **Play Developer API access.** Without it `PLAY_PACKAGE_NAME` is set but verification fails as *transient*, and paying subscribers only get a rolling 3-day grace window. Play Console → Setup → API access → link the GCP project that owns the service account, then grant it order/financial read access.

## Renaming

- App display name: `app/android/app/src/main/AndroidManifest.xml` (`android:label`).
- Dart package name: `app/pubspec.yaml` (`name:`) — then update imports `package:speakflow/...`.
- Backend service name: `backend/package.json` + `backend/render.yaml`.
