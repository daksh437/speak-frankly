/**
 * Generate metadata/play-console-steps.md — one paste-ready page for whoever
 * fills in the Play Console form.
 *
 * Generated rather than hand-written so the copy in it can never drift from the
 * copy in store-text/: the character counts printed beside each field are
 * measured from the same files at build time.
 *
 * Usage: node scripts/build-console-steps.mjs
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const read = (p) => readFileSync(resolve(ROOT, p), 'utf8');
const len = (s) => [...s].length;

const title = read('store-text/app-title.txt');
const short = read('store-text/short-description.txt');
const full = read('store-text/full-description.txt').trim();
const hiTitle = read('store-text/hi/app-title.txt');
const hiShort = read('store-text/hi/short-description.txt');
const hiFull = read('store-text/hi/full-description.txt').trim();

const F = '```';
const DELETE_URL = 'https://speak-frankly.onrender.com/delete-account';

const md = `# Play Console — paste-ready steps

Everything below is copy-paste. Nothing here needs another file open.

App: **Speak Frankly** · \`com.speakfrankly\` · Education
Assets folder: \`listing-content/\` (in this repo)

Play Console → your app → **Grow → Store presence → Main store listing**

> Only the Main store listing is in scope. Do not touch the package name,
> production releases, pricing or monetisation.

---

## 1. App name  — ${len(title)}/30 characters

${F}
${title}
${F}

## 2. Short description  — ${len(short)}/80 characters

${F}
${short}
${F}

## 3. Full description  — ${len(full)}/4000 characters

${F}
${full}
${F}

---

## 4. Graphics — drag these in

| Play field | File |
|---|---|
| App icon | \`icon/icon-512.png\` |
| Feature graphic | \`graphics/feature-graphic-1024x500.png\` |
| Phone screenshots | \`screenshots/\` 01 through 08 — **in this order** |

Screenshot order matters; it is the story the listing tells:

1. \`01-core-value.png\` — Speak English with confidence
2. \`02-ai-conversation.png\` — Practise real conversations
3. \`03-speaking-practice.png\` — Practise speaking out loud
4. \`04-story-mode.png\` — Learn through real-life situations
5. \`05-vocabulary.png\` — Build your everyday vocabulary
6. \`06-picture-match.png\` — Learn while having fun
7. \`07-progress.png\` — See your progress
8. \`08-daily-practice.png\` — Make English practice a daily habit

An alternative feature graphic sits at \`graphics/feature-graphic-alternative.png\`
if you would rather A/B test the centred composition.

---

## 5. Hindi translation (optional, but India is the main market)

Main store listing → **Manage translations → Add your own translation → हिन्दी**

App name — ${len(hiTitle)}/30:

${F}
${hiTitle}
${F}

Short description — ${len(hiShort)}/80:

${F}
${hiShort}
${F}

Full description — ${len(hiFull)}/4000:

${F}
${hiFull}
${F}

---

## 6. BEFORE publishing — two declarations that can get this rejected

**Data safety** (Policy → App content → Data safety):

- [ ] Declare the **advertising ID**. The app serves real AdMob banner,
      interstitial and rewarded ads, so it collects one. Failing to declare this
      is a common rejection reason.
- [ ] Add the **account deletion URL**: \`${DELETE_URL}\`
      Play requires a deletion route for any app with accounts. In-app deletion
      now also exists at Profile → Delete account.

**Then:** preview the listing exactly as a user sees it, at phone width.

> If Play shows ANY warning, policy flag or missing declaration — stop there and
> ask, rather than clicking "Send for review".

---

## 7. Worth improving later (not blockers)

Three shots are honest but thinner than they could be — see
\`metadata/screenshot-alt-text.txt\` for the notes marked LIMITATION:

- **03** shows Shadowing Practice *before* anyone speaks, so the pronunciation
  score is missing. Speaking into the mic and recapturing makes this the
  strongest image in the set.
- **07** shows Speaking as 0 in the fluency map, for the same reason.
- **05** shows an empty translation row because the demo account's native
  language is English.

Recapture with \`node scripts/capture.mjs\`, then rebuild with
\`node scripts/build-screenshots.mjs\`.
`;

writeFileSync(resolve(ROOT, 'metadata/play-console-steps.md'), md);
console.log(`wrote metadata/play-console-steps.md (${(md.length / 1024).toFixed(1)} KB)`);
console.log(`  title ${len(title)}/30 · short ${len(short)}/80 · full ${len(full)}/4000`);
console.log(`  hi:   title ${len(hiTitle)}/30 · short ${len(hiShort)}/80 · full ${len(hiFull)}/4000`);
