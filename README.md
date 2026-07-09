# Speak Frankly — AI English Tutor

Learn English by *talking* — real-life scenarios, an AI conversation partner that
matches your level, gentle in-context corrections, and tap-any-word dictionary
help. Built to reuse the InstaFlow architecture (Gemini, graceful AI fallbacks,
Firestore-authoritative usage limits) as a **separate service + separate Firebase
project**, so the live InstaFlow app is never touched.

> Name: "Speak Frankly". Android package id: `com.speakfrankly.app`. Firebase project: `speakfrankly-cdddf`.

## Structure

```
english_tutor_ai/
  backend/   Node/Express API  (tutor chat, dictionary, scenarios, plan limits)
  app/       Flutter app        (onboarding → scenarios → chat + dictionary)
```

## MVP scope (built)

- **Scenario library** — Ordering Food, Job Interview, Shopping, Doctor, Small Talk, Airport.
- **AI conversation** — level-matched replies, answers meaning-first, ≤2 gentle corrections/turn, quick-reply suggestions. Runs in **MOCK mode** with no API key.
- **Dictionary** — tap any word → meaning, phonetics, audio, + L1 translation. Real data from dictionaryapi.dev (free), cached.
- **Monetization** — trial (7d unlimited) → free (25 msg/day) → premium (unlimited). Enforced server-side.
- **Onboarding** — native language, goal, level. Local session id (swaps to Firebase UID later).

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

- Firebase Auth in the app (replace the local session id).
- Speaking + pronunciation scoring (speech-to-text) — technically the hardest piece.
- Saved-vocabulary list + spaced-repetition review games.
- Google Play billing wiring for the premium plan.

## Renaming

- App display name: `app/android/app/src/main/AndroidManifest.xml` (`android:label`).
- Dart package name: `app/pubspec.yaml` (`name:`) — then update imports `package:speakflow/...`.
- Backend service name: `backend/package.json` + `backend/render.yaml`.
