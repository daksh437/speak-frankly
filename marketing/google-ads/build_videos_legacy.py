"""
Google Ads video creative builder for Speak Frankly.

All product footage is REAL screen capture from the production app (1.5.3 /
build 23) on a physical Galaxy A34 — see source-recordings/. Nothing is mocked
up or re-drawn. The synthetic pixels are the scrims, the type, the lifted card
and the end card.

HOW THIS IS CUT, AND WHY
The first version of this file put a small phone in the middle of a purple
background and changed the caption every four seconds. That reads as a slide
deck. App install creatives that actually work look different:

  * the interface fills the frame — on 9:16 the recording runs full-bleed at
    100% width, because the product IS the creative;
  * cuts land every ~2 seconds, not every 4-5. Each message gets two shots: a
    wide one and a punch-in on the thing being talked about;
  * the punch-in is a real 1.25x framing move onto the element, not a zoom on
    the whole screen;
  * on the correction beat the card is LIFTED out of the interface — cropped
    from the same screenshot, scaled up, dropped over a dimmed screen — which
    is the one move that makes a UI ad feel designed rather than recorded;
  * type is large, bottom-anchored over a scrim, with the operative word in
    amber;
  * hard cuts, not cross-fades. Cross-fades read as "corporate", and they also
    smear the two seconds you are actually paying for.

Pipeline
  1. screen_track(): every shot trimmed, framed and hard-cut into one track at
     the phone's native 1080x2340.
  2. compose(): per ratio — full-bleed crop (9:16) or a large device (1:1,
     16:9), then scrims, type, lifted card, progress bar, end card.

Output: videos/concept-NN/{15,30,45}s-{16x9,9x16,1x1}.mp4
Run:    python build_videos.py [01 02 ...]
"""

from __future__ import annotations

import os
import subprocess
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
REC = os.path.join(HERE, "source-recordings")
SRC = os.path.join(HERE, "source-screens")
OUT = os.path.join(HERE, "videos")
WORK = os.path.join(HERE, ".video-build")

FONT_DIR = r"D:/new/New folder/src/flutter/bin/cache/artifacts/material_fonts"
F_BLACK = os.path.join(FONT_DIR, "roboto-black.ttf")
F_BOLD = os.path.join(FONT_DIR, "roboto-bold.ttf")
F_REG = os.path.join(FONT_DIR, "roboto-regular.ttf")
ICON = os.path.join(REPO, "app", "assets", "icon_512.png")

VIOLET = (108, 92, 231)
VIOLET_DEEP = (74, 60, 180)
VIOLET_LIGHT = (139, 124, 240)
AMBER = (245, 158, 11)
WHITE = (255, 255, 255)
SUB = (223, 218, 250)
INK = (14, 11, 24)

APP_NAME = "Speak Frankly"
END_CTA = "Start speaking today"

FPS = 30
END_CARD = 2.4
SRC_W, SRC_H = 1080, 2340

# 9:16 runs the interface full-bleed. 1:1 and 16:9 keep a device, but a big one.
RATIOS = {
    "9x16": dict(size=(1080, 1920), mode="bleed", crop_y=250,
                 cap=76, sub=36, pad=76),
    "1x1": dict(size=(1080, 1080), mode="device", inner=(384, 832), at=(632, 124),
                cap=52, sub=26, pad=72, col=(72, 492)),
    "16x9": dict(size=(1920, 1080), mode="device", inner=(452, 979), at=(1330, 50),
                 cap=70, sub=34, pad=112, col=(112, 1070)),
}


def font(p, s):
    return ImageFont.truetype(p, s)


def wrap(draw, text, fnt, max_w):
    lines = []
    for para in text.split("\n"):
        cur = ""
        for w in para.split():
            t = f"{cur} {w}".strip()
            if draw.textlength(t, font=fnt) <= max_w or not cur:
                cur = t
            else:
                lines.append(cur)
                cur = w
        lines.append(cur)
    return lines


def gradient(size):
    w, h = size
    n = int((w ** 2 + h ** 2) ** 0.5) + 80
    ramp = Image.new("L", (1, n))
    px = ramp.load()
    for i in range(n):
        px[0, i] = int(255 * i / (n - 1))
    ramp = ramp.resize((n, n)).rotate(-32, resample=Image.BICUBIC)
    big = Image.composite(Image.new("RGB", (n, n), VIOLET_DEEP),
                          Image.new("RGB", (n, n), VIOLET_LIGHT), ramp)
    l, t = (n - w) // 2, (n - h) // 2
    return big.crop((l, t, l + w, t + h))


def rounded_mask(size, r):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], r, fill=255)
    return m


def logo(size):
    ic = Image.open(ICON).convert("RGBA").resize((size, size), Image.LANCZOS)
    ic.putalpha(rounded_mask((size, size), int(size * 0.26)))
    return ic


def glow(canvas, cx, cy, radius, colour, strength=70):
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse(
        [cx - radius, cy - radius, cx + radius, cy + radius], fill=colour + (strength,))
    return Image.alpha_composite(canvas, layer.filter(ImageFilter.GaussianBlur(radius * 0.55)))


def crop_to_ink(canvas, path, pad=8):
    box = canvas.getbbox()
    if not box:
        canvas.save(path)
        return 0, 0
    W, H = canvas.size
    box = (max(0, box[0] - pad), max(0, box[1] - pad),
           min(W, box[2] + pad), min(H, box[3] + pad))
    canvas.crop(box).save(path)
    return box[0], box[1]


# ---- static plates ---------------------------------------------------------
def scrim_png(ratio, path):
    """Top and bottom scrims. Type sits over a live interface that is mostly
    white, so these have to be genuinely dark — a polite 40% wash is why the
    first pass was unreadable."""
    cfg = RATIOS[ratio]
    W, H = cfg["size"]
    col = Image.new("L", (1, H), 0)
    px = col.load()
    top_h = int(H * 0.26)
    bot_start = int(H * (0.46 if cfg["mode"] == "bleed" else 0.62))
    for y in range(H):
        a = 0
        if y < top_h:
            a = int(242 * (1 - y / top_h) ** 1.25)
        if y >= bot_start:
            k = (y - bot_start) / max(1, H - bot_start)
            a = max(a, int(248 * k ** 1.15))
        px[0, y] = a
    alpha = col.resize((W, H))
    canvas = Image.new("RGBA", (W, H), INK + (0,))
    canvas.putalpha(alpha)
    canvas.save(path)
    return 0, 0


def back_phone(screen, height, tilt=-7, dim=0.72):
    """A second, smaller device holding a still of another screen.

    16:9 with a portrait phone in it is mostly empty by construction. One real
    product ad answer is a second device behind the first — it fills the frame,
    adds depth, and still shows nothing but the real app.
    """
    im = Image.open(os.path.join(SRC, screen)).convert("RGB").crop((0, 92, SRC_W, 2292))
    w = int(im.width * height / im.height)
    im = im.resize((w, height), Image.LANCZOS)
    im = Image.eval(im, lambda v: int(v * dim))

    b = 12
    frame = Image.new("RGBA", (w + b * 2, height + b * 2), (18, 14, 30, 255))
    frame.paste(im, (b, b))
    frame.putalpha(rounded_mask(frame.size, 40))
    return frame.rotate(tilt, expand=True, resample=Image.BICUBIC)


def device_bg(ratio, path):
    """Brand backdrop with the device bezel, for the non-bleed ratios."""
    cfg = RATIOS[ratio]
    W, H = cfg["size"]
    canvas = gradient((W, H)).convert("RGBA")
    canvas = glow(canvas, int(W * 0.10), int(H * 0.08), int(min(W, H) * 0.5), VIOLET_LIGHT, 58)
    canvas = glow(canvas, int(W * 0.95), int(H * 0.95), int(min(W, H) * 0.4), (54, 40, 146), 76)

    iw, ih = cfg["inner"]
    x, y = cfg["at"]

    back = back_phone("01-home-top.png", int(ih * 0.82))
    bx, by = x + int(iw * 0.86), y + int(ih * 0.10)
    bsh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    bsh.paste(back, (bx, by), back)
    canvas = Image.alpha_composite(
        canvas, bsh.filter(ImageFilter.GaussianBlur(1)))

    b = 14
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        [x - b, y - b + 26, x + iw + b, y + ih + b + 26], 46, fill=(14, 9, 40, 165))
    canvas = Image.alpha_composite(canvas, sh.filter(ImageFilter.GaussianBlur(38)))
    ImageDraw.Draw(canvas).rounded_rectangle(
        [x - b, y - b, x + iw + b, y + ih + b], 46, fill=(20, 16, 32))
    canvas.convert("RGB").save(path)
    return 0, 0


def brand_row(ratio, path):
    cfg = RATIOS[ratio]
    W, H = cfg["size"]
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(canvas)
    s = 54 if W <= 1080 else 58
    ic = logo(s)
    x = cfg["col"][0] if cfg["mode"] == "device" else cfg["pad"]
    y = int(H * 0.052)
    canvas.paste(ic, (x, y), ic)
    d.text((x + s + 16, y + s * 0.22), APP_NAME, font=font(F_BOLD, int(s * 0.52)), fill=WHITE)
    return crop_to_ink(canvas, path)


def cta_chip(ratio, path):
    """The call to action, held for the whole cut on the device ratios."""
    cfg = RATIOS[ratio]
    W, H = cfg["size"]
    x = cfg["col"][0]
    f = font(F_BOLD, int(cfg["cap"] * 0.46))
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(canvas)
    tw = d.textlength(END_CTA, font=f)
    pad_x, pad_y = 42, 26
    y = int(H * 0.74)
    d.rounded_rectangle([x, y, x + tw + pad_x * 2, y + f.size + pad_y * 2],
                        (f.size + pad_y * 2) / 2, fill=WHITE)
    d.text((x + pad_x, y + pad_y - f.size * 0.08), END_CTA, font=f, fill=VIOLET)
    return crop_to_ink(canvas, path)


def caption_png(ratio, head, sub, key, path):
    """Big bottom-anchored type; the operative word carries the amber."""
    cfg = RATIOS[ratio]
    W, H = cfg["size"]
    pad, col = (cfg["pad"], W - cfg["pad"] * 2)
    if cfg["mode"] == "device":
        pad, col = cfg["col"]
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(canvas)

    fh = font(F_BLACK, cfg["cap"])
    fs = font(F_REG, cfg["sub"])
    head_lines = wrap(d, head, fh, col)
    sub_lines = wrap(d, sub, fs, col) if sub else []

    lh, ls = int(fh.size * 1.06), int(fs.size * 1.34)
    block = len(head_lines) * lh + (18 + len(sub_lines) * ls if sub_lines else 0)
    y = (H - int(H * 0.15) - block) if cfg["mode"] == "bleed" else int((H - block) / 2)

    if cfg["mode"] == "bleed":
        widest = max([d.textlength(l, font=fh) for l in head_lines]
                     + [d.textlength(l, font=fs) for l in sub_lines] or [0])
        plate = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(plate).rounded_rectangle(
            [pad - 26, y - 26, min(W - pad + 26, pad + widest + 26), y + block + 22],
            26, fill=INK + (168,))
        canvas = Image.alpha_composite(canvas, plate.filter(ImageFilter.GaussianBlur(2)))
        d = ImageDraw.Draw(canvas)

    for line in head_lines:
        x = pad
        # Draw word by word so the keyword can take the accent colour.
        for w in line.split():
            bare = w.strip(".,!?\"'")
            fill = AMBER if key and bare.lower() == key.lower() else WHITE
            d.text((x, y), w + " ", font=fh, fill=fill)
            x += d.textlength(w + " ", font=fh)
        y += lh
    if sub_lines:
        y += 18
        for line in sub_lines:
            d.text((pad, y), line, font=fs, fill=SUB)
            y += ls
    return crop_to_ink(canvas, path)


def lifted_card_png(rect, path, width=980):
    """The correction card, lifted out of the screenshot and enlarged.

    Cropped from the very screenshot the footage comes from, so it is the same
    pixels the learner sees — just presented at a size an ad viewer can read on
    a phone held at arm's length.
    """
    im = Image.open(os.path.join(SRC, "09b-job-interview-correction.png")).convert("RGB")
    card = im.crop(rect)
    h = int(card.height * width / card.width)
    card = card.resize((width, h), Image.LANCZOS)

    pad = 60
    canvas = Image.new("RGBA", (width + pad * 2, h + pad * 2), (0, 0, 0, 0))
    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        [pad, pad + 16, pad + width, pad + h + 16], 28, fill=(0, 0, 0, 190))
    canvas = Image.alpha_composite(canvas, sh.filter(ImageFilter.GaussianBlur(30)))

    rc = card.convert("RGBA")
    rc.putalpha(rounded_mask((width, h), 28))
    canvas.paste(rc, (pad, pad), rc)
    ImageDraw.Draw(canvas).rounded_rectangle(
        [pad, pad, pad + width, pad + h], 28, outline=AMBER + (255,), width=6)
    canvas.save(path)
    return canvas.size


def endcard_pngs(ratio, bg_path, cta_path):
    cfg = RATIOS[ratio]
    W, H = cfg["size"]
    canvas = gradient((W, H)).convert("RGBA")
    canvas = glow(canvas, W // 2, int(H * 0.36), int(min(W, H) * 0.5), VIOLET_LIGHT, 74)
    d = ImageDraw.Draw(canvas)

    ic = logo(int(min(W, H) * 0.18))
    f_name = font(F_BLACK, int(min(W, H) * 0.082))
    f_tag = font(F_REG, int(min(W, H) * 0.036))
    f_cta = font(F_BOLD, int(min(W, H) * 0.042))

    tag = "Practise real English conversations"
    g1, g2, g3 = 34, 18, 48
    btn_h = f_cta.size + 46
    block = ic.height + g1 + f_name.size * 1.2 + g2 + f_tag.size * 1.2 + g3 + btn_h
    y = (H - block) / 2

    canvas.paste(ic, ((W - ic.width) // 2, int(y)), ic)
    y += ic.height + g1
    d.text(((W - d.textlength(APP_NAME, font=f_name)) / 2, y), APP_NAME, font=f_name, fill=WHITE)
    y += f_name.size * 1.2 + g2
    d.text(((W - d.textlength(tag, font=f_tag)) / 2, y), tag, font=f_tag, fill=SUB)
    y += f_tag.size * 1.2 + g3
    canvas.convert("RGB").save(bg_path)

    btn = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    db = ImageDraw.Draw(btn)
    bw = db.textlength(END_CTA, font=f_cta) + 82
    bx = (W - bw) / 2
    db.rounded_rectangle([bx, y, bx + bw, y + btn_h], btn_h / 2, fill=WHITE)
    db.text((bx + 41, y + 21), END_CTA, font=f_cta, fill=VIOLET)
    return crop_to_ink(btn, cta_path)


# ---- source material -------------------------------------------------------
A = "rec-chat-correction.mp4"
B = "rec-home-browse.mp4"
C = "rec-story-mode.mp4"
D = "rec-speak-progress.mp4"

CORRECTION_RECT = (140, 1045, 1020, 1415)
CORRECTION_MID = ((140 + 1020) // 2, (1045 + 1415) // 2)

# Where to punch in for each beat: a point in the source frame worth filling
# the screen with.
CHAT_MID = (540, 1250)
LOWER = (540, 1750)
UPPER = (540, 700)

# (clip, start, headline, sub, keyword, punch point, lift-the-card?)
CONCEPTS = {
    "01": dict(name="Problem / solution", beats=[
        (A, 21.0, "You understand English.", "The words just stop coming out.", "stop", UPPER, False),
        (A, 12.2, "Say it here first.", "Type it or speak it. Nobody is watching.", "here", LOWER, False),
        (A, 15.0, "It fixes your mistake.", "One clear correction, then it keeps talking.", "fixes", CORRECTION_MID, True),
        (C, 6.5, "Real situations.", "Interviews, shopping, the doctor, travel.", "Real", CHAT_MID, False),
        (D, 2.5, "Then say it out loud.", "Listen to a phrase and repeat it.", "loud", CHAT_MID, False),
        (B, 3.0, "A new word every day.", "Learn it, save it, review it.", "word", UPPER, False),
        (D, 16.5, "Watch it add up.", "Streaks, XP and levels.", "up", CHAT_MID, False),
        (A, 18.5, "A few minutes a day.", "That is the whole trick.", "minutes", LOWER, False),
    ]),
    "02": dict(name="AI English tutor", beats=[
        (A, 21.0, "An AI tutor that talks back.", "Any time you want. No appointment.", "talks", UPPER, False),
        (A, 12.2, "Write like you speak.", "Mistakes and all. That is the point.", "Mistakes", LOWER, False),
        (A, 15.2, "Corrected, not judged.", "The fix, the reason, and straight on.", "judged", CORRECTION_MID, True),
        (A, 19.6, "Never stuck for words.", "Tap a suggested reply and keep going.", "stuck", LOWER, False),
        (C, 8.0, "Play out a whole scene.", "Guided role-plays that work offline.", "scene", CHAT_MID, False),
        (B, 9.0, "Pick your situation.", "Job interview, shopping, ordering food.", "situation", CHAT_MID, False),
        (D, 4.0, "Practise speaking too.", "Listen, then shadow the phrase.", "speaking", CHAT_MID, False),
        (D, 17.2, "See yourself improve.", "Conversations, vocabulary, consistency.", "improve", CHAT_MID, False),
    ]),
    "03": dict(name="Fear of mistakes", beats=[
        (A, 21.0, "Afraid of making mistakes?", "Nobody is listening. Nobody is judging.", "mistakes", UPPER, False),
        (A, 12.2, "Good. Make them here.", "Write it wrong. On purpose.", "wrong", LOWER, False),
        (A, 15.5, "This is the right way.", "One line. No lecture.", "right", CORRECTION_MID, True),
        (A, 19.2, "And the chat keeps going.", "It never stops to grade you.", "keeps", LOWER, False),
        (C, 10.0, "Try again. And again.", "As many times as you need.", "again", CHAT_MID, False),
        (D, 3.0, "Then say it out loud.", "Where it is safe to get it wrong.", "safe", CHAT_MID, False),
        (D, 18.0, "Confidence, not perfection.", "That is what daily practice builds.", "Confidence", CHAT_MID, False),
        (B, 5.0, "Start with five minutes.", "Today.", "five", UPPER, False),
    ]),
    "04": dict(name="Feature tour", beats=[
        (A, 15.2, "AI conversations", "That correct you as you go.", "conversations", CORRECTION_MID, True),
        (C, 7.0, "Story mode", "Guided role-plays. Works offline.", "Story", CHAT_MID, False),
        (D, 3.0, "Speaking practice", "Listen, then repeat out loud.", "Speaking", CHAT_MID, False),
        (B, 2.5, "Word of the day", "One new word, every single day.", "Word", UPPER, False),
        (D, 17.2, "Progress you can see", "Streaks, XP, levels and badges.", "Progress", CHAT_MID, False),
        (B, 10.0, "Real-life scenarios", "Interviews, shopping, travel, the doctor.", "Real-life", CHAT_MID, False),
        (A, 20.0, "Reply suggestions", "For the moments you freeze.", "freeze", LOWER, False),
        (C, 14.0, "All in one app.", "Free to start.", "Free", CHAT_MID, False),
    ]),
    "05": dict(name="Complete experience", beats=[
        (B, 1.5, "This is Speak Frankly.", "English practice that talks back.", "back", UPPER, False),
        (B, 8.0, "Choose a situation.", "The ones you will really be in.", "situation", CHAT_MID, False),
        (A, 5.0, "Say what you can.", "Broken English is welcome here.", "Broken", LOWER, False),
        (A, 15.6, "Get one kind correction.", "Then carry on with the conversation.", "kind", CORRECTION_MID, True),
        (C, 9.0, "Play the whole scene.", "Pick your reply, see where it goes.", "scene", CHAT_MID, False),
        (D, 3.5, "Practise the sounds.", "Listen and shadow the phrase.", "sounds", CHAT_MID, False),
        (B, 3.5, "Learn a word a day.", "And review it before you forget.", "word", UPPER, False),
        (D, 17.5, "Keep the streak alive.", "A few minutes daily is the trick.", "streak", CHAT_MID, False),
    ]),
}

DURATIONS = {15: 3, 30: 6, 45: 8}


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"ffmpeg failed:\n{' '.join(str(c) for c in cmd[:14])}\n{r.stderr[-1600:]}")
    return r


_dur: dict[str, float] = {}


def clip_len(name):
    if name not in _dur:
        _dur[name] = float(run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                "-of", "default=nw=1:nk=1", os.path.join(REC, name)]).stdout.strip())
    return _dur[name]


# A punch-in two seconds after its wide shot often lands on an open keyboard,
# which is a poor close-up. These name a better moment in the same recording.
PUNCH_AT = {
    ("01", 0): (16.6,), ("01", 1): (13.4,),
    ("02", 0): (16.6,), ("02", 1): (13.4,),
    ("03", 0): (16.6,), ("03", 1): (13.4,),
    ("05", 2): (16.6,),
}


def shot_filter(kind, focus, length):
    """wide = a slow push. punch = a 1.25x framing move onto `focus`."""
    frames = max(1, int(length * FPS))
    if kind == "wide":
        z = f"min(1.01+0.045*on/{frames},1.055)"
        x, y = "iw/2-(iw/zoom/2)", "ih/2-(ih/zoom/2)"
    else:
        fx, fy = focus
        z = f"min(1.16+0.10*on/{frames},1.26)"
        x, y = f"{fx}-(iw/zoom/2)", f"{fy}-(ih/zoom/2)"
    return (f"zoompan=z='{z}':x='{x}':y='{y}':d=1:s={SRC_W}x{SRC_H}:fps={FPS}")


def screen_track(concept, total, beats):
    """Two shots per beat — wide, then punch — hard cut together."""
    body = total - END_CARD
    beat = body / len(beats)
    shot = beat / 2
    os.makedirs(WORK, exist_ok=True)

    parts = []
    for i, (clip, start, _, _, _, focus, _) in enumerate(beats):
        for j, kind in enumerate(("wide", "punch")):
            raw = start + j * shot
            if j == 1 and (concept, i) in PUNCH_AT:
                raw = PUNCH_AT[(concept, i)][0]
            st = min(raw, max(0.0, clip_len(clip) - shot - 0.05))
            p = os.path.join(WORK, f"{concept}-{total}-{i}{j}.mp4")
            run(["ffmpeg", "-v", "error", "-y", "-ss", f"{st:.2f}", "-t", f"{shot:.2f}",
                 "-i", os.path.join(REC, clip),
                 "-vf", f"fps={FPS},scale={SRC_W}:{SRC_H},setsar=1,"
                        f"{shot_filter(kind, focus, shot)}",
                 "-an", "-c:v", "libx264", "-preset", "veryfast", "-crf", "18", p])
            parts.append(p)

    lst = os.path.join(WORK, f"{concept}-{total}.txt")
    with open(lst, "w") as f:
        for p in parts:
            f.write(f"file '{os.path.basename(p)}'\n")
    track = os.path.join(WORK, f"track-{concept}-{total}.mp4")
    run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", lst,
         "-c", "copy", track])
    return track, beat


def compose(concept, total, ratio, track, beat, beats, out_path):
    cfg = RATIOS[ratio]
    W, H = cfg["size"]
    body = total - END_CARD

    scrim = os.path.join(WORK, f"scrim-{ratio}.png")
    brand = os.path.join(WORK, f"brand-{ratio}.png")
    endbg = os.path.join(WORK, f"endbg-{ratio}.png")
    endcta = os.path.join(WORK, f"endcta-{ratio}.png")
    if not os.path.exists(scrim):
        scrim_png(ratio, scrim)
    brand_at = brand_row(ratio, brand)
    cta_at = endcard_pngs(ratio, endbg, endcta)

    chip = None
    if cfg["mode"] == "device":
        cp = os.path.join(WORK, f"cta-{ratio}.png")
        chip = (cp, cta_chip(ratio, cp))

    caps = []
    for i, (_, _, head, sub, key, _, _) in enumerate(beats):
        p = os.path.join(WORK, f"cap-{concept}-{total}-{ratio}-{i}.png")
        caps.append((p, caption_png(ratio, head, sub, key, p)))

    lift_beat = next((i for i, b in enumerate(beats) if b[6]), None)
    card = None
    if lift_beat is not None:
        p = os.path.join(WORK, f"card-{ratio}.png")
        cw = int(W * 0.86) if cfg["mode"] == "bleed" else int(cfg["col"][1] * 1.02)
        card = (p, lifted_card_png(CORRECTION_RECT, p, width=cw))

    inputs = ["-loop", "1", "-i", scrim] if cfg["mode"] == "bleed" else \
             ["-loop", "1", "-i", os.path.join(WORK, f"devbg-{ratio}.png")]
    if cfg["mode"] == "device" and not os.path.exists(os.path.join(WORK, f"devbg-{ratio}.png")):
        device_bg(ratio, os.path.join(WORK, f"devbg-{ratio}.png"))

    cmd = ["ffmpeg", "-v", "error", "-y"] + inputs + ["-i", track]
    idx = 2
    if cfg["mode"] == "bleed":
        pass
    else:
        cmd += ["-loop", "1", "-i", scrim]
        scrim_idx = idx
        idx += 1
    cmd += ["-loop", "1", "-i", brand]
    brand_idx = idx
    idx += 1
    cap_idx = []
    for p, _ in caps:
        cmd += ["-loop", "1", "-i", p]
        cap_idx.append(idx)
        idx += 1
    chip_idx = None
    if chip:
        cmd += ["-loop", "1", "-i", chip[0]]
        chip_idx = idx
        idx += 1
    card_idx = None
    if card:
        cmd += ["-loop", "1", "-i", card[0]]
        card_idx = idx
        idx += 1
    endbg_idx, endcta_idx = idx, idx + 1
    cmd += ["-loop", "1", "-i", endbg, "-loop", "1", "-i", endcta,
            "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=44100"]
    audio_idx = idx + 2

    fc = []
    if cfg["mode"] == "bleed":
        # Full-bleed: the interface IS the frame.
        fc.append(f"[1:v]scale={W}:-1,crop={W}:{H}:0:{cfg['crop_y']},setsar=1[scr]")
        fc.append(f"[scr][0:v]overlay=0:0[v0]")
    else:
        iw, ih = cfg["inner"]
        ax, ay = cfg["at"]
        fc.append(f"[1:v]scale={iw}:{ih},setsar=1[scr]")
        fc.append(f"[0:v][scr]overlay=x='{ax}':y='{ay}':shortest=0[vd]")
        fc.append(f"[vd][{scrim_idx}:v]overlay=0:0[v0]")
    prev = "v0"

    bx, by = brand_at
    fc.append(f"[{brand_idx}:v]format=rgba,fade=t=in:st=0:d=0.4:alpha=1,"
              f"fade=t=out:st={body-0.3:.2f}:d=0.3:alpha=1[br]")
    fc.append(f"[{prev}][br]overlay={bx}:{by}:enable='lt(t,{body:.2f})'[v1]")
    prev = "v1"

    for i, (_, (cx, cy)) in enumerate(caps):
        st, en = i * beat, min((i + 1) * beat, body)
        fc.append(f"[{cap_idx[i]}:v]format=rgba,"
                  f"fade=t=in:st={st:.2f}:d=0.22:alpha=1,"
                  f"fade=t=out:st={max(st, en-0.22):.2f}:d=0.22:alpha=1[c{i}]")
        fc.append(f"[{prev}][c{i}]overlay=x={cx}:"
                  f"y='{cy}+40*(1-min(1,max(0,(t-{st:.2f}))/0.30))':"
                  f"enable='between(t,{st:.2f},{en:.2f})'[vc{i}]")
        prev = f"vc{i}"

    if card:
        # The lift lands on the punch half of that beat.
        st = lift_beat * beat + beat / 2
        en = min((lift_beat + 1) * beat, body)
        cw, ch = card[1]
        if cfg["mode"] == "bleed":
            dim = f"x=0:y=0:w={W}:h={H}"
        else:
            dx, dy = cfg["at"]
            diw, dih = cfg["inner"]
            dim = f"x={dx}:y={dy}:w={diw}:h={dih}"
        fc.append(f"[{prev}]drawbox={dim}:color=black@0.45:t=fill:"
                  f"enable='between(t,{st:.2f},{en:.2f})'[vdim]")
        fc.append(f"[{card_idx}:v]format=rgba,"
                  f"scale=w='{cw}*(0.88+0.12*min(1,max(0,(t-{st:.2f}))/0.30))':h=-1:eval=frame,"
                  f"fade=t=in:st={st:.2f}:d=0.22:alpha=1,"
                  f"fade=t=out:st={max(st, en-0.22):.2f}:d=0.22:alpha=1[cd]")
        if cfg["mode"] == "bleed":
            ox, oy = "(W-w)/2", f"(H-h)/2-{int(H*0.06)}"
        else:
            ox, oy = f"{cfg['col'][0] - 30}", "(H-h)/2"
        fc.append(f"[vdim][cd]overlay=x='{ox}':y='{oy}':"
                  f"enable='between(t,{st:.2f},{en:.2f})'[vl]")
        prev = "vl"

    if chip:
        cx2, cy2 = chip[1]
        fc.append(f"[{chip_idx}:v]format=rgba,fade=t=in:st=0.5:d=0.35:alpha=1,"
                  f"fade=t=out:st={body-0.3:.2f}:d=0.3:alpha=1[ch]")
        fc.append(f"[{prev}][ch]overlay=x={cx2}:"
                  f"y='{cy2}+24*(1-min(1,max(0,(t-0.5))/0.35))':"
                  f"enable='between(t,0.5,{body:.2f})'[vch]")
        prev = "vch"

    bar_h = max(6, H // 190)
    fc.append(f"[{prev}]drawbox=x=0:y={H-bar_h}:w='iw*min(t/{total},1)':h={bar_h}:"
              f"color=0x{AMBER[0]:02X}{AMBER[1]:02X}{AMBER[2]:02X}@0.95:t=fill[vb]")
    prev = "vb"

    fc.append(f"[{endbg_idx}:v]format=rgba,fade=t=in:st={body:.2f}:d=0.3:alpha=1[eb]")
    fc.append(f"[{prev}][eb]overlay=0:0:enable='gte(t,{body:.2f})'[ve]")
    ex, ey = cta_at
    fc.append(f"[{endcta_idx}:v]format=rgba,fade=t=in:st={body+0.38:.2f}:d=0.26:alpha=1[ec]")
    fc.append(f"[ve][ec]overlay=x={ex}:"
              f"y='{ey}+30*(1-min(1,max(0,(t-{body+0.38:.2f}))/0.30))':"
              f"enable='gte(t,{body+0.38:.2f})'[vout]")

    cmd += ["-filter_complex", ";".join(fc),
            "-map", "[vout]", "-map", f"{audio_idx}:a", "-t", f"{total}",
            "-c:v", "libx264", "-preset", "veryfast", "-crf", "21",
            "-pix_fmt", "yuv420p", "-r", str(FPS),
            "-c:a", "aac", "-b:a", "96k", "-shortest", out_path]
    run(cmd)


def main():
    only = [a for a in sys.argv[1:] if a in CONCEPTS]
    todo = only or list(CONCEPTS)
    os.makedirs(WORK, exist_ok=True)

    made = 0
    for cid in todo:
        spec = CONCEPTS[cid]
        folder = os.path.join(OUT, f"concept-{cid}")
        os.makedirs(folder, exist_ok=True)
        for total, nbeats in DURATIONS.items():
            beats = spec["beats"][:nbeats]
            track, beat = screen_track(cid, total, beats)
            for ratio in RATIOS:
                out = os.path.join(folder, f"{total}s-{ratio}.mp4")
                compose(cid, total, ratio, track, beat, beats, out)
                made += 1
                print(f"  {os.path.relpath(out, HERE)}")
    print(f"{made} videos written")


if __name__ == "__main__":
    main()
