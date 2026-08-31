"""
Google Ads image creative builder for Speak Frankly.

Everything here composes REAL screenshots captured from the production app on a
physical device (marketing/google-ads/source-screens/) with the app's own brand
assets and typeface. No invented UI, no invented numbers, no stock imagery.

Brand values are taken from the app itself:
  seed violet   #6C5CE7   app/lib/theme/app_theme.dart
  light surface #F7F6FC   scaffoldBackgroundColor
  correction    #F59E0B   AppColors.correction
  typeface      Roboto    the app's Material default

Run:  python build_images.py
Out:  images/<nn>-<slug>/{1.91-horizontal-1200x628,4x5-1200x1500,1x1-1200x1200}.png
"""

from __future__ import annotations

import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(HERE, "source-screens")
OUT = os.path.join(HERE, "images")

FONT_DIR = r"D:/new/New folder/src/flutter/bin/cache/artifacts/material_fonts"
F_BLACK = os.path.join(FONT_DIR, "roboto-black.ttf")
F_BOLD = os.path.join(FONT_DIR, "roboto-bold.ttf")
F_MED = os.path.join(FONT_DIR, "roboto-medium.ttf")
F_REG = os.path.join(FONT_DIR, "roboto-regular.ttf")

ICON = os.path.join(REPO, "app", "assets", "icon_512.png")

# ---- brand -----------------------------------------------------------------
VIOLET = (108, 92, 231)        # #6C5CE7  app seed
VIOLET_DEEP = (74, 60, 180)
VIOLET_LIGHT = (139, 124, 240)
SURFACE = (247, 246, 252)      # #F7F6FC
INK = (22, 20, 31)
MUTED = (108, 104, 124)
AMBER = (245, 158, 11)         # #F59E0B  correction
WHITE = (255, 255, 255)

APP_NAME = "Speak Frankly"


def font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size)


# ---- text helpers ----------------------------------------------------------
def wrap(draw: ImageDraw.ImageDraw, text: str, fnt, max_w: int) -> list[str]:
    """Greedy word wrap. Honours explicit newlines."""
    lines: list[str] = []
    for para in text.split("\n"):
        words, cur = para.split(), ""
        for w in words:
            trial = f"{cur} {w}".strip()
            if draw.textlength(trial, font=fnt) <= max_w or not cur:
                cur = trial
            else:
                lines.append(cur)
                cur = w
        lines.append(cur)
    return lines


def draw_block(draw, xy, text, fnt, fill, max_w, leading=1.16, spacing_after=0):
    """Draw wrapped text, return the y just below the block."""
    x, y = xy
    lh = int(fnt.size * leading)
    for line in wrap(draw, text, fnt, max_w):
        draw.text((x, y), line, font=fnt, fill=fill)
        y += lh
    return y + spacing_after


# ---- surfaces --------------------------------------------------------------
def gradient(size, top=VIOLET_LIGHT, bottom=VIOLET_DEEP):
    """Seamless diagonal brand gradient (rendered oversized, then centre-cropped
    so the rotation never leaves empty corners)."""
    w, h = size
    n = int((w ** 2 + h ** 2) ** 0.5) + 80
    ramp = Image.new("L", (1, n))
    px = ramp.load()
    for i in range(n):
        px[0, i] = int(255 * i / (n - 1))
    ramp = ramp.resize((n, n)).rotate(-32, resample=Image.BICUBIC)
    big = Image.composite(Image.new("RGB", (n, n), bottom),
                          Image.new("RGB", (n, n), top), ramp)
    left, top_ = (n - w) // 2, (n - h) // 2
    return big.crop((left, top_, left + w, top_ + h))


def glow(canvas, cx, cy, radius, colour, strength=70):
    """A soft blob of light. A flat fill reads cheap; this gives it depth."""
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse(
        [cx - radius, cy - radius, cx + radius, cy + radius], fill=colour + (strength,))
    return Image.alpha_composite(canvas, layer.filter(ImageFilter.GaussianBlur(radius * 0.55)))


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius, fill=255)
    return m


def shadowed(img, radius, blur=34, offset=(0, 18), alpha=110):
    """Rounded card with a soft drop shadow, on a transparent canvas."""
    w, h = img.size
    pad = blur * 2
    canvas = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))

    sh = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        [pad + offset[0], pad + offset[1], pad + w + offset[0], pad + h + offset[1]],
        radius, fill=(30, 24, 60, alpha))
    canvas = Image.alpha_composite(canvas, sh.filter(ImageFilter.GaussianBlur(blur)))

    card = img.convert("RGBA")
    card.putalpha(rounded_mask((w, h), radius))
    canvas.paste(card, (pad, pad), card)
    return canvas


def draw_ring(im, crop, rect):
    """Ring an element of the screen, in the screenshot's own pixel space.

    Drawn before the resize so it scales with the UI and stays locked to the
    thing it points at, at any output size.
    """
    x0, y0, x1, y1 = rect
    box = [x0 - crop[0], y0 - crop[1], x1 - crop[0], y1 - crop[1]]
    halo = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(halo).rounded_rectangle(box, 26, outline=AMBER + (200,), width=16)
    out = Image.alpha_composite(im.convert("RGBA"), halo.filter(ImageFilter.GaussianBlur(12)))
    ImageDraw.Draw(out).rounded_rectangle(box, 26, outline=AMBER + (255,), width=7)
    return out.convert("RGB")


def phone(screen_path, crop, box, bezel=14, bleed=False, ring=None):
    """A real screenshot as a phone-like card, scaled to FIT inside `box`.

    `bleed=True` lets a long screen run past the bottom of the box (a deliberate
    look for full-screen captures); a close-up crop always fits entirely, because
    the whole point of it is the text it contains.
    """
    im = Image.open(os.path.join(SRC, screen_path)).convert("RGB").crop(crop)
    if ring:
        im = draw_ring(im, crop, ring)
    bw, bh = box
    bw, bh = bw - bezel * 2, bh - bezel * 2

    scale = bw / im.width if bleed else min(bw / im.width, bh / im.height)
    w, h = max(1, int(im.width * scale)), max(1, int(im.height * scale))
    im = im.resize((w, h), Image.LANCZOS)

    if bezel:
        frame = Image.new("RGB", (w + bezel * 2, h + bezel * 2), (28, 24, 40))
        frame.paste(im, (bezel, bezel))
        im = frame
    return im


def logo_chip(size=64):
    ic = Image.open(ICON).convert("RGBA").resize((size, size), Image.LANCZOS)
    ic.putalpha(rounded_mask((size, size), int(size * 0.26)))
    return ic


def put_logo(canvas, x, y, on_dark=True, size=62, name=True):
    ic = logo_chip(size)
    canvas.paste(ic, (x, y), ic)
    if name:
        d = ImageDraw.Draw(canvas)
        d.text((x + size + 18, y + size * 0.20), APP_NAME,
               font=font(F_BOLD, int(size * 0.52)),
               fill=WHITE if on_dark else INK)
    return y + size


def cta_pill(canvas, x, y, text, dark_bg=True, pad=(34, 20), fsize=32):
    d = ImageDraw.Draw(canvas)
    f = font(F_BOLD, fsize)
    tw = d.textlength(text, font=f)
    w, h = int(tw + pad[0] * 2), int(fsize + pad[1] * 2)
    bg = WHITE if dark_bg else VIOLET
    fg = VIOLET if dark_bg else WHITE
    d.rounded_rectangle([x, y, x + w, y + h], h // 2, fill=bg)
    d.text((x + pad[0], y + pad[1] - fsize * 0.08), text, font=f, fill=fg)
    return w, h


# ---- concepts --------------------------------------------------------------
# Every headline below describes something the app demonstrably does, shown in
# the screenshot it is paired with. Crops exclude the system status bar and any
# in-app ad slot.
CROP_FULL = (0, 92, 1080, 2292)
CROP_HOME = (0, 92, 1080, 1870)      # above the banner-ad slot
CROP_WORDS = (0, 92, 1080, 1900)     # above the banner-ad slot
CORRECTION_RECT = (140, 1045, 1020, 1415)  # the amber correction card, in screenshot pixels
CROP_TIGHT_FIX = (0, 800, 1080, 1800)   # the mistake -> correction -> reply beat
CROP_TIGHT_SUGGEST = (0, 1412, 1080, 2270)  # the tap-a-reply suggestions + input bar
CROP_SPEAK = (0, 92, 1080, 2210)        # phrase card through the mic button

CONCEPTS = [
    dict(slug="01-mistakes-welcome",
         head="Make mistakes.\nThat's the point.",
         sub="Your AI tutor fixes them kindly and keeps the conversation going.",
         cta="Start speaking today",
         screen="09b-job-interview-correction.png", crop=CROP_TIGHT_FIX,
         style="gradient", tight=True, ring=CORRECTION_RECT),

    dict(slug="02-ai-tutor",
         head="Your AI English\nconversation partner",
         sub="Chat any time. It replies, corrects and keeps you talking.",
         cta="Practise English now",
         screen="09b-job-interview-correction.png", crop=CROP_FULL,
         style="light", ring=CORRECTION_RECT),

    dict(slug="03-never-stuck",
         head="Never stuck\nfor words",
         sub="Not sure what to say? Tap a suggested reply and keep going.",
         cta="Try a conversation",
         screen="09b-job-interview-correction.png", crop=CROP_TIGHT_SUGGEST,
         style="gradient", tight=True),

    dict(slug="04-job-interview",
         head="Practise the\njob interview",
         sub="Answer real interview questions in English before the real one.",
         cta="Start practising",
         screen="09b-job-interview-correction.png", crop=CROP_FULL,
         style="dark"),

    dict(slug="05-speak-out-loud",
         head="Speak it.\nDon't just read it.",
         sub="Listen to a phrase, then say it out loud into the mic.",
         cta="Practise speaking",
         screen="02-speak.png", crop=CROP_SPEAK,
         style="light"),

    dict(slug="06-real-situations",
         head="Practise real\nsituations",
         sub="Interviews, shopping, the doctor, travel — guided role-plays.",
         cta="Pick a scenario",
         screen="07-story-play.png", crop=CROP_FULL,
         style="gradient"),

    dict(slug="07-daily-habit",
         head="A little English,\nevery day",
         sub="Streaks, XP and levels turn practice into a habit.",
         cta="Build your streak",
         screen="01-home-top.png", crop=CROP_HOME,
         style="light"),

    dict(slug="08-words-that-stick",
         head="A new word\nevery day",
         sub="Learn it, save it, and review it before you forget it.",
         cta="Grow your English",
         screen="03-words.png", crop=CROP_WORDS,
         style="dark"),
]


def palette(style):
    if style == "gradient":
        return dict(bg=None, fg=WHITE, sub=(233, 229, 255), on_dark=True)
    if style == "dark":
        return dict(bg=(24, 21, 36), fg=WHITE, sub=(190, 185, 215), on_dark=True)
    return dict(bg=SURFACE, fg=INK, sub=MUTED, on_dark=False)


def background(size, style):
    W, H = size
    if style == "gradient":
        c = gradient(size).convert("RGBA")
        c = glow(c, int(W * 0.10), int(H * 0.08), int(min(W, H) * 0.46), VIOLET_LIGHT, 62)
        return glow(c, int(W * 0.95), int(H * 0.92), int(min(W, H) * 0.38), (58, 44, 150), 72)
    c = Image.new("RGBA", size, palette(style)["bg"])
    if style == "dark":
        c = glow(c, int(W * 0.18), int(H * 0.12), int(min(W, H) * 0.44), VIOLET, 52)
        return glow(c, int(W * 0.92), int(H * 0.9), int(min(W, H) * 0.34), (70, 55, 170), 46)
    return glow(c, int(W * 0.14), int(H * 0.1), int(min(W, H) * 0.5), VIOLET_LIGHT, 26)


def accent_bar(canvas, x, y, h=8, w=110, color=AMBER):
    ImageDraw.Draw(canvas).rounded_rectangle([x, y, x + w, y + h], h // 2, fill=color)


# ---- layouts ---------------------------------------------------------------
def build_horizontal(c):
    """1.91:1 - copy on the left, the real screen on the right."""
    W, H = 1200, 628
    pal = palette(c["style"])
    canvas = background((W, H), c["style"])
    tight = c.get("tight", False)

    if tight:
        ph = phone(c["screen"], c["crop"], (480, 500), ring=c.get("ring"))
        card = shadowed(ph, 30)
        canvas.paste(card, (W - card.width - 20, (H - card.height) // 2), card)
    else:
        ph = phone(c["screen"], c["crop"], (300, H), bleed=True, ring=c.get("ring"))
        card = shadowed(ph, 30)
        canvas.paste(card, (W - card.width - 60, 46), card)

    d = ImageDraw.Draw(canvas)
    x, col = 72, 570 if tight else 640
    put_logo(canvas, x, 58, on_dark=pal["on_dark"], size=52)
    accent_bar(canvas, x, 158)
    y = draw_block(d, (x, 186), c["head"], font(F_BLACK, 58), pal["fg"], col, 1.10, 16)
    y = draw_block(d, (x, y), c["sub"], font(F_REG, 26), pal["sub"], col - 30, 1.32, 24)
    cta_pill(canvas, x, y, c["cta"], dark_bg=pal["on_dark"], fsize=26, pad=(30, 17))
    return canvas


def build_portrait(c):
    """4:5 - copy stacked over a tall screen."""
    W, H = 1200, 1500
    pal = palette(c["style"])
    canvas = background((W, H), c["style"])
    tight = c.get("tight", False)

    d = ImageDraw.Draw(canvas)
    x, col = 90, 1020
    put_logo(canvas, x, 84, on_dark=pal["on_dark"], size=62)
    accent_bar(canvas, x, 206)
    y = draw_block(d, (x, 240), c["head"], font(F_BLACK, 80), pal["fg"], col, 1.08, 20)
    y = draw_block(d, (x, y), c["sub"], font(F_REG, 33), pal["sub"], col - 60, 1.34, 34)
    _, cta_h = cta_pill(canvas, x, y, c["cta"], dark_bg=pal["on_dark"], fsize=32, pad=(36, 22))

    top = y + cta_h + 46
    if tight:
        ph = phone(c["screen"], c["crop"], (1020, H - top - 60), ring=c.get("ring"))
    else:
        ph = phone(c["screen"], c["crop"], (600, H - top), bleed=True, ring=c.get("ring"))
    card = shadowed(ph, 36)
    canvas.paste(card, ((W - card.width) // 2, top - 60), card)
    return canvas


def build_square(c):
    """1:1 - copy on top, screen anchored bottom-centre."""
    W, H = 1200, 1200
    pal = palette(c["style"])
    canvas = background((W, H), c["style"])
    tight = c.get("tight", False)

    d = ImageDraw.Draw(canvas)
    x, col = 84, 1032
    put_logo(canvas, x, 74, on_dark=pal["on_dark"], size=58)
    accent_bar(canvas, x, 186)
    y = draw_block(d, (x, 216), c["head"], font(F_BLACK, 70), pal["fg"], col, 1.08, 16)
    y = draw_block(d, (x, y), c["sub"], font(F_REG, 30), pal["sub"], col - 80, 1.32, 26)
    _, cta_h = cta_pill(canvas, x, y, c["cta"], dark_bg=pal["on_dark"], fsize=29, pad=(32, 20))

    top = y + cta_h + 40
    if tight:
        ph = phone(c["screen"], c["crop"], (1032, H - top - 50), ring=c.get("ring"))
    else:
        ph = phone(c["screen"], c["crop"], (520, H - top), bleed=True, ring=c.get("ring"))
    card = shadowed(ph, 34)
    canvas.paste(card, ((W - card.width) // 2, top - 54), card)
    return canvas


SIZES = {
    "1.91-horizontal-1200x628.png": (build_horizontal, (1200, 628)),
    "4x5-1200x1500.png": (build_portrait, (1200, 1500)),
    "1x1-1200x1200.png": (build_square, (1200, 1200)),
}


def main():
    made = []
    for c in CONCEPTS:
        folder = os.path.join(OUT, c["slug"])
        os.makedirs(folder, exist_ok=True)
        for name, (fn, size) in SIZES.items():
            img = fn(c).convert("RGB")
            assert img.size == size, f"{c['slug']}/{name} is {img.size}, expected {size}"
            path = os.path.join(folder, name)
            img.save(path, "PNG", optimize=True)
            made.append((path, size, os.path.getsize(path)))
    print(f"{len(made)} images written")
    for p, s, b in made:
        print(f"  {os.path.relpath(p, HERE)}  {s[0]}x{s[1]}  {b/1024:.0f} KB")


if __name__ == "__main__":
    main()
