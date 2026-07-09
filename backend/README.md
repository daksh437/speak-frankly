# Speak Frankly Backend

AI English-tutor API. Node/Express, reuses the InstaFlow architecture (Gemini,
graceful AI fallbacks, Firestore-authoritative usage limits) but is a **separate
service and a separate Firebase project** — InstaFlow is untouched.

## Run locally

```bash
cd backend
npm install
cp .env.example .env      # fill in keys when ready (works with none for now)
npm start                 # http://localhost:10000
npm test                  # smoke test (no keys needed)
```

With **no** `GEMINI_API_KEY` → tutor runs in **MOCK mode** (canned replies).
With **no** Firebase creds → **degraded mode** (limits not enforced; fine for dev).

## Endpoints

| Method | Path              | Notes                                   |
|--------|-------------------|-----------------------------------------|
| GET    | `/health`         | liveness                                |
| GET    | `/scenarios`      | scenario library (`?level=`, `?theme=`) |
| GET    | `/scenarios/:id`  | one scenario                            |
| GET    | `/dictionary/:word` | dictionary card (`?target=Hindi` adds a translation) |
| GET    | `/access`         | learner's plan + remaining messages (needs `x-user-uid`) |
| POST   | `/tutor/chat`     | conversation turn (metered)             |
| POST   | `/tutor/feedback` | end-of-session report (metered)         |

Auth for metered routes: send the Firebase UID as `x-user-uid` (same contract as
InstaFlow). Body for `/tutor/chat`:

```json
{
  "scenarioId": "ordering-food",
  "level": "A1",
  "nativeLanguage": "Hindi",
  "messages": [{ "role": "user", "text": "I want one coffee please" }]
}
```

## Deploy (Render — a NEW service, not InstaFlow's)

1. Push this repo to GitHub.
2. Render → New → Web Service → root dir `backend`, build `npm install`, start `npm start`.
3. Set env vars: `NODE_ENV=production`, `CORS_ORIGINS`, `GEMINI_API_KEY`,
   `GEMINI_MODEL`, `FIREBASE_SERVICE_ACCOUNT_JSON`, `FIREBASE_PROJECT_ID`.
   Do **not** set `DEV_SKIP_LIMITS` (the server refuses to boot with it in prod).

## Plan model

- **trial** — `TRIAL_DAYS` (default 7) of unlimited tutor use for new users.
- **free** — `DAILY_MESSAGES_FREE` (default 25) messages/day, reset midnight UTC.
- **premium** — unlimited (Google Play; `premiumExpiry` in the future).

Limits are enforced server-side only (`middleware/aiAccess.js`).
