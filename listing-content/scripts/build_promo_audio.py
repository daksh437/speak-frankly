"""
Voiceover and music for the Play Store promo video.

Reuses the house sound already established for this project's ad creatives
(marketing/google-ads): neural Indian-English TTS, an original synthesised music
bed, and a sidechain that ducks the bed under the voice. Matching them means the
store listing and the ads sound like the same product.

Nothing here is licensed from anywhere. The voice is generated, and the bed is
synthesised from a chord progression in code, so there is nothing to clear and
no copyright claim waiting on the YouTube upload.

One line per scene, placed at that scene's start; the rest of the scene stays
quiet, which is how a real ad mix breathes. Lines are written short on purpose —
if one still overruns its scene it is re-rendered slightly faster, and this
warns if even that is not enough.

Reads:  video/scenes.json  (written by build-video.mjs)
        video/speak-frankly-promo-silent.mp4
Writes: video/speak-frankly-promo.mp4

Run:  python scripts/build_promo_audio.py
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
VIDEO = os.path.join(ROOT, "video")
WORK = os.path.join(VIDEO, ".audio")

# The music generator lives with the ad creatives; it is the same bed, so the
# listing and the ads share one sonic identity rather than inventing a second.
MUSIC_SRC = os.path.abspath(os.path.join(ROOT, "..", "marketing", "google-ads"))
sys.path.insert(0, MUSIC_SRC)
import build_music  # noqa: E402

PY = sys.executable
VOICE = "en-IN-NeerjaNeural"   # the accent the primary market actually hears
BASE_RATE = 4                  # percent; a touch brisk reads as confident
MAX_RATE = 26
LEAD_IN = 0.30                 # let the scene land before the voice starts
OVERLAP = 0.45                 # a line may run this far into the next scene

# The bed sits well below its own peak, then the sidechain pulls it down further
# while the voice speaks. Release has to recover inside the gaps between lines,
# or the music never actually reappears.
MUSIC_GAIN = 0.20
DUCK = "threshold=0.03:ratio=5:attack=5:release=240:makeup=1"

FMT = "aformat=sample_fmts=fltp:sample_rates=44100:channel_layouts=stereo"


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"failed: {' '.join(str(c) for c in cmd[:8])}\n{r.stderr[-1500:]}")
    return r


def ffbin(name):
    for p in (os.path.join(os.environ.get("LOCALAPPDATA", ""), "Microsoft", "WinGet", "Links", f"{name}.exe"),
              f"/usr/bin/{name}"):
        if p and os.path.exists(p):
            return p
    return name


FFMPEG, FFPROBE = ffbin("ffmpeg"), ffbin("ffprobe")


def duration(path):
    out = run([FFPROBE, "-v", "error", "-show_entries", "format=duration",
               "-of", "default=nw=1:nk=1", path]).stdout.strip()
    return float(out)


def say(text, rate):
    """Render one line. Cached on (text, rate, voice) so reruns are instant."""
    key = hashlib.sha1(f"{text}|{rate}|{VOICE}".encode()).hexdigest()[:16]
    path = os.path.join(WORK, f"vo-{key}.mp3")
    if not os.path.exists(path):
        run([PY, "-m", "edge_tts", "--voice", VOICE,
             "--rate", f"{rate:+d}%", "--text", text, "--write-media", path])
    return path


def fitted(text, budget):
    """Render `text` so it fits `budget` seconds, speeding up only if it must."""
    rate = BASE_RATE
    path = say(text, rate)
    d = duration(path)
    while d > budget and rate < MAX_RATE:
        rate = min(MAX_RATE, rate + 7)
        path = say(text, rate)
        d = duration(path)
    if d > budget:
        print(f"    ! over by {d - budget:.2f}s even at {rate:+d}%: \"{text}\"")
    return path, d, rate


def main():
    os.makedirs(WORK, exist_ok=True)
    silent = os.path.join(VIDEO, "speak-frankly-promo-silent.mp4")
    if not os.path.exists(silent):
        raise SystemExit("run `node scripts/build-video.mjs` first")

    cfg = json.load(open(os.path.join(VIDEO, "scenes.json"), encoding="utf-8"))
    total = cfg["total"]

    print(f"Voicing {len(cfg['scenes'])} scenes with {VOICE}\n")
    placed = []
    for s in cfg["scenes"]:
        budget = s["dur"] - LEAD_IN + OVERLAP
        path, d, rate = fitted(s["vo"], budget)
        placed.append((path, s["start"] + LEAD_IN))
        print(f"  {s['id']:<10} {d:4.1f}s / {budget:4.1f}s  {rate:+d}%   \"{s['vo'][:52]}\"")

    music = os.path.join(WORK, f"music-{total:.0f}.wav")
    if not os.path.exists(music):
        print(f"\nSynthesising {total:.0f}s music bed")
        build_music.render(total, music, end_card=3.5)

    cmd = [FFMPEG, "-v", "error", "-y"]
    for p, _ in placed:
        cmd += ["-i", p]
    cmd += ["-i", music]
    music_idx = len(placed)

    parts, labels = [], []
    for i, (_, start) in enumerate(placed):
        ms = int(start * 1000)
        parts.append(f"[{i}:a]{FMT},adelay={ms}|{ms}[a{i}]")
        labels.append(f"[a{i}]")
    parts.append(f"{''.join(labels)}amix=inputs={len(placed)}:duration=longest:"
                 f"normalize=0,alimiter=limit=0.95[vomix]")

    # The voice feeds the mix twice: once as itself, once as the key that ducks
    # the bed. Without the sidechain a bed this warm still muddies consonants.
    parts.append("[vomix]asplit=2[vo][key]")
    parts.append(f"[{music_idx}:a]{FMT},volume={MUSIC_GAIN}[bed]")
    parts.append(f"[bed][key]sidechaincompress={DUCK}[ducked]")
    parts.append("[ducked][vo]amix=inputs=2:duration=first:normalize=0,"
                 "alimiter=limit=0.95,apad[out]")

    track = os.path.join(WORK, "track.m4a")
    cmd += ["-filter_complex", ";".join(parts), "-map", "[out]",
            "-t", str(total), "-c:a", "aac", "-b:a", "192k", track]
    run(cmd)

    final = os.path.join(VIDEO, "speak-frankly-promo.mp4")
    run([FFMPEG, "-v", "error", "-y", "-i", silent, "-i", track,
         "-map", "0:v:0", "-map", "1:a:0", "-c:v", "copy", "-c:a", "aac",
         "-b:a", "192k", "-shortest", "-movflags", "+faststart", final])

    mb = os.path.getsize(final) / 1024 / 1024
    # Plain ASCII on purpose: the Windows console is cp1252 and raises on emoji.
    print(f"\n-> video/speak-frankly-promo.mp4  {duration(final):.1f}s  {mb:.1f} MB  (voice + music)")


if __name__ == "__main__":
    main()
