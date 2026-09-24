#!/usr/bin/env python3
"""make_masters.py - procedural texture sets for the wave A master materials.

Materials lead, wave A (docs/wave-a-materials-notes.md). Everything here is generated
from seeded noise with numpy, so it needs no source image, costs no credits and rebuilds
byte for byte. Every filter runs in the frequency domain (FFT), which is periodic by
construction: every map tiles with a seam of exactly zero, no mirror blending needed.

The brief that shaped the numbers ("why ours reads as a toy", docs/look/menu-hero-options-v2.html):
the old metal read as crumpled foil because its normal maps were strong and fine. So the
detail here lives in ROUGHNESS, not in the normal. Normals are generated at low relief and
the .tres files pull them down further; a brushed plate at menu distance should show its
grain as a stretched highlight (anisotropy plus a streaked roughness), never as bumps.

Outputs (Arena/assets/textures/...):

  painted/painted_surface.png   1024 RGBA, LINEAR data for rb_painted.gdshader
      R  roughness breakup, 0.5 = the material's own value, +-0.5 = +-range
      G  clearcoat micro-scratches, 0 = clean lacquer, 1 = a scratch
      B  chip noise, rank-equalised so a threshold of t exposes exactly t of the area
      A  grime / dust breakup, low frequency (kept >= 0.08 so no pixel is fully clear
         and the importer's alpha-border fix never rewrites RGB)
  brushed_steel/brushed_steel_{albedo,roughness,normal}.png
      1024 albedo, 1024 roughness, 512 normal. Streaks run along U, which is the tangent,
      which is the anisotropy direction (docs/wave-a-contracts.md 1.3).
  scratched_titanium/scratched_titanium_{albedo,roughness,normal}.png
      Same shape, warmer and mottled, milder streak, sparse bright scratches.

Usage:  python3 Tools/textures/make_masters.py [--preview-dir Tools/textures/previews]
"""

from __future__ import annotations

import argparse
import os

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TEX = os.path.join(ROOT, "Arena", "assets", "textures")


# ---------------------------------------------------------------- periodic helpers

def blur(img: np.ndarray, sx: float, sy: float) -> np.ndarray:
    """Gaussian blur with wrap-around, sigma in pixels along x (U) and y (V)."""
    h, w = img.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    kernel = np.exp(-2.0 * (np.pi ** 2) * ((fx * sx) ** 2 + (fy * sy) ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(img) * kernel))


def norm01(img: np.ndarray) -> np.ndarray:
    lo, hi = np.percentile(img, 0.5), np.percentile(img, 99.5)
    return np.clip((img - lo) / max(hi - lo, 1e-9), 0.0, 1.0)


def equalise(img: np.ndarray) -> np.ndarray:
    """Rank transform to a uniform 0..1 histogram."""
    flat = img.ravel()
    ranks = np.empty_like(flat)
    ranks[np.argsort(flat, kind="stable")] = np.linspace(0.0, 1.0, flat.size)
    return ranks.reshape(img.shape)


def fbm(rng, size: int, base_sigma: float, octaves: int, gain: float = 0.55,
        aniso: float = 1.0) -> np.ndarray:
    """Sum of blurred white noise, sigma halving per octave. aniso > 1 stretches along U."""
    out = np.zeros((size, size))
    amp = 1.0
    sigma = base_sigma
    for _ in range(octaves):
        n = rng.standard_normal((size, size))
        layer = blur(n, sigma * aniso, sigma)
        layer /= layer.std() + 1e-9
        out += amp * layer
        amp *= gain
        sigma = max(sigma * 0.5, 0.6)
    return out


def scratches(rng, size: int, count: int, length: tuple[float, float],
              angle_deg: float, spread_deg: float, width: float = 1.0,
              supersample: int = 2) -> np.ndarray:
    """Thin wrapped line segments, 0..1 coverage. Drawn supersampled, 3x3 tiled so a
    line crossing an edge re-enters on the far side."""
    s = size * supersample
    canvas = Image.new("L", (s, s), 0)
    draw = ImageDraw.Draw(canvas)
    for _ in range(count):
        x, y = rng.uniform(0, s, 2)
        a = np.radians(angle_deg + rng.normal(0.0, spread_deg))
        ln = rng.uniform(*length) * s
        dx, dy = np.cos(a) * ln, np.sin(a) * ln
        val = int(rng.uniform(120, 255))
        wid = max(1, int(round(width * supersample * rng.uniform(0.6, 1.2))))
        for ox in (-s, 0, s):
            for oy in (-s, 0, s):
                draw.line([(x + ox, y + oy), (x + dx + ox, y + dy + oy)], fill=val, width=wid)
    img = canvas.resize((size, size), Image.LANCZOS)
    return np.asarray(img, dtype=np.float64) / 255.0


def height_to_normal(h: np.ndarray, strength: float) -> np.ndarray:
    """Tangent-space normal, +Y up (OpenGL / Godot), wrapped central differences."""
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5 * strength
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5 * strength
    n = np.stack([-dx, dy, np.ones_like(h)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def downsample(img: np.ndarray, size: int) -> np.ndarray:
    if img.shape[0] == size:
        return img
    f = img.shape[0] // size
    if img.ndim == 2:
        return img.reshape(size, f, size, f).mean(axis=(1, 3))
    return img.reshape(size, f, size, f, img.shape[2]).mean(axis=(1, 3))


def linear_to_srgb(x: np.ndarray) -> np.ndarray:
    x = np.clip(x, 0.0, 1.0)
    return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1.0 / 2.4) - 0.055)


def save(img: np.ndarray, path: str, mode: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    arr = np.clip(np.round(img * 255.0), 0, 255).astype(np.uint8)
    Image.fromarray(arr).save(path, optimize=True)
    print("wrote", os.path.relpath(path, ROOT), arr.shape)


def seam_error(img: np.ndarray) -> float:
    """Wrapped edge difference against the interior neighbour difference; 1.0 = no seam."""
    a = np.abs(img[:, 0] - img[:, -1]).mean() + np.abs(img[0, :] - img[-1, :]).mean()
    b = np.abs(img[:, 1] - img[:, 0]).mean() + np.abs(img[1, :] - img[0, :]).mean()
    return float(a / max(b, 1e-9))


# ---------------------------------------------------------------- sets

def painted_surface(size: int = 1024, seed: int = 11) -> np.ndarray:
    rng = np.random.default_rng(seed)
    # R: roughness breakup. A soft low-frequency blotch (hand-sanded patches, overspray)
    # plus a faint fine grain. Kept gentle: +-0.5 here maps to the shader's +-range.
    blotch = fbm(rng, size, 48.0, 4, 0.5)
    grain = fbm(rng, size, 1.2, 2, 0.6)
    r = norm01(blotch * 1.0 + grain * 0.25)
    r = 0.5 + (r - 0.5) * 0.9
    # G: clearcoat micro-scratches. Swirl from polishing plus a few longer handling
    # scratches. Sparse: this is lacquer on a show machine, not a scrapyard.
    swirl = scratches(rng, size, 900, (0.01, 0.05), 0.0, 180.0, 0.7)
    long_ = scratches(rng, size, 60, (0.08, 0.25), 20.0, 25.0, 0.8)
    g = np.clip(swirl * 0.55 + long_ * 0.9, 0.0, 1.0)
    # B: chip noise. Mid-frequency blotches with a sharp fine edge, rank-equalised so the
    # shader's threshold is an area fraction.
    chips = fbm(rng, size, 10.0, 4, 0.62) + 0.35 * fbm(rng, size, 1.5, 2, 0.5)
    b = equalise(chips)
    # A: grime breakup, very low frequency.
    a = 0.08 + 0.92 * norm01(fbm(rng, size, 90.0, 3, 0.5))
    return np.stack([r, g, b, a], axis=-1)


def brushed_steel(size: int = 1024, seed: int = 23):
    rng = np.random.default_rng(seed)
    # Brush grain: white noise smeared along U. Two scales so it reads at the menu camera
    # (1 px ~ 1 mm) and still has something at 2x zoom.
    streak = norm01(blur(rng.standard_normal((size, size)), 60.0, 0.5)) - 0.5
    streak2 = norm01(blur(rng.standard_normal((size, size)), 220.0, 1.6)) - 0.5
    mottle = norm01(fbm(rng, size, 70.0, 3, 0.5)) - 0.5
    marks = scratches(rng, size, 70, (0.03, 0.18), 0.0, 35.0, 0.9)

    base = np.array([0.56, 0.57, 0.58])  # linear, docs/look/reference-study.md 3.3
    shade = 1.0 + streak * 0.07 + streak2 * 0.05 + mottle * 0.05 + marks * 0.10
    albedo = linear_to_srgb(base[None, None, :] * shade[..., None])

    # Roughness 0.32 +-0.08 (spec): streaks carry it, scratches are glossier.
    rough = 0.32 + streak * 0.16 + streak2 * 0.10 + mottle * 0.10 - marks * 0.10
    rough = np.clip(rough, 0.20, 0.46)

    height = streak * 0.6 + streak2 * 0.4 - marks * 0.6
    normal = downsample(height_to_normal(height, 1.1), 512)
    return albedo, rough, normal


def titanium(size: int = 1024, seed: int = 37):
    rng = np.random.default_rng(seed)
    streak = norm01(blur(rng.standard_normal((size, size)), 26.0, 0.6)) - 0.5
    mottle = norm01(fbm(rng, size, 36.0, 4, 0.55)) - 0.5
    cloud = norm01(fbm(rng, size, 120.0, 2, 0.5)) - 0.5
    marks = scratches(rng, size, 140, (0.01, 0.10), -30.0, 70.0, 0.9)

    base = np.array([0.54, 0.50, 0.45])  # linear, reference-study 3.3
    shade = 1.0 + streak * 0.04 + mottle * 0.07 + cloud * 0.06 + marks * 0.16
    albedo = linear_to_srgb(base[None, None, :] * shade[..., None])

    # 0.28 +-0.06, mottled rather than streaked; scratches cut glossy.
    rough = 0.28 + mottle * 0.08 + cloud * 0.04 + streak * 0.03 - marks * 0.10
    rough = np.clip(rough, 0.16, 0.40)

    height = mottle * 0.4 + streak * 0.2 - marks * 0.3
    normal = downsample(height_to_normal(height, 1.0), 512)
    return albedo, rough, normal


def preview(path: str, tiles: list[tuple[str, np.ndarray]]) -> None:
    """2x2 tiled strip of each map, for eyeballing seams."""
    cells = []
    for _name, img in tiles:
        im = img if img.ndim == 3 else np.repeat(img[..., None], 3, axis=-1)
        im = im[..., :3]
        t = np.tile(im, (2, 2, 1))
        cells.append(np.asarray(Image.fromarray((np.clip(t, 0, 1) * 255).astype(np.uint8))
                                .resize((512, 512), Image.LANCZOS)))
    strip = np.concatenate(cells, axis=1)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(strip).save(path)
    print("preview", os.path.relpath(path, ROOT))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview-dir", default=os.path.join(ROOT, "Tools", "textures", "previews"))
    args = ap.parse_args()

    surf = painted_surface()
    save(surf, os.path.join(TEX, "painted", "painted_surface.png"), "RGBA")
    for i, ch in enumerate("RGBA"):
        print(f"  painted_surface.{ch} seam ratio {seam_error(surf[..., i]):.3f}")

    for name, fn in (("brushed_steel", brushed_steel), ("scratched_titanium", titanium)):
        albedo, rough, normal = fn()
        d = os.path.join(TEX, name)
        save(albedo, os.path.join(d, f"{name}_albedo.png"), "RGB")
        save(rough, os.path.join(d, f"{name}_roughness.png"), "L")
        save(normal, os.path.join(d, f"{name}_normal.png"), "RGB")
        print(f"  {name} roughness mean {rough.mean():.3f} sd {rough.std():.3f}, "
              f"seam ratio {seam_error(rough):.3f}")
        preview(os.path.join(args.preview_dir, f"{name}_master.png"),
                [("albedo", albedo), ("rough", rough), ("normal", normal)])
    preview(os.path.join(args.preview_dir, "painted_surface.png"),
            [(c, surf[..., i]) for i, c in enumerate("RGBA")])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
