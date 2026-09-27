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
  yard_floor.png    2048 x 2048 RGB, ONE unique map over the Yard's whole 10.4 m floor
                    (venue_floor.gdshader): big irregular steel plates with their own tone,
                    seams, welds, a few corner bolts, oil, heavy tyre marks, grime at the
                    wall feet. The spike patch is clean.
  yard_floor_wet.png 512 x 512 greyscale: how oily and wet each spot is.
  yard_floor_n.png  2048 x 2048 RGB normal map of the same plates (seam grooves, weld
                    beads, bolt heads); imported at 1024 (size_limit) for the package.
  workshop_floor*.png the workshop test bay (venues/workshop.gd): sealed concrete bays with
                    the painted test floor (_workshop_paint); map imported at 1536,
                    normal at 512 (size_limit).
  workshop_wall.png 1024 x 512 RGB: a pegboard tool wall band and the TEST BAY sign band.

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
    big = font("SairaStencilOne-Regular.ttf", 110)
    small = font("SairaSemiCondensed-Bold.ttf", 38)
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
    stencil = font("SairaStencilOne-Regular.ttf", 152)
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
               rivets=False, weld_share=0.5, grind=(), clean=(), patch_clean=True, cracks=0,
               paint=None, save_normal=True, tone_range=(0.84, 1.1)):
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
        tone = rng.uniform(*tone_range)
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

    # Painted floor markings (the workshop's test floor): under the oil and the tyre marks.
    if paint is not None:
        paint(mul, height, wet, wx, wz, to_px, ppm, size, rng, fine)

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

    # Cracks in concrete: branching random walks, dark and a little raised at the lips.
    if cracks:
        cr = Image.new("L", (size, size), 0)
        cd = ImageDraw.Draw(cr)
        for _ in range(cracks):
            x, z = rng.uniform(-5.0, 5.0, 2)
            ang = rng.uniform(0, math.tau)
            steps = rng.integers(20, 60)
            width = 3
            for _s in range(steps):
                ang += rng.normal(0, 0.45)
                nx, nz = x + math.cos(ang) * 0.09, z + math.sin(ang) * 0.09
                cd.line([to_px(x, z), to_px(nx, nz)], fill=230, width=width)
                if rng.random() < 0.06:
                    bx, bz, ba = nx, nz, ang + rng.choice([-1, 1]) * rng.uniform(0.6, 1.2)
                    for _b in range(rng.integers(5, 15)):
                        ba += rng.normal(0, 0.5)
                        cx2, cz2 = bx + math.cos(ba) * 0.08, bz + math.sin(ba) * 0.08
                        cd.line([to_px(bx, bz), to_px(cx2, cz2)], fill=180, width=2)
                        bx, bz = cx2, cz2
                x, z = nx, nz
        cm = np.asarray(cr.filter(ImageFilter.GaussianBlur(0.8)), np.float32) / 255.0
        cm *= ~inpatch
        mul *= (1.0 - 0.75 * cm)[..., None]
        height -= cm * 0.8
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

    # RGB map at full size (ETC2 RGB on the phone, half the bytes of RGBA) and the wet mask
    # as its own small greyscale map (it is soft; 512 is plenty). Package size, 2026-09-27.
    Image.fromarray((np.clip(mul, 0, 1) * 255).astype(np.uint8), "RGB").save(
        os.path.join(OUT, name + ".png"), optimize=True)
    wet_img = Image.fromarray((np.clip(wet, 0, 1) * 255).astype(np.uint8), "L")
    wet_img.resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, name + "_wet.png"), optimize=True)

    if not save_normal:
        return
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


def furnace_floor():
    """Furnace: riveted foundry plate, a few welds, spilled oil and slag drips, no tyre
    spirals to speak of (the belt carries the machines, they do not skid much)."""
    yard_floor("furnace_floor", seed=7070, oil=5, tyres=6, drips=160, damp_on=False, rivets=True,
               weld_share=0.3, patch_clean=False)


def crush_floor():
    """The Crush: pale poured concrete bays, cracked by the rams, dust, few tyre marks."""
    yard_floor("crush_floor", seed=9090, oil=3, tyres=8, drips=40, damp_on=False, rivets=False,
               weld_share=0.0, patch_clean=False, cracks=26)


def coliseum_floor():
    """Coliseum: polished dark championship plate. The map covers 10.4 m but the floor is
    12 m (the shader stretches it to 12.4), so world positions are scaled by 10.4 / 12.4.
    Clean round the turntables (r 2.0), the grinder wells and the central spike patch."""
    k = YARD_EXTENT / 12.4
    clean = [(-2.9 * k, 2.9 * k, 2.3 * k), (2.9 * k, -2.9 * k, 2.3 * k),
             (-4.6 * k, -1.5 * k, 0.75 * k), (4.6 * k, 1.5 * k, 0.75 * k), (0.0, 0.0, 1.6 * k)]
    yard_floor("coliseum_floor", seed=1212, oil=0, tyres=10, drips=0, damp_on=False, rivets=False,
               weld_share=0.0, patch_clean=False, clean=clean)


# ---------------------------------------------------------------------------------
# The workshop test bay (Arena/arena/kit/venues/workshop.gd, the builder's test arena)
WORKSHOP_WHITE = (0.93, 0.92, 0.88)
WORKSHOP_YELLOW = (0.95, 0.7, 0.1)
WORKSHOP_BLACK = (0.16, 0.16, 0.17)


def _workshop_paint(mul, height, wet, wx, wz, to_px, ppm, size, rng, fine):
    """The test floor's paint: a metre grid of crosses, measuring tapes along the far
    south and east edges with 10 cm ticks and numbers, pivot circles with 15 degree ticks
    in the middle, the two start boxes, and the impact lane in front of the target pad on
    the north wall (test_arena.gd: pad 1.8 m wide, centred on x 0 at z -4.9)."""
    ss = 2                                   # draw at 2x, downsample: clean edges
    big = size * ss

    def P(x, z):
        px, pz = to_px(x, z)
        return (px * ss, pz * ss)

    def W(m):
        return max(1, int(round(m * ppm * ss)))

    layers = {k: Image.new("L", (big, big), 0) for k in ("white", "yellow", "black")}
    dr = {k: ImageDraw.Draw(v) for k, v in layers.items()}
    stencil = font("SairaStencilOne-Regular.ttf", int(0.29 * ppm * ss))
    small = font("SairaSemiCondensed-Bold.ttf", int(0.19 * ppm * ss))

    def line(layer, a, b, w):
        dr[layer].line([P(*a), P(*b)], fill=255, width=W(w))

    def text(layer, x, z, t, f, rot=180):
        # Rotated text: draw on its own tile and paste.
        bbox = f.getbbox(t)
        tw, th = bbox[2] - bbox[0] + 8, bbox[3] - bbox[1] + 8
        tile = Image.new("L", (tw, th), 0)
        ImageDraw.Draw(tile).text((tw / 2, th / 2), t, font=f, fill=255, anchor="mm")
        if rot:
            tile = tile.rotate(rot, expand=True)
        cx, cz = P(x, z)
        layers[layer].paste(255, (int(cx - tile.width / 2), int(cz - tile.height / 2)), tile)

    # Keep-out line 0.12 m inside the walls, solid yellow, 6 cm.
    k = 4.78
    for a, b in (((-k, -k), (k, -k)), ((k, -k), (k, k)), ((k, k), (-k, k)), ((-k, k), (-k, -k))):
        line("yellow", a, b, 0.06)
    # Metre grid: small crosses at every metre, not on the tapes or the pivot rings.
    for gx in range(-4, 5):
        for gz in range(-4, 5):
            if math.hypot(gx, gz) < 1.7 or gz == 4 or gx == 4:
                continue
            line("white", (gx - 0.07, gz), (gx + 0.07, gz), 0.025)
            line("white", (gx, gz - 0.07), (gx, gz + 0.07), 0.025)
    # Measuring tapes: along z = +4.3 (south, x -4..4) and x = +4.3 (east, z -4..3), ticks
    # inward, numbers between the tape and the keep-out line (clear of start box B).
    for axis in ("south", "east"):
        def at(t, off):
            return (t, 4.3 + off) if axis == "south" else (4.3 + off, t)
        end = 4.0 if axis == "south" else 3.6
        line("white", at(-4.0, 0.0), at(end, 0.0), 0.04)
        for i in range(0, int(round((end + 4.0) * 10)) + 1):
            t = -4.0 + i * 0.1
            ln = 0.28 if i % 10 == 0 else (0.18 if i % 5 == 0 else 0.1)
            line("white", at(t, 0.0), at(t, -ln), 0.025 if i % 10 else 0.04)
        for m in range(0, 9 if axis == "south" else 8):
            t = -4.0 + m
            text("white", *at(t + 0.13, 0.24), str(m), stencil)
        text("yellow", *at(-3.35, 0.27), "METRES", small)
    # Pivot rings in the middle, with 15 degree ticks between them and a cross.
    for r, w in ((0.75, 0.05), (1.3, 0.05)):
        bb = [P(-r, -r), P(r, r)]
        dr["white"].ellipse([bb[0], bb[1]], outline=255, width=W(w))
    for i in range(24):
        a = math.radians(i * 15)
        r0 = 1.08 if i % 6 else 0.85
        line("white", (r0 * math.cos(a), r0 * math.sin(a)), (1.3 * math.cos(a), 1.3 * math.sin(a)),
             0.03 if i % 6 else 0.045)
    line("yellow", (-0.2, 0), (0.2, 0), 0.04)
    line("yellow", (0, -0.2), (0, 0.2), 0.04)
    text("white", 0.0, -1.55, "PIVOT", small)
    # Start boxes round both spawns (fight_types.gd SPAWN_PLAYER / SPAWN_OPPONENT, +-3.2).
    for (cx, cz, lab) in ((-3.2, -3.2, "A"), (3.2, 3.2, "B")):
        h = 0.75
        for sx in (-1, 1):
            for sz in (-1, 1):
                x0, z0 = cx + sx * h, cz + sz * h
                line("yellow", (x0, z0), (x0 - sx * 0.35, z0), 0.07)
                line("yellow", (x0, z0), (x0, z0 - sz * 0.35), 0.07)
        text("yellow", cx, cz + 1.0 if lab == "A" else cz - 1.0, lab, stencil)
    # Impact lane in front of the target pad (north wall, z -5): a hatched strike zone at
    # the wall foot and range lines across at 1, 2 and 3 m from the pad's face.
    face = -4.88
    x0, x1 = -1.0, 1.0
    zone = [P(x0, face), P(x1, face + 0.55)]
    dr["yellow"].rectangle(zone, fill=255)
    hatch = Image.new("L", (big, big), 0)
    hd = ImageDraw.Draw(hatch)
    step = 0.24
    t = x0 - 0.6
    while t < x1 + 0.1:
        hd.polygon([P(t, face), P(t + step * 0.5, face), P(t + step * 0.5 + 0.55, face + 0.55),
                    P(t + 0.55, face + 0.55)], fill=255)
        t += step
    clip = Image.new("L", (big, big), 0)
    ImageDraw.Draw(clip).rectangle(zone, fill=255)
    layers["black"] = Image.fromarray(np.minimum(np.asarray(hatch), np.asarray(clip)).astype(np.uint8))
    dr["black"] = ImageDraw.Draw(layers["black"])
    for d in (1.0, 2.0, 3.0):
        line("white", (x0, face + d), (x1, face + d), 0.05)
        text("white", x1 + 0.28, face + d, "%dM" % int(d), small)
    line("white", (x0, face + 0.55), (x0, face + 3.0), 0.04)
    line("white", (x1, face + 0.55), (x1, face + 3.0), 0.04)

    # The sealed concrete sits darker than the paint, so the lines carry at 7 m.
    mul *= 0.6
    # Down to map size, worn by the floor's own noise, scuffed where the machines run.
    wear = np.clip(0.55 + 0.9 * (fine - 0.5) + 0.35 * (value_noise(size, 12, rng, 3) - 0.5), 0, 1)
    wear = np.clip((wear - 0.12) / 0.5, 0, 1) * 0.92
    for name, col in (("white", WORKSHOP_WHITE), ("yellow", WORKSHOP_YELLOW), ("black", WORKSHOP_BLACK)):
        a = np.asarray(layers[name].resize((size, size), Image.LANCZOS), np.float32) / 255.0 * wear
        c = np.array(col, np.float32)
        mul[...] = mul * (1.0 - a[..., None]) + c * (0.85 + 0.15 * mul) * a[..., None]
        height += a * 0.25


def workshop_floor():
    """The workshop test bay: sealed grey concrete in saw-cut bays (the seams), a painted
    test floor over it (_workshop_paint), light tyre marks from testing, a few drips.
    The normal map (joints and paint edges) imports at 512 (size_limit) for the package."""
    yard_floor("workshop_floor", seed=4444, oil=3, tyres=7, drips=30, damp_on=False, rivets=False,
               weld_share=0.0, patch_clean=False, cracks=0, paint=_workshop_paint,
               tone_range=(0.94, 1.03))


def workshop_wall():
    """1024 x 512 RGB, two 1024 x 256 bands for the workshop's walls: 0 a pegboard tool
    wall (shadow-board outlines with the tools hung in them), 1 the stencil wall sign
    ("TEST BAY" on a painted band). Invented, no brands."""
    rng = np.random.default_rng(4545)
    out = Image.new("RGB", (1024, 512))
    # Pegboard.
    img = Image.new("RGB", (1024, 256), (58, 62, 58))
    d = ImageDraw.Draw(img)
    for y in range(8, 256, 16):
        for x in range(8, 1024, 16):
            d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=(24, 25, 24))
    tools = [("spanner", 16), ("hammer", 0), ("spanner", 0), ("screwdriver", 0), ("pliers", 0),
             ("spanner", 0), ("saw", 0), ("screwdriver", 0), ("spanner", 0), ("hammer", 0),
             ("pliers", 0), ("screwdriver", 0), ("spanner", 0), ("square", 0)]
    x = 30
    steel = (150, 152, 156)
    grip = [(190, 40, 30), (230, 170, 30), (30, 70, 150), (30, 30, 32)]
    for i, (kind, _) in enumerate(tools):
        g = grip[i % len(grip)]
        cx = x
        if kind == "spanner":
            L = rng.integers(120, 190)
            d.rounded_rectangle([cx - 14, 40, cx + 14, 40 + L], 10, outline=(236, 230, 200), width=3)
            d.rectangle([cx - 7, 50, cx + 7, 40 + L - 10], fill=steel)
            d.ellipse([cx - 12, 36, cx + 12, 60], fill=steel)
            x += 44
        elif kind == "hammer":
            d.rectangle([cx - 30, 36, cx + 30, 60], outline=(236, 230, 200), width=3)
            d.rectangle([cx - 28, 38, cx + 28, 58], fill=(70, 72, 76))
            d.rectangle([cx - 7, 58, cx + 7, 200], fill=g)
            x += 74
        elif kind == "screwdriver":
            d.rectangle([cx - 9, 40, cx + 9, 110], fill=g)
            d.rectangle([cx - 3, 110, cx + 3, 200], fill=steel)
            x += 34
        elif kind == "pliers":
            d.polygon([(cx - 4, 40), (cx + 4, 40), (cx + 16, 180), (cx + 4, 180), (cx, 100), (cx - 4, 180), (cx - 16, 180)], fill=steel)
            d.rectangle([cx - 18, 120, cx - 6, 190], fill=g)
            d.rectangle([cx + 6, 120, cx + 18, 190], fill=g)
            x += 54
        elif kind == "saw":
            d.polygon([(cx - 20, 50), (cx + 60, 50), (cx + 60, 70), (cx - 20, 200)], fill=steel)
            d.rectangle([cx - 36, 40, cx - 8, 90], fill=g)
            x += 104
        else:
            d.rectangle([cx - 4, 40, cx + 4, 200], fill=steel)
            d.rectangle([cx - 4, 192, cx + 70, 200], fill=steel)
            x += 90
        x += int(rng.integers(8, 22))
        if x > 990:
            break
    img = _grunge(img, rng, 0.25)
    out.paste(img, (0, 0))
    # Wall sign band.
    sign = Image.new("RGB", (1024, 256), (38, 44, 50))
    sd = ImageDraw.Draw(sign)
    stencil = font("SairaStencilOne-Regular.ttf", 136)
    sd.text((512, 128), "TEST BAY", font=stencil, fill=(236, 190, 40), anchor="mm")
    sign = _grunge(sign, rng, 0.35)
    out.paste(sign, (0, 256))
    out.save(os.path.join(OUT, "workshop_wall.png"), optimize=True)


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
    furnace_floor()
    crush_floor()
    coliseum_floor()
    workshop_floor()
    workshop_wall()
    print("wrote", sorted(os.listdir(OUT)))


if __name__ == "__main__":
    main()
