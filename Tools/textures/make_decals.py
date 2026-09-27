#!/usr/bin/env python3
"""make_decals.py - the machine marking decals (wave A, materials lead).

Procedural, so every mark is invented and nothing is traced from a real brand:
lettering is set in Saira Stencil One (SIL OFL, shipped in Arena/assets/fonts; the decals
baked before 2026-09-27 were cut from Barlow Condensed ExtraBold, since removed),
cut with stencil bridges and sprayed (soft overspray edge, speckle, chips), and the
emblems are drawn from plain geometry. A Recraft attempt at a stencil sheet came back
with tanks, soldiers and misspelt words (4 credits, notes 5), which is why.

Every stencil is a WHITE mark on transparent, so the Decal node's `modulate` picks its
paint colour per machine (white on dark liveries, black on pale ones). The hazard stripe
and the grime carry their own colour.

Outputs, Arena/assets/textures/decals/ (RGBA, sRGB albedo for Decal.texture_albedo):

  decal_hazard_stripe.png   1024 x 256  yellow and black 45 deg bands, chipped
  decal_kestrel_works.png    512 x 256  invented maker's mark: hawk chevron + wordmark
  decal_torq9.png            512 x 128  model code "TORQ-9"
  decal_lift_point.png       256 x 256  ringed arrow + "LIFT POINT"
  decal_high_voltage.png     256 x 256  bolt triangle + "HIGH VOLTAGE"
  decal_no_step.png          256 x 128  "NO STEP" with a bar
  decal_bolt_grime.png       256 x 256  oily ring round a bolt with a run below it

Usage: python3 Tools/textures/make_decals.py
"""

from __future__ import annotations

import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "Arena", "assets", "textures", "decals")
FONT = os.path.join(ROOT, "Arena", "assets", "fonts", "SairaStencilOne-Regular.ttf")
SS = 4  # supersample


def font(px: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT, px * SS)


def canvas(w: int, h: int) -> Image.Image:
    return Image.new("L", (w * SS, h * SS), 0)


def text_centered(draw: ImageDraw.ImageDraw, box, text: str, px: int, tracking: float = 0.04):
    """Draw tracked text centred in box (x0, y0, x1, y1), all in supersampled px."""
    f = font(px)
    widths = [draw.textlength(c, font=f) for c in text]
    track = px * SS * tracking
    total = sum(widths) + track * (len(text) - 1)
    asc, desc = f.getmetrics()
    x = (box[0] + box[2]) / 2 - total / 2
    y = (box[1] + box[3]) / 2 - (asc + desc) / 2 - desc * 0.15
    for c, w in zip(text, widths):
        draw.text((x, y), c, font=f, fill=255)
        x += w + track
    return (box[1] + box[3]) / 2, px * SS


def stencil_bridges(mask: Image.Image, centre_y: float, cap: float, width: float = 0.075):
    """Cut one horizontal bridge through the lettering at mid cap height."""
    d = ImageDraw.Draw(mask)
    half = cap * width / 2
    d.rectangle([0, centre_y - half, mask.width, centre_y + half], fill=0)


def spray(mask: Image.Image, w: int, h: int, seed: int, overspray: float = 1.2,
          chips: float = 0.06, colour=(255, 255, 255)) -> Image.Image:
    """Downsample, soften the edge like a sprayed stencil, speckle it, chip it."""
    rng = np.random.default_rng(seed)
    a = np.asarray(mask.resize((w, h), Image.LANCZOS), dtype=np.float64) / 255.0
    soft = np.asarray(Image.fromarray((a * 255).astype(np.uint8))
                      .filter(ImageFilter.GaussianBlur(overspray)), dtype=np.float64) / 255.0
    # Overspray: a faint halo outside the hard edge, speckled.
    halo = np.clip(soft - a, 0, 1) * (rng.random((h, w)) < 0.35) * 0.5
    alpha = np.maximum(a, halo)
    # Chips: blotchy holes, larger near nothing in particular (paint worn off).
    n = rng.standard_normal((h // 4 + 1, w // 4 + 1))
    n = np.asarray(Image.fromarray(((n - n.min()) / (np.ptp(n) + 1e-9) * 255).astype(np.uint8))
                   .resize((w, h), Image.BICUBIC).filter(ImageFilter.GaussianBlur(1.5)),
                   dtype=np.float64) / 255.0
    alpha *= np.where(n > 1.0 - chips, 0.0, 1.0)
    # Density variation: a sprayed coat is never quite even.
    alpha *= 0.82 + 0.18 * rng.random((h, w)) ** 0.3
    rgba = np.zeros((h, w, 4), dtype=np.uint8)
    rgba[..., 0], rgba[..., 1], rgba[..., 2] = colour
    rgba[..., 3] = np.clip(alpha * 255, 0, 255).astype(np.uint8)
    return Image.fromarray(rgba)


def save(img: Image.Image, name: str) -> None:
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    img.save(path, optimize=True)
    print("wrote", os.path.relpath(path, ROOT), img.size)


# ---------------------------------------------------------------- marks

def hazard_stripe():
    w, h = 1024, 256
    rng = np.random.default_rng(3)
    yy, xx = np.mgrid[0:h, 0:w]
    band = ((xx + yy) // 128) % 2  # 45 deg, 128 px period over 256 = seamless along U
    yellow = np.array([0.93, 0.70, 0.05])
    black = np.array([0.04, 0.04, 0.045])
    rgb = np.where(band[..., None] == 0, yellow, black)
    # Wear: chips expose nothing (alpha 0) so the livery or metal under it shows.
    n = rng.standard_normal((h // 8, w // 8))
    n = np.asarray(Image.fromarray(((n - n.min()) / np.ptp(n) * 255).astype(np.uint8))
                   .resize((w, h), Image.BICUBIC).filter(ImageFilter.GaussianBlur(2)),
                   dtype=np.float64) / 255.0
    edge = np.minimum(yy, h - 1 - yy) / (h * 0.5)  # 0 at top/bottom edge
    wear = n + (1.0 - edge) ** 8 * 0.3
    alpha = np.where(wear > 0.9, 0.0, 1.0)
    alpha *= np.clip(edge * 40, 0, 1)  # crisp masked edge, 1 px soft
    grime = 1.0 - 0.18 * np.asarray(Image.fromarray((n * 255).astype(np.uint8))
                                    .filter(ImageFilter.GaussianBlur(10)), dtype=np.float64) / 255.0
    rgb = rgb * grime[..., None]
    srgb = np.clip(rgb, 0, 1) ** (1 / 2.2)
    out = np.dstack([srgb * 255, alpha * 255]).astype(np.uint8)
    save(Image.fromarray(out), "decal_hazard_stripe.png")


def kestrel_works():
    w, h = 512, 256
    m = canvas(w, h)
    d = ImageDraw.Draw(m)
    S = SS
    # Hawk chevron: two nested chevrons with a beak notch, invented.
    cx, top = 256 * S, 26 * S
    outer = [(cx - 70 * S, top), (cx, top + 64 * S), (cx + 70 * S, top),
             (cx + 70 * S, top + 26 * S), (cx, top + 92 * S), (cx - 70 * S, top + 26 * S)]
    d.polygon(outer, fill=255)
    inner = [(cx - 40 * S, top + 8 * S), (cx, top + 48 * S), (cx + 40 * S, top + 8 * S)]
    d.polygon(inner, fill=0)
    d.polygon([(cx - 8 * S, top + 70 * S), (cx, top + 104 * S), (cx + 8 * S, top + 70 * S)], fill=255)
    cy, cap = text_centered(d, (0, 150 * S, w * S, 222 * S), "KESTREL WORKS", 64, 0.06)
    stencil_bridges(m, cy + cap * 0.02, cap * 0.62)
    save(spray(m, w, h, 11), "decal_kestrel_works.png")


def torq9():
    w, h = 512, 128
    m = canvas(w, h)
    d = ImageDraw.Draw(m)
    cy, cap = text_centered(d, (0, 0, w * SS, h * SS), "TORQ-9", 104, 0.08)
    stencil_bridges(m, cy + cap * 0.02, cap * 0.62)
    save(spray(m, w, h, 12), "decal_torq9.png")


def lift_point():
    w, h = 256, 256
    m = canvas(w, h)
    d = ImageDraw.Draw(m)
    S = SS
    c, r = 128 * S, 70 * S
    d.ellipse([c - r, 88 * S - r, c + r, 88 * S + r], outline=255, width=12 * S)
    d.polygon([(c, 40 * S), (c - 34 * S, 86 * S), (c - 12 * S, 86 * S), (c - 12 * S, 126 * S),
               (c + 12 * S, 126 * S), (c + 12 * S, 86 * S), (c + 34 * S, 86 * S)], fill=255)
    cy, cap = text_centered(d, (0, 176 * S, w * S, 244 * S), "LIFT POINT", 52, 0.06)
    stencil_bridges(m, cy + cap * 0.02, cap * 0.62)
    save(spray(m, w, h, 13), "decal_lift_point.png")


def high_voltage():
    w, h = 256, 256
    m = canvas(w, h)
    d = ImageDraw.Draw(m)
    S = SS
    tri = [(128 * S, 14 * S), (218 * S, 166 * S), (38 * S, 166 * S)]
    d.polygon(tri, fill=255)
    d.polygon([(128 * S, 44 * S), (190 * S, 150 * S), (66 * S, 150 * S)], fill=0)
    d.polygon([(136 * S, 66 * S), (108 * S, 112 * S), (126 * S, 112 * S), (116 * S, 144 * S),
               (148 * S, 96 * S), (130 * S, 96 * S), (142 * S, 66 * S)], fill=255)
    cy, cap = text_centered(d, (0, 180 * S, w * S, 246 * S), "HIGH VOLTAGE", 46, 0.04)
    stencil_bridges(m, cy + cap * 0.02, cap * 0.62)
    save(spray(m, w, h, 14), "decal_high_voltage.png")


def no_step():
    w, h = 256, 128
    m = canvas(w, h)
    d = ImageDraw.Draw(m)
    S = SS
    cy, cap = text_centered(d, (0, 8 * S, w * S, 92 * S), "NO STEP", 60, 0.08)
    stencil_bridges(m, cy + cap * 0.02, cap * 0.62)
    d.rectangle([22 * S, 102 * S, 234 * S, 114 * S], fill=255)
    save(spray(m, w, h, 15), "decal_no_step.png")


def bolt_grime():
    w = h = 256
    rng = np.random.default_rng(21)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
    cx, cy = 128.0, 96.0
    r = np.hypot(xx - cx, yy - cy)
    ring = np.exp(-((r - 26) / 14) ** 2) * 0.8 + np.exp(-(r / 30) ** 2) * 0.35
    # A run: oil and dust weeping down (+V, which the placer orients to gravity).
    run_w = 10 + (yy - cy) * 0.06
    run = np.exp(-((xx - cx - 2 * np.sin(yy / 17)) / np.maximum(run_w, 1)) ** 2) \
        * np.clip((yy - cy) / 20, 0, 1) * np.clip(1 - (yy - cy) / 150, 0, 1) * 0.55
    a = np.clip(ring + run, 0, 1)
    n = rng.random((h, w))
    a *= 0.7 + 0.3 * n
    a = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2)),
                   dtype=np.float64) / 255.0
    edge = np.clip(np.minimum.reduce([xx, yy, w - 1 - xx, h - 1 - yy]) / 12, 0, 1)
    a *= edge
    col = np.array([34, 28, 22], dtype=np.float64)  # oily brown-black, sRGB
    out = np.zeros((h, w, 4), dtype=np.uint8)
    out[..., :3] = col
    out[..., 3] = np.clip(a * 235, 0, 255).astype(np.uint8)
    save(Image.fromarray(out), "decal_bolt_grime.png")


def main() -> int:
    hazard_stripe()
    kestrel_works()
    torq9()
    lift_point()
    high_voltage()
    no_step()
    bolt_grime()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
