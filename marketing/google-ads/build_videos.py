"""
Google Ads video creative builder for Speak Frankly — floating-UI style.

WHERE THE STYLE COMES FROM
Modelled on a reference clip the client supplied (a "Stimuler: Your Speaking
Coach" ad). Its visual language, minus anything that belongs to that brand:

  * a soft lavender wash, not a dark saturated brand slab;
  * interface elements float FREE — no phone bezel. The correction card, a chat
    bubble, the streak row are lifted out and shown at a size you can read on a
    phone at arm's length;
  * screenshots appear tilted and overlapping, as objects in a scene;
  * huge type, one word carrying the accent colour with an amber underline;
  * chevrons walking the eye down the frame;
  * nothing sits still — cards drift, type arrives line by line.

WHAT IS DELIBERATELY NOT COPIED
The reference opens with illustrated characters acting out the problem, and
carries a "12M+ learners" badge. The artwork is that brand's own, Speak Frankly
has no character or mascot, and we have no verified learner count. Inventing
either would be inventing brand identity and inventing statistics — both ruled
out by the brief. Type carries the emotional beat here instead.

EVERY card and screenshot below is a crop of a REAL screen capture taken from
the production app (1.5.3 / build 23) on a physical Galaxy A34.

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
SRC = os.path.join(HERE, "source-screens")
OUT = os.path.join(HERE, "videos")
WORK = os.path.join(HERE, ".video-build")

FONT_DIR = r"D:/new/New folder/src/flutter/bin/cache/artifacts/material_fonts"
F_BLACK = os.path.join(FONT_DIR, "roboto-black.ttf")
F_BOLD = os.path.join(FONT_DIR, "roboto-bold.ttf")
F_REG = os.path.join(FONT_DIR, "roboto-regular.ttf")
ICON = os.path.join(REPO, "app", "assets", "icon_512.png")

BG_TOP = (243, 240, 255)
BG_BOT = (214, 205, 250)
VIOLET = (108, 92, 231)
AMBER = (245, 158, 11)
INK = (26, 22, 44)
MUTED = (104, 98, 136)
WHITE = (255, 255, 255)

APP_NAME = "Speak Frankly"
END_CTA = "Start speaking today"

FPS = 30
END_CARD = 2.6
SRC_W, SRC_H = 1080, 2340

# type=(x, y, size, column width)   card=(centre x, centre y)   chev=(x, y)
RATIOS = {
    "9x16": dict(size=(1080, 1920), type=(84, 205, 88, 912), card=(540, 1035),
                 chev=(540, 1560), card_max=980, phone_h=920),
    "1x1": dict(size=(1080, 1080), type=(78, 168, 64, 924), card=(540, 720),
                chev=(540, 1000), card_max=840, phone_h=520),
    "16x9": dict(size=(1920, 1080), type=(104, 300, 80, 800), card=(1330, 540),
                 chev=(1330, 975), card_max=940, phone_h=760),
}

# Real UI, cropped out of real screenshots. Verified crop by crop.
PIECES = {
    "correction": ("09b-job-interview-correction.png", (140, 1040, 1020, 1420)),
    "user_bubble": ("09b-job-interview-correction.png", (160, 810, 1055, 1035)),
    "reply_bubble": ("09b-job-interview-correction.png", (40, 1445, 790, 1700)),
    "suggestions": ("09b-job-interview-correction.png", (30, 1895, 1060, 2070)),
    "stats_row": ("01-home-top.png", (44, 330, 1036, 500)),
    "wotd": ("01-home-top.png", (44, 585, 1036, 1015)),
    "talk_card": ("01-home-top.png", (44, 1035, 1036, 1330)),
    "phrase": ("02-speak.png", (44, 415, 1036, 835)),
    "saved_word": ("03-words.png", (44, 495, 1036, 1035)),
    "session_xp": ("10-session-report.png", (44, 130, 1036, 700)),
    "story_choices": ("07-story-play.png", (40, 1880, 1040, 2210)),
}

PHONES = ("07-story-play.png", "06-story-list.png")


def C(head, sub, key, visual):
    return dict(head=head, sub=sub, key=key, visual=visual)


CONCEPTS = {
    "01": dict(name="Problem / solution", beats=[
        C("You understand English.", "The words just stop coming out.", "understand", "user_bubble"),
        C("Say it here first.", "Type it or speak it. Nobody is watching.", "here", "talk_card"),
        C("Your tutor fixes it. Kindly.", "One correction, then it keeps talking.", "fixes", "correction"),
        C("Practise real situations.", "Interviews, shopping, the doctor.", "real", "phones"),
        C("Then say it out loud.", "Listen to a phrase and repeat it.", "loud", "phrase"),
        C("A new word every day.", "Learn it, save it, review it.", "word", "wotd"),
        C("Watch it add up.", "Streaks, XP and levels.", "up", "stats_row"),
        C("A few minutes a day.", "That is the whole trick.", "minutes", "session_xp"),
    ]),
    "02": dict(name="AI English tutor", beats=[
        C("An AI tutor that talks back.", "Any time you want. No appointment.", "talks", "reply_bubble"),
        C("Write like you speak.", "Mistakes and all. That is the point.", "Mistakes", "user_bubble"),
        C("Corrected, not judged.", "The fix, the reason, and straight on.", "judged", "correction"),
        C("Never stuck for words.", "Tap a suggested reply and keep going.", "stuck", "suggestions"),
        C("Play out a whole scene.", "Guided role-plays that work offline.", "scene", "story_choices"),
        C("Pick your situation.", "Job interview, shopping, ordering food.", "situation", "phones"),
        C("Practise speaking too.", "Listen, then shadow the phrase.", "speaking", "phrase"),
        C("See yourself improve.", "Streaks, XP and levels.", "improve", "stats_row"),
    ]),
    "03": dict(name="Fear of mistakes", beats=[
        C("Afraid of making mistakes?", "Nobody is listening. Nobody is judging.", "mistakes", "user_bubble"),
        C("Good. Make them here.", "Write it wrong. On purpose.", "wrong", "talk_card"),
        C("This is the right way.", "One line. No lecture.", "right", "correction"),
        C("And the chat keeps going.", "It never stops to grade you.", "keeps", "reply_bubble"),
        C("Try again. And again.", "As many times as you need.", "again", "story_choices"),
        C("Then say it out loud.", "Where it is safe to get it wrong.", "safe", "phrase"),
        C("Confidence, not perfection.", "That is what daily practice builds.", "Confidence", "session_xp"),
        C("Start with five minutes.", "Today.", "five", "stats_row"),
    ]),
    "04": dict(name="Feature tour", beats=[
        C("AI conversations", "That correct you as you go.", "conversations", "correction"),
        C("Story mode", "Guided role-plays. Works offline.", "Story", "phones"),
        C("Speaking practice", "Listen, then repeat out loud.", "Speaking", "phrase"),
        C("Word of the day", "One new word, every single day.", "Word", "wotd"),
        C("Progress you can see", "Streaks, XP and levels.", "Progress", "stats_row"),
        C("Reply suggestions", "For the moments you freeze.", "freeze", "suggestions"),
        C("Save every new word.", "And review it before you forget.", "Save", "saved_word"),
        C("All in one app.", "Free to start.", "Free", "session_xp"),
    ]),
    "05": dict(name="Complete experience", beats=[
        C("This is Speak Frankly.", "English practice that talks back.", "back", "talk_card"),
        C("Choose a situation.", "The ones you will really be in.", "situation", "phones"),
        C("Say what you can.", "Broken English is welcome here.", "Broken", "user_bubble"),
        C("Get one kind correction.", "Then carry on with the conversation.", "kind", "correction"),
        C("Play the whole scene.", "Pick your reply, see where it goes.", "scene", "story_choices"),
        C("Practise the sounds.", "Listen and shadow the phrase.", "sounds", "phrase"),
        C("Learn a word a day.", "And review it before you forget.", "word", "wotd"),
        C("Keep the streak alive.", "A few minutes daily is the trick.", "streak", "stats_row"),
    ]),
}

DURATIONS = {15: 3, 30: 6, 45: 8}


def font(p, s):
    return ImageFont.truetype(p, s)


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"ffmpeg failed:\n{' '.join(str(c) for c in cmd[:14])}\n{r.stderr[-1500:]}")
    return r


def rounded_mask(size, r):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], r, fill=255)
    return m


def crop_to_ink(canvas, path, pad=10):
    box = canvas.getbbox()
    if not box:
        canvas.save(path)
        return 0, 0
    box = (max(0, box[0] - pad), max(0, box[1] - pad),
           min(canvas.width, box[2] + pad), min(canvas.height, box[3] + pad))
    canvas.crop(box).save(path)
    return box[0], box[1]


def background(ratio, path):
    W, H = RATIOS[ratio]["size"]
    ramp = Image.new("L", (1, H))
    px = ramp.load()
    for y in range(H):
        px[0, y] = int(255 * (y / (H - 1)) ** 0.9)
    canvas = Image.composite(Image.new("RGB", (W, H), BG_BOT),
                             Image.new("RGB", (W, H), BG_TOP),
                             ramp.resize((W, H))).convert("RGBA")

    for cx, cy, r, col, a in ((int(W * 0.12), int(H * 0.10), int(min(W, H) * 0.48), WHITE, 150),
                              (int(W * 0.95), int(H * 0.42), int(min(W, H) * 0.42), (198, 186, 252), 130),
                              (int(W * 0.20), int(H * 0.88), int(min(W, H) * 0.46), (226, 219, 255), 150)):
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(layer).ellipse([cx - r, cy - r, cx + r, cy + r], fill=col + (a,))
        canvas = Image.alpha_composite(canvas, layer.filter(ImageFilter.GaussianBlur(r * 0.5)))

    curve = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(curve).arc([-int(W * 0.25), int(H * 0.52), W + int(W * 0.25), int(H * 0.97)],
                              200, 340, fill=VIOLET + (85,), width=7)
    canvas = Image.alpha_composite(canvas, curve)

    ic = Image.open(ICON).convert("RGBA").resize((60, 60), Image.LANCZOS)
    ic.putalpha(rounded_mask((60, 60), 16))
    x, y = RATIOS[ratio]["type"][0], int(H * 0.045)
    canvas.paste(ic, (x, y), ic)
    ImageDraw.Draw(canvas).text((x + 76, y + 14), APP_NAME, font=font(F_BOLD, 32), fill=INK)
    canvas.convert("RGB").save(path)


def float_card(piece, width, path, tilt=0, radius=26, border=None):
    name, rect = PIECES[piece]
    im = Image.open(os.path.join(SRC, name)).convert("RGB").crop(rect)
    h = int(im.height * width / im.width)
    im = im.resize((width, h), Image.LANCZOS)

    pad = 70
    canvas = Image.new("RGBA", (width + pad * 2, h + pad * 2), (0, 0, 0, 0))
    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        [pad, pad + 20, pad + width, pad + h + 20], radius, fill=(70, 52, 140, 120))
    canvas = Image.alpha_composite(canvas, sh.filter(ImageFilter.GaussianBlur(34)))

    card = im.convert("RGBA")
    card.putalpha(rounded_mask((width, h), radius))
    canvas.paste(card, (pad, pad), card)
    if border:
        ImageDraw.Draw(canvas).rounded_rectangle(
            [pad, pad, pad + width, pad + h], radius, outline=border + (255,), width=6)
    if tilt:
        canvas = canvas.rotate(tilt, expand=True, resample=Image.BICUBIC)
    canvas.save(path)
    return canvas.size


def tilted_phone(screen, height, path, tilt=-8):
    im = Image.open(os.path.join(SRC, screen)).convert("RGB").crop((0, 92, SRC_W, 2292))
    w = int(im.width * height / im.height)
    im = im.resize((w, height), Image.LANCZOS)
    b = 10
    frame = Image.new("RGBA", (w + b * 2, height + b * 2), (24, 20, 40, 255))
    frame.paste(im, (b, b))
    frame.putalpha(rounded_mask(frame.size, 34))

    pad = 70
    canvas = Image.new("RGBA", (frame.width + pad * 2, frame.height + pad * 2), (0, 0, 0, 0))
    sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        [pad, pad + 22, pad + frame.width, pad + frame.height + 22], 34, fill=(70, 52, 140, 130))
    canvas = Image.alpha_composite(canvas, sh.filter(ImageFilter.GaussianBlur(30)))
    canvas.paste(frame, (pad, pad), frame)
    canvas = canvas.rotate(tilt, expand=True, resample=Image.BICUBIC)
    canvas.save(path)
    return canvas.size


def head_lines(ratio, head, key, prefix):
    """One plate per line, so the headline can arrive line by line."""
    W, H = RATIOS[ratio]["size"]
    x, y, size, col = RATIOS[ratio]["type"]
    d0 = ImageDraw.Draw(Image.new("RGBA", (10, 10)))
    fh = font(F_BLACK, size)

    lines, cur = [], ""
    for w in head.split():
        t = f"{cur} {w}".strip()
        if d0.textlength(t, font=fh) <= col or not cur:
            cur = t
        else:
            lines.append(cur)
            cur = w
    lines.append(cur)

    out = []
    for i, line in enumerate(lines):
        canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(canvas)
        cx, cy = x, y + i * int(size * 1.10)
        for w in line.split():
            hot = key and w.strip(".,!?").lower() == key.lower()
            d.text((cx, cy), w, font=fh, fill=VIOLET if hot else INK)
            wl = d.textlength(w, font=fh)
            if hot:
                d.rounded_rectangle([cx, cy + size * 1.02, cx + wl, cy + size * 1.02 + 9],
                                    5, fill=AMBER)
            cx += wl + d.textlength(" ", font=fh)
        p = f"{prefix}-h{i}.png"
        out.append((p, crop_to_ink(canvas, p)))
    return out, y + len(lines) * int(size * 1.10)


def sub_plate(ratio, sub, y, path):
    W, H = RATIOS[ratio]["size"]
    x, _, size, col = RATIOS[ratio]["type"]
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(canvas)
    fs = font(F_REG, int(size * 0.36))
    cy = y + 20
    cur = ""
    lines = []
    for w in sub.split():
        t = f"{cur} {w}".strip()
        if d.textlength(t, font=fs) <= col or not cur:
            cur = t
        else:
            lines.append(cur)
            cur = w
    lines.append(cur)
    for line in lines:
        d.text((x, cy), line, font=fs, fill=MUTED)
        cy += int(fs.size * 1.34)
    return crop_to_ink(canvas, path)


def chevrons(path, size=64):
    canvas = Image.new("RGBA", (size * 2, size * 3), (0, 0, 0, 0))
    d = ImageDraw.Draw(canvas)
    for i in range(3):
        y = i * size
        a = int(255 * (0.35 + 0.65 * i / 2))
        d.line([(size * 0.35, y + size * 0.25), (size, y + size * 0.72)], fill=VIOLET + (a,), width=13)
        d.line([(size, y + size * 0.72), (size * 1.65, y + size * 0.25)], fill=VIOLET + (a,), width=13)
    return crop_to_ink(canvas, path, pad=4)


def endcard(ratio, bg_path, path):
    W, H = RATIOS[ratio]["size"]
    canvas = Image.open(bg_path).convert("RGBA")
    d = ImageDraw.Draw(canvas)
    s = int(min(W, H) * 0.15)
    ic = Image.open(ICON).convert("RGBA").resize((s, s), Image.LANCZOS)
    ic.putalpha(rounded_mask((s, s), int(s * 0.26)))

    f_name = font(F_BLACK, int(min(W, H) * 0.072))
    f_tag = font(F_REG, int(min(W, H) * 0.032))
    f_cta = font(F_BOLD, int(min(W, H) * 0.036))
    tag = "Practise real English conversations"
    btn_h = f_cta.size + 48
    block = s + 38 + f_name.size * 1.15 + 18 + f_tag.size * 1.2 + 50 + btn_h
    y = (H - block) / 2

    canvas.paste(ic, ((W - s) // 2, int(y)), ic)
    y += s + 38
    d.text(((W - d.textlength(APP_NAME, font=f_name)) / 2, y), APP_NAME, font=f_name, fill=INK)
    y += f_name.size * 1.15 + 18
    d.text(((W - d.textlength(tag, font=f_tag)) / 2, y), tag, font=f_tag, fill=MUTED)
    y += f_tag.size * 1.2 + 50
    bw = d.textlength(END_CTA, font=f_cta) + 92
    bx = (W - bw) / 2
    d.rounded_rectangle([bx, y, bx + bw, y + btn_h], btn_h / 2, fill=VIOLET)
    d.text((bx + 46, y + 23), END_CTA, font=f_cta, fill=WHITE)
    canvas.convert("RGB").save(path)


def build(concept, total, ratio, beats, out_path):
    cfg = RATIOS[ratio]
    W, H = cfg["size"]
    ccx, ccy = cfg["card"]
    body = total - END_CARD
    beat = body / len(beats)
    pre = os.path.join(WORK, f"{concept}-{total}-{ratio}")

    bg = os.path.join(WORK, f"bg-{ratio}.png")
    if not os.path.exists(bg):
        background(ratio, bg)
    end = os.path.join(WORK, f"end-{ratio}.png")
    if not os.path.exists(end):
        endcard(ratio, bg, end)
    chev = os.path.join(WORK, "chev.png")
    if not os.path.exists(chev):
        chevrons(chev)

    inputs = ["-loop", "1", "-i", bg, "-loop", "1", "-i", chev]
    idx = 2
    scenes = []

    for i, b in enumerate(beats):
        heads, after = head_lines(ratio, b["head"], b["key"], f"{pre}-{i}")
        sp = f"{pre}-{i}-sub.png"
        sub_at = sub_plate(ratio, b["sub"], after, sp)

        hi = []
        for p, at in heads:
            inputs += ["-loop", "1", "-i", p]
            hi.append((idx, at))
            idx += 1
        inputs += ["-loop", "1", "-i", sp]
        si = idx
        idx += 1

        vis = b["visual"]
        if vis == "phones":
            p1, p2 = f"{pre}-{i}-pa.png", f"{pre}-{i}-pb.png"
            w1, h1 = tilted_phone(PHONES[0], cfg["phone_h"], p1, tilt=-9)
            w2, h2 = tilted_phone(PHONES[1], int(cfg["phone_h"] * 0.92), p2, tilt=7)
            inputs += ["-loop", "1", "-i", p2, "-loop", "1", "-i", p1]
            visual = ("phones", idx, w2, h2, idx + 1, w1, h1)
            idx += 2
        else:
            cp = f"{pre}-{i}-card.png"
            border = AMBER if vis == "correction" else None
            cw, ch = float_card(vis, cfg["card_max"], cp, tilt=-2 if i % 2 else 2, border=border)
            inputs += ["-loop", "1", "-i", cp]
            visual = ("card", idx, cw, ch)
            idx += 1

        scenes.append(dict(heads=hi, sub=(si, sub_at), visual=visual))

    inputs += ["-loop", "1", "-i", end]
    end_idx = idx
    inputs += ["-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=44100"]
    audio_idx = idx + 1

    fc = ["[0:v]null[v0]"]
    prev = "v0"
    cvx, cvy = cfg["chev"]
    fc.append(f"[1:v]format=rgba,fade=t=in:st=0.5:d=0.4:alpha=1,"
              f"fade=t=out:st={body-0.4:.2f}:d=0.3:alpha=1[chev]")
    fc.append(f"[{prev}][chev]overlay=x={cvx-40}:y='{cvy}+14*sin(2*PI*t/1.6)':"
              f"enable='between(t,0.5,{body:.2f})'[vch]")
    prev = "vch"

    for i, s in enumerate(scenes):
        st = i * beat
        en = min(st + beat, body)
        out_st = max(st, en - 0.26)

        for k, (ii, (ax, ay)) in enumerate(s["heads"]):
            d0 = st + k * 0.11
            fc.append(f"[{ii}:v]format=rgba,fade=t=in:st={d0:.2f}:d=0.26:alpha=1,"
                      f"fade=t=out:st={out_st:.2f}:d=0.24:alpha=1[h{i}_{k}]")
            fc.append(f"[{prev}][h{i}_{k}]overlay=x={ax}:"
                      f"y='{ay}+44*(1-min(1,max(0,(t-{d0:.2f}))/0.34))':"
                      f"enable='between(t,{st:.2f},{en:.2f})'[vh{i}_{k}]")
            prev = f"vh{i}_{k}"

        si, (sx, sy) = s["sub"]
        d0 = st + 0.22
        fc.append(f"[{si}:v]format=rgba,fade=t=in:st={d0:.2f}:d=0.26:alpha=1,"
                  f"fade=t=out:st={out_st:.2f}:d=0.24:alpha=1[s{i}]")
        fc.append(f"[{prev}][s{i}]overlay=x={sx}:"
                  f"y='{sy}+30*(1-min(1,max(0,(t-{d0:.2f}))/0.34))':"
                  f"enable='between(t,{st:.2f},{en:.2f})'[vs{i}]")
        prev = f"vs{i}"

        v = s["visual"]
        if v[0] == "phones":
            _, bi, bw, bh, fi, fw, fh = v
            fc.append(f"[{bi}:v]format=rgba,fade=t=in:st={st+0.18:.2f}:d=0.32:alpha=1,"
                      f"fade=t=out:st={out_st:.2f}:d=0.24:alpha=1[pb{i}]")
            fc.append(f"[{prev}][pb{i}]overlay=x={int(ccx + cfg['card_max']*0.22) - bw//2}:"
                      f"y='{ccy - bh//2}+64*(1-min(1,max(0,(t-{st+0.18:.2f}))/0.42))"
                      f"+7*sin(2*PI*t/5)':enable='between(t,{st:.2f},{en:.2f})'[vpb{i}]")
            fc.append(f"[{fi}:v]format=rgba,fade=t=in:st={st+0.32:.2f}:d=0.32:alpha=1,"
                      f"fade=t=out:st={out_st:.2f}:d=0.24:alpha=1[pf{i}]")
            fc.append(f"[vpb{i}][pf{i}]overlay=x={int(ccx - cfg['card_max']*0.26) - fw//2}:"
                      f"y='{ccy - fh//2}+74*(1-min(1,max(0,(t-{st+0.32:.2f}))/0.42))"
                      f"+9*sin(2*PI*t/6+1)':enable='between(t,{st:.2f},{en:.2f})'[vv{i}]")
        else:
            _, ci, cw, ch = v
            fc.append(f"[{ci}:v]format=rgba,"
                      f"scale=w='{cw}*(0.91+0.09*min(1,max(0,(t-{st:.2f}))/0.40))':h=-1:eval=frame,"
                      f"fade=t=in:st={st+0.14:.2f}:d=0.30:alpha=1,"
                      f"fade=t=out:st={out_st:.2f}:d=0.24:alpha=1[cd{i}]")
            fc.append(f"[{prev}][cd{i}]overlay=x='{ccx}-w/2':"
                      f"y='{ccy}-h/2+60*(1-min(1,max(0,(t-{st:.2f}))/0.42))"
                      f"+8*sin(2*PI*t/5.5)':enable='between(t,{st:.2f},{en:.2f})'[vv{i}]")
        prev = f"vv{i}"

    bar_h = max(6, H // 190)
    fc.append(f"[{prev}]drawbox=x=0:y={H-bar_h}:w='iw*min(t/{total},1)':h={bar_h}:"
              f"color=0x{VIOLET[0]:02X}{VIOLET[1]:02X}{VIOLET[2]:02X}@0.92:t=fill[vb]")
    fc.append(f"[{end_idx}:v]format=rgba,fade=t=in:st={body:.2f}:d=0.35:alpha=1[e]")
    fc.append(f"[vb][e]overlay=0:0:enable='gte(t,{body:.2f})'[vout]")

    cmd = ["ffmpeg", "-v", "error", "-y"] + inputs + [
        "-filter_complex", ";".join(fc), "-map", "[vout]", "-map", f"{audio_idx}:a",
        "-t", str(total), "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
        "-pix_fmt", "yuv420p", "-r", str(FPS),
        "-c:a", "aac", "-b:a", "96k", "-shortest", out_path]
    run(cmd)


def main():
    only = [a for a in sys.argv[1:] if a in CONCEPTS]
    todo = only or list(CONCEPTS)
    os.makedirs(WORK, exist_ok=True)

    made = 0
    for cid in todo:
        folder = os.path.join(OUT, f"concept-{cid}")
        os.makedirs(folder, exist_ok=True)
        for total, n in DURATIONS.items():
            beats = CONCEPTS[cid]["beats"][:n]
            for ratio in RATIOS:
                out = os.path.join(folder, f"{total}s-{ratio}.mp4")
                build(cid, total, ratio, beats, out)
                made += 1
                print(f"  {os.path.relpath(out, HERE)}")
    print(f"{made} videos written")


if __name__ == "__main__":
    main()
