# Play Store listing — Speak Frankly

Everything the Google Play **Main store listing** needs, in one folder. Built
against the real installed build, not the source tree.

- App: **Speak Frankly** · `com.speakfrankly` · Education
- Verified against build **1.5.3 (versionCode 23)**
- Screenshots captured on a **Samsung Galaxy A34 5G** (1080 x 2340, Android 16)

---

## The three rules this folder follows

**1. Real app over mockup.** Every screenshot is a real capture from a real
phone. Nothing here is a drawn approximation of the UI.

**2. Existing branding over new design.** The mark, the gradient and the colours
all come from assets the app already ships. `icon/icon-512.png` is a
byte-for-byte copy of `app/assets/icon_512.png` — the store icon and the icon on
the user's home screen are literally the same file.

**3. Accuracy over hype.** Every feature named in the copy was opened on the
device and confirmed working. Claims the app cannot support are listed as
explicitly rejected in `store-text/keywords.txt`.

---

## Layout

```
listing-content/
├── README.md                      you are here
├── store-text/
│   ├── app-title.txt              28/30 chars
│   ├── short-description.txt      78/80 chars
│   ├── full-description.txt       2632/4000 chars
│   ├── keywords.txt               ASO guidance + claims deliberately avoided
│   ├── screenshot-copy.txt        the 8 headlines, and why each one is there
│   └── hi/                        Hindi translation of the three text fields
├── screenshots/
│   ├── 01-core-value.png … 08-daily-practice.png    the 8 finals (1080x1920)
│   ├── raw/                       untouched device captures
│   └── src/                       caption + frame template
├── graphics/
│   ├── feature-graphic-1024x500.png
│   ├── feature-graphic-alternative.png
│   └── src/                       HTML sources + the app's real head mark
├── icon/
│   └── icon-512.png               the app's real icon, unmodified
├── metadata/
│   ├── screenshot-alt-text.txt
│   ├── asset-dimensions.txt       measured, not assumed
│   └── play-store-checklist.md    run this before publishing
└── scripts/
    ├── capture.mjs                pull a screenshot off the phone
    ├── render.mjs                 HTML → exact-size PNG
    └── build-screenshots.mjs      composite raw captures into finals
```

---

## Brand facts, sampled not guessed

Read pixel-for-pixel out of `app/assets/icon_512.png`:

| | |
|---|---|
| Gradient start | `#7A67FF` |
| Gradient mid | `#6B59EB` |
| Gradient end | `#5B4BD6` |
| Mark | `#FFFFFF` white speaking-head silhouette |
| Seed / primary | `#6C5CE7` |
| Light background | `#F7F6FC` |

> **Watch out:** `store-assets/icon.svg` in the repo root shows a *speech bubble
> with sound bars*. That is **not** the app's identity — it is stale and is not
> what ships. The real mark is the **speaking head**. Anything new must match
> the head, or the store page will not look like the installed app.

---

## Regenerating

```bash
node scripts/render.mjs             # both feature graphics
node scripts/capture.mjs            # device status + which screenshots remain
node scripts/build-screenshots.mjs  # raw captures → finished screenshots
```

`render.mjs` re-reads every PNG's own header after writing it and fails if the
size is off by even one pixel — Play rejects a wrong-sized upload rather than
resizing it for you.

The icon is deliberately **not** generated. It already exists and already meets
every Play requirement, so it is copied, never redrawn.

---

## Two things that must be true when capturing

**Capture from a normal account, never the owner account.** The home screen
renders an **Admin panel** row for any email in `ADMIN_OWNER_EMAILS`. That is
owner-only UI and must never appear in a store screenshot.

**Progress data has to be real.** The fluency map, streak and XP screenshot only
works with genuine usage behind it. Generate it by actually using the app —
hold conversations, save words, finish a scenario. Do not fabricate numbers.

---

## Still needs a human

See `metadata/play-store-checklist.md` for the full list. The two that can
block a release:

- **Data safety form** must declare the advertising ID — the app serves real
  AdMob banner, interstitial and rewarded ads.
- **Account deletion URL** (`/delete-account`) must be entered in the Data
  safety form, alongside the in-app path at Profile → Delete account.
