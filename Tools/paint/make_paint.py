#!/usr/bin/env python3
"""make_paint.py - the ten cosmetic paint jobs of brief v5 section 7.

Each paint job ships as ONE tileable 1024 overlay,
`Arena/assets/textures/paint/<id>_albedo.png`: greyscale in RGB, coverage in
alpha. At runtime `Arena/bot/livery.gd` hangs it on the livery material as a
Godot DETAIL map over the player's own colour, so one texture serves every
livery. Four of them (carbon, hex, chequer, circuit) also ship a
`<id>_normal.png`, because those four are relief and not just paint.

Two blend modes are used, and which one a paint job takes decides what the
texture has to contain:

  MIX  ALBEDO = mix(livery, overlay_rgb, overlay_a)
       The overlay carries its OWN value. Black stripes, white racing stripes,
       carbon black, bright circuit traces. Alpha 0 means the livery shows.
  MUL  ALBEDO = mix(livery, livery * overlay_rgb, overlay_a)
       The overlay only shades the livery, so the paint stays the player's
       colour. Camo, hex plate, and the two metals' micro detail. 1.0 means
       leave the livery exactly as it was; it can darken, never brighten.

Tiling is not left to chance. Every pattern here either divides 1024 exactly
(hazard 256, chequer 128, carbon 128, hex 128 x 102.4, racing 1024) or is drawn
on a torus (circuit, the noise fields), and the two Recraft-sourced patterns
(camo, flames) are mirror-blended and then re-quantised so the wrap is exact
rather than merely blended. `--check` prints the seam numbers the way
docs/graphics-textures-notes.md does.

    python3 Tools/paint/make_paint.py           # build everything
    python3 Tools/paint/make_paint.py --check   # build, then print seam numbers

Sources: Tools/paint/sources/*.png, five picked Recraft generations (16
credits). Everything else is drawn here.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SOURCES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sources")
TEXTURES = os.path.join(ROOT, "Arena", "assets", "textures", "paint")
PREVIEWS = os.path.join(ROOT, "Art", "paint")

SIZE = 1024
PREVIEW = 512

# The preview panel is deliberately NEUTRAL: the picker is showing the pattern,
# not a colour the player may not have chosen. Steel grey, mid value, no hue of
# its own to fight the paint.
PREVIEW_LIVERY = (0.42, 0.45, 0.49)


# ------------------------------------------------------------------ helpers

def _load(name: str) -> np.ndarray:
    """A source generation as a 0..1 greyscale array at SIZE."""
    path = os.path.join(SOURCES, name)
    image = Image.open(path).convert("L")
    if image.size != (SIZE, SIZE):
        image = image.resize((SIZE, SIZE), Image.LANCZOS)
    return np.asarray(image, dtype=np.float64) / 255.0


def wrap_blur(a: np.ndarray, sigma: float) -> np.ndarray:
    """Gaussian blur that wraps at both borders, so a blurred tile still tiles."""
    if sigma <= 0:
        return a.copy()
    radius = int(max(1, round(sigma * 3)))
    x = np.arange(-radius, radius + 1, dtype=np.float64)
    kernel = np.exp(-(x * x) / (2 * sigma * sigma))
    kernel /= kernel.sum()
    out = np.zeros_like(a)
    for i, k in zip(range(-radius, radius + 1), kernel):
        out += k * np.roll(a, i, axis=1)
    rolled = out
    out = np.zeros_like(a)
    for i, k in zip(range(-radius, radius + 1), kernel):
        out += k * np.roll(rolled, i, axis=0)
    return out


def flatten(a: np.ndarray, sigma: float) -> np.ndarray:
    """Divide out the generator's studio lighting, keeping the mean.

    docs/graphics-textures-notes.md: tiled, a soft lighting gradient reads as a
    regular grid of light and dark patches, which is louder than any seam.
    """
    base = wrap_blur(a, sigma)
    base = np.maximum(base, 1e-3)
    return np.clip(a / base * a.mean(), 0.0, 1.0)


def detail_of(a: np.ndarray, sigma: float) -> np.ndarray:
    """The high frequency half of a field, centred on zero."""
    return a - wrap_blur(a, sigma)


def seamless(a: np.ndarray, band: float = 0.07) -> np.ndarray:
    """Mirror blend the borders so column 0 and column w-1 become identical.

    The exact trick from G2: near the left edge blend with the left-right
    mirror on a cosine ramp that is 0.5 at the border. At x=0 the mirror
    supplies column w-1 and at x=w-1 it supplies column 0, so both land on the
    same value by construction.
    """
    out = a.copy()
    size = a.shape[0]
    width = max(2, int(round(size * band)))
    ramp = 0.5 * (1.0 + np.cos(np.pi * np.arange(width) / width))  # 1 -> 0
    weight = 0.5 * ramp

    mirrored = out[:, ::-1]
    w = weight[np.newaxis, :]
    left = out[:, :width] * (1 - w) + mirrored[:, :width] * w
    right = out[:, size - width:] * (1 - w[:, ::-1]) + mirrored[:, size - width:] * w[:, ::-1]
    out[:, :width] = left
    out[:, size - width:] = right

    mirrored = out[::-1, :]
    w = weight[:, np.newaxis]
    top = out[:width, :] * (1 - w) + mirrored[:width, :] * w
    bottom = out[size - width:, :] * (1 - w[::-1]) + mirrored[size - width:, :] * w[::-1]
    out[:width, :] = top
    out[size - width:, :] = bottom
    return out


def roll_to_dense(a: np.ndarray, band: float, dark_is_content: bool = True) -> np.ndarray:
    """Roll a pattern so its BUSIEST rows and columns land on the tile border.

    A stencil generation has empty margins, and a mirror blend keeps whatever
    it is given: blend two empty margins and the wrap carries a clean band of
    bare paint right across the machine, once per tile, which is the loudest
    tiling tell there is. Rolling the content first costs nothing and puts a
    dense band where the join will be.
    """
    content = (1.0 - a) if dark_is_content else a
    size = a.shape[0]
    width = max(2, int(round(size * band)))
    rows = content.mean(axis=1)
    cols = content.mean(axis=0)

    def best_offset(profile):
        # Density of the two bands the wrap will sit between, for every roll.
        doubled = np.concatenate([profile, profile])
        window = np.convolve(doubled, np.ones(width * 2), mode="valid")[:size]
        # The band straddling the border is rows [-width, +width) after rolling
        # by k, which is window[(k - width) % size].
        return int(np.argmax(np.roll(window, width)))

    return np.roll(np.roll(a, -best_offset(rows), axis=0), -best_offset(cols), axis=1)


def quantise(a: np.ndarray, levels: np.ndarray) -> np.ndarray:
    """Snap every value to the nearest of `levels`.

    Run AFTER the mirror blend, this is what makes a flat-toned pattern (camo,
    a flame stencil) wrap EXACTLY instead of carrying a band of in-between
    tones around the border: the two border columns are fed the same blended
    value, so they snap to the same level.
    """
    index = np.abs(a[..., np.newaxis] - levels[np.newaxis, np.newaxis, :]).argmin(axis=2)
    return levels[index]


def torus_noise(size: int, cells: int, seed: int, octaves: int = 4) -> np.ndarray:
    """Value noise that wraps exactly, 0..1, built by tiling a small lattice."""
    rng = np.random.default_rng(seed)
    total = np.zeros((size, size), dtype=np.float64)
    amplitude = 1.0
    weight = 0.0
    for octave in range(octaves):
        n = cells * (2 ** octave)
        if n > size:
            break
        lattice = rng.random((n, n))
        # Bilinear, wrapped, by upsampling the lattice with np.take(mode="wrap").
        grid = (np.arange(size) + 0.5) * n / size - 0.5
        i0 = np.floor(grid).astype(int)
        frac = grid - i0
        # Smoothstep, so the lattice corners do not show as a grid.
        frac = frac * frac * (3 - 2 * frac)
        i1 = i0 + 1
        a00 = lattice[np.ix_(i0 % n, i0 % n)]
        a01 = lattice[np.ix_(i0 % n, i1 % n)]
        a10 = lattice[np.ix_(i1 % n, i0 % n)]
        a11 = lattice[np.ix_(i1 % n, i1 % n)]
        fx = frac[np.newaxis, :]
        fy = frac[:, np.newaxis]
        value = (a00 * (1 - fx) * (1 - fy) + a01 * fx * (1 - fy)
                 + a10 * (1 - fx) * fy + a11 * fx * fy)
        total += amplitude * value
        weight += amplitude
        amplitude *= 0.5
    return total / max(weight, 1e-6)


def wrap_resize(a: np.ndarray, size: int) -> np.ndarray:
    """Resize a tiling field and keep it tiling.

    PIL clamps at the border, which quietly puts a seam back into every map
    that is downsampled. Padding with the opposite edge first means the filter
    sees the torus it is actually working on.
    """
    if a.shape[0] == size:
        return a
    pad = 16
    wide = np.pad(a, pad, mode="wrap")
    scale = size / a.shape[0]
    wide_size = int(round(wide.shape[0] * scale))
    small = np.asarray(
        Image.fromarray((np.clip(wide, 0, 1) * 255).astype(np.uint8))
        .resize((wide_size, wide_size), Image.LANCZOS), dtype=np.float64) / 255.0
    edge = int(round(pad * scale))
    return small[edge:edge + size, edge:edge + size]


def normal_from_height(height: np.ndarray, strength: float, size: int) -> Image.Image:
    """Wrapped Sobel of a height field, OpenGL convention, +Y up (Godot's).

    The Sobel is taken at full resolution and the VECTOR FIELD is what gets
    downsampled, then renormalised: averaging unit vectors shortens them, and a
    short normal reads as a flattened surface rather than a blurrier one
    (docs/graphics-textures-notes.md).
    """
    h = np.clip(height, 0, 1)
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * strength
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * strength
    # +Y up: screen y grows downward, so the green channel takes -dy.
    nx, ny, nz = -dx, dy, np.ones_like(h)
    if h.shape[0] != size:
        nx = wrap_resize(nx * 0.5 + 0.5, size) * 2.0 - 1.0
        ny = wrap_resize(ny * 0.5 + 0.5, size) * 2.0 - 1.0
        nz = np.ones_like(nx)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.stack([nx / length, ny / length, nz / length], axis=2) * 0.5 + 0.5
    return Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8))


def save_albedo(name: str, value: np.ndarray, alpha: np.ndarray) -> bool:
    """Write the overlay. Returns True when it needed an alpha channel.

    An overlay that covers the whole panel (carbon, hex, the two metals) is
    written WITHOUT alpha, because a texture with no alpha samples 1.0 and
    Godot imports it as ETC2 RGB8 at half the VRAM and half the pack size of
    the RGBA8 it would otherwise pick. Four megabytes of the pack, for a
    channel that is a constant.
    """
    rgb = (np.clip(value, 0, 1) * 255 + 0.5).astype(np.uint8)
    a = (np.clip(alpha, 0, 1) * 255 + 0.5).astype(np.uint8)
    opaque = bool(a.min() >= 254)
    if opaque:
        image = Image.fromarray(np.stack([rgb, rgb, rgb], axis=2))
    else:
        image = Image.fromarray(np.stack([rgb, rgb, rgb, a], axis=2))
    image.save(os.path.join(TEXTURES, f"{name}_albedo.png"), optimize=True)
    return not opaque


def save_normal(name: str, height: np.ndarray, strength: float, size: int) -> None:
    normal_from_height(height, strength, size).save(
        os.path.join(TEXTURES, f"{name}_normal.png"), optimize=True)


def hash_field(cells: np.ndarray, seed: int) -> np.ndarray:
    """A stable 0..1 value per integer cell id, so a plate always looks the same."""
    x = (cells.astype(np.int64) * 0x9E3779B1 + seed * 0x85EBCA6B) & 0xFFFFFFFF
    x = (x ^ (x >> 15)) * 0x2545F491 & 0xFFFFFFFF
    x = x ^ (x >> 13)
    return (x & 0xFFFF) / 65535.0


XX, YY = np.meshgrid(np.arange(SIZE), np.arange(SIZE))


def aa_step(edge: np.ndarray, width: float = 1.4) -> np.ndarray:
    """0 below the edge, 1 above, with `width` pixels of antialiasing."""
    return np.clip(edge / width + 0.5, 0.0, 1.0)


# ------------------------------------------------------------ the wear layer

def wear_fields() -> tuple[np.ndarray, np.ndarray]:
    """(swirl, chips): the two Recraft wear generations, flattened and tiled.

    One wear layer serves all ten. It is what stops a drawn pattern reading as
    a vector graphic: real paint has polish swirls in it and real edges chip.
    """
    swirl = seamless(flatten(_load("wear_swirl.png"), 26.0), band=0.06)
    chips = seamless(flatten(_load("wear_chips.png"), 26.0), band=0.06)
    return swirl, chips


# --------------------------------------------------------------- paint jobs

def build_hazard(swirl, chips):
    """Level 10. Black hazard stripes at 45 degrees, chipped at the edges.

    Period 256 px along (x+y). 1024 % 256 == 0, so the stripes wrap exactly in
    both axes with no blending at all, the way the arena chevron does.
    """
    period = 256.0
    t = ((XX + YY) % period) / period
    # Distance in pixels to the nearer stripe edge, positive inside the stripe.
    inside = np.minimum(t, 0.5 - t) * period
    inside = np.where(t < 0.5, inside, -np.minimum(t - 0.5, 1.0 - t) * period)
    alpha = aa_step(inside, 1.6)

    # Chipping: the brightest specks of the chip generation eat the paint, and
    # only near an edge, which is where paint actually lets go.
    chip = np.clip((chips - 0.62) * 5.0, 0, 1)
    near_edge = np.clip(1.0 - np.abs(inside) / 9.0, 0, 1)
    alpha = np.clip(alpha - chip * near_edge * 0.9, 0, 1)

    value = 0.048 + 0.085 * np.clip(swirl - 0.45, -0.4, 0.4) + 0.03 * chip
    return np.clip(value, 0.02, 0.35), alpha


def build_racing(swirl, chips):
    """Level 20. One pair of broad stripes with pinstripe liners, per tile.

    Runs along the texture's y axis and repeats once across x, so a chassis
    panel carries one stripe pair at the kit's texel density.
    """
    u = XX / SIZE
    value = np.zeros_like(u)
    alpha = np.zeros_like(u)

    def stripe(centre, half, tone, cover_it=True):
        d = np.abs(((u - centre + 0.5) % 1.0) - 0.5) * SIZE
        cover = aa_step(half * SIZE - d, 1.4)
        np.copyto(value, tone, where=cover > 0.5)
        if cover_it:
            np.maximum(alpha, cover, out=alpha)
        else:
            np.minimum(alpha, 1.0 - cover, out=alpha)

    # A Le Mans twin stripe: two broad pale stripes with a thin dark liner
    # outside each, and the machine's OWN colour showing down the middle.
    stripe(0.3800, 0.0045, 0.06)
    stripe(0.4400, 0.0500, 0.88)
    stripe(0.5600, 0.0500, 0.88)
    stripe(0.6200, 0.0045, 0.06)
    stripe(0.5000, 0.0100, 0.0, cover_it=False)

    # A racing stripe is sprayed, not printed: the value moves under the clear
    # coat and the edge is not a perfect line.
    value = value + 0.07 * np.clip(swirl - 0.5, -0.5, 0.5) * (alpha > 0)
    chip = np.clip((chips - 0.70) * 6.0, 0, 1)
    alpha = np.clip(alpha - chip * 0.35, 0, 1)
    return np.clip(value, 0.02, 1.0), alpha


def build_camo(swirl, chips):
    """Level 30. Four tone disruptive camo, in the machine's own colour.

    MUL, so the pattern shades the livery rather than replacing it: a works
    team's camo scheme, not a borrowed army's.
    """
    source = seamless(_load("camo.png"), band=0.08)
    tones = np.array([0.0, 0.34, 0.62, 1.0])
    snapped = quantise(source, tones)
    # 1.0 leaves the livery alone; the others take it down in real steps.
    factor = np.select(
        [snapped == 0.0, snapped == 0.34, snapped == 0.62],
        [0.30, 0.52, 0.76], default=1.0)
    factor = wrap_blur(factor, 0.7)                     # one pixel of antialiasing
    factor = factor * (0.97 + 0.06 * swirl)             # sprayed, not printed
    # The chips go into the VALUE, not into alpha. Camo covers the whole panel, so an
    # alpha channel carrying nothing but a few specks would cost this one texture an
    # extra 700 KB of ETC2 RGBA in the pack for a mark MUL can make on its own.
    chip = np.clip((chips - 0.74) * 6.0, 0, 1)
    factor = factor + chip * 0.22 * (1.0 - factor)
    return np.clip(factor, 0.0, 1.0), np.ones_like(factor)


def build_chequer(swirl, chips):
    """Level 40. Chequered vinyl over the livery, 128 px squares, with relief."""
    cell = 128
    dark = (((XX // cell) + (YY // cell)) % 2) == 0
    # Antialias by distance to the square boundary rather than by blurring the
    # mask, so the wrap stays exact.
    fx = (XX % cell) - cell / 2.0
    fy = (YY % cell) - cell / 2.0
    edge = cell / 2.0 - np.maximum(np.abs(fx), np.abs(fy))
    # Signed: positive inside a dark square, negative inside a light one, so
    # one aa_step covers both sides of every boundary continuously.
    signed = np.where(dark, edge, -edge)
    alpha = np.clip(aa_step(signed, 1.4), 0, 1)

    chip = np.clip((chips - 0.68) * 5.0, 0, 1)
    near_edge = np.clip(1.0 - edge / 7.0, 0, 1)
    alpha = np.clip(alpha - chip * near_edge * 0.8, 0, 1)

    value = 0.055 + 0.09 * np.clip(swirl - 0.45, -0.4, 0.4)
    # The vinyl has thickness: a soft lip at the edge of every dark square.
    height = np.clip(edge / 5.0, 0, 1) * dark
    height = wrap_blur(height, 1.6)
    return np.clip(value, 0.02, 0.4), alpha, height


def build_flames(swirl, chips):
    """Level 50. A hot rod flame job: black licks with a pale pinstripe."""
    source = seamless(roll_to_dense(_load("flames.png"), 0.07), band=0.07)
    # Quantise AFTER the mirror blend: both border columns are fed the same
    # blended value, so they snap to the same level and the wrap is exact.
    mask = 1.0 - quantise(source, np.array([0.0, 1.0]))   # 1 where the flame is

    # The pinstripe: a ring just outside the flame, which is what makes a flame
    # job read as paint rather than as a sticker.
    grown = wrap_blur(mask, 2.0)
    outline = np.clip((grown - 0.10) * 9.0, 0, 1) * (1.0 - mask)
    outline = np.clip(outline, 0, 1)

    alpha = np.clip(mask + outline, 0, 1)
    value = np.where(mask > 0.5,
                     0.055 + 0.09 * np.clip(swirl - 0.45, -0.4, 0.4),
                     0.80 - 0.12 * (1 - outline))
    chip = np.clip((chips - 0.72) * 6.0, 0, 1)
    alpha = np.clip(alpha - chip * 0.3, 0, 1)
    return np.clip(value, 0.02, 1.0), alpha


def build_carbon(swirl, chips):
    """Level 60. Real 2x2 twill, drawn tow by tow, under the clear coat.

    Tow 32 px, twill period 128 px, and 1024 % 128 == 0, so it wraps exactly.
    """
    tow = 16
    cx = XX // tow
    cy = YY // tow
    # 2x2 twill, drawn the way it photographs: blocks two tows square, the
    # fibre direction turning 90 degrees from block to block. A strict float
    # pattern gives a herringbone on a flat panel; this gives the weave a
    # player recognises as carbon.
    warp_on_top = (((cx // 2) + (cy // 2)) % 2) == 0

    across_h = ((YY % tow) + 0.5) / tow          # across a horizontal tow
    across_v = ((XX % tow) + 0.5) / tow
    along_h = XX.astype(np.float64)
    along_v = YY.astype(np.float64)

    across = np.where(warp_on_top, across_v, across_h)
    along = np.where(warp_on_top, along_v, along_h)

    # The tow is a rounded bundle: bright along its crown, dark at its edges.
    crown = np.sin(np.pi * np.clip(across, 0, 1)) ** 0.8
    # Individual filaments, 4 px apart (a whole number of them per tile),
    # running ALONG the tow.
    filament = 0.5 + 0.5 * np.sin(along * (2 * np.pi / 4.0))
    # The block itself sits slightly proud where its tows pass over.
    block = np.sin(np.pi * np.clip(((np.where(warp_on_top, XX, YY) % (tow * 2)) + 0.5)
                                   / (tow * 2), 0, 1)) ** 0.5

    value = 0.028 + 0.130 * crown * (0.72 + 0.28 * block) + 0.042 * crown * filament
    value += 0.05 * np.clip(swirl - 0.5, -0.5, 0.5)     # clear coat swirl
    alpha = np.ones_like(value)
    height = crown * (0.55 + 0.30 * block) + 0.15 * filament * crown
    return np.clip(value, 0.015, 0.55), alpha, height


def build_chrome(swirl, chips):
    """Level 70. Mirror chrome: this one is almost entirely material.

    The overlay only carries the polish swirl, multiplied over a chrome albedo
    that livery.gd sets, with metallic 1.0 and a roughness far below anything
    the hdpe base could reach.
    """
    swirls = 0.5 + detail_of(swirl, 6.0) * 2.2
    value = np.clip(0.94 + (swirls - 0.5) * 0.10, 0.80, 1.0)
    # A few long polishing strokes, so it is not uniform noise.
    # 3 cycles across x and 1 up y: whole cycles, so the stroke wraps exactly.
    strokes = 0.5 + 0.5 * np.sin((XX * 3 + YY * 1) * (2 * np.pi / SIZE))
    value = np.clip(value - 0.035 * (1 - strokes), 0.78, 1.0)
    return value, np.ones_like(value)


def build_circuit(swirl, chips):
    """Level 80. Printed circuit traces, drawn on a torus so they wrap.

    Recraft draws circuit boards with invented lettering on them, which is
    exactly what a texture must not have, so this one is generated: a random
    walk on a 64 px lattice with pads at the turns, seeded once and therefore
    the same every build.
    """
    cell = 64
    nodes = SIZE // cell
    rng = np.random.default_rng(20260921)

    image = Image.new("L", (SIZE, SIZE), 0)
    relief = Image.new("L", (SIZE, SIZE), 0)
    draw = ImageDraw.Draw(image)
    draw_relief = ImageDraw.Draw(relief)

    def wrapped(fn, x0, y0, x1, y1, **kw):
        for ox in (-SIZE, 0, SIZE):
            for oy in (-SIZE, 0, SIZE):
                fn((x0 + ox, y0 + oy, x1 + ox, y1 + oy), **kw)

    def trace(ax, ay, bx, by, width):
        for target, draw_on in ((image, draw), (relief, draw_relief)):
            wrapped(draw_on.line, ax, ay, bx, by, fill=255, width=width)

    def pad(x, y, radius, hole):
        for draw_on in (draw, draw_relief):
            wrapped(draw_on.ellipse, x - radius, y - radius, x + radius, y + radius, fill=255)
        if hole > 0:
            wrapped(draw.ellipse, x - hole, y - hole, x + hole, y + hole, fill=0)
            wrapped(draw_relief.ellipse, x - hole, y - hole, x + hole, y + hole, fill=0)

    steps = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)]
    for _ in range(46):
        gx, gy = int(rng.integers(nodes)), int(rng.integers(nodes))
        direction = steps[int(rng.integers(len(steps)))]
        width = 5 if rng.random() < 0.65 else 8
        for leg in range(int(rng.integers(2, 6))):
            length = int(rng.integers(1, 4))
            nx, ny = gx + direction[0] * length, gy + direction[1] * length
            trace(gx * cell + cell // 2, gy * cell + cell // 2,
                  nx * cell + cell // 2, ny * cell + cell // 2, width)
            gx, gy = nx % nodes, ny % nodes
            if leg == 0 or rng.random() < 0.4:
                pad(gx * cell + cell // 2, gy * cell + cell // 2,
                    int(width * 1.9), int(width * 0.7))
            # Turn, mostly by 45 degrees, which is how a board is actually routed.
            choice = rng.random()
            if choice < 0.45:
                direction = steps[int(rng.integers(len(steps)))]

    traces = np.asarray(image, dtype=np.float64) / 255.0
    height = np.asarray(relief.filter(ImageFilter.GaussianBlur(1.2)),
                        dtype=np.float64) / 255.0

    # The solder mask under the traces: a fine hatched grid, barely there, which
    # is what stops the bare livery between traces looking empty.
    hatch = ((XX % cell < 1.6) | (YY % cell < 1.6)).astype(np.float64)
    value = np.where(traces > 0.5, 0.80 + 0.12 * np.clip(swirl - 0.5, -0.5, 0.5), 0.34)
    alpha = np.clip(traces + hatch * 0.22, 0, 1)
    chip = np.clip((chips - 0.76) * 6.0, 0, 1)
    alpha = np.clip(alpha - chip * 0.25, 0, 1)
    return np.clip(value, 0.1, 1.0), alpha, height


def build_hex(swirl, chips):
    """Level 90. Hexagonal armour plate, seamed and chamfered.

    The lattice is a=(128, 0), b=(64, 102.4). (1024, 0) = 8a and (0, 1024) =
    10b - 5a, so both wraps land exactly on a lattice point: the hexes are
    squashed 7.6 % against a regular hexagon, which no eye finds and which buys
    an exact tile.
    """
    ax, ay = 128.0, 0.0
    bx, by = 64.0, 102.4
    # Inverse of the lattice matrix [[ax, bx], [ay, by]].
    det = ax * by - bx * ay
    inv = np.array([[by, -bx], [-ay, ax]]) / det
    u = inv[0, 0] * XX + inv[0, 1] * YY
    v = inv[1, 0] * XX + inv[1, 1] * YY
    ui, vi = np.round(u), np.round(v)

    best = np.full(XX.shape, 1e9)
    second = np.full(XX.shape, 1e9)
    best_id = np.zeros(XX.shape, dtype=np.int64)
    for du in (-1, 0, 1):
        for dv in (-1, 0, 1):
            cu, cv = ui + du, vi + dv
            px = cu * ax + cv * bx
            py = cu * ay + cv * by
            d = np.hypot(XX - px, YY - py)
            # The tile is 8a across and 10b - 5a up, so a plate id has to be
            # invariant under (cu, cv) -> (cu + 8, cv) AND -> (cu - 5, cv + 10),
            # or the plate to plate variation puts a seam back in.
            ci = cu.astype(np.int64)
            cj = cv.astype(np.int64)
            cjm = cj % 10
            cell_id = ((ci + 5 * ((cj - cjm) // 10)) % 8) * 10 + cjm
            closer = d < best
            second = np.where(closer, best, np.minimum(second, d))
            best_id = np.where(closer, cell_id, best_id)
            best = np.where(closer, d, best)
    edge = (second - best) * 0.5          # pixels to the nearest cell boundary

    seam = aa_step(edge - 2.4, 1.4)                       # 0 in the seam
    chamfer = np.clip((edge - 2.4) / 9.0, 0, 1) ** 0.7    # the bevel shading
    plate = 0.93 + 0.07 * hash_field(best_id, 7)          # plate to plate variation
    value = (0.30 + 0.70 * seam) * (0.80 + 0.20 * chamfer) * plate
    value *= 0.98 + 0.04 * swirl
    height = np.clip((edge - 1.5) / 6.0, 0, 1)
    height = wrap_blur(height, 1.1)
    return np.clip(value, 0.0, 1.0), np.ones_like(value), height


def build_gold(swirl, chips):
    """Level 100. Champion gold: engine turned, the way a trophy is finished."""
    spacing = 64.0
    cx = np.round(XX / spacing) * spacing
    cy = np.round(YY / spacing) * spacing
    r = np.hypot(XX - cx, YY - cy)
    rings = 0.5 + 0.5 * np.sin(r * (2 * np.pi / 5.0))
    fall = np.clip(1.0 - r / (spacing * 0.82), 0, 1)
    jewel = 0.78 + 0.22 * rings * fall
    jewel *= 0.97 + 0.06 * np.clip(swirl - 0.4, -0.4, 0.4)
    value = np.clip(jewel, 0.62, 1.0)
    return value, np.ones_like(value)


# ----------------------------------------------------------------- previews

def preview(job_id: str, value: np.ndarray, alpha: np.ndarray, blend: str,
            height: np.ndarray | None, metal: dict | None) -> None:
    """512 square: the paint on a neutral panel, lit from the top left.

    Composited with exactly the arithmetic `livery.gd` asks the GPU for, so the
    picker cannot promise something the machine does not do.
    """
    n = PREVIEW
    value_s = np.asarray(Image.fromarray((np.clip(value, 0, 1) * 255).astype(np.uint8))
                         .resize((n, n), Image.LANCZOS), dtype=np.float64) / 255.0
    alpha_s = np.asarray(Image.fromarray((np.clip(alpha, 0, 1) * 255).astype(np.uint8))
                         .resize((n, n), Image.LANCZOS), dtype=np.float64) / 255.0

    base = np.array(PREVIEW_LIVERY, dtype=np.float64)
    if metal is not None:
        base = np.array(metal["albedo"], dtype=np.float64) * (1 - metal["livery_mix"]) \
            + np.array(PREVIEW_LIVERY) * metal["livery_mix"]
    rgb = np.ones((n, n, 3)) * base

    overlay = np.stack([value_s] * 3, axis=2)
    a = alpha_s[..., np.newaxis]
    if blend == "mix":
        rgb = rgb * (1 - a) + overlay * a
    else:
        rgb = rgb * (1 - a) + rgb * overlay * a

    # One key light from the top left across a panel that is not flat, plus the
    # relief of the normal map where the paint has any.
    yy, xx = np.mgrid[0:n, 0:n] / n
    lamp = 0.78 + 0.34 * np.clip(1.25 - (xx * 0.55 + yy * 1.05), 0, 1)
    if height is not None:
        h = np.asarray(Image.fromarray((np.clip(height, 0, 1) * 255).astype(np.uint8))
                       .resize((n, n), Image.LANCZOS), dtype=np.float64) / 255.0
        relief = (np.roll(h, 1, axis=1) - np.roll(h, -1, axis=1)) \
            + (np.roll(h, 1, axis=0) - np.roll(h, -1, axis=0))
        lamp = lamp + np.clip(relief, -1, 1) * 0.35
    rgb = rgb * lamp[..., np.newaxis]

    if metal is not None:
        # A mirror finish is its own lighting: a broad sky gradient and one hot
        # sweep, which is the only honest way to show chrome on a still.
        # A mirror shows a room. The horizon is what makes chrome read as
        # chrome on a still image: bright studio above it, dark floor below.
        horizon = 1.0 / (1.0 + np.exp((yy - 0.56) * 34.0))
        sky = 0.55 + 0.75 * np.clip(1.0 - yy * 1.3, 0, 1)
        floor = 0.30 + 0.22 * np.clip(yy - 0.5, 0, 1)
        room = (sky * horizon + floor * (1 - horizon))[..., np.newaxis]
        sweep = np.exp(-((xx * 0.7 + yy * 0.5 - 0.42) ** 2) / 0.006)[..., np.newaxis]
        rgb = rgb * room + np.array(metal["albedo"]) * sweep * metal["sweep"]

    # Clear coat: one soft highlight across the top third of the panel.
    coat = np.exp(-((yy - 0.16) ** 2) / 0.010) * np.clip(1.0 - xx * 0.35, 0, 1)
    rgb = rgb + coat[..., np.newaxis] * 0.10

    srgb = np.clip(rgb, 0, 1) ** (1 / 1.06)
    panel = Image.fromarray((srgb * 255 + 0.5).astype(np.uint8))

    # The design system's panel: a cut top-right corner, never a rounded
    # rectangle (docs/design-system.md 2). Edge to edge and with no rim of its
    # own, because the picker tile clips to the same shape and draws the rim:
    # a preview that carried its own inset and border would show a corner
    # inside a corner and a line beside a line.
    out = Image.new("RGB", (n, n), (7, 9, 12))
    cut = 52
    shape = [(0, 0), (n - cut, 0), (n - 1, cut), (n - 1, n - 1), (0, n - 1)]
    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).polygon(shape, fill=255)
    out.paste(panel, (0, 0), mask)
    out.save(os.path.join(PREVIEWS, f"{job_id}.png"), optimize=True)


# --------------------------------------------------------------- seam check

def seam_ratio(path: str) -> tuple[float, float, float, float]:
    """(seam dx, seam dy, dx vs the WORST interior pair, dy vs the worst).

    G2 measured the seam against the MEAN interior pair, which is the right
    test for a photographed material with no structure in it. It is the wrong
    test for a drawn pattern: the tile border of a chequer or a carbon weave
    lands on a square edge or a tow edge by construction, so the pair at the
    border is a real edge of the pattern and reads as three or four times the
    average pair while tiling perfectly. What matters is whether the border
    pair is WORSE than an edge the tile already contains, so the ratio here is
    against the worst interior pair. Under 1.0 means the wrap is not the
    loudest boundary in the texture, which is the honest definition of
    invisible for a pattern.
    """
    a = np.asarray(Image.open(path).convert("L"), dtype=np.float64)
    dx = np.abs(a[:, 0] - a[:, -1]).mean()
    dy = np.abs(a[0, :] - a[-1, :]).mean()
    worst_x = np.abs(np.diff(a, axis=1)).mean(axis=0).max()
    worst_y = np.abs(np.diff(a, axis=0)).mean(axis=1).max()
    return dx, dy, dx / max(worst_x, 1e-6), dy / max(worst_y, 1e-6)


# --------------------------------------------------------------------- main

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="print the seam numbers")
    args = parser.parse_args()

    os.makedirs(TEXTURES, exist_ok=True)
    os.makedirs(PREVIEWS, exist_ok=True)
    swirl, chips = wear_fields()

    chrome_metal = {"albedo": (0.78, 0.80, 0.84), "livery_mix": 0.14, "sweep": 0.95}
    gold_metal = {"albedo": (1.00, 0.78, 0.34), "livery_mix": 0.0, "sweep": 0.55}

    jobs = [
        ("paint_hazard", build_hazard, "mix", None, None),
        ("paint_racing", build_racing, "mix", None, None),
        ("paint_camo", build_camo, "mul", None, None),
        ("paint_chequer", build_chequer, "mix", 512, None),
        ("paint_flames", build_flames, "mix", None, None),
        ("paint_carbon", build_carbon, "mix", 1024, None),
        ("paint_chrome", build_chrome, "mul", None, chrome_metal),
        ("paint_circuit", build_circuit, "mix", 512, None),
        ("paint_hex", build_hex, "mul", 512, None),
        ("paint_gold", build_gold, "mul", None, gold_metal),
    ]

    for job_id, build, blend, normal_size, metal in jobs:
        result = build(swirl, chips)
        height = None
        if len(result) == 3:
            value, alpha, height = result
        else:
            value, alpha = result
        has_alpha = save_albedo(job_id, value, alpha)
        if normal_size is not None and height is not None:
            strength = {"paint_carbon": 2.4, "paint_hex": 5.5,
                        "paint_chequer": 4.0, "paint_circuit": 3.2}[job_id]
            save_normal(job_id, height, strength, normal_size)
        preview(job_id, value, alpha, blend, height, metal)
        print(f"  {job_id:<15} albedo 1024{' rgba' if has_alpha else ' rgb '}"
              + (f"  normal {normal_size}" if normal_size else "")
              + f"  cover {float(np.mean(alpha)):.2f}  value {float(np.mean(value)):.2f}")

    if args.check:
        print("\nseam check: the border pair against the WORST pair inside the tile.")
        print("under 1.0 = the wrap is not the loudest boundary in the texture.")
        print(f"  {'texture':<24}{'seam dx':>9}{'seam dy':>9}{'vs worst x':>12}{'vs worst y':>12}")
        for name in sorted(os.listdir(TEXTURES)):
            if not name.endswith(".png"):
                continue
            dx, dy, rx, ry = seam_ratio(os.path.join(TEXTURES, name))
            print(f"  {name:<24}{dx:>9.3f}{dy:>9.3f}{rx:>12.2f}{ry:>12.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
