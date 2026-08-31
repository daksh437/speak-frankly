"""
Generate the edit script for every video deliverable.

Timings, on-screen text and voiceover are read from the SAME data the builders
use (build_videos.CONCEPTS / DURATIONS, build_voiceover.VO), so a script can
never drift out of sync with the file it describes.

Out: videos/scripts/concept-NN-<slug>.md
"""

from __future__ import annotations

import os

import build_videos as bv
import build_voiceover as vo

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "videos", "scripts")

# What each floating element actually is, and where it came from.
PIECE_NOTES = {
    "correction": "the amber correction card — \"I have worked as a graphic designer "
                  "for two years\" plus its reason — lifted from the Job Interview chat",
    "user_bubble": "the learner's own message, \"I working as a graphic designer since "
                   "two years\", mistakes intact",
    "reply_bubble": "the tutor's reply, \"That is great experience. What are your main "
                    "strengths as a designer?\"",
    "suggestions": "the \"Not sure what to say? Tap a reply\" strip with its two "
                   "suggestion chips",
    "stats_row": "the home screen's Streak / XP / Level row",
    "wotd": "the Word of the Day card (\"recommend\")",
    "talk_card": "the \"Talk about anything\" card from the home screen",
    "phrase": "the Shadowing Practice phrase card with its Listen button",
    "saved_word": "the Saved Words entry for \"recommend\", with phonetics and meaning",
    "session_xp": "the end-of-session card — \"Great session! +20 XP\"",
    "story_choices": "the \"Choose your reply\" options from a Story mode role-play",
    "phones": "two tilted device stills — a Story mode role-play beside the Story mode "
              "list",
}

MUSIC = (
    f"**Voiceover and music are already mixed into every delivered cut.** Voice: "
    f"neural Indian-English TTS (`{vo.VOICE}`), one line per scene at that scene's "
    "start. Music: an original instrumental generated in-repo (`build_music.py`) — "
    "I-V-vi-IV in C major at 96 BPM, lyric-free, resolving onto the tonic under the "
    "end card — so there is no third-party licence to clear. The bed is side-chained "
    "to the voice and drops ~12 dB while a line is speaking. Rebuild the audio with "
    "`build_voiceover.py`. For a human read, the Voiceover column below is the script."
)


def write_script(cid: str) -> str:
    spec = bv.CONCEPTS[cid]
    slug = spec["name"].lower().replace(" / ", "-").replace(" ", "-")
    path = os.path.join(OUT, f"concept-{cid}-{slug}.md")
    beats = spec["beats"]

    L = [f"# Video concept {cid} — {spec['name']}", "",
         "**Deliverables:** "
         + ", ".join(f"`{d}s-{r}.mp4`" for d in bv.DURATIONS for r in bv.RATIOS), "",
         f"**Hook (scene 1):** \"{beats[0]['head']}\" — {beats[0]['sub']}", "",
         "**Look:** floating-UI motion graphics on a lavender wash. Real interface "
         "elements are lifted out of the app — no phone bezel — and shown at a size "
         "that reads on a handset. Type arrives line by line with the operative word "
         "in violet under an amber rule. Cards drift continuously; nothing is static.",
         "",
         "**Framing per ratio**", "",
         "| Ratio | Canvas | Composition |", "|---|---|---|",
         "| 9:16 | 1080x1920 | Type top, floating element centred, chevrons low. Built "
         "for the format, not cropped from 16:9. |",
         "| 1:1 | 1080x1080 | Compact: type top, element centred, smaller device stills. |",
         "| 16:9 | 1920x1080 | Type in the left column, element floating right. |",
         "", MUSIC, ""]

    for total, nbeats in bv.DURATIONS.items():
        used = beats[:nbeats]
        body = total - bv.END_CARD
        per = body / len(used)
        L += [f"## {total}-second cut", "",
              f"{len(used)} scenes of {per:.1f}s + {bv.END_CARD}s end card.", "",
              "| # | Timestamp | Real UI shown | On-screen text | Voiceover |",
              "|---|---|---|---|---|"]
        for i, b in enumerate(used):
            st, en = i * per, (i + 1) * per
            L.append(f"| {i+1} | {st:.1f}–{en:.1f}s | {PIECE_NOTES[b['visual']]} "
                     f"| **{b['head']}**<br>{b['sub']} | \"{vo.VO[cid][i]}\" |")
        L.append(f"| END | {body:.1f}–{total}.0s | brand end card "
                 f"| **Speak Frankly**<br>Practise real English conversations "
                 f"| \"{vo.END_VO}\" |")
        L += ["", f"**CTA:** on-card button **\"{bv.END_CTA}\"**, held for the full "
                  f"{bv.END_CARD}s. The Google Play install button is supplied by the "
                  "campaign.", ""]

    L += ["## Production notes", "",
          "- Every card and device still is a crop of a REAL screen capture from "
          "`com.speakfrankly` 1.5.3 (build 23) on a Galaxy A34. Nothing is mocked up "
          "or redrawn.",
          "- Captures were taken with Do-Not-Disturb on, and the status bar, gesture "
          "bar and in-app ad slots are cropped out of every piece.",
          "- Type sits inside the ratio's own column, clear of all edges, so "
          "platform-side cropping cannot cut it.",
          "- No claim goes beyond what the paired element shows. See "
          "`creative-strategy.md` section 9 for the excluded-feature list.",
          "- The reference this style is modelled on opens with illustrated characters "
          "and a learner-count badge. Neither is reproduced: Speak Frankly has no "
          "character artwork, and no learner count is verified.", ""]

    os.makedirs(OUT, exist_ok=True)
    open(path, "w", encoding="utf-8").write("\n".join(L))
    return path


if __name__ == "__main__":
    for cid in bv.CONCEPTS:
        print(" ", os.path.relpath(write_script(cid), HERE))
