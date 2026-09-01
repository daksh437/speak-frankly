# Play Store listing checklist — Speak Frankly

Tick these before touching **Publish**. Anything unticked is a reason to stop.

Legend: `[x]` verified · `[ ]` pending · `[!]` needs a decision

---

## Assets

### App icon — `icon/icon-512.png`
- [x] 512 x 512 px (read from the PNG header, not assumed)
- [x] 32-bit PNG with alpha, fully opaque
- [x] 19 KB — well under the 1 MB cap
- [x] **Byte-identical to `app/assets/icon_512.png`** — the app's real launcher
      icon, not a redesign. Store icon and installed icon will match exactly.
- [x] No pre-rounded corners (Play applies its own mask)

### Feature graphic — `graphics/feature-graphic-1024x500.png`
- [x] 1024 x 500 px
- [x] 24-bit RGB PNG, **no alpha channel** (Play requires this)
- [x] 253 KB — under the 15 MB cap
- [x] Uses the app's real speaking-head mark and its exact sampled gradient
      (#7A67FF → #5B4BD6)
- [x] Meaningful content inside a 64 px safe margin
- [x] Read at full size — no typos found

### Screenshots — `screenshots/01..08-*.png`
- [x] 8 files present
- [x] Each 1080 x 1920, 24-bit PNG, no alpha (verified from PNG headers)
- [x] Long side ≤ 2x short side (9:16 passes)
- [x] Each under 8 MB (largest 547 KB)
- [x] Captured from a real device, not mocked up (Galaxy A34 5G)
- [x] All 8 share one visual system (same type, spacing, background, crop)

---

## Content safety — the things that get a listing rejected

- [x] No fake ratings, review counts, awards or user numbers
- [x] No "No.1" / "Best" / "#1" / "Millions of users"
- [x] No "Download now" / "Install now" inside screenshots
- [x] No Google Play badge inside any asset
- [x] No unsupported outcome claims ("fluent in 30 days", "guaranteed")
- [x] No exam claims (IELTS/TOEFL) — the app has no exam content
- [x] No "native teacher" / "certified teacher" — there are no human teachers
- [x] No accent-training claims — the score measures **intelligibility**, not
      accent, so the copy says "which words came through clearly"
- [x] No keyword stuffing; `keywords.txt` is guidance, never pasted into Play
- [x] **No personal data in any screenshot** — status bar (clock, notification
      icons, battery) is cropped out of every shot. One capture accidentally
      caught a phone dialer with a real call log; it was deleted, not used.
- [x] **No owner-only UI** — recaptured from a normal, non-admin account, so the
      "Admin panel" row is absent from every shot.
- [x] No loading spinners or error states. Ad banners are cropped out by the
      shared viewport (the free plan shows one on Home and Words).

---

## Every feature shown actually exists

Verified on-device against build **1.5.3 (versionCode 23)**:

- [x] AI scenario conversations with in-line corrections
- [x] "Talk about anything" — type any topic, the tutor starts a chat
- [x] Shadowing Practice with pronunciation scoring
- [x] Story mode — guided role-plays, stated by the app itself to work offline
- [x] Picture match
- [x] Word of the Day
- [x] Saved Words + tap-a-word dictionary
- [x] Profile: streak, XP, words saved, fluency map, badges
- [x] Placement test, level filters (A1/A2/B1)
- [x] UI in English, Hindi, Spanish, French, Portuguese
- [x] Free trial → free daily limit → Premium

Claimed nowhere, because it is not in this build: exam prep, human tutors,
certificates, offline AI conversation (only Story mode is offline).

---

## Store text

- [x] Title 28/30 characters
- [x] Short description 78/80 characters
- [x] Full description 2632/4000 characters
- [x] No emoji
- [x] Hindi translation prepared in `store-text/hi/`
- [x] Proofread — no typos found

---

## Play Console — do NOT touch

Only the Main Store Listing is in scope. Leave alone:

- [ ] Package name
- [ ] Production APK/AAB and any release settings
- [ ] Pricing and monetisation
- [ ] App content declarations — **except** see the open item below

---

## Known thin spots (honest, not blockers)

- **Screenshot 3** shows Shadowing Practice *before* anyone speaks, so the
  pronunciation score is not visible. adb cannot inject audio. Recapturing with
  a real voice would make this the strongest shot in the set.
- **Screenshot 7** shows Speaking 0 in the fluency map for the same reason.
- **Screenshot 5** shows an empty translation row (`recommend —`) because the
  demo account's native language is English.
- The demo account has 1 saved word and a 1-day streak. Real but modest.

## Open items before publishing

- [!] **Data safety form.** The app shows AdMob ads (real banner, interstitial
      and rewarded units) and therefore accesses the advertising ID. The Data
      safety section must declare this, and the app must declare the
      `com.google.android.gms.permission.AD_ID` permission. Confirm this is
      already declared, or the listing risks rejection.
- [!] **Account deletion URL.** Play requires a deletion route for any app with
      accounts. The app now has in-app deletion (Profile → Delete account) plus
      a public page at `/delete-account`. That URL must be entered in the Data
      safety form.
- [ ] Preview the finished listing exactly as a user sees it, on a phone-sized
      window, before publishing.
- [ ] If Play shows **any** warning, policy flag or missing declaration —
      stop and ask, do not publish.
