# Deploying the Speak Frankly backend to Render

The backend must be on GitHub, then Render builds & hosts it. The Flutter app
then points at the Render URL instead of `localhost` — so it works anywhere,
no USB needed.

## Step 1 — Put the code on GitHub (private)

1. Go to https://github.com/new → name it **`speak-frankly`** → set **Private** →
   **do NOT** add a README/.gitignore (the repo already has them) → Create.
2. Tell Claude the repo name and it will push (`git remote add` + `git push`).
   Or push yourself from `english_tutor_ai/`:
   ```bash
   git remote add origin https://github.com/daksh437/speak-frankly.git
   git push -u origin main
   ```

Secrets are safe: `.env` and `serviceAccount.json` are gitignored and were NOT committed.

## Step 2 — Create the Render service

1. https://render.com → sign in with GitHub → **New +** → **Blueprint**.
2. Pick the `speak-frankly` repo. Render reads `render.yaml` and proposes the
   **speak-frankly-backend** web service (root dir `backend`, free plan).
   *(No Blueprint? Use **New + → Web Service**: root dir `backend`, build
   `npm install`, start `npm start`, health check `/health`.)*
3. Click **Apply / Create**.

## Step 3 — Set the environment variables

Open `RENDER_ENV_VALUES.txt` (in the project root, gitignored) and paste each
KEY = VALUE into Render → the service → **Environment**. The important ones:

| Key | Value |
|-----|-------|
| `NODE_ENV` | `production` |
| `GEMINI_API_KEY` | (from the file) |
| `GEMINI_MODEL` | `gemini-3-flash-preview` |
| `FIREBASE_PROJECT_ID` | `speakfrankly-cdddf` |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | (the long one-line JSON from the file) |
| `DAILY_MESSAGES_FREE` | `25` |
| `TRIAL_DAYS` | `7` |

Do **not** set `DEV_SKIP_LIMITS` (the server refuses to boot with it in production).

## Step 4 — Deploy & verify

- Render builds and deploys. When live, open `https://<your-service>.onrender.com/health`
  → should return `{"status":"ok","success":true}`.
- Free plan note: the service **sleeps after ~15 min idle**; the first request
  then takes ~30–50s to wake. Fine for testing; upgrade later for always-on.

## Step 5 — Point the app at Render

Update the app's default backend URL to the new Render URL in
`app/lib/config/app_config.dart` (the `defaultValue`), then rebuild:
```bash
cd app
flutter build apk --release
```
Now the app works over any network (WiFi/mobile data) — no USB / `adb reverse` needed.
