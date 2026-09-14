#!/usr/bin/env python3
"""
App Store screenshot frame template for Roboteer.

Takes a 2868 x 1320 landscape simulator screenshot and lays a caption band over
the bottom of it in the locked AAA chrome style from docs/stage2-art-direction.md:
bold condensed white capitals with tight tracking on translucent dark glass with a
thin light top edge, and gold #f2c14e used only for scrap words.

The band sits INSIDE the frame, so the output is still exactly 2868 x 1320 and is
still a valid App Store 6.9 inch landscape screenshot. Output is RGB with no alpha,
which is the one hard rule Apple documents for screenshots.

Usage
-----
    python3 Art/store/frame-template.py SHOT.png OUT.png "CAPTION TEXT"

Options
-------
    --gold WORD[,WORD...]   words rendered in gold rather than white. Default is
                            the scrap vocabulary: SCRAP, BLUEPRINT, BLUEPRINTS,
                            BOLTS, WINNER, KO.
    --sub "SECOND LINE"     an optional smaller second line under the caption.
    --band top|bottom       which edge the band sits on. Default bottom.
    --check                 print the output size and alpha state and exit non-zero
                            if either is wrong.

Notes
-----
* Caption text IS indexed by App Store search, so write real words, not slogans
  made of punctuation.
* No em dashes anywhere in a caption. The script refuses them.
* Fonts: Avenir Next Condensed is used because it ships with macOS and is the
  closest system face to the locked "bold condensed sans". Drop a licensed
  condensed face at Art/store/fonts/caption.ttf and it will be used instead.
"""

from __future__ import annotations

import argparse
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SHOT_W, SHOT_H = 2868, 1320

GOLD = (242, 193, 78)
WHITE = (255, 255, 255)
GLASS = (10, 13, 16)
EDGE = (150, 168, 180)

DEFAULT_GOLD_WORDS = {"SCRAP", "BLUEPRINT", "BLUEPRINTS", "BOLTS", "WINNER", "KO"}

HERE = os.path.dirname(os.path.abspath(__file__))
CUSTOM_FONT = os.path.join(HERE, "fonts", "caption.ttf")
SYSTEM_CONDENSED = "/System/Library/Fonts/Avenir Next Condensed.ttc"
SYSTEM_FALLBACK = "/System/Library/Fonts/HelveticaNeue.ttc"


def load_font(size: int, bold: bool = True) -> ImageFont.FreeTypeFont:
    """Bold condensed if we can get it, bold otherwise."""
    if os.path.exists(CUSTOM_FONT):
        return ImageFont.truetype(CUSTOM_FONT, size)
    if os.path.exists(SYSTEM_CONDENSED):
        # Avenir Next Condensed.ttc face order, verified with getname():
        # 0 Bold, 2 Demi Bold, 5 Medium, 7 Regular, 8 Heavy. Odd indices are italics.
        for index in ((8, 0) if bold else (2, 5)):
            try:
                return ImageFont.truetype(SYSTEM_CONDENSED, size, index=index)
            except (OSError, ValueError):
                continue
    if os.path.exists(SYSTEM_FALLBACK):
        return ImageFont.truetype(SYSTEM_FALLBACK, size, index=1 if bold else 0)
    return ImageFont.load_default()


def tracked_runs(text: str, gold_words: set[str]) -> list[tuple[str, tuple[int, int, int]]]:
    """Split a caption into coloured word runs. Gold is only ever the scrap words."""
    runs: list[tuple[str, tuple[int, int, int]]] = []
    for word in text.split(" "):
        bare = word.strip(".,:;!?()").upper()
        runs.append((word, GOLD if bare in gold_words else WHITE))
    return runs


def draw_tracked(
    draw: ImageDraw.ImageDraw,
    runs: list[tuple[str, tuple[int, int, int]]],
    font: ImageFont.FreeTypeFont,
    origin: tuple[int, int],
    tracking: int,
    space: int,
) -> int:
    """Draw coloured runs letter by letter so tracking is real. Returns the width drawn."""
    x, y = origin
    start = x
    for i, (word, colour) in enumerate(runs):
        for ch in word:
            draw.text((x, y), ch, font=font, fill=colour)
            x += int(draw.textlength(ch, font=font)) + tracking
        if i < len(runs) - 1:
            x += space
    return x - start


def measure_tracked(
    draw: ImageDraw.ImageDraw,
    runs: list[tuple[str, tuple[int, int, int]]],
    font: ImageFont.FreeTypeFont,
    tracking: int,
    space: int,
) -> int:
    width = 0
    for i, (word, _) in enumerate(runs):
        for ch in word:
            width += int(draw.textlength(ch, font=font)) + tracking
        if i < len(runs) - 1:
            width += space
    return width


def frame(
    shot_path: str,
    out_path: str,
    caption: str,
    sub: str | None = None,
    gold_words: set[str] | None = None,
    band: str = "bottom",
) -> str:
    if "—" in caption or (sub and "—" in sub):
        raise SystemExit("No em dashes in store copy. Rewrite the caption.")

    gold_words = DEFAULT_GOLD_WORDS if gold_words is None else gold_words
    caption = caption.upper()

    shot = Image.open(shot_path).convert("RGB")
    if shot.size != (SHOT_W, SHOT_H):
        shot = shot.resize((SHOT_W, SHOT_H), Image.LANCZOS)

    band_h = 320 if sub else 236
    band_y = SHOT_H - band_h if band == "bottom" else 0

    # Translucent dark glass: blur what is behind the band, then darken it.
    region = shot.crop((0, band_y, SHOT_W, band_y + band_h))
    region = region.filter(ImageFilter.GaussianBlur(28))
    glass = Image.new("RGB", region.size, GLASS)
    region = Image.blend(region, glass, 0.84)
    shot.paste(region, (0, band_y))

    draw = ImageDraw.Draw(shot)

    # Thin light edge on the side of the band that faces the picture.
    edge_y = band_y if band == "bottom" else band_y + band_h - 2
    draw.rectangle([(0, edge_y), (SHOT_W, edge_y + 1)], fill=EDGE)

    # Caption, shrunk to fit the safe width if it is long.
    size = 112
    tracking, space = 5, 28
    runs = tracked_runs(caption, gold_words)
    safe = SHOT_W - 320
    while size > 56:
        font = load_font(size)
        if measure_tracked(draw, runs, font, tracking, space) <= safe:
            break
        size -= 4
    font = load_font(size)

    # Lay the lines out on real cap heights so the band is optically centred.
    cap_h = font.getbbox("H")[3] - font.getbbox("H")[1]
    sub_font = load_font(int(size * 0.44), bold=False) if sub else None
    sub_runs = tracked_runs(sub.upper(), gold_words) if sub else []
    sub_cap = (sub_font.getbbox("H")[3] - sub_font.getbbox("H")[1]) if sub else 0
    gap = int(size * 0.34) if sub else 0

    block_h = cap_h + gap + sub_cap
    top = band_y + (band_h - block_h) // 2

    width = measure_tracked(draw, runs, font, tracking, space)
    draw_tracked(
        draw,
        runs,
        font,
        ((SHOT_W - width) // 2, top - font.getbbox("H")[1]),
        tracking,
        space,
    )

    if sub:
        sub_w = measure_tracked(draw, sub_runs, sub_font, 4, 20)
        draw_tracked(
            draw,
            sub_runs,
            sub_font,
            ((SHOT_W - sub_w) // 2, top + cap_h + gap - sub_font.getbbox("H")[1]),
            4,
            20,
        )

    shot.convert("RGB").save(out_path, format="PNG", optimize=True)
    return out_path


def main() -> int:
    p = argparse.ArgumentParser(description="Add a Roboteer caption band to a screenshot.")
    p.add_argument("shot")
    p.add_argument("out")
    p.add_argument("caption")
    p.add_argument("--sub", default=None)
    p.add_argument("--gold", default=None, help="comma separated words to render in gold")
    p.add_argument("--band", default="bottom", choices=["top", "bottom"])
    p.add_argument("--check", action="store_true")
    a = p.parse_args()

    gold = None
    if a.gold:
        gold = {w.strip().upper() for w in a.gold.split(",") if w.strip()}

    out = frame(a.shot, a.out, a.caption, sub=a.sub, gold_words=gold, band=a.band)

    if a.check:
        done = Image.open(out)
        ok = done.size == (SHOT_W, SHOT_H) and done.mode == "RGB"
        print(f"{out}: {done.size[0]}x{done.size[1]} mode={done.mode} ok={ok}")
        return 0 if ok else 1

    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
