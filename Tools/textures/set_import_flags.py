#!/usr/bin/env python3
"""set_import_flags.py - fix the Godot import settings on the texture PNGs.

Godot's default for a freshly imported PNG is mipmaps/generate=false. It flips
that on by itself only when the *editor* first notices the texture being used
on a 3D material (detect_3d/compress_to). A headless import, which is how this
project builds and tests, never notices, so without this step every texture
would ship without mipmaps.

That is not a small thing here: the arena floor is tiled 4x and viewed at a
50 degree pitch, so its far half is minified hard. Without mipmaps it aliases
into a crawling moire the moment the camera moves - the single most obvious
"not a real game" artefact there is, and the exact opposite of the PS4-class
bar this work is for.

It also forces compress/mode=2 (VRAM Compressed) on every texture. Godot's
default is Lossless, which is the wrong default for a phone: a GPU cannot sample
a PNG, so a "lossless" texture is stored raw in the pck and costs full
uncompressed RGBA in VRAM. VRAM Compressed keeps the ETC2/ASTC blocks all the
way to the sampler. This needs rendering/textures/vram_compression/
import_etc2_astc=true in project.godot, or the mobile variants are never built.

Normal maps additionally get compress/normal_map=1 (two-channel normal path,
treated as linear rather than sRGB) and compress/high_quality=true (ASTC 4x4
rather than ETC2), because normals are the maps that actually suffer from block
compression.

Safe to re-run. Only touches keys it owns - in particular it leaves G1's
roughness/mode and roughness/src_normal (roughness-from-normal, the specular
anti-aliasing fix) alone - and only rewrites a file that actually changes, so
Godot does not re-import the whole set for nothing.
"""

from __future__ import annotations

import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TEX = os.path.join(ROOT, "Arena", "assets", "textures")


def patch(path: str) -> bool:
    with open(path) as fh:
        text = fh.read()

    # compress/mode=2 is VRAM Compressed (0=Lossless, 1=Lossy, 3=VRAM Uncompressed,
    # 4=Basis Universal). Lossless is Godot's default and it is the wrong default for
    # a phone: the GPU cannot sample a PNG, so a "lossless" texture is decompressed to
    # raw RGBA in VRAM and stored raw in the pck. VRAM Compressed keeps the ETC2/ASTC
    # blocks all the way to the sampler, which is both ~6x smaller on disk and the only
    # form that does not cost full uncompressed VRAM on device.
    wanted = {"mipmaps/generate": "true", "compress/mode": "2"}

    if os.path.basename(path).endswith("_normal.png.import"):
        # normal_map=1 switches the importer to the two-channel normal path, which
        # stores XY only and reconstructs Z. That is dramatically better than putting a
        # normal through ordinary RGB block compression, where the three channels
        # compete for the same endpoint line.
        wanted["compress/normal_map"] = "1"
        # high_quality picks ASTC 4x4 over ETC2 on mobile. Paid only on the normals,
        # which are the maps that actually suffer from block compression - a wrong
        # normal shows up as shading that crawls, which is far more visible than a
        # slightly wrong albedo value.
        wanted["compress/high_quality"] = "true"

    out = text
    for key, value in wanted.items():
        pattern = re.compile(r"^" + re.escape(key) + r"=.*$", re.MULTILINE)
        if pattern.search(out):
            out = pattern.sub(f"{key}={value}", out)
        else:
            out = out.replace("[params]\n", f"[params]\n\n{key}={value}\n", 1)

    if out == text:
        return False
    with open(path, "w") as fh:
        fh.write(out)
    return True


def main() -> int:
    if not os.path.isdir(TEX):
        print(f"error: no {TEX}", file=sys.stderr)
        return 1
    found = changed = 0
    for dirpath, _dirs, files in os.walk(TEX):
        for name in sorted(files):
            if not name.endswith(".png.import"):
                continue
            found += 1
            if patch(os.path.join(dirpath, name)):
                changed += 1
    if found == 0:
        print("no .import files yet - run `Godot --headless --path Arena --import` first")
        return 1
    print(f"import flags: {changed} of {found} .import files updated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
