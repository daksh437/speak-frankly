# Analytics events — what the app sends, and what Google Ads should optimise on

Firebase project `speakfrankly-cdddf` · GA4 stream `544708653` · `com.speakfrankly`

---

## What Firebase collects on its own

No code involved. These already flow from the shipped build.

| Event | Fires when |
|---|---|
| `first_open` | The app is opened for the first time — this is the **install** conversion |
| `session_start` | Every session |
| `screen_view` | Every screen |
| `in_app_purchase` | **Automatically collected on Android once the app is linked to Google Play.** No code needed |

> **On `in_app_purchase` vs `purchase`:** they are different events and do NOT
> collide. `in_app_purchase` is collected automatically by the SDK; `purchase`
> is a recommended event that only fires if the app logs it. The app logs
> `purchase` deliberately (below) so that value and currency are attached for
> value-based bidding — the automatic event alone does not give Google Ads that.

## What the app logs itself

Everything goes through `AnalyticsService.log` (`lib/services/analytics_service.dart`),
which no-ops safely if Firebase is unavailable.

### Standard Firebase events — the ones Google Ads understands natively

| Event | Where | Params |
|---|---|---|
| `purchase` | `premium_service.dart` | `transaction_id`, `value`, `currency`, `item_id` |
| `sign_up` | `auth_service.dart` | `method: google` — only when `isNewUser` |
| `login` | `auth_service.dart` | `method: google` — returning learners |
| `tutorial_complete` | `onboarding_screen.dart` | `level`, `goal`, `native_language` |

`sign_up` and `login` are split on `additionalUserInfo.isNewUser`. Firing
`sign_up` on every sign-in would count each returning learner as a fresh
acquisition and quietly inflate the number the ad platform bids against.

`purchase` fires only on `PurchaseStatus.purchased`, never on `restored` —
a restore is the same subscription re-applied on a reinstall, and counting it
would report money nobody paid again.

### Custom events — product behaviour

| Event | Where |
|---|---|
| `scenario_started` / `scenario_completed` | `chat_screen.dart` |
| `story_started` / `story_completed` | `story_screen.dart` |
| `speaking_attempt` (`score`) | `speak_screen.dart` |
| `picture_match_done` (`score`) | `picture_match_screen.dart` |
| `word_guess_done` (`score`) | `word_guess_screen.dart` |
| `custom_scenario` | `home_screen.dart` |
| `content_import` (`count`) | `import_text_screen.dart` |
| `ai_content_reported` (`reason`) | `chat_screen.dart` |

---

## Which of these Google Ads should bid on

App campaigns can optimise for install volume, for an in-app action, or for
revenue. The constraint that decides everything is **volume**: the algorithm
needs roughly 10 conversions a day to learn anything. Picking an event that is
too deep starves the campaign and it never leaves the learning phase.

### Use these

| Event | Why | Timing |
|---|---|---|
| **`first_open`** | The install conversion. What the campaign runs on today | Instant |
| **`tutorial_complete`** | Onboarding finished — an activated user, not just a download. Fires within a couple of minutes of install, so volume stays close to install volume | ~2 min |
| **`purchase`** | Revenue, with value and currency attached. The only event that enables target-ROAS bidding | Days–weeks |

### Good signals, but thin

`scenario_completed` — the real value moment, someone actually held a
conversation. Better quality signal than `tutorial_complete`, lower volume.

`sign_up` — account created.

### Never bid on these

`scenario_started`, `story_started` — too shallow; opening a screen is not an
outcome.

`speaking_attempt`, `picture_match_done`, `word_guess_done` — engagement, but
noisy and repeatable by the same user many times a day.

`login`, `session_start` — not conversions at all.

**`ai_content_reported`** — this one matters: it is a *safety* signal. A learner
reporting an offensive AI reply is bad news. Optimising towards it would be
actively backwards.

---

## The order to switch in

```
Now                          first_open  (Install volume) — change nothing
Once installs are steady     tutorial_complete
                             (~10+/day, so the algorithm has signal to learn from)
Once real revenue exists     purchase + target ROAS
```

The common mistake is jumping to `purchase` early. With a handful of
subscriptions a month there is nothing for the model to learn from, and
delivery collapses.

---

## Before any of this works

1. **Ship a build.** `purchase`, `sign_up`, `login` and `tutorial_complete` were
   added after 1.5.3 (versionCode 23). The installed app does not send them.
   Until a new release is live and in real users' hands, Google Ads cannot see
   them — an event that has never been received cannot be imported.

2. **Mark the ones you want as key events.** Firebase Console → Analytics →
   Events → toggle "Mark as key event". Google Ads only offers key events in its
   import list, which is why the ten custom events above do not appear there yet.

   Worth marking, in this order: `tutorial_complete`, `purchase`,
   `scenario_completed`, `sign_up`.

3. **Then import.** Google Ads → Goals → Conversions → New conversion action →
   App → Google Analytics 4 (Firebase).
