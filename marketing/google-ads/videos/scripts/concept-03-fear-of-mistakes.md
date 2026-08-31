# Video concept 03 — Fear of mistakes

**Deliverables:** `15s-9x16.mp4`, `15s-1x1.mp4`, `15s-16x9.mp4`, `30s-9x16.mp4`, `30s-1x1.mp4`, `30s-16x9.mp4`, `45s-9x16.mp4`, `45s-1x1.mp4`, `45s-16x9.mp4`

**Hook (scene 1):** "Afraid of making mistakes?" — Nobody is listening. Nobody is judging.

**Look:** floating-UI motion graphics on a lavender wash. Real interface elements are lifted out of the app — no phone bezel — and shown at a size that reads on a handset. Type arrives line by line with the operative word in violet under an amber rule. Cards drift continuously; nothing is static.

**Framing per ratio**

| Ratio | Canvas | Composition |
|---|---|---|
| 9:16 | 1080x1920 | Type top, floating element centred, chevrons low. Built for the format, not cropped from 16:9. |
| 1:1 | 1080x1080 | Compact: type top, element centred, smaller device stills. |
| 16:9 | 1920x1080 | Type in the left column, element floating right. |

**Voiceover and music are already mixed into every delivered cut.** Voice: neural Indian-English TTS (`en-IN-NeerjaNeural`), one line per scene at that scene's start. Music: an original instrumental generated in-repo (`build_music.py`) — I-V-vi-IV in C major at 96 BPM, lyric-free, resolving onto the tonic under the end card — so there is no third-party licence to clear. The bed is side-chained to the voice and drops ~12 dB while a line is speaking. Rebuild the audio with `build_voiceover.py`. For a human read, the Voiceover column below is the script.

## 15-second cut

3 scenes of 4.1s + 2.6s end card.

| # | Timestamp | Real UI shown | On-screen text | Voiceover |
|---|---|---|---|---|
| 1 | 0.0–4.1s | the learner's own message, "I working as a graphic designer since two years", mistakes intact | **Afraid of making mistakes?**<br>Nobody is listening. Nobody is judging. | "Afraid of making mistakes in English?" |
| 2 | 4.1–8.3s | the "Talk about anything" card from the home screen | **Good. Make them here.**<br>Write it wrong. On purpose. | "Here, make them. Write it wrong." |
| 3 | 8.3–12.4s | the amber correction card — "I have worked as a graphic designer for two years" plus its reason — lifted from the Job Interview chat | **This is the right way.**<br>One line. No lecture. | "Your tutor shows the right way." |
| END | 12.4–15.0s | brand end card | **Speak Frankly**<br>Practise real English conversations | "Start speaking today." |

**CTA:** on-card button **"Start speaking today"**, held for the full 2.6s. The Google Play install button is supplied by the campaign.

## 30-second cut

6 scenes of 4.6s + 2.6s end card.

| # | Timestamp | Real UI shown | On-screen text | Voiceover |
|---|---|---|---|---|
| 1 | 0.0–4.6s | the learner's own message, "I working as a graphic designer since two years", mistakes intact | **Afraid of making mistakes?**<br>Nobody is listening. Nobody is judging. | "Afraid of making mistakes in English?" |
| 2 | 4.6–9.1s | the "Talk about anything" card from the home screen | **Good. Make them here.**<br>Write it wrong. On purpose. | "Here, make them. Write it wrong." |
| 3 | 9.1–13.7s | the amber correction card — "I have worked as a graphic designer for two years" plus its reason — lifted from the Job Interview chat | **This is the right way.**<br>One line. No lecture. | "Your tutor shows the right way." |
| 4 | 13.7–18.3s | the tutor's reply, "That is great experience. What are your main strengths as a designer?" | **And the chat keeps going.**<br>It never stops to grade you. | "And the conversation keeps going." |
| 5 | 18.3–22.8s | the "Choose your reply" options from a Story mode role-play | **Try again. And again.**<br>As many times as you need. | "Try again. Nobody is counting." |
| 6 | 22.8–27.4s | the Shadowing Practice phrase card with its Listen button | **Then say it out loud.**<br>Where it is safe to get it wrong. | "Say it out loud, safely." |
| END | 27.4–30.0s | brand end card | **Speak Frankly**<br>Practise real English conversations | "Start speaking today." |

**CTA:** on-card button **"Start speaking today"**, held for the full 2.6s. The Google Play install button is supplied by the campaign.

## 45-second cut

8 scenes of 5.3s + 2.6s end card.

| # | Timestamp | Real UI shown | On-screen text | Voiceover |
|---|---|---|---|---|
| 1 | 0.0–5.3s | the learner's own message, "I working as a graphic designer since two years", mistakes intact | **Afraid of making mistakes?**<br>Nobody is listening. Nobody is judging. | "Afraid of making mistakes in English?" |
| 2 | 5.3–10.6s | the "Talk about anything" card from the home screen | **Good. Make them here.**<br>Write it wrong. On purpose. | "Here, make them. Write it wrong." |
| 3 | 10.6–15.9s | the amber correction card — "I have worked as a graphic designer for two years" plus its reason — lifted from the Job Interview chat | **This is the right way.**<br>One line. No lecture. | "Your tutor shows the right way." |
| 4 | 15.9–21.2s | the tutor's reply, "That is great experience. What are your main strengths as a designer?" | **And the chat keeps going.**<br>It never stops to grade you. | "And the conversation keeps going." |
| 5 | 21.2–26.5s | the "Choose your reply" options from a Story mode role-play | **Try again. And again.**<br>As many times as you need. | "Try again. Nobody is counting." |
| 6 | 26.5–31.8s | the Shadowing Practice phrase card with its Listen button | **Then say it out loud.**<br>Where it is safe to get it wrong. | "Say it out loud, safely." |
| 7 | 31.8–37.1s | the end-of-session card — "Great session! +20 XP" | **Confidence, not perfection.**<br>That is what daily practice builds. | "This is how confidence gets built." |
| 8 | 37.1–42.4s | the home screen's Streak / XP / Level row | **Start with five minutes.**<br>Today. | "Five minutes today. Start now." |
| END | 42.4–45.0s | brand end card | **Speak Frankly**<br>Practise real English conversations | "Start speaking today." |

**CTA:** on-card button **"Start speaking today"**, held for the full 2.6s. The Google Play install button is supplied by the campaign.

## Production notes

- Every card and device still is a crop of a REAL screen capture from `com.speakfrankly` 1.5.3 (build 23) on a Galaxy A34. Nothing is mocked up or redrawn.
- Captures were taken with Do-Not-Disturb on, and the status bar, gesture bar and in-app ad slots are cropped out of every piece.
- Type sits inside the ratio's own column, clear of all edges, so platform-side cropping cannot cut it.
- No claim goes beyond what the paired element shows. See `creative-strategy.md` section 9 for the excluded-feature list.
- The reference this style is modelled on opens with illustrated characters and a learner-count badge. Neither is reproduced: Speak Frankly has no character artwork, and no learner count is verified.
