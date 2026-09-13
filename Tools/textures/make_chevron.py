#!/usr/bin/env python3
"""make_chevron.py - build the arena hazard stripe albedo.

The chevron is the one texture in the set that must not come straight out of a
generator. It runs as a band around the arena wall and along the floor edge, so
it tiles horizontally hundreds of times in a single frame, and a stripe whose
period does not divide the texture width shows a visible stutter every repeat.
A generated stripe is never exactly periodic.

So the geometry is drawn here and only the *wear* comes from Recraft: the
generated hazard-stripe image is reduced to a grunge field (its high frequency
detail, with the stripes themselves divided out) and multiplied over an exact
45 degree stripe pattern.

Period: 256 px, which divides both 2048 and 512, so the strip wraps exactly in
x and in y with no blending at all.

Colours follow docs/stage2-art-direction.md: the hazard yellow is the "dusted
down" #c3b98c rather than a saturated yellow, because the arena palette holds
exactly one strong warm - the gold bolts - and a bright chevron would compete
with it and break the readability rule.
"""

from __future__ import annotations

import argparse
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_pbr import luminance, normalise01, wrap_blur  # noqa: E402

YELLOW = np.array([0.827, 0.741, 0.290], dtype=np.float32)   # before wear
BLACK = np.array([0.105, 0.102, 0.098], dtype=np.float32)
METAL = np.array([0.553, 0.580, 0.600], dtype=np.float32)    # bare steel in the chips


def _blend(u: np.ndarray, duty: float, edge: np.ndarray) -> np.ndarray:
    """1 inside the yellow stripe, 0 inside the black one, soft across the edge."""
    hard = (u < duty).astype(np.float32)
    return hard * edge + (1.0 - hard) * (1.0 - edge)


def grunge_from(path: str, w: int, h: int) -> tuple[np.ndarray, np.ndarray]:
    """Pull a tiling wear field out of the generated hazard-stripe image.

    Returns (dirt, chips): dirt is a multiplier around 1.0 carrying the grime
    and paint thinning, chips is 0..1 where the paint has come off entirely.
    """
    src = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0
    lum = luminance(src)
    # Divide out the stripes themselves: what is left is only the wear.
    detail = lum / np.maximum(wrap_blur(lum, 14.0), 1e-3)
    detail = normalise01(detail, 1.0, 99.0)

    sh, sw = detail.shape
    tiles_y = int(np.ceil(h / sh))
    tiles_x = int(np.ceil(w / sw))
    tiled = np.tile(detail, (tiles_y, tiles_x))[:h, :w]

    dirt = 0.72 + 0.56 * tiled
    chips = np.clip((tiled - 0.80) / 0.20, 0.0, 1.0) ** 1.6
    return dirt.astype(np.float32), chips.astype(np.float32)


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("grunge_source", help="the generated hazard-stripe image, used for wear only")
    p.add_argument("out", help="output albedo png")
    p.add_argument("--width", type=int, default=2048)
    p.add_argument("--height", type=int, default=512)
    p.add_argument("--period", type=int, default=256)
    p.add_argument("--duty", type=float, default=0.5)
    p.add_argument("--soft", type=float, default=2.5, help="painted edge softness in px")
    a = p.parse_args(argv)

    if a.width % a.period or a.height % a.period:
        print(f"error: period {a.period} must divide both {a.width} and {a.height}", file=sys.stderr)
        return 2

    y, x = np.mgrid[0 : a.height, 0 : a.width].astype(np.float32)
    u = np.mod(x + y, a.period) / a.period
    d = np.minimum(np.abs(u - a.duty), np.minimum(u + (1.0 - a.duty), (1.0 - u) + a.duty))
    edge = np.clip(d * a.period / max(a.soft, 1e-3), 0.0, 1.0)
    edge = 0.5 - 0.5 * np.cos(np.pi * edge)
    mask = _blend(u, a.duty, edge)[:, :, None]

    paint = YELLOW * mask + BLACK * (1.0 - mask)
    dirt, chips = grunge_from(a.grunge_source, a.width, a.height)
    worn = paint * dirt[:, :, None]
    out = worn * (1.0 - chips[:, :, None]) + METAL * chips[:, :, None]
    out = np.clip(out, 0.0, 1.0)

    Image.fromarray((out * 255.0 + 0.5).astype(np.uint8)).save(a.out, optimize=True)

    # Prove the wrap without any blending: column 0 against column w-1.
    v = luminance(out) * 255.0
    seam_x = float(np.abs(v[:, 0] - v[:, -1]).mean())
    seam_y = float(np.abs(v[0, :] - v[-1, :]).mean())
    inner = float(np.abs(np.diff(v, axis=1)).mean())
    ymean = float(luminance(out[mask[:, :, 0] > 0.5][:, None, :]).mean()) if mask.any() else 0.0
    print(
        f"chevron {a.width}x{a.height} period={a.period} "
        f"seam_dx={seam_x:.3f} seam_dy={seam_y:.3f} inner={inner:.3f} "
        f"ratio_x={seam_x / max(inner, 1e-6):.3f} ratio_y={seam_y / max(inner, 1e-6):.3f} "
        f"yellow_mean={ymean:.3f}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
