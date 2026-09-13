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

Also sets compress/normal_map=1 on the normal maps, which tells the importer
that the texture is a normal map: it is then treated as linear rather than
sRGB, and compressed with the channel layout meant for normals.

Safe to re-run. Only touches keys it owns, and only rewrites a file that
actually changes, so Godot does not re-import the whole set for nothing.
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

    wanted = {"mipmaps/generate": "true"}
    if os.path.basename(path).endswith("_normal.png.import"):
        wanted["compress/normal_map"] = "1"

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
