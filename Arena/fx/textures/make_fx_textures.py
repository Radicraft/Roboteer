#!/usr/bin/env python3
"""make_fx_textures.py - the four FX billboard textures, drawn with PIL.

Deterministic: a fixed seed and pure maths, so re-running produces byte identical
PNGs and Godot does not re-import for nothing.

    python3 Arena/fx/textures/make_fx_textures.py

All four are WHITE with an alpha shape. The materials tint them (gold trails,
orange sparks, grey dust, orange flame), so one greyscale sprite serves several
colours and nothing in here bakes a hue that the art direction might move.

| file | size | what |
|---|---|---|
| flame_soft.png   | 128 | radial gradient, the flame cone billboard |
| spark_glow.png   |  64 | hot core with a tight halo, collect flash + detach core |
| dust_soft.png    | 128 | soft puff with a little low frequency break-up |
| trail_streak.png |  64x128 | head-to-tail streak for the bolt trail quads |
"""

from __future__ import annotations

import math
import os
import random
import re

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))


def _write(img: Image.Image, name: str) -> None:
    path = os.path.join(HERE, name)
    img.save(path, "PNG", optimize=True)
    print(f"  {name}  {img.size[0]}x{img.size[1]}")


def flame_soft(size: int = 128) -> Image.Image:
    """Radial gradient. Dense core out to 20 % of the radius, then a smoothstep
    fade to nothing at the rim, so a cone of these stacks into a soft body of
    flame instead of a bag of discs."""
    img = Image.new("RGBA", (size, size))
    px = img.load()
    c = (size - 1) * 0.5
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - c, y - c) / c
            if d >= 1.0:
                a = 0.0
            elif d <= 0.2:
                a = 1.0
            else:
                t = 1.0 - (d - 0.2) / 0.8
                a = t * t * (3.0 - 2.0 * t)   # smoothstep
                a *= a                        # a little hotter in the middle
            px[x, y] = (255, 255, 255, int(round(a * 255.0)))
    return img


def spark_glow(size: int = 64) -> Image.Image:
    """A hot point: a tiny solid core and an inverse square halo. This is the
    flash quad for a collected bolt and the white core of a detach burst."""
    img = Image.new("RGBA", (size, size))
    px = img.load()
    c = (size - 1) * 0.5
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - c, y - c) / c
            if d >= 1.0:
                a = 0.0
            else:
                core = 1.0 if d <= 0.14 else 0.0
                halo = 1.0 / (1.0 + 7.5 * d * d)
                a = min(1.0, core + halo) * (1.0 - d * d) ** 1.2
            px[x, y] = (255, 255, 255, int(round(a * 255.0)))
    return img


def dust_soft(size: int = 128) -> Image.Image:
    """A soft puff. Value noise at two octaves breaks the edge so a dust cloud
    does not read as a stack of identical circles, which is what kills a cheap
    billboard dust the instant two of them overlap."""
    rng = random.Random(4014)
    grids = []
    for cells in (7, 14):
        g = [[rng.random() for _ in range(cells + 1)] for _ in range(cells + 1)]
        for i in range(cells + 1):          # wrap so the noise has no seam
            g[i][cells] = g[i][0]
            g[cells][i] = g[0][i]
        grids.append((cells, g))

    def value(nx: float, ny: float) -> float:
        total = 0.0
        weight = 0.0
        for k, (cells, g) in enumerate(grids):
            amp = 1.0 / (k + 1)
            fx, fy = nx * cells, ny * cells
            x0, y0 = int(fx), int(fy)
            tx, ty = fx - x0, fy - y0
            sx = tx * tx * (3 - 2 * tx)
            sy = ty * ty * (3 - 2 * ty)
            a = g[y0][x0] + (g[y0][x0 + 1] - g[y0][x0]) * sx
            b = g[y0 + 1][x0] + (g[y0 + 1][x0 + 1] - g[y0 + 1][x0]) * sx
            total += (a + (b - a) * sy) * amp
            weight += amp
        return total / weight

    img = Image.new("RGBA", (size, size))
    px = img.load()
    c = (size - 1) * 0.5
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - c, y - c) / c
            n = value(x / size, y / size)
            edge = 0.84 + 0.16 * n           # the rim wobbles with the noise
            if d >= edge:
                a = 0.0
            else:
                t = 1.0 - d / edge
                a = t * t * (3.0 - 2.0 * t) * (0.74 + 0.26 * n)
            px[x, y] = (255, 255, 255, int(round(min(1.0, a) * 255.0)))
    return img


def trail_streak(w: int = 64, h: int = 128) -> Image.Image:
    """The bolt trail quad. V = 0 is the HEAD (at the bolt) and V = 1 the TAIL,
    so alpha falls off down the length; across the width it is a soft round
    section. Additive, so the falloff is the whole shape of the streak."""
    img = Image.new("RGBA", (w, h))
    px = img.load()
    for y in range(h):
        v = y / (h - 1.0)
        along = (1.0 - v) ** 2.2            # bright at the head, gone at the tail
        for x in range(w):
            u = abs(x - (w - 1) * 0.5) / ((w - 1) * 0.5)
            across = max(0.0, 1.0 - u * u)
            across = across * across * across
            a = along * across
            px[x, y] = (255, 255, 255, int(round(a * 255.0)))
    return img


def patch_imports() -> None:
    """Force mipmaps on, exactly as Tools/textures/set_import_flags.py does for the
    material textures, and for the same reason: Godot imports a PNG with
    mipmaps/generate=false and only flips it when the EDITOR first notices the
    texture on a 3D material. This project imports headless, so that never fires.
    An FX billboard without mipmaps sparkles and crawls the moment the camera moves,
    which is the cheapest possible way to look like a student project.

    Run after `Godot --headless --path Arena --import` has written the .import files.
    Safe to re-run; only rewrites a file that actually changes.
    """
    for name in sorted(os.listdir(HERE)):
        if not name.endswith(".png.import"):
            continue
        path = os.path.join(HERE, name)
        with open(path) as fh:
            text = fh.read()
        out = re.sub(r"^mipmaps/generate=.*$", "mipmaps/generate=true", text, flags=re.MULTILINE)
        if "mipmaps/generate=" not in out:
            out = out.replace("[params]\n", "[params]\n\nmipmaps/generate=true\n", 1)
        if out != text:
            with open(path, "w") as fh:
                fh.write(out)
            print(f"  mipmaps on: {name}")


def main() -> int:
    print("FX textures ->", HERE)
    _write(flame_soft(), "flame_soft.png")
    _write(spark_glow(), "spark_glow.png")
    _write(dust_soft(), "dust_soft.png")
    _write(trail_streak(), "trail_streak.png")
    patch_imports()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
