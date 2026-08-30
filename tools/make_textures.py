#!/usr/bin/env python3
"""
Generates every PNG the mod ships with.

Committed so the art is reproducible and tweakable rather than a set of opaque
binaries. Run from the repository root:

    python3 tools/make_textures.py

Requires Pillow.
"""

import os
import math
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MOD = os.path.join(ROOT, "Contents", "mods", "ERLeveling")
TEX = os.path.join(MOD, "media", "textures")
TEX_MOD = os.path.join(TEX, "ERLeveling")

# Palette, matching ERLeveling_Balance.lua COLOR table.
GOLD = (201, 162, 39)
GOLD_BRIGHT = (233, 201, 96)
GOLD_DIM = (122, 101, 32)
DARK = (10, 9, 8)
WARN = (180, 67, 46)
PALE = (214, 224, 231)

SS = 8  # supersample factor


def canvas(size, scale=SS):
    """A transparent supersampled canvas plus its draw context."""
    img = Image.new("RGBA", (size[0] * scale, size[1] * scale), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def finish(img, size, path, blur=0.0):
    out = img.resize(size, Image.LANCZOS)
    if blur > 0:
        out = out.filter(ImageFilter.GaussianBlur(blur))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out.save(path)
    print("  wrote", os.path.relpath(path, ROOT))


def diamond(draw, cx, cy, rx, ry, fill):
    draw.polygon([(cx, cy - ry), (cx + rx, cy), (cx, cy + ry), (cx - rx, cy)], fill=fill)


def glow(size, centre, radius, colour, strength=1.0):
    """A soft radial glow as its own RGBA layer."""
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    px = layer.load()
    cx, cy = centre
    for y in range(size[1]):
        for x in range(size[0]):
            d = math.hypot(x - cx, y - cy) / radius
            if d >= 1.0:
                continue
            a = int(255 * strength * ((1.0 - d) ** 2.2))
            if a > 0:
                px[x, y] = (colour[0], colour[1], colour[2], a)
    return layer


# ---------------------------------------------------------------------------
# UI textures
# ---------------------------------------------------------------------------
def rune_icon(path, size=32):
    img, d = canvas((size, size))
    s = size * SS
    c = s / 2
    diamond(d, c, c, s * 0.40, s * 0.48, GOLD)
    diamond(d, c, c, s * 0.30, s * 0.36, (*DARK, 210))
    diamond(d, c, c, s * 0.16, s * 0.20, GOLD_BRIGHT)
    # Four spurs, the Elden Ring rune silhouette.
    for dx, dy in ((0, -1), (0, 1), (-1, 0), (1, 0)):
        d.line([(c, c), (c + dx * s * 0.46, c + dy * s * 0.52)], fill=GOLD_BRIGHT,
               width=max(1, int(s * 0.035)))
    base = img.resize((size, size), Image.LANCZOS)
    out = Image.alpha_composite(glow((size, size), (size / 2, size / 2), size * 0.5,
                                     GOLD, 0.30), base)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out.save(path)
    print("  wrote", os.path.relpath(path, ROOT))


def bloodstain(path, w=64, h=40):
    img, d = canvas((w, h))
    sw, sh = w * SS, h * SS
    # Layered ellipses: a pooled, uneven edge rather than a clean oval.
    d.ellipse([sw * 0.06, sh * 0.20, sw * 0.94, sh * 0.86], fill=(*GOLD_DIM, 150))
    d.ellipse([sw * 0.16, sh * 0.30, sw * 0.86, sh * 0.78], fill=(*GOLD, 190))
    d.ellipse([sw * 0.30, sh * 0.40, sw * 0.70, sh * 0.68], fill=(*GOLD_BRIGHT, 225))
    for i, (ox, oy, r) in enumerate([(0.14, 0.72, 0.07), (0.82, 0.34, 0.05),
                                     (0.70, 0.82, 0.06), (0.26, 0.24, 0.045)]):
        d.ellipse([sw * (ox - r), sh * (oy - r * 1.6), sw * (ox + r), sh * (oy + r * 1.6)],
                  fill=(*GOLD, 150))
    base = img.resize((w, h), Image.LANCZOS).filter(ImageFilter.GaussianBlur(0.6))
    out = Image.alpha_composite(glow((w, h), (w / 2, h * 0.55), w * 0.5, GOLD, 0.35), base)
    out.save(path)
    print("  wrote", os.path.relpath(path, ROOT))


def grace_glow(path, size=128):
    out = glow((size, size), (size / 2, size / 2), size * 0.5, GOLD_BRIGHT, 0.85)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out.save(path)
    print("  wrote", os.path.relpath(path, ROOT))


def divider(path, w=64, h=4):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for x in range(w):
        # Bright in the middle, fading to nothing at both ends.
        t = 1.0 - abs((x / (w - 1)) * 2 - 1)
        a = int(200 * (t ** 0.7))
        px[x, h // 2] = (*GOLD, a)
        px[x, h // 2 - 1] = (*GOLD_DIM, a // 2)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print("  wrote", os.path.relpath(path, ROOT))


# ---------------------------------------------------------------------------
# Item icons (32x32, PZ expects media/textures/Item_<Icon>.png)
# ---------------------------------------------------------------------------
def item_rune_arc(path, size=32):
    img, d = canvas((size, size))
    s = size * SS
    c = s / 2
    # An arc, open at the bottom.
    box = [s * 0.12, s * 0.12, s * 0.88, s * 0.88]
    d.arc(box, start=200, end=340, fill=GOLD_BRIGHT, width=int(s * 0.10))
    d.arc([b + (s * 0.09 if i < 2 else -s * 0.09) for i, b in enumerate(box)],
          start=200, end=340, fill=GOLD_DIM, width=int(s * 0.05))
    diamond(d, c, s * 0.68, s * 0.14, s * 0.20, GOLD)
    diamond(d, c, s * 0.68, s * 0.07, s * 0.10, GOLD_BRIGHT)
    finish(img, (size, size), path)


def item_golden_rune(path, size=32):
    img, d = canvas((size, size))
    s = size * SS
    c = s / 2
    d.ellipse([s * 0.22, s * 0.22, s * 0.78, s * 0.78], fill=GOLD)
    d.ellipse([s * 0.30, s * 0.30, s * 0.62, s * 0.62], fill=GOLD_BRIGHT)
    for i in range(8):
        a = math.radians(i * 45 + 22)
        d.line([(c + math.cos(a) * s * 0.30, c + math.sin(a) * s * 0.30),
                (c + math.cos(a) * s * 0.46, c + math.sin(a) * s * 0.46)],
               fill=GOLD, width=int(s * 0.045))
    finish(img, (size, size), path)


def item_larval_tear(path, size=32):
    img, d = canvas((size, size))
    s = size * SS
    c = s / 2
    d.polygon([(c, s * 0.12), (c + s * 0.26, s * 0.60), (c, s * 0.88), (c - s * 0.26, s * 0.60)],
              fill=(*PALE, 235))
    d.ellipse([s * 0.30, s * 0.48, s * 0.70, s * 0.84], fill=(*PALE, 255))
    d.ellipse([s * 0.40, s * 0.56, s * 0.56, s * 0.70], fill=(255, 255, 255, 255))
    finish(img, (size, size), path)


def item_grace_idol(path, size=32):
    img, d = canvas((size, size))
    s = size * SS
    c = s / 2
    # A small stake with a flame: PZ's own campfire read at 32px.
    d.polygon([(c - s * 0.06, s * 0.44), (c + s * 0.06, s * 0.44),
               (c + s * 0.10, s * 0.90), (c - s * 0.10, s * 0.90)], fill=GOLD_DIM)
    d.polygon([(c, s * 0.10), (c + s * 0.16, s * 0.36), (c, s * 0.50),
               (c - s * 0.16, s * 0.36)], fill=GOLD)
    d.polygon([(c, s * 0.20), (c + s * 0.08, s * 0.36), (c, s * 0.44),
               (c - s * 0.08, s * 0.36)], fill=GOLD_BRIGHT)
    d.line([(c - s * 0.24, s * 0.90), (c + s * 0.24, s * 0.90)], fill=GOLD_DIM,
           width=int(s * 0.06))
    base = img.resize((size, size), Image.LANCZOS)
    out = Image.alpha_composite(glow((size, size), (size / 2, size * 0.32),
                                     size * 0.40, GOLD_BRIGHT, 0.40), base)
    out.save(path)
    print("  wrote", os.path.relpath(path, ROOT))


def item_bloodstain(path, size=32):
    img, d = canvas((size, size))
    s = size * SS
    d.ellipse([s * 0.10, s * 0.30, s * 0.90, s * 0.74], fill=(*GOLD_DIM, 200))
    d.ellipse([s * 0.24, s * 0.38, s * 0.76, s * 0.66], fill=(*GOLD, 230))
    d.ellipse([s * 0.40, s * 0.45, s * 0.60, s * 0.58], fill=(*GOLD_BRIGHT, 255))
    finish(img, (size, size), path, blur=0.3)


# ---------------------------------------------------------------------------
# Workshop poster
# ---------------------------------------------------------------------------
def poster(path, w=512, h=256):
    img = Image.new("RGBA", (w, h), (*DARK, 255))
    d = ImageDraw.Draw(img)

    # Vignette of warm light from below, the Erdtree read.
    img = Image.alpha_composite(img, glow((w, h), (w / 2, h * 1.05), h * 1.3, GOLD, 0.22))
    img = Image.alpha_composite(img, glow((w, h), (w / 2, h * 0.52), h * 0.62, GOLD, 0.16))
    d = ImageDraw.Draw(img)

    def font(size):
        for candidate in ("/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf",
                          "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"):
            if os.path.exists(candidate):
                return ImageFont.truetype(candidate, size)
        return ImageFont.load_default()

    def centred(text, y, f, fill):
        bbox = d.textbbox((0, 0), text, font=f)
        d.text(((w - (bbox[2] - bbox[0])) / 2 - bbox[0], y), text, font=f, fill=fill)

    centred("TARNISHED", 78, font(44), GOLD_BRIGHT)
    centred("ELDEN RING LEVELING", 130, font(17), GOLD)
    centred("for Project Zomboid", 156, font(14), (150, 140, 120))

    d.line([(w * 0.28, 116), (w * 0.72, 116)], fill=(*GOLD_DIM, 220), width=1)
    d.line([(w * 0.30, 180), (w * 0.70, 180)], fill=(*GOLD_DIM, 160), width=1)
    centred("RUNES  -  SITES OF GRACE  -  BLOODSTAINS", 194, font(11), (140, 126, 92))

    # A rune mark in each lower corner.
    for cx in (44, w - 44):
        dd = ImageDraw.Draw(img)
        for r, col in ((16, GOLD_DIM), (10, GOLD), (4, GOLD_BRIGHT)):
            dd.polygon([(cx, h - 44 - r), (cx + r * 0.8, h - 44),
                        (cx, h - 44 + r), (cx - r * 0.8, h - 44)], fill=col)

    d.rectangle([0, 0, w - 1, h - 1], outline=(*GOLD_DIM, 200))
    img.convert("RGB").save(path)
    print("  wrote", os.path.relpath(path, ROOT))


def main():
    print("Generating textures...")
    rune_icon(os.path.join(TEX_MOD, "rune_icon.png"))
    bloodstain(os.path.join(TEX_MOD, "bloodstain.png"))
    grace_glow(os.path.join(TEX_MOD, "grace_glow.png"))
    divider(os.path.join(TEX_MOD, "divider.png"))

    item_rune_arc(os.path.join(TEX, "Item_RuneArc.png"))
    item_golden_rune(os.path.join(TEX, "Item_GoldenRune.png"))
    item_larval_tear(os.path.join(TEX, "Item_LarvalTear.png"))
    item_grace_idol(os.path.join(TEX, "Item_GraceIdol.png"))
    item_bloodstain(os.path.join(TEX, "Item_Bloodstain.png"))

    poster(os.path.join(MOD, "poster.png"))
    print("Done.")


if __name__ == "__main__":
    main()
