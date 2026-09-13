#!/usr/bin/env python3
"""make_pbr.py - turn one albedo photo into a tileable PBR set for Godot.

Roboteer agent G2. Input is a single square-ish image (in practice a Recraft
"seamless tileable material" generation, which is never actually seamless and
almost always carries a soft lighting gradient). Output is a directory holding

    <name>_albedo.png     RGB, made genuinely seamless
    <name>_normal.png     RGB tangent-space normal, +Y up (Godot/OpenGL)
    <name>_roughness.png  L
    <name>_metallic.png   L
    <name>_ao.png         L
    preview.png           the albedo tiled 2x2 plus thumbnails of the maps

and prints a seam report so the tiling can be checked without looking at it.

Pipeline, in order:

 1. flatten     divide out a heavily blurred copy of the image, which removes
                the studio lighting gradient. Without this, a tiled texture
                shows a regular grid of light and dark patches even when the
                seam itself is perfect.
 2. grade       optional desaturate / target mean / tint, so HDPE can be made
                genuinely neutral for a multiply-by-livery.
 3. seamless    mirror-blend at the borders (see make_seamless). Guarantees the
                wrapped seam is *exactly* continuous, by construction, not
                approximately.
 4. height      luminance, high-passed to drop the remaining albedo variation.
 5. normal      wrapped Sobel of the height, configurable strength.
 6. roughness   base + gain * (1 - local contrast) + dirt * (1 - albedo value)
 7. metallic    a constant, or an image mask.
 8. ao          cavity occlusion: how far below its neighbourhood a point sits.

Every blur and every derivative wraps around the borders, so the derived maps
tile exactly as well as the albedo does.

Decal mode (--decal) is different: the source is dark marks on white paper, the
alpha is keyed from darkness, the borders are faded to zero alpha instead of
being made seamless, and only albedo (RGBA) + normal + roughness are written.

Usage examples:

  python3 make_pbr.py src/brushed_steel.png out/brushed_steel --name brushed_steel \\
      --flatten 96 --normal-strength 2.5 --rough-base 0.32 --metallic 1.0

  python3 make_pbr.py src/scorch.png out/scorch --name scorch --decal \\
      --size 512 --decal-colour 18,16,15
"""

from __future__ import annotations

import argparse
import json
import os
import sys

import numpy as np
from PIL import Image

Image.MAX_IMAGE_PIXELS = None

# Rec. 709 luma. Used everywhere a single "value" is needed.
LUMA = np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)


# ---------------------------------------------------------------- primitives


def _box_blur_axis(a: np.ndarray, radius: int, axis: int) -> np.ndarray:
    """Box blur along one axis with wrap-around edges, via a cumulative sum.

    Wrapping matters: a blur that clamps at the edges biases the border pixels
    and quietly destroys the seam we worked to create.
    """
    if radius < 1:
        return a
    n = a.shape[axis]
    r = min(radius, n - 1)
    pad = [(0, 0)] * a.ndim
    pad[axis] = (r + 1, r)
    p = np.pad(a, pad, mode="wrap")
    c = np.cumsum(p, axis=axis, dtype=np.float64)
    lo = np.take(c, np.arange(0, n), axis=axis)
    hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis)
    return ((hi - lo) / float(2 * r + 1)).astype(np.float32)


def wrap_blur(a: np.ndarray, sigma: float) -> np.ndarray:
    """Gaussian-ish blur that wraps: three box passes, the usual approximation.

    Three boxes of width w approximate a gaussian of sigma ~= w / sqrt(12) * ...
    close enough for lighting removal and cavity AO, and it is O(n) rather than
    O(n * kernel), which matters at 2048 with a sigma of 100.
    """
    if sigma <= 0:
        return a
    r = max(1, int(round(sigma * 0.85)))
    out = a.astype(np.float32)
    for _ in range(3):
        out = _box_blur_axis(out, r, 0)
        out = _box_blur_axis(out, r, 1)
    return out


def luminance(rgb: np.ndarray) -> np.ndarray:
    return (rgb * LUMA).sum(axis=2)


def normalise01(a: np.ndarray, lo_pct: float = 0.5, hi_pct: float = 99.5) -> np.ndarray:
    """Stretch to 0..1 on percentiles, so one stray white pixel cannot flatten
    the whole map."""
    lo = float(np.percentile(a, lo_pct))
    hi = float(np.percentile(a, hi_pct))
    if hi - lo < 1e-6:
        return np.full_like(a, 0.5)
    return np.clip((a - lo) / (hi - lo), 0.0, 1.0)


def load_rgb(path: str) -> np.ndarray:
    im = Image.open(path).convert("RGB")
    return np.asarray(im, dtype=np.float32) / 255.0


def save_rgb(a: np.ndarray, path: str) -> None:
    Image.fromarray(np.clip(a * 255.0 + 0.5, 0, 255).astype(np.uint8)).save(path, optimize=True)


def save_rgba(a: np.ndarray, path: str) -> None:
    Image.fromarray(np.clip(a * 255.0 + 0.5, 0, 255).astype(np.uint8)).save(path, optimize=True)


def save_l(a: np.ndarray, path: str, scale: float = 1.0) -> None:
    """Single-channel map. `scale` < 1 writes it smaller: roughness, AO and
    metallic are low frequency and a half-size map is indistinguishable in the
    frame while costing a quarter of the disk."""
    im = Image.fromarray(np.clip(a * 255.0 + 0.5, 0, 255).astype(np.uint8))
    if scale != 1.0:
        w = max(4, int(round(im.width * scale)))
        h = max(4, int(round(im.height * scale)))
        im = im.resize((w, h), Image.LANCZOS)
    im.save(path, optimize=True)


# ---------------------------------------------------------------- the steps


def flatten_lighting(rgb: np.ndarray, sigma: float) -> np.ndarray:
    """Divide out low-frequency illumination, keeping the overall mean.

    A generated "flat lit" material photo is never flat lit. Dividing by a very
    blurred copy of itself leaves only the detail that belongs to the material,
    which is both more correct and dramatically more tileable.
    """
    if sigma <= 0:
        return rgb
    base = wrap_blur(rgb, sigma)
    base = np.maximum(base, 1e-3)
    mean = rgb.reshape(-1, 3).mean(axis=0)
    return np.clip(rgb / base * mean, 0.0, 1.0)


def equalise_detail(rgb: np.ndarray, sigma: float, amount: float, limit: float = 2.5) -> np.ndarray:
    """Even out how *busy* the material is across the frame.

    Flattening fixes uneven lighting, but not uneven wear. A generator will
    happily put a dense thicket of scratches across one half of the image and
    leave the other half almost clean. Flattening cannot see that, because the
    local mean is the same in both halves - only the local contrast differs. A
    tile like that shows a repeating band of "busy" every time it wraps.

    So: split into a local mean and a detail term, measure the local RMS of the
    detail, and rescale it towards the image-wide RMS. Wear density becomes
    uniform, and the seam band stops being visible as a stripe of busyness.
    """
    if amount <= 0.0 or sigma <= 0.0:
        return rgb
    lum = np.maximum(luminance(rgb), 1e-4)
    base = wrap_blur(lum, sigma)
    detail = lum - base
    rms = np.sqrt(np.maximum(wrap_blur(detail * detail, sigma), 1e-10))
    target = float(np.sqrt(float((detail * detail).mean())))
    gain = np.clip(target / np.maximum(rms, 1e-5), 1.0 / limit, limit)
    gain = 1.0 + amount * (gain - 1.0)
    new_lum = np.maximum(base + detail * gain, 1e-4)
    return np.clip(rgb * (new_lum / lum)[:, :, None], 0.0, 1.0)


def grade(
    rgb: np.ndarray,
    desaturate: float = 0.0,
    target_mean: float | None = None,
    tint: tuple[float, float, float] | None = None,
    contrast: float = 1.0,
) -> np.ndarray:
    out = rgb
    if desaturate > 0.0:
        lum = luminance(out)[:, :, None]
        out = out * (1.0 - desaturate) + lum * desaturate
    if contrast != 1.0:
        m = float(out.mean())
        out = np.clip((out - m) * contrast + m, 0.0, 1.0)
    if target_mean is not None:
        cur = float(luminance(out).mean())
        if cur > 1e-4:
            out = np.clip(out * (target_mean / cur), 0.0, 1.0)
    if tint is not None:
        out = np.clip(out * np.array(tint, dtype=np.float32), 0.0, 1.0)
    return out


def make_seamless(a: np.ndarray, band_frac: float = 0.14, mode: str = "mirror") -> np.ndarray:
    """Make the image wrap exactly, by mirror-blending the borders.

    The trick: near the left edge, blend the image with its own left-right
    mirror. At x = 0 the mirror supplies column w-1, so a 50/50 mix there gives
    0.5*A[0] + 0.5*A[w-1]. At x = w-1 the mirror supplies column 0, so the mix
    there is *the same value*. Column 0 and column w-1 therefore become
    identical by construction and the wrapped seam is exact, not merely small.
    The blend weight falls from 0.5 at the border to 0 at `band`, on a cosine
    ramp, so the interior of the texture is untouched.

    mode="offset" rolls the image by half first, which moves the original
    (already accepted) border content into the middle of the tile. Useful when
    the source has an obvious feature running along one edge.
    """
    if band_frac <= 0:
        return a
    out = a.astype(np.float32).copy()
    if mode == "offset":
        out = np.roll(out, (a.shape[0] // 2, a.shape[1] // 2), axis=(0, 1))

    h, w = out.shape[:2]

    def ramp(n: int, band: int) -> np.ndarray:
        # 0.5 at both borders, 0 by `band` pixels in.
        i = np.arange(n, dtype=np.float32)
        d = np.minimum(i, n - 1 - i)
        t = np.clip(d / max(1.0, float(band)), 0.0, 1.0)
        return 0.5 * 0.5 * (1.0 + np.cos(np.pi * t))  # 0.5 -> 0, cosine

    bx = max(2, int(round(w * band_frac)))
    mx = ramp(w, bx)[None, :]
    if out.ndim == 3:
        mx = mx[:, :, None]
    out = out * (1.0 - mx) + out[:, ::-1] * mx

    by = max(2, int(round(h * band_frac)))
    my = ramp(h, by)[:, None]
    if out.ndim == 3:
        my = my[:, :, None]
    out = out * (1.0 - my) + out[::-1, :] * my
    return out


def seam_report(a: np.ndarray) -> dict:
    """How visible is the wrap seam, in units of ordinary interior detail?

    seam_dx  : mean |column 0 - column w-1|, the discontinuity a 2x2 tile shows.
    inner_dx : mean |column i - column i+1| over the interior, i.e. how much a
               neighbouring pair of columns normally differs in this material.
    ratio    : seam_dx / inner_dx. 1.0 means the seam is exactly as smooth as
               any other pixel boundary in the texture, so it cannot be seen.
               Anything under ~1.5 is invisible in motion on a phone.
    """
    x = a if a.ndim == 2 else luminance(a)
    x = x * 255.0
    h, w = x.shape
    seam_dx = float(np.abs(x[:, 0] - x[:, w - 1]).mean())
    seam_dy = float(np.abs(x[0, :] - x[h - 1, :]).mean())
    inner_dx = float(np.abs(np.diff(x[:, 1 : w - 1], axis=1)).mean())
    inner_dy = float(np.abs(np.diff(x[1 : h - 1, :], axis=0)).mean())
    return {
        "seam_dx": round(seam_dx, 3),
        "seam_dy": round(seam_dy, 3),
        "inner_dx": round(inner_dx, 3),
        "inner_dy": round(inner_dy, 3),
        "ratio_x": round(seam_dx / max(inner_dx, 1e-6), 3),
        "ratio_y": round(seam_dy / max(inner_dy, 1e-6), 3),
    }


def height_from(rgb: np.ndarray, highpass: float) -> np.ndarray:
    """Estimate height from luminance, high-passed.

    Raw luminance is a bad height field because a dark *colour* is not a dent.
    Subtracting a blurred copy keeps only the local relief, which is what a
    scratch, a grain or a tread groove actually is.
    """
    lum = luminance(rgb)
    if highpass > 0:
        lum = lum - wrap_blur(lum, highpass) + 0.5
    return normalise01(lum, 0.2, 99.8)


def normal_from_height(height: np.ndarray, strength: float) -> np.ndarray:
    """Wrapped Sobel -> tangent-space normal, Godot convention (+Y up, +Z out)."""
    h = height.astype(np.float32)
    n = np.roll(h, 1, axis=0)
    s = np.roll(h, -1, axis=0)
    w_ = np.roll(h, 1, axis=1)
    e = np.roll(h, -1, axis=1)
    nw, ne = np.roll(n, 1, axis=1), np.roll(n, -1, axis=1)
    sw, se = np.roll(s, 1, axis=1), np.roll(s, -1, axis=1)
    dx = (ne + 2.0 * e + se) - (nw + 2.0 * w_ + sw)
    dy = (sw + 2.0 * s + se) - (nw + 2.0 * n + ne)
    nx = -dx * strength
    ny = -dy * strength
    nz = np.ones_like(nx)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / ln, ny / ln, nz / ln], axis=2) * 0.5 + 0.5


def roughness_from(
    rgb: np.ndarray,
    height: np.ndarray,
    base: float,
    gain: float,
    dirt: float,
    contrast_sigma: float,
) -> np.ndarray:
    """base + gain * (1 - local contrast) + dirt * (1 - albedo value).

    Local contrast is the local standard deviation of the height field. With a
    positive gain, the busy detailed areas come out *smoother* (a scratch or a
    machined groove catches the light) and the featureless areas come out
    rougher, which is what the spec asks for. A negative gain inverts that for
    materials where the wear is dull rather than shiny - tyre rubber uses one.
    """
    m = wrap_blur(height, contrast_sigma)
    var = np.maximum(wrap_blur(height * height, contrast_sigma) - m * m, 0.0)
    contrast = normalise01(np.sqrt(var), 1.0, 99.0)
    r = base + gain * (1.0 - contrast)
    if dirt != 0.0:
        r = r + dirt * (1.0 - normalise01(luminance(rgb), 1.0, 99.0))
    return np.clip(r, 0.0, 1.0)


def ao_from_height(height: np.ndarray, sigma: float, strength: float) -> np.ndarray:
    """Cavity AO: a point sitting below its neighbourhood is occluded."""
    cav = np.clip(wrap_blur(height, sigma) - height, 0.0, 1.0)
    cav = normalise01(cav, 2.0, 99.0)
    return np.clip(1.0 - strength * cav, 0.0, 1.0)


# ---------------------------------------------------------------- decal mode


def decal_alpha(rgb: np.ndarray, white: float, black: float, gamma: float) -> np.ndarray:
    """Key alpha out of a dark-marks-on-white-paper image.

    Recraft will not return transparency, so the decals are generated as marks
    on white and the paper is turned into the transparent part here.
    """
    lum = luminance(rgb)
    a = (white - lum) / max(white - black, 1e-4)
    return np.clip(a, 0.0, 1.0) ** gamma


def fade_border(a: np.ndarray, frac: float) -> np.ndarray:
    """Push the alpha to zero at the edges so a decal never shows a hard
    rectangle where the projector box ends."""
    if frac <= 0:
        return a
    h, w = a.shape
    bx = max(1, int(w * frac))
    by = max(1, int(h * frac))
    fx = np.clip(np.minimum(np.arange(w), w - 1 - np.arange(w)) / bx, 0, 1)
    fy = np.clip(np.minimum(np.arange(h), h - 1 - np.arange(h)) / by, 0, 1)
    fx = 0.5 - 0.5 * np.cos(np.pi * fx)
    fy = 0.5 - 0.5 * np.cos(np.pi * fy)
    return a * fx[None, :] * fy[:, None]


# ---------------------------------------------------------------- preview


def build_preview(
    albedo: np.ndarray,
    maps: list[tuple[str, np.ndarray]],
    path: str,
    width: int = 1024,
) -> None:
    """The albedo tiled 2x2 with the other maps as a thumbnail strip below.

    2x2 is the point: it is the smallest tiling that shows every seam (left to
    right, top to bottom, and the four-corner junction) in one glance.
    """
    h, w = albedo.shape[:2]
    if albedo.shape[2] == 4:
        chk = np.indices((h, w)).sum(axis=0) // 32 % 2
        bg = (0.30 + 0.12 * chk)[:, :, None]
        rgb = albedo[:, :, :3] * albedo[:, :, 3:4] + bg * (1.0 - albedo[:, :, 3:4])
    else:
        rgb = albedo[:, :, :3]
    tile = np.tile(rgb, (2, 2, 1))
    top = Image.fromarray(np.clip(tile * 255 + 0.5, 0, 255).astype(np.uint8))
    top = top.resize((width, int(width * tile.shape[0] / tile.shape[1])), Image.LANCZOS)

    if maps:
        tw = width // len(maps)
        th = tw
        strip = Image.new("RGB", (width, th), (20, 20, 20))
        for i, (_label, m) in enumerate(maps):
            arr = m if m.ndim == 3 else np.repeat(m[:, :, None], 3, axis=2)
            thumb = Image.fromarray(
                np.clip(arr * 255 + 0.5, 0, 255).astype(np.uint8)
            ).resize((tw, th), Image.LANCZOS)
            strip.paste(thumb, (i * tw, 0))
        out = Image.new("RGB", (width, top.height + th), (20, 20, 20))
        out.paste(top, (0, 0))
        out.paste(strip, (0, top.height))
    else:
        out = top
    out.save(path, optimize=True)


# ---------------------------------------------------------------- driver


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("source")
    p.add_argument("outdir")
    p.add_argument("--name", default=None, help="file stem; defaults to the outdir name")
    p.add_argument("--size", type=int, default=0, help="resize the source to NxN first (0 = leave alone)")
    p.add_argument("--width", type=int, default=0, help="non-square output width (with --height)")
    p.add_argument("--height-px", type=int, default=0)

    p.add_argument("--flatten", type=float, default=96.0, help="sigma for lighting removal, 0 to skip")
    p.add_argument("--equalise", type=float, default=0.0, help="0..1, even out local wear density")
    p.add_argument("--equalise-sigma", type=float, default=60.0)
    p.add_argument("--desaturate", type=float, default=0.0)
    p.add_argument("--target-mean", type=float, default=None, help="scale so mean luminance lands here")
    p.add_argument("--tint", default=None, help="r,g,b multipliers, e.g. 0.98,1.0,1.04")
    p.add_argument("--contrast", type=float, default=1.0)

    p.add_argument("--seam-band", type=float, default=0.14, help="mirror-blend band as a fraction")
    p.add_argument("--seam-mode", default="mirror", choices=["mirror", "offset"])
    p.add_argument("--no-seamless", action="store_true")

    p.add_argument("--height-highpass", type=float, default=24.0)
    p.add_argument("--normal-strength", type=float, default=2.0)

    p.add_argument("--rough-base", type=float, default=0.5)
    p.add_argument("--rough-gain", type=float, default=0.18)
    p.add_argument("--rough-dirt", type=float, default=0.0)
    p.add_argument("--rough-sigma", type=float, default=6.0)

    p.add_argument("--metallic", type=float, default=0.0)
    p.add_argument("--metallic-mask", default=None)

    p.add_argument("--ao-sigma", type=float, default=10.0)
    p.add_argument("--ao-strength", type=float, default=0.55)

    p.add_argument("--map-scale", type=float, default=0.5, help="scale for roughness/AO output")
    p.add_argument("--metallic-scale", type=float, default=0.125)

    p.add_argument("--decal", action="store_true")
    p.add_argument("--decal-white", type=float, default=0.94)
    p.add_argument("--decal-black", type=float, default=0.18)
    p.add_argument("--decal-gamma", type=float, default=1.0)
    p.add_argument("--decal-colour", default=None, help="force the RGB to this 0-255 triple")
    p.add_argument("--decal-fade", type=float, default=0.04)

    p.add_argument("--preview-width", type=int, default=1024)
    a = p.parse_args(argv)

    name = a.name or os.path.basename(a.outdir.rstrip("/"))
    os.makedirs(a.outdir, exist_ok=True)

    rgb = load_rgb(a.source)
    if a.width and a.height_px:
        rgb = np.asarray(
            Image.fromarray((rgb * 255).astype(np.uint8)).resize(
                (a.width, a.height_px), Image.LANCZOS
            ),
            dtype=np.float32,
        ) / 255.0
    elif a.size:
        rgb = np.asarray(
            Image.fromarray((rgb * 255).astype(np.uint8)).resize(
                (a.size, a.size), Image.LANCZOS
            ),
            dtype=np.float32,
        ) / 255.0

    report: dict = {"name": name, "source": os.path.basename(a.source), "size": list(rgb.shape[:2][::-1])}

    if a.decal:
        alpha = decal_alpha(rgb, a.decal_white, a.decal_black, a.decal_gamma)
        alpha = fade_border(alpha, a.decal_fade)
        if a.decal_colour:
            col = np.array([float(v) / 255.0 for v in a.decal_colour.split(",")], dtype=np.float32)
            base = np.ones_like(rgb) * col
            # keep a little of the source variation so it is not a flat sticker
            base = np.clip(base * (0.75 + 0.5 * luminance(rgb)[:, :, None]), 0, 1)
        else:
            base = rgb
        height = height_from(rgb, a.height_highpass)
        # A decal's dark marks are gouges and burns, i.e. *below* the surface,
        # so the height field is used as-is: dark reads as low, which is what a
        # scratch is. Do not invert it.
        normal = normal_from_height(height, a.normal_strength)
        rough = roughness_from(base, height, a.rough_base, a.rough_gain, a.rough_dirt, a.rough_sigma)

        rgba = np.concatenate([base, alpha[:, :, None]], axis=2)
        save_rgba(rgba, os.path.join(a.outdir, f"{name}_albedo.png"))
        save_rgb(normal, os.path.join(a.outdir, f"{name}_normal.png"))
        save_l(rough, os.path.join(a.outdir, f"{name}_roughness.png"), a.map_scale)
        build_preview(rgba, [("normal", normal), ("rough", rough)],
                      os.path.join(a.outdir, "preview.png"), a.preview_width)
        report.update({
            "mode": "decal",
            "alpha_coverage": round(float((alpha > 0.05).mean()), 4),
            "alpha_mean": round(float(alpha.mean()), 4),
        })
        print(json.dumps(report, indent=1))
        return 0

    rgb = flatten_lighting(rgb, a.flatten)
    rgb = equalise_detail(rgb, a.equalise_sigma, a.equalise)
    tint = tuple(float(v) for v in a.tint.split(",")) if a.tint else None
    rgb = grade(rgb, a.desaturate, a.target_mean, tint, a.contrast)
    before = seam_report(rgb)
    if not a.no_seamless:
        rgb = make_seamless(rgb, a.seam_band, a.seam_mode)
    after = seam_report(rgb)

    height = height_from(rgb, a.height_highpass)
    normal = normal_from_height(height, a.normal_strength)
    rough = roughness_from(rgb, height, a.rough_base, a.rough_gain, a.rough_dirt, a.rough_sigma)
    ao = ao_from_height(height, a.ao_sigma, a.ao_strength)

    if a.metallic_mask:
        metal = normalise01(luminance(load_rgb(a.metallic_mask)))
        mscale = a.map_scale
    else:
        metal = np.full(height.shape, a.metallic, dtype=np.float32)
        mscale = a.metallic_scale

    save_rgb(rgb, os.path.join(a.outdir, f"{name}_albedo.png"))
    save_rgb(normal, os.path.join(a.outdir, f"{name}_normal.png"))
    save_l(rough, os.path.join(a.outdir, f"{name}_roughness.png"), a.map_scale)
    save_l(metal, os.path.join(a.outdir, f"{name}_metallic.png"), mscale)
    save_l(ao, os.path.join(a.outdir, f"{name}_ao.png"), a.map_scale)
    build_preview(rgb, [("normal", normal), ("rough", rough), ("ao", ao)],
                  os.path.join(a.outdir, "preview.png"), a.preview_width)

    report.update({
        "mode": "tiling",
        "seam_before": before,
        "seam_after": after,
        "albedo_mean": round(float(luminance(rgb).mean()), 4),
        "roughness_mean": round(float(rough.mean()), 4),
        "metallic": a.metallic if not a.metallic_mask else "mask",
        "ao_mean": round(float(ao.mean()), 4),
    })
    print(json.dumps(report, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
