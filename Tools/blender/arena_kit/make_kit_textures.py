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
                    (yard_floor.gdshader): RGB multiplies the plate albedo (oil, tyre
                    marks, weld seams, grime along the wall feet), A is how oily and wet
                    the spot is (low roughness). The spike patch stays clean.

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


def yard_floor():
    size = 2048
    rng = np.random.default_rng(424242)
    ppm = size / YARD_EXTENT

    def to_px(x, z):
        return ((x + YARD_EXTENT / 2) * ppm, (z + YARD_EXTENT / 2) * ppm)

    mul = np.ones((size, size), np.float32)
    wet = np.zeros((size, size), np.float32)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    wx = xx / ppm - YARD_EXTENT / 2
    wz = yy / ppm - YARD_EXTENT / 2
    # General grime: low-frequency blotches plus a fine stipple.
    n1 = value_noise(size, 5, rng, 5)
    n2 = value_noise(size, 40, rng, 3)
    mul *= 0.62 + 0.38 * n1
    mul *= 0.9 + 0.1 * n2
    # The wall feet collect dirt; the middle is scrubbed by the machines.
    edge = np.maximum(np.abs(wx), np.abs(wz))
    mul *= 1.0 - 0.45 * np.clip((edge - 3.6) / 1.4, 0, 1) ** 1.5
    # Oil stains: soft pools with a splashy noise edge and a darker core, glossy.
    fine = value_noise(size, 90, rng, 3)
    for _ in range(16):
        while True:
            cx, cz = rng.uniform(-4.6, 4.6, 2)
            if max(abs(cx), abs(cz)) > 1.5:
                break
        rx, rz = rng.uniform(0.2, 0.7), rng.uniform(0.15, 0.45)
        ang = rng.uniform(0, math.pi)
        ca, sa = math.cos(ang), math.sin(ang)
        dx, dz = wx - cx, wz - cz
        u = (dx * ca + dz * sa) / rx
        v = (-dx * sa + dz * ca) / rz
        r = np.sqrt(u * u + v * v)
        field = 1.0 - r + 0.55 * (n2 - 0.5) + 0.35 * (fine - 0.5)
        m = np.clip(field / 0.25, 0, 1)
        core = np.clip((1.0 - r * 1.4) / 0.5, 0, 1)
        dark = rng.uniform(0.5, 0.68)
        mul *= 1.0 - (1.0 - dark) * m - 0.08 * core
        wet = np.maximum(wet, m * rng.uniform(0.6, 0.95))
    # Tyre marks: skids that tighten into spirals (a machine turning hard), a few
    # doughnuts; rubber black, faintly glossy. Two tracks per mark, tread broken up.
    tyre = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(tyre)
    for k in range(22):
        cx, cz = rng.uniform(-5.5, 5.5, 2)
        rad0 = rng.uniform(0.8, 3.6)
        tighten = rng.uniform(0.35, 1.0)
        span = rng.uniform(70, 200) if k % 6 else rng.uniform(300, 400)
        a0 = rng.uniform(0, 360)
        width = max(3, int(ppm * rng.uniform(0.06, 0.1)))
        track = rng.uniform(0.3, 0.42)
        strength = rng.uniform(0.3, 0.75)
        steps = 120
        for side in (-1, 1):
            prev = None
            for st in range(steps + 1):
                f = st / steps
                t = math.radians(a0 + span * f)
                r = rad0 * (1.0 - (1.0 - tighten) * f) + side * track / 2
                p = to_px(cx + r * math.cos(t), cz + r * math.sin(t))
                if prev is not None:
                    fade = math.sin(math.pi * f) ** 0.4
                    d.line([prev, p], fill=int(255 * strength * fade * rng.uniform(0.6, 1.0)), width=width)
                prev = p
    tm = np.asarray(tyre.filter(ImageFilter.GaussianBlur(3.0)), np.float32) / 255.0
    tm *= 0.5 + 0.5 * value_noise(size, 80, rng, 2)
    # Keep the spike patch itself clean (it is its own machine).
    patch = np.clip((np.maximum(np.abs(wx), np.abs(wz)) - 1.05) / 0.25, 0, 1)
    tm *= patch
    mul *= 1.0 - 0.8 * tm
    wet = np.maximum(wet, tm * 0.3)
    # Weld seams between the 2.6 m plates: a dark gap, a bead, a heat-tinted margin.
    seam = Image.new("L", (size, size), 0)
    sd = ImageDraw.Draw(seam)
    for v in (-2.6, 2.6):
        for horizontal in (True, False):
            for i in range(0, size, 5):
                wob = rng.uniform(-1.5, 1.5)
                a, _ = to_px(v, 0)
                if horizontal:
                    sd.ellipse([i - 5, a - 5 + wob, i + 5, a + 5 + wob], fill=210)
                else:
                    sd.ellipse([a - 5 + wob, i - 5, a + 5 + wob, i + 5], fill=210)
    sm = np.asarray(seam.filter(ImageFilter.GaussianBlur(1.0)), np.float32) / 255.0
    heat = np.asarray(seam.filter(ImageFilter.GaussianBlur(14)), np.float32) / 255.0
    mul *= 1.0 - 0.55 * sm
    mul *= 1.0 - 0.25 * np.clip(heat * 3, 0, 1)
    # Small drips and bolt spots.
    for _ in range(260):
        cx, cz = rng.uniform(-5.1, 5.1, 2)
        if max(abs(cx), abs(cz)) < 1.2:
            continue
        px, pz = to_px(cx, cz)
        r = rng.uniform(2, 9)
        sd2 = Image.new("L", (1, 1))
        yl, xl = int(max(pz - r, 0)), int(max(px - r, 0))
        yh, xh = int(min(pz + r, size)), int(min(px + r, size))
        m = ((xx[yl:yh, xl:xh] - px) ** 2 + (yy[yl:yh, xl:xh] - pz) ** 2) < r * r
        mul[yl:yh, xl:xh][m] *= rng.uniform(0.35, 0.7)
        wet[yl:yh, xl:xh][m] = np.maximum(wet[yl:yh, xl:xh][m], 0.6)
    # Near neutral: the sodium key brings the warmth, the map only the dirt.
    rgb = np.stack([mul * 1.0, mul * 0.985, mul * 0.97], -1)
    rgb = np.clip(rgb, 0, 1)
    out = np.concatenate([rgb, np.clip(wet, 0, 1)[..., None]], -1)
    Image.fromarray((out * 255).astype(np.uint8), "RGBA").save(
        os.path.join(OUT, "yard_floor.png"), optimize=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    floor_grime()
    chainlink()
    boards()
    gate_signs()
    noise()
    yard_floor()
    print("wrote", sorted(os.listdir(OUT)))


if __name__ == "__main__":
    main()
