"""
Voiceover for the Speak Frankly video creatives.

Neural Indian-English TTS (edge-tts, en-IN-NeerjaNeural) — the accent the
primary market actually hears in Indian advertising. One line per scene, placed
at that scene's start; the rest of the scene stays quiet, which is how a real ad
mix breathes.

Lines are written short on purpose: the 15-second cut only gives each scene
~4.1s, so a line that needs 6s would have to be sped up until it sounds
panicked. If a line still overruns its scene, it is re-rendered slightly faster,
and the script warns if even that is not enough.

Run:  python build_voiceover.py            (all concepts)
      python build_voiceover.py 01 03      (only these)

This rewrites the audio track of the existing MP4s; the video stream is copied,
never re-encoded.
"""

from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import sys

import build_videos as bv
import build_music

HERE = os.path.dirname(os.path.abspath(__file__))
VID = os.path.join(HERE, "videos")
WORK = os.path.join(HERE, ".vo-build")

PY = sys.executable
VOICE = "en-IN-NeerjaNeural"
BASE_RATE = 4          # percent; a touch brisk reads as confident, not rushed
MAX_RATE = 26
LEAD_IN = 0.25         # let the scene land before the voice starts
OVERLAP = 0.45         # a line may run this far into the next scene

# The bed sits ~14 dB below its own peak, then the sidechain pulls it down
# further while the voice is speaking. Gaps between lines are only about a
# second, so the release has to recover inside that or the music never
# actually reappears and you have paid for silence.
MUSIC_GAIN = 0.20
DUCK = "threshold=0.03:ratio=5:attack=5:release=240:makeup=1"

# One line per scene, matched to that scene's on-screen caption.
VO = {
    "01": [
        "You understand English. But you freeze.",
        "Say it here first. Type or speak.",
        "Your tutor fixes one thing. Kindly.",
        "Practise the situations you will actually face.",
        "Then say it out loud. Nobody judges.",
        "Learn a new word every day.",
        "Streaks, XP, levels. It adds up.",
        "A few minutes a day. That is it.",
    ],
    "02": [
        "Meet an English tutor that talks back.",
        "Write the way you speak.",
        "It corrects one thing, and explains why.",
        "Stuck? Tap a reply and keep going.",
        "Or play out a whole scene.",
        "Interviews. Shopping. Ordering food.",
        "Then practise saying it out loud.",
        "And watch your English add up.",
    ],
    "03": [
        "Afraid of making mistakes in English?",
        "Here, make them. Write it wrong.",
        "Your tutor shows the right way.",
        "And the conversation keeps going.",
        "Try again. Nobody is counting.",
        "Say it out loud, safely.",
        "This is how confidence gets built.",
        "Five minutes today. Start now.",
    ],
    "04": [
        "AI conversations that correct you.",
        "Story mode. Role-plays that work offline.",
        "Speaking practice. Listen, then repeat.",
        "A new word every single day.",
        "Streaks, XP and levels.",
        "Reply suggestions for when you freeze.",
        "Save every new word, and review it.",
        "All in one app. Free to start.",
    ],
    "05": [
        "This is Speak Frankly.",
        "Choose the situation you need.",
        "Say what you can. Broken English welcome.",
        "Get one kind correction. Then carry on.",
        "Play the scene, one reply at a time.",
        "Practise the sounds until they feel normal.",
        "Pick up a word a day.",
        "Keep the streak alive.",
    ],
}

END_VO = "Start speaking today."


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"failed: {' '.join(str(c) for c in cmd[:10])}\n{r.stderr[-1200:]}")
    return r


def duration(path):
    out = run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
               "-of", "default=nw=1:nk=1", path]).stdout.strip()
    return float(out)


def say(text, rate):
    """Render one line, cached on (text, rate)."""
    key = hashlib.sha1(f"{text}|{rate}|{VOICE}".encode()).hexdigest()[:16]
    path = os.path.join(WORK, f"vo-{key}.mp3")
    if not os.path.exists(path):
        run([PY, "-m", "edge_tts", "--voice", VOICE,
             "--rate", f"{rate:+d}%", "--text", text, "--write-media", path])
    return path


def fitted_line(text, budget):
    """Render `text` so it fits `budget` seconds, speeding up only if needed."""
    rate = BASE_RATE
    path = say(text, rate)
    d = duration(path)
    while d > budget and rate < MAX_RATE:
        rate = min(MAX_RATE, rate + 7)
        path = say(text, rate)
        d = duration(path)
    if d > budget:
        print(f"    ! over by {d - budget:.2f}s at {rate:+d}%: \"{text}\"")
    return path, d


def build_track(cid, total, out_path):
    """One audio track: each line placed at its scene start, silence between."""
    beats = bv.CONCEPTS[cid]["beats"][: bv.DURATIONS[total]]
    body = total - bv.END_CARD
    per = body / len(beats)

    placed = []  # (path, start seconds)
    for i in range(len(beats)):
        start = i * per + LEAD_IN
        budget = per - LEAD_IN + OVERLAP
        p, _ = fitted_line(VO[cid][i], budget)
        placed.append((p, start))

    p, _ = fitted_line(END_VO, bv.END_CARD - 0.3)
    placed.append((p, body + 0.15))

    music = os.path.join(WORK, f"music-{total}.wav")
    if not os.path.exists(music):
        build_music.render(total, music, end_card=bv.END_CARD)

    cmd = ["ffmpeg", "-v", "error", "-y"]
    for p, _ in placed:
        cmd += ["-i", p]
    cmd += ["-i", music]
    music_idx = len(placed)

    fmt = "aformat=sample_fmts=fltp:sample_rates=44100:channel_layouts=stereo"
    parts, labels = [], []
    for i, (_, start) in enumerate(placed):
        parts.append(f"[{i}:a]{fmt},adelay={int(start*1000)}|{int(start*1000)}[a{i}]")
        labels.append(f"[a{i}]")
    parts.append(f"{''.join(labels)}amix=inputs={len(placed)}:duration=longest:"
                 f"normalize=0,alimiter=limit=0.95[vomix]")

    # The voice feeds the mix twice: once as itself, once as the key that ducks
    # the music. Without the sidechain a bed this warm still muddies consonants.
    parts.append("[vomix]asplit=2[vo][key]")
    parts.append(f"[{music_idx}:a]{fmt},volume={MUSIC_GAIN}[bed]")
    parts.append(f"[bed][key]sidechaincompress={DUCK}[ducked]")
    parts.append("[ducked][vo]amix=inputs=2:duration=first:normalize=0,"
                 "alimiter=limit=0.95,apad[out]")

    cmd += ["-filter_complex", ";".join(parts), "-map", "[out]",
            "-t", str(total), "-c:a", "aac", "-b:a", "160k", out_path]
    run(cmd)


def mux(video, track):
    tmp = video + ".tmp.mp4"
    run(["ffmpeg", "-v", "error", "-y", "-i", video, "-i", track,
         "-map", "0:v:0", "-map", "1:a:0", "-c:v", "copy", "-c:a", "aac",
         "-b:a", "128k", "-shortest", tmp])
    os.replace(tmp, video)


def main():
    only = [a for a in sys.argv[1:] if a in VO]
    todo = only or list(VO)
    os.makedirs(WORK, exist_ok=True)

    n = 0
    failed = []
    for cid in todo:
        print(f"concept {cid}")
        for total in bv.DURATIONS:
            track = os.path.join(WORK, f"track-{cid}-{total}.m4a")
            build_track(cid, total, track)
            for ratio in bv.RATIOS:
                v = os.path.join(VID, f"concept-{cid}", f"{total}s-{ratio}.mp4")
                if not os.path.exists(v):
                    continue
                try:
                    mux(v, track)
                    n += 1
                except RuntimeError as e:
                    # One unreadable file used to abort the whole pass, which is
                    # why later concepts kept ending up silent. Report and carry on.
                    failed.append(os.path.relpath(v, HERE))
            print(f"  {total}s track -> 3 cuts")
    print(f"{n} videos now carry voiceover ({VOICE}) over an original music bed")
    for f in failed:
        print(f"  ! could not mux (rebuild it): {f}")


if __name__ == "__main__":
    main()
