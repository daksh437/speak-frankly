# Speak Frankly — Google Ads creative strategy

Built from a hands-on audit of the **production app running on a physical
device** (Samsung Galaxy A34, `com.speakfrankly` 1.5.3 / build 23), not from the
source tree. Every claim below is something that was seen working on that phone.

---

## 1. Target audience

**Primary — "the silent understander" (India, 18–34).**
Reads English well, follows English content, has studied English for years, and
still freezes the moment they have to *produce* it out loud. Typically:

- students and early-career workers in tier-2/tier-3 cities
- job seekers preparing for interviews conducted in English
- customer-facing workers (retail, hospitality, BPO, delivery ops)
- first-language Hindi or a regional language; English is the work language

They do not need another course. They have had courses. What they have never had
is **a low-stakes partner to be bad at English in front of.**

**Secondary — the habit seeker.** Already tried a big-name language app, got
bored of matching pictures to words, wants something that feels like talking.

## 2. Main problem

> "I understand English. I just can't speak it."

Underneath that sentence sit three fears, in this order of intensity:

1. **Being judged for mistakes** — in front of colleagues, interviewers, strangers.
2. **Freezing mid-sentence** — knowing the word exists and not finding it in time.
3. **No one to practise with** — nobody at home or work will sit and let them
   fumble through English for ten minutes a day.

## 3. Main promise

**A conversation partner who never makes you feel stupid.**

You type or say whatever English you have. It answers the *meaning*, slips in one
kind correction, and keeps the conversation moving. Nothing is graded. Nobody is
watching.

## 4. Strongest feature

**The correction card inside a live conversation.** Verified on-device: the
learner sent *"I working as a graphic designer since two years"* and got back

- an amber correction card: **"I have worked as a graphic designer for two years"**
  with the reason *"Use 'have worked' for past to present, and 'for' with a period
  of time (two years)."*
- and then, unbroken, the tutor's next question: *"That is great experience. What
  are your main strengths as a designer?"*

That single screen is the entire product argument: **correction without
interruption, and without embarrassment.** It is the hero asset of this package.

Runner-up: **"Not sure what to say? Tap a reply"** — real suggestion chips
(*"I am very creative."*, *"I am good at Photoshop"*) that rescue a learner who
has frozen. This is the feature that keeps a beginner in the conversation, and no
competitor screenshot in this category shows anything like it.

## 5. Strongest emotional hook

> **"Make mistakes. That's the point."**

It inverts the exact fear that stops the audience from practising. Tested
alternatives that are weaker because they describe the tool rather than the
feeling: "AI English tutor", "Practise English daily", "Improve your English".

Runner-up hook, more literal and higher intent for search-adjacent placements:
**"You understand English. But can you speak it?"**

## 6. Best CTA

**"Start speaking today"** — verb-first, matches the app's own language ("Let's
speak English" on the home screen), and promises an action the user can complete
in 60 seconds. See `cta.txt` for the full rotation.

## 7. Top creative concepts, ranked

Ranked by expected install intent for the primary audience.

| # | Concept | Hook | Proof shown | Why it should work |
|---|---|---|---|---|
| 01 | **Mistakes welcome** | "Make mistakes. That's the point." | The real correction card, close-up | Attacks the #1 blocker head-on. The screenshot *proves* the promise in the same frame — the reader does not have to trust a claim. |
| 04 | **Job interview** | "Practise the job interview" | Job Interview scenario, B1, real correction | Highest-intent angle in India: English practice tied to a job outcome, not a hobby. Narrow, so it converts on a smaller, hotter audience. |
| 03 | **Never stuck for words** | "Never stuck for words" | "Tap a reply" chips + mic input bar | Speaks to the freeze, not the grammar. Differentiated: shows a mechanic competitors don't have. |
| 02 | **AI tutor** | "Your AI English conversation partner" | Full chat thread | The broadest, most searched framing. Best cold-audience reach; weaker differentiation, so it works as volume. |
| 05 | **Speak out loud** | "Speak it. Don't just read it." | Shadowing Practice with Listen + mic | Separates the app from read/tap vocabulary apps. Strong for users who tried Duolingo and felt they still couldn't talk. |
| 06 | **Real situations** | "Practise real situations" | Story mode role-play thread | Concrete and relatable — ordering food, the doctor, an interview. Sells usefulness rather than study. |
| 07 | **Daily habit** | "A little English, every day" | Home: streak, XP, level, word of the day | Retention-flavoured; better for re-engagement than cold acquisition. |
| 08 | **Words that stick** | "A new word every day" | Saved Words + "1 word due for review" | Lowest intent of the eight (vocabulary is a crowded promise) but cheap reach and pairs well with the speaking angles. |

Video concepts follow the same ranking logic and are documented in
`scripts/` — concept 01 (problem/solution) and concept 03 (fear of mistakes)
carry the hero footage in their first three seconds.

## 8. Why each concept should work

- **01 / 03 — fear-first.** The audience's blocker is emotional, not
  informational. Ads that name the fear ("afraid of making mistakes?") outperform
  ads that name the feature, because the reader recognises themselves rather than
  evaluating a product.
- **04 — outcome-first.** "Job interview" converts a vague desire (better
  English) into a dated, painful, specific event. It also self-selects users who
  will actually open the app tomorrow.
- **03 / 02 — mechanic-first.** Showing an interface element competitors do not
  have (suggested replies, live correction card) gives the ad a reason to exist
  beyond category keywords.
- **05 — category break.** "Don't just read it" is a direct, fair contrast with
  tap-and-match apps, using our own real screen as evidence.
- **06 — usefulness.** Scenario names do the persuading; no adjectives needed.
- **07 / 08 — habit and vocabulary.** Weakest cold hooks, strongest for
  remarketing and for lookalikes of engaged users.

## 9. Features that must NOT be advertised

| Feature | Why it is excluded |
|---|---|
| **Picture Match** | **Fixed, but still not shootable.** On device a **green** bicycle emoji had "He is riding a **blue** bicycle" as the correct answer — twice, across a refresh. Root cause: emoji render in different colours per platform, so a colour claim can never be true for every learner. The generator prompt now forbids colour and the server drops any item that names one (`backend/tests/picture-match.test.js`). Two things still stand between this and a creative: the fix has to be **deployed**, and the only capture we hold is the broken one (`source-screens/EXCLUDED-picture-match-content-bug.png`). Re-capture on device after the deploy, then it is fair game. |
| **Pronunciation score / word-by-word grading** | Could not be verified: it needs real speech into the mic, which cannot be injected over adb. The Speak screen and mic are shown; **no score, accuracy number or "AI checks your pronunciation" claim is made anywhere in this package.** |
| **Offline packs** | Premium-gated and not exercised on device. (Story mode's own "works offline" label is on-screen and is quoted only where that screenshot is shown.) |
| **Prices, trials, discounts** | ₹200/month and ₹1,000/year are live in Play, with a ₹4 / 3-day intro offer for new subscribers in India only. Prices localise per country and change, and the intro is not offered outside India at all. No creative states a price. |
| **Daily limits, ads, rewarded ads** | The free tier shows banner and interstitial ads and caps messages ("5 of 8 left today"). True, but it is a reason not to install. Excluded, and all screenshots are cropped above the ad slot. |
| **Ratings, install counts, "No.1", awards, testimonials** | No verified source exists. Nothing of the kind appears in any asset. |
| **Badges, streak numbers as claims** | The streak/XP/level UI is shown as *interface*; no creative claims a typical result ("learn in 30 days", "fluent in 3 months"). |
| **Named competitors** | No comparison uses a brand name. |

## 10. Brand rules applied

- Logo: the existing `app/assets/icon_512.png`, unmodified, rounded only.
- Colour: `#6C5CE7` seed violet, `#F59E0B` correction amber, `#F7F6FC` surface —
  all read straight out of `app/lib/theme/app_theme.dart`.
- Type: **Roboto** (Black / Bold / Regular) — the app's own Material typeface.
- Product imagery: unretouched screenshots and screen recordings from the device.
  Cropped only to remove the system status bar, the gesture bar and the ad slot.
- No new logo, no new icon, no redrawn UI, no stock photography, no models.
