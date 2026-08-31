"""
Original music bed for the Speak Frankly video creatives.

WHY THIS IS SYNTHESISED RATHER THAN DOWNLOADED
A bed lifted from a free-music site is only as safe as its licence, and a
mis-licensed track on a paid campaign means a copyright claim against the ad
account. Everything here is generated from scratch — a chord progression, four
synth voices and a soft drum part written in code — so the recording is original
to this repo and there is nothing to clear.

The piece: I-V-vi-IV in C major at 96 BPM. Warm, mid-tempo, no lyrics, nothing
that fights a voiceover. It opens sparse, fills in, and resolves onto the tonic
under the end card.

Run:  python build_music.py            (writes a 45s demo to .music/demo.wav)
Use:  from build_music import render;  render(seconds, path)
"""

from __future__ import annotations

import os
import wave

import numpy as np

SR = 44100
BPM = 96
BEAT = 60.0 / BPM          # 0.625s
BAR = BEAT * 4             # 2.5s

# I - V - vi - IV, voiced so the top notes move by step rather than leaping.
PROGRESSION = [
    [48, 55, 60, 64, 67],   # C   C3 G3 C4 E4 G4
    [43, 50, 59, 62, 67],   # G   G2 D3 B3 D4 G4
    [45, 52, 60, 64, 69],   # Am  A2 E3 C4 E4 A4
    [41, 48, 57, 60, 65],   # F   F2 C3 A3 C4 F4
]
TONIC = PROGRESSION[0]


def hz(midi: float) -> float:
    return 440.0 * 2 ** ((midi - 69) / 12.0)


def env_exp(n: int, tau: float) -> np.ndarray:
    return np.exp(-np.arange(n) / (SR * tau))


def fade(sig: np.ndarray, attack: float, release: float) -> np.ndarray:
    n = len(sig)
    a = min(int(SR * attack), n // 2)
    r = min(int(SR * release), n // 2)
    w = np.ones(n)
    if a:
        w[:a] = np.linspace(0, 1, a) ** 2
    if r:
        w[-r:] = np.linspace(1, 0, r) ** 2
    return sig * w


def one_pole(sig: np.ndarray, cutoff: float) -> np.ndarray:
    """Cheap low-pass; takes the glassy edge off the synth voices."""
    a = np.exp(-2 * np.pi * cutoff / SR)
    out = np.empty_like(sig)
    acc = 0.0
    for i, s in enumerate(sig):
        acc = (1 - a) * s + a * acc
        out[i] = acc
    return out


def render(seconds: float, path: str, end_card: float = 2.6) -> str:
    """Write `seconds` of bed, resolving to the tonic under the last `end_card`."""
    total = int(SR * seconds)
    t = np.arange(total) / SR
    pad = np.zeros(total)
    arp = np.zeros(total)
    bass = np.zeros(total)
    perc = np.zeros(total)

    body = seconds - end_card
    n_bars = int(np.ceil(seconds / BAR))

    for b in range(n_bars):
        start = b * BAR
        i0 = int(start * SR)
        if i0 >= total:
            break
        # Everything from the end card onwards sits on the tonic, so the music
        # lands rather than stopping mid-phrase.
        chord = TONIC if start >= body - BAR else PROGRESSION[b % len(PROGRESSION)]

        # --- pad: three upper voices, slightly detuned, overlapping bars ------
        seg_n = min(int((BAR + 0.6) * SR), total - i0)
        st = np.arange(seg_n) / SR
        voice = np.zeros(seg_n)
        for m in chord[2:]:
            for cents in (-4, 0, 4):
                f = hz(m + cents / 100.0)
                voice += np.sin(2 * np.pi * f * st)
        voice /= max(1, len(chord[2:]) * 3)
        pad[i0:i0 + seg_n] += fade(voice, 0.45, 0.55) * 0.55

        # --- bass: root, one octave down -------------------------------------
        seg_n = min(int(BAR * SR), total - i0)
        st = np.arange(seg_n) / SR
        f = hz(chord[0] - 12)
        b_sig = np.sin(2 * np.pi * f * st) + 0.25 * np.sin(4 * np.pi * f * st)
        bass[i0:i0 + seg_n] += fade(b_sig, 0.04, 0.25) * 0.5

        # --- arpeggio: eighth notes over the chord tones ----------------------
        tones = [chord[2], chord[3], chord[4], chord[3]]
        for k in range(8):
            j0 = i0 + int(k * (BEAT / 2) * SR)
            if j0 >= total:
                break
            nn = min(int(0.45 * SR), total - j0)
            st = np.arange(nn) / SR
            f = hz(tones[k % len(tones)] + (12 if k % 4 == 2 else 0))
            note = (np.sin(2 * np.pi * f * st) + 0.35 * np.sin(4 * np.pi * f * st))
            arp[j0:j0 + nn] += note * env_exp(nn, 0.16) * 0.30

        # --- soft kick on 1 and 3, quiet hat on the off-beats -----------------
        for beat in (0, 2):
            j0 = i0 + int(beat * BEAT * SR)
            if j0 >= total:
                break
            nn = min(int(0.22 * SR), total - j0)
            st = np.arange(nn) / SR
            sweep = 45 + 70 * np.exp(-st / 0.035)
            perc[j0:j0 + nn] += np.sin(2 * np.pi * sweep * st) * env_exp(nn, 0.09) * 0.55
        rng = np.random.default_rng(1234 + b)
        for k in range(1, 8, 2):
            j0 = i0 + int(k * (BEAT / 2) * SR)
            if j0 >= total:
                break
            nn = min(int(0.05 * SR), total - j0)
            noise = rng.standard_normal(nn)
            noise = np.diff(noise, prepend=0.0)          # crude high-pass
            # ...then tamed again: raw noise reads as hiss on phone speakers and
            # drags the whole bed bright, which is the opposite of what should
            # sit under a voice.
            noise = one_pole(noise, 6500)
            perc[j0:j0 + nn] += noise * env_exp(nn, 0.010) * 0.16

    # --- arrangement: start sparse, fill in, thin out for the end card -------
    def ramp(at, dur=0.6, up=True):
        r = np.clip((t - at) / dur, 0, 1)
        return r if up else 1 - r

    arp_gain = ramp(BAR) * ramp(body - 0.4, 0.6, up=False)
    perc_gain = ramp(BAR * 2) * ramp(body - 0.8, 0.8, up=False)
    swell = 1.0 + 0.25 * np.clip((t - (body - 1.2)) / 1.2, 0, 1)

    # Voiced for a phone speaker, not a studio monitor. Most of these ads play
    # on a handset that cannot reproduce anything below ~300 Hz, so weight the
    # arpeggio and pad (which live in the mids) over the sub-heavy bass —
    # otherwise most of the bed's energy is spent on frequencies nobody hears.
    mix = (one_pole(pad, 3400) * 0.46 * swell
           + one_pole(arp, 5200) * 0.52 * arp_gain
           + one_pole(bass, 900) * 0.24
           + perc * 0.34 * perc_gain)

    mix = fade(mix, 0.35, 0.5)
    peak = float(np.max(np.abs(mix))) or 1.0
    mix = mix / peak * 0.72

    # Gentle stereo width: the pad leans a few milliseconds apart per side.
    d = int(0.008 * SR)
    left = mix.copy()
    right = np.concatenate([np.zeros(d), mix[:-d]]) if d else mix.copy()
    stereo = np.stack([left, right], axis=1)

    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    data = np.clip(stereo, -1, 1)
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((data * 32767).astype("<i2").tobytes())
    return path


if __name__ == "__main__":
    p = render(45.0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                  ".music", "demo.wav"))
    print("wrote", p)
