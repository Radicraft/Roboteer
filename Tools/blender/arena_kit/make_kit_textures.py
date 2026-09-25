"""Arena kit textures (wave A, the venue kit lead). Plain PIL + numpy, no Blender needed.

    python3 Tools/blender/arena_kit/make_kit_textures.py

Writes Arena/arena/kit/textures/:

  floor_grime.png   1024 x 1024 RGBA, a 2 x 2 atlas of floor grime the venue lays on
                    top of any arena floor: 0 oil stain, 1 tyre skid arcs, 2 dust and
                    scuff patch, 3 weld seam and burn. Dark colour, soft alpha.
  chainlink.png     256 x 256 RGBA tileable chain-link wire (alpha cut), for the
                    `grating` slot on fence panels.
  boards.png        1024 x 1024 RGB, four 1024 x 256 advertising boards with INVENTED
                    marks only (brief v3 section 3: no real shows, teams or brands).
  gate_signs.png    1024 x 512 RGB, two 1024 x 256 gate plates: the fighters' entrance
                    ("MACHINES IN") and the venue name ("THE YARD").
  noise.png         256 x 256 greyscale tileable value noise for the shaders (haze,
                    screen grime, beam breakup).
  yard_floor.png    2048 x 2048 RGBA, ONE unique map over the Yard's whole 10.4 m floor
                    (venue_floor.gdshader): big irregular steel plates with their own tone,
                    seams, welds, a few corner bolts, oil, heavy tyre marks, grime at the
                    wall feet; A is how oily and wet the spot is. The spike patch is clean.
  yard_floor_n.png  2048 x 2048 RGB normal map of the same plates (seam grooves, weld
                    beads, bolt heads).

Every output is seeded, so a rerun is byte-identical.
"""

import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(REPO, "Arena", "arena", "kit", "textures")
FONTS = os.path.join(REPO, "Arena", "assets", "fonts")

RNG = np.random.default_rng(20260924)


def font(name, size):
    return ImageFont.truetype(os.path.join(FONTS, name), size)


def value_noise(size, cells, rng, octaves=4):
    """Tileable fractal value noise in 0..1."""
    out = np.zeros((size, size), np.float32)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        c = cells * (2 ** o)
        grid = rng.random((c, c)).astype(np.float32)
        img = Image.fromarray((grid * 255).astype(np.uint8))
        # Tile 3x3 then crop the middle so the bicubic edge wraps.
        big = Image.new("L", (c * 3, c * 3))
        for i in range(3):
            for j in range(3):
                big.paste(img, (i * c, j * c))
        big = big.resize((size * 3, size * 3), Image.BICUBIC)
        layer = np.asarray(big, np.float32)[size:size * 2, size:size * 2] / 255.0
        out += layer * amp
        total += amp
        amp *= 0.5
    return out / total


def soft_blob(size, rng, lobes=7, rough=0.35):
    """An irregular soft-edged blob mask, 0..1."""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    cx = cy = size / 2
    ang = np.arctan2(yy - cy, xx - cx)
    r = np.hypot(xx - cx, yy - cy) / (size * 0.5)
    radius = np.full_like(ang, 0.62)
    for k in range(1, lobes + 1):
        radius += rng.uniform(-rough, rough) / k * np.cos(k * ang + rng.uniform(0, math.tau))
    n = value_noise(size, 6, rng, 4)
    edge = radius * (0.85 + 0.3 * n)
    m = np.clip((edge - r) / 0.18, 0.0, 1.0)
    return m * m * (3 - 2 * m)


def cell_oil(size):
    rng = np.random.default_rng(11)
    m = soft_blob(size, rng, 9, 0.45)
    # A few satellite drips.
    for _ in range(6):
        s = int(size * rng.uniform(0.12, 0.25))
        b = soft_blob(s, rng, 5, 0.3)
        x = int(rng.uniform(0.05, 0.95) * (size - s))
        y = int(rng.uniform(0.05, 0.95) * (size - s))
        m[y:y + s, x:x + s] = np.maximum(m[y:y + s, x:x + s], b * 0.85)
    n = value_noise(size, 8, rng, 4)
    a = np.clip(m * (0.55 + 0.45 * n), 0, 1) * 0.82
    rgb = np.zeros((size, size, 3), np.float32)
    rgb[..., 0] = 0.035 + 0.03 * n
    rgb[..., 1] = 0.032 + 0.028 * n
    rgb[..., 2] = 0.03 + 0.03 * n
    return rgb, a


def cell_tyre(size):
    rng = np.random.default_rng(12)
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)
    for arc in range(7):
        cx = rng.uniform(-0.2, 1.2) * size
        cy = rng.uniform(-0.2, 1.2) * size
        rad = rng.uniform(0.3, 0.7) * size
        a0 = rng.uniform(0, 360)
        span = rng.uniform(60, 140)
        width = int(rng.uniform(0.05, 0.075) * size)
        for pair in (0, 1):
            off = pair * width * 2.4
            steps = 80
            for s in range(steps):
                t0 = math.radians(a0 + span * s / steps)
                t1 = math.radians(a0 + span * (s + 1) / steps)
                r = rad + off
                fade = math.sin(math.pi * s / steps) ** 0.6
                val = int(255 * fade * rng.uniform(0.6, 1.0))
                d.line([(cx + r * math.cos(t0), cy + r * math.sin(t0)),
                        (cx + r * math.cos(t1), cy + r * math.sin(t1))], fill=val, width=width)
    img = img.filter(ImageFilter.GaussianBlur(1.6))
    m = np.asarray(img, np.float32) / 255.0
    # Tread breakup: stripes across the mark.
    n = value_noise(size, 16, rng, 3)
    a = np.clip(m * (0.45 + 0.55 * n), 0, 1) * 0.8
    rgb = np.zeros((size, size, 3), np.float32) + 0.025
    return rgb, a


def cell_dust(size):
    rng = np.random.default_rng(13)
    m = soft_blob(size, rng, 8, 0.5)
    n = value_noise(size, 5, rng, 5)
    speck = (rng.random((size, size)) > 0.985).astype(np.float32)
    speck = np.asarray(Image.fromarray((speck * 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(0.7)), np.float32) / 255.0
    a = np.clip(m * n * 0.9 + speck * m, 0, 1) * 0.55
    rgb = np.zeros((size, size, 3), np.float32)
    rgb[..., 0] = 0.36 + 0.1 * n
    rgb[..., 1] = 0.31 + 0.08 * n
    rgb[..., 2] = 0.25 + 0.06 * n
    return rgb, a


def cell_weld(size):
    rng = np.random.default_rng(14)
    img = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(img)
    # Two crossing weld seams with bead ripples.
    for horizontal in (True, False):
        pos = size * rng.uniform(0.35, 0.65)
        for i in range(0, size, 6):
            wob = rng.uniform(-2, 2)
            if horizontal:
                d.ellipse([i - 7, pos - 7 + wob, i + 7, pos + 7 + wob], fill=200)
            else:
                d.ellipse([pos - 7 + wob, i - 7, pos + 7 + wob, i + 7], fill=200)
    seam = np.asarray(img.filter(ImageFilter.GaussianBlur(1.2)), np.float32) / 255.0
    burn = soft_blob(size, rng, 6, 0.4)
    n = value_noise(size, 7, rng, 4)
    a = np.clip(np.maximum(seam * 0.9, burn * n * 0.6), 0, 1)
    rgb = np.zeros((size, size, 3), np.float32)
    heat = np.clip(burn * n * 1.4, 0, 1)
    rgb[..., 0] = 0.05 + 0.10 * seam + 0.10 * heat
    rgb[..., 1] = 0.045 + 0.08 * seam + 0.05 * heat
    rgb[..., 2] = 0.05 + 0.10 * seam + 0.12 * heat * (1 - heat)
    return rgb, a


def floor_grime():
    size = 512
    atlas = np.zeros((1024, 1024, 4), np.float32)
    for i, fn in enumerate((cell_oil, cell_tyre, cell_dust, cell_weld)):
        rgb, a = fn(size)
        y, x = (i // 2) * size, (i % 2) * size
        atlas[y:y + size, x:x + size, :3] = rgb
        atlas[y:y + size, x:x + size, 3] = a
    img = Image.fromarray((np.clip(atlas, 0, 1) * 255).astype(np.uint8), "RGBA")
    img.save(os.path.join(OUT, "floor_grime.png"), optimize=True)


def chainlink():
    s = 256
    scale = 4
    big = Image.new("RGBA", (s * scale, s * scale), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    pitch = s * scale // 4
    wire = 3 * scale
    col = (178, 184, 190, 255)
    for i in range(-1, 6):
        for j in range(-1, 6):
            cx, cy = i * pitch, j * pitch
            pts = [(cx, cy - pitch // 2), (cx + pitch // 2, cy), (cx, cy + pitch // 2),
                   (cx - pitch // 2, cy), (cx, cy - pitch // 2)]
            d.line(pts, fill=col, width=wire, joint="curve")
    img = big.resize((s, s), Image.LANCZOS)
    img.save(os.path.join(OUT, "chainlink.png"), optimize=True)


def _mark(d, kind, x, y, s, fg):
    if kind == "gear":
        r = s * 0.5
        for k in range(10):
            a = math.tau * k / 10
            d.rectangle([x + math.cos(a) * r * 0.8 - s * 0.08, y + math.sin(a) * r * 0.8 - s * 0.08,
                         x + math.cos(a) * r * 0.8 + s * 0.08, y + math.sin(a) * r * 0.8 + s * 0.08], fill=fg)
        d.ellipse([x - r * 0.8, y - r * 0.8, x + r * 0.8, y + r * 0.8], fill=fg)
        return
    if kind == "bolt":
        pts = [(x - s * 0.1, y - s * 0.55), (x + s * 0.28, y - s * 0.55), (x + s * 0.04, y - s * 0.05),
               (x + s * 0.3, y - s * 0.05), (x - s * 0.22, y + s * 0.6), (x - s * 0.04, y + s * 0.08),
               (x - s * 0.3, y + s * 0.08)]
        d.polygon(pts, fill=fg)
        return
    if kind == "hex":
        pts = [(x + math.cos(math.tau * k / 6) * s * 0.5, y + math.sin(math.tau * k / 6) * s * 0.5)
               for k in range(6)]
        d.polygon(pts, fill=fg)
        return
    if kind == "rivet":
        for k in range(3):
            d.ellipse([x - s * 0.5 + k * s * 0.36, y - s * 0.16, x - s * 0.18 + k * s * 0.36, y + s * 0.16],
                      fill=fg)


def _grunge(img, rng, amount=0.25):
    arr = np.asarray(img, np.float32) / 255.0
    n = value_noise(max(img.size), 6, rng, 5)[:img.size[1], :img.size[0]]
    scratches = np.zeros_like(n)
    sc = Image.new("L", img.size, 0)
    sd = ImageDraw.Draw(sc)
    for _ in range(40):
        x0 = rng.uniform(0, img.size[0])
        y0 = rng.uniform(0, img.size[1])
        sd.line([(x0, y0), (x0 + rng.uniform(-60, 60), y0 + rng.uniform(-8, 8))], fill=255, width=1)
    scratches = np.asarray(sc, np.float32) / 255.0
    arr = arr * (1.0 - amount * (1 - n))[..., None]
    arr = arr * (1.0 - 0.35 * scratches[..., None]) + 0.2 * scratches[..., None]
    return Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), img.mode)


def boards():
    # (background, foreground, accent, name, strap, mark). Invented marks only.
    specs = [
        ((22, 24, 28), (242, 190, 36), (242, 190, 36), "GRINDLOW", "SALVAGE  &  BREAKERS", "gear"),
        ((196, 44, 38), (250, 246, 238), (30, 28, 30), "RIVETHAUS", "TOOLS THAT TAKE A HIT", "rivet"),
        ((238, 236, 228), (26, 60, 120), (220, 90, 30), "OHMWORKS", "CELLS  ·  MOTORS  ·  POWER", "bolt"),
        ((18, 94, 84), (240, 238, 226), (242, 190, 36), "HEXLINE", "FASTENERS BY THE TONNE", "hex"),
    ]
    rng = np.random.default_rng(21)
    atlas = Image.new("RGB", (1024, 1024))
    big = font("BarlowCondensed-ExtraBoldItalic.ttf", 138)
    small = font("BarlowCondensed-Bold.ttf", 40)
    for i, (bg, fg, acc, name, strap, mark) in enumerate(specs):
        img = Image.new("RGB", (1024, 256), bg)
        d = ImageDraw.Draw(img)
        d.rectangle([0, 0, 1023, 14], fill=acc)
        d.rectangle([0, 241, 1023, 255], fill=acc)
        _mark(d, mark, 120, 128, 150, fg)
        d.text((236, 104), name, font=big, fill=fg, anchor="lm")
        d.text((244, 196), strap, font=small, fill=fg, anchor="lm")
        img = _grunge(img, rng, 0.18)
        atlas.paste(img, (0, i * 256))
    atlas.save(os.path.join(OUT, "boards.png"), optimize=True)


def gate_signs():
    rng = np.random.default_rng(31)
    out = Image.new("RGB", (1024, 512))
    stencil = font("BarlowCondensed-ExtraBold.ttf", 190)
    for i, (text, bg, fg) in enumerate([("MACHINES IN", (24, 25, 27), (242, 190, 36)),
                                         ("THE YARD", (120, 42, 22), (236, 228, 212))]):
        img = Image.new("RGB", (1024, 256), bg)
        d = ImageDraw.Draw(img)
        # Painted lettering.
        txt = Image.new("L", (1024, 256), 0)
        td = ImageDraw.Draw(txt)
        td.text((512, 132), text, font=stencil, fill=255, anchor="mm")
        cut = Image.new("L", (1024, 256), 255)
        cd = ImageDraw.Draw(cut)
        for x in ():  # no bridges: at 20 m they read as damage, not stencil
            cd.rectangle([x + 20, 0, x + 26, 256], fill=0)
        mask = Image.fromarray(np.minimum(np.asarray(txt), np.asarray(cut)).astype(np.uint8))
        img.paste(Image.new("RGB", img.size, fg), (0, 0), mask)
        # Bolt heads in the corners.
        for (x, y) in ((22, 22), (1002, 22), (22, 234), (1002, 234)):
            d.ellipse([x - 9, y - 9, x + 9, y + 9], fill=(90, 88, 84))
        img = _grunge(img, rng, 0.35)
        out.paste(img, (0, i * 256))
    out.save(os.path.join(OUT, "gate_signs.png"), optimize=True)


def noise():
    n = value_noise(256, 4, np.random.default_rng(41), 5)
    n = (n - n.min()) / (n.max() - n.min())
    Image.fromarray((n * 255).astype(np.uint8), "L").save(os.path.join(OUT, "noise.png"), optimize=True)


YARD_EXTENT = 10.4   # metres covered by yard_floor.png, centred on the arena


def _plates(rng, square_middle=True):
    """The Yard's floor as big, irregular steel plates: rows of different depths along z,
    each split at staggered x. The middle row is cut round the spike patch's own frame.
    Returns [(x0, z0, x1, z1)] in metres."""
    half = YARD_EXTENT / 2
    rows = [-half, -2.95, -1.12, 1.12, 3.25, half]
    plates = []
    for r in range(len(rows) - 1):
        z0, z1 = rows[r], rows[r + 1]
        if r == 2 and square_middle:
            cuts = [-half, -3.4, -1.12, 1.12, 2.9, half]
        else:
            cuts = [-half]
            x = -half + rng.uniform(1.3, 2.6)
            while x < half - 1.2:
                cuts.append(x)
                x += rng.uniform(1.9, 3.4)
            cuts.append(half)
        for i in range(len(cuts) - 1):
            plates.append((cuts[i], z0, cuts[i + 1], z1))
    return plates


def yard_floor(name="yard_floor", seed=424242, oil=12, tyres=20, drips=90, damp_on=True,
               rivets=False, weld_share=0.5, grind=(), clean=(), patch_clean=True):
    """<name>.png (RGB albedo multiplier, A wet) and <name>_n.png (tangent-space normal
    from a height field: seam grooves, weld beads, bolt heads, plate edge wear).
    The Yard uses the defaults. Other arenas: `rivets` puts rivet rows along every seam,
    `grind` = [(x, z, r)] lays radial grind marks and bright filings round a hazard well,
    `clean` = [(x, z, r)] keeps seams, stains and marks out of a circle."""
    size = 2048
    rng = np.random.default_rng(seed)
    ppm = size / YARD_EXTENT
    half = YARD_EXTENT / 2

    def to_px(x, z):
        return ((x + half) * ppm, (z + half) * ppm)

    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    wx = xx / ppm - half
    wz = yy / ppm - half
    inpatch = (np.maximum(np.abs(wx), np.abs(wz)) < 1.08) if patch_clean else np.zeros((size, size), bool)
    for (cx, cz, cr) in clean:
        inpatch |= np.hypot(wx - cx, wz - cz) < cr
    mul = np.ones((size, size, 3), np.float32)
    wet = np.zeros((size, size), np.float32)
    height = np.zeros((size, size), np.float32)
    n1 = value_noise(size, 5, rng, 5)
    n2 = value_noise(size, 40, rng, 3)
    fine = value_noise(size, 90, rng, 3)

    # Plates: each its own tone and a faint warm or cold cast, worn lighter where machines
    # run, darker toward its edges; seams are 8 mm grooves with a slight bevel.
    plates = _plates(rng, patch_clean)
    seam = np.zeros((size, size), np.float32)
    for (x0, z0, x1, z1) in plates:
        m = (wx >= x0) & (wx < x1) & (wz >= z0) & (wz < z1)
        tone = rng.uniform(0.84, 1.1)
        cast = rng.uniform(-0.035, 0.035)
        mul[m] *= np.array([tone * (1 + cast), tone, tone * (1 - cast)], np.float32)
        d = np.minimum(np.minimum(wx - x0, x1 - wx), np.minimum(wz - z0, z1 - wz))
        edge = np.clip(d / 0.12, 0, 1)
        mul[m] *= (0.82 + 0.18 * edge[m])[:, None]
        height[m] += (0.3 * np.clip(d / 0.02, 0, 1))[m]
        seam = np.maximum(seam, np.where(m, 1.0 - np.clip(d / 0.008, 0, 1), 0.0))
    seam *= ~inpatch
    mul *= (1.0 - 0.8 * seam)[..., None]

    # Welds on about half of the seams: a rippled raised bead with a heat-tinted margin.
    weld = np.zeros((size, size), np.float32)
    heat = np.zeros((size, size), np.float32)
    for (x0, z0, x1, z1) in plates:
        for edge in ((x0, z0, x0, z1), (x0, z0, x1, z0)):
            if rng.random() < 1.0 - weld_share or abs(edge[0]) >= half - 0.01 or abs(edge[1]) >= half - 0.01 and edge[1] == edge[3]:
                continue
            ex0, ez0, ex1, ez1 = edge
            vertical = ex0 == ex1
            length = (ez1 - ez0) if vertical else (ex1 - ex0)
            steps = int(length * ppm / 3)
            for k in range(steps):
                t = k / max(steps, 1)
                px, pz = to_px(ex0 + (0 if vertical else t * length), ez0 + (t * length if vertical else 0))
                r = 4.5 + 1.5 * math.sin(k * 0.9)
                yl, yh = int(max(pz - 12, 0)), int(min(pz + 12, size))
                xl, xh = int(max(px - 12, 0)), int(min(px + 12, size))
                dd = np.hypot(xx[yl:yh, xl:xh] - px, yy[yl:yh, xl:xh] - pz)
                weld[yl:yh, xl:xh] = np.maximum(weld[yl:yh, xl:xh], np.clip(1 - dd / r, 0, 1))
                heat[yl:yh, xl:xh] = np.maximum(heat[yl:yh, xl:xh], np.clip(1 - dd / 22.0, 0, 1))
    weld *= ~inpatch
    heat *= ~inpatch
    height += weld * 1.2
    mul *= (1.0 - 0.35 * weld)[..., None]
    tint = np.stack([1 - 0.1 * heat, 1 - 0.13 * heat, 1 - 0.12 * heat], -1)
    mul *= tint

    # A few bolt heads, only at some plate corners (the old grid of holes is gone).
    for (x0, z0, x1, z1) in plates:
        for (cx, cz) in ((x0, z0), (x1, z0), (x0, z1), (x1, z1)):
            if (rng.random() > 0.35 and not rivets) or max(abs(cx), abs(cz)) >= half - 0.05:
                continue
            for dx, dz in ((0.09, 0.09), (-0.09, 0.09), (0.09, -0.09), (-0.09, -0.09)):
                bx, bz = cx + dx, cz + dz
                if max(abs(bx), abs(bz)) < 1.12:
                    continue
                px, pz = to_px(bx, bz)
                yl, yh = int(max(pz - 8, 0)), int(min(pz + 8, size))
                xl, xh = int(max(px - 8, 0)), int(min(px + 8, size))
                dd = np.hypot(xx[yl:yh, xl:xh] - px, yy[yl:yh, xl:xh] - pz)
                b = np.clip(1 - dd / 5.5, 0, 1)
                height[yl:yh, xl:xh] += np.sqrt(b) * 0.9
                mul[yl:yh, xl:xh] *= (1 - 0.3 * b)[..., None]
                wet[yl:yh, xl:xh] = np.maximum(wet[yl:yh, xl:xh], b * 0.4)

    # General grime and the wall feet.
    g = (0.7 + 0.3 * n1) * (0.92 + 0.08 * n2)
    edge = np.maximum(np.abs(wx), np.abs(wz))
    g *= 1.0 - 0.45 * np.clip((edge - 3.6) / 1.4, 0, 1) ** 1.5
    mul *= g[..., None]

    # Oil pools: dark, glossy, wide sheen margins so the key catches them.
    if rivets:
        # Rivet rows along every plate edge, 0.25 m apart, 6 cm in from the seam.
        for (x0, z0, x1, z1) in plates:
            pts = []
            for t in np.arange(x0 + 0.12, x1 - 0.06, 0.25):
                pts += [(t, z0 + 0.06), (t, z1 - 0.06)]
            for t in np.arange(z0 + 0.12, z1 - 0.06, 0.25):
                pts += [(x0 + 0.06, t), (x1 - 0.06, t)]
            for (bx, bz) in pts:
                if max(abs(bx), abs(bz)) >= half - 0.03:
                    continue
                px, pz = to_px(bx, bz)
                yl, yh = int(max(pz - 6, 0)), int(min(pz + 6, size))
                xl, xh = int(max(px - 6, 0)), int(min(px + 6, size))
                dd = np.hypot(xx[yl:yh, xl:xh] - px, yy[yl:yh, xl:xh] - pz)
                b = np.clip(1 - dd / 4.0, 0, 1) * ~inpatch[yl:yh, xl:xh]
                height[yl:yh, xl:xh] += np.sqrt(b) * 0.8
                mul[yl:yh, xl:xh] *= (1 - 0.25 * b)[..., None]
    for (gx, gz, gr) in grind:
        # Radial grind marks and bright filings round a well: lighter, glossy steel.
        dx, dz = wx - gx, wz - gz
        rr = np.hypot(dx, dz)
        ang = np.arctan2(dz, dx)
        streak = value_noise(size, 64, rng, 2)
        rad = 0.5 + 0.5 * np.sin(ang * 90.0 + 6.0 * streak)
        ring = np.clip(1 - np.abs(rr - gr * 1.35) / (gr * 0.8), 0, 1) * (rr > gr * 0.95)
        mark = ring * np.clip((rad - 0.55) / 0.3, 0, 1) * (0.5 + 0.5 * fine)
        mul *= (1.0 + 0.45 * mark)[..., None]
        wet = np.maximum(wet, mark * 0.5)
        fil = (rng.random((size, size)) > 0.994) & (ring > 0.2)
        mul[fil] *= 1.6
    for _ in range(oil):
        while True:
            cx, cz = rng.uniform(-4.6, 4.6, 2)
            if max(abs(cx), abs(cz)) > 1.5:
                break
        rx, rz = rng.uniform(0.25, 0.8), rng.uniform(0.18, 0.5)
        ang = rng.uniform(0, math.pi)
        ca, sa = math.cos(ang), math.sin(ang)
        dx, dz = wx - cx, wz - cz
        u = (dx * ca + dz * sa) / rx
        v = (-dx * sa + dz * ca) / rz
        r = np.sqrt(u * u + v * v)
        field = 1.0 - r + 0.55 * (n2 - 0.5) + 0.35 * (fine - 0.5)
        m = np.clip(field / 0.25, 0, 1)
        sheen = np.clip((field + 0.6) / 0.6, 0, 1)
        mul *= (1.0 - rng.uniform(0.18, 0.3) * m)[..., None]
        wet = np.maximum(wet, np.maximum(m * 0.7, sheen * 0.5))
    # Puddled damp along the wall feet and seams: the floor is wet in the concept.
    damp = np.clip((n1 - 0.55) / 0.2, 0, 1) * np.clip((fine - 0.3) / 0.4, 0, 1) * (1.0 if damp_on else 0.0)
    wet = np.maximum(wet, damp * 0.7)
    wet = np.maximum(wet, seam * 0.6)

    # Tyre marks: heavy black rubber that reads from 7 m, arcs and spirals, doughnuts,
    # thicker in the middle of the floor where most fights happen.
    tyre = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(tyre)
    for k in range(tyres):
        c = rng.uniform(-5.5, 5.5, 2)
        cx, cz = float(np.clip(c[0], -4.6, 4.6)), float(np.clip(c[1], -4.6, 4.6))
        rad0 = rng.uniform(1.0, 4.5)
        tighten = rng.uniform(0.2, 0.9)
        span = rng.uniform(50, 140) if k % 7 else rng.uniform(280, 380)
        wob = rng.uniform(0.05, 0.25)
        a0 = rng.uniform(0, 360)
        width = max(4, int(ppm * rng.uniform(0.07, 0.11)))
        track = rng.uniform(0.3, 0.42)
        strength = rng.uniform(0.55, 1.0)
        steps = 140
        for side in (-1, 1):
            prev = None
            for st in range(steps + 1):
                f = st / steps
                t = math.radians(a0 + span * f)
                r = rad0 * (1.0 - (1.0 - tighten) * f) * (1.0 + wob * math.sin(f * 7.0 + k)) + side * track / 2
                pt = to_px(cx + r * math.cos(t), cz + r * math.sin(t))
                if prev is not None:
                    fade = math.sin(math.pi * f) ** 0.35
                    d.line([prev, pt], fill=int(255 * strength * fade * rng.uniform(0.7, 1.0)), width=width)
                prev = pt
    tm = np.asarray(tyre.filter(ImageFilter.GaussianBlur(2.5)), np.float32) / 255.0
    tm *= 0.6 + 0.4 * value_noise(size, 80, rng, 2)
    tm *= np.clip((np.maximum(np.abs(wx), np.abs(wz)) - 1.05) / 0.25, 0, 1) if patch_clean else 1.0
    if clean:
        tm *= ~inpatch
    mul *= (1.0 - 0.85 * tm)[..., None]
    wet = np.maximum(wet, tm * 0.35)

    # Small drips.
    for _ in range(drips):
        cx, cz = rng.uniform(-5.1, 5.1, 2)
        if max(abs(cx), abs(cz)) < 1.2:
            continue
        px, pz = to_px(cx, cz)
        r = rng.uniform(2, 8)
        yl, xl = int(max(pz - r, 0)), int(max(px - r, 0))
        yh, xh = int(min(pz + r, size)), int(min(px + r, size))
        m = ((xx[yl:yh, xl:xh] - px) ** 2 + (yy[yl:yh, xl:xh] - pz) ** 2) < r * r
        mul[yl:yh, xl:xh][m] *= rng.uniform(0.4, 0.7)
        wet[yl:yh, xl:xh][m] = np.maximum(wet[yl:yh, xl:xh][m], 0.7)

    out = np.concatenate([np.clip(mul, 0, 1), np.clip(wet, 0, 1)[..., None]], -1)
    Image.fromarray((out * 255).astype(np.uint8), "RGBA").save(
        os.path.join(OUT, name + ".png"), optimize=True)

    # Normal map from the height field (OpenGL convention, +Y up in the image = -Z world).
    h = np.asarray(Image.fromarray(np.clip(height / 2.0 * 255, 0, 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(1.0)), np.float32) / 255.0 * 2.0
    h -= 1.0 * seam
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    gz = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    k = 2.2
    nx, ny, nz = -gx * k, gz * k, np.ones_like(h)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    nrm = np.stack([nx / ln, ny / ln, nz / ln], -1) * 0.5 + 0.5
    Image.fromarray((nrm * 255).astype(np.uint8), "RGB").save(
        os.path.join(OUT, name + "_n.png"), optimize=True)


def grinder_floor():
    """The Grinder: a machine-shop floor. Riveted plates, few welds, a little oil, grind
    marks and filings round both wells (grinder.gd GRINDER_A / GRINDER_B, disc r 0.55)."""
    wells = [(-3.3, 1.1), (3.3, -1.1)]
    yard_floor("grinder_floor", seed=5150, oil=3, tyres=9, drips=30, damp_on=False, rivets=True,
               weld_share=0.2, grind=[(x, z, 0.55) for x, z in wells],
               clean=[(x, z, 0.62) for x, z in wells], patch_clean=False)


def drop_zone_floor():
    """Drop Zone: poured concrete bays with expansion joints, damp, tyre marks, old oil,
    nothing inside the pit's rim (drop_zone.gd PIT 2.4 m)."""
    yard_floor("drop_zone_floor", seed=3030, oil=6, tyres=16, drips=60, damp_on=True, rivets=False,
               weld_share=0.0, clean=[(0.0, 0.0, 1.85)], patch_clean=False)


def main():
    os.makedirs(OUT, exist_ok=True)
    floor_grime()
    chainlink()
    boards()
    gate_signs()
    noise()
    yard_floor()
    grinder_floor()
    drop_zone_floor()
    print("wrote", sorted(os.listdir(OUT)))


if __name__ == "__main__":
    main()
