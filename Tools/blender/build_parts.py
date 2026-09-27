"""Roboteer part generator (agent G3).

    ~/Applications/Blender.app/Contents/MacOS/Blender -b --python \
        Tools/blender/build_parts.py -- [--only wedge,flipper] [--out DIR] [--no-uv]

Writes Arena/assets/parts/<category>/<id>.glb plus
Arena/assets/parts/manifest.json.  See docs/graphics-models-notes.md.
"""

import argparse
import json
import os
import sys
import time

_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)

import rkit                                        # noqa: E402
import parts_chassis                               # noqa: E402
import parts_drive                                 # noqa: E402
import parts_weapon                                # noqa: E402
import parts_boss                                 # noqa: E402
import parts_misc                                  # noqa: E402
import parts_hero                                  # noqa: E402
from verify_parts import read_glb, manifest_entry  # noqa: E402

REPO = os.path.abspath(os.path.join(_HERE, "..", ".."))
DEFAULT_OUT = os.path.join(REPO, "Arena", "assets", "parts")
CATALOGUE = os.path.join(REPO, "Shared", "parts.json")

# id -> (builder, catalogue section or None)
REGISTRY = {}
for _i, _f in parts_chassis.BUILDERS.items():
    REGISTRY[_i] = (_f, "chassis", _i)
for _i, _f in parts_drive.BUILDERS.items():
    REGISTRY[_i] = (_f, None, None)
for _i, _f in parts_weapon.BUILDERS.items():
    REGISTRY[_i] = (_f, "weapon", _i)
for _i, _f in parts_misc.BUILDERS.items():
    REGISTRY[_i] = (_f, None, None)
for _i, _f in parts_boss.BUILDERS.items():
    REGISTRY[_i] = (_f, None, None)
# Wave A: the hero build's v2 parts REPLACE the v1 builders of the same id (the
# v1 functions stay in their files as the reference for what changed), and add
# the chassis-fitted plates.  Registered last so they win.
for _i, _f in parts_hero.BUILDERS.items():
    REGISTRY[_i] = (_f,) + (REGISTRY[_i][1:] if _i in REGISTRY else (None, None))

ORDER = (list(parts_chassis.BUILDERS) + list(parts_drive.BUILDERS)
         + list(parts_weapon.BUILDERS) + list(parts_misc.BUILDERS)
         + list(parts_boss.BUILDERS))
ORDER += [_i for _i in parts_hero.BUILDERS if _i not in ORDER]

# Measured budgets.  docs/graphics-bar.md guessed 4-8k chassis and 300-800 for a
# panel before anyone had rendered one; the second detail pass (washers and
# recessed sockets on every visible fastener, pressed ribs, diamond tread,
# cable channels, drain slots, edge rails) costs more than that and is what
# carries the PS4 read.  Raised deliberately, see docs/graphics-models-notes.md.
BUDGET = {"chassis": 12000, "drive": 1000, "weapon": 6000,
          "armour": 1800, "utility": 3000, "fx": 40, "boss": 8000}
BUDGET_NOTE = {"track_unit": 2600,
               # Wave P (agent E).  The three new drives are not wheels either: a
               # leg is a four-off sub-assembly, a hover is a skirt plus four
               # ducted fans, and the segmented belt is a link at a time.
               "adaptive_tracks": 4200, "hover": 3600, "legs": 1600,
               # Wave A hero (v2) parts: lathed tyre with 32 chevron lugs, a
               # folded flipper sheet with its gas system, fitted plates with
               # button-head hardware.  Godot generates LODs on import
               # (meshes/generate_lods), so this is the close-up cost only.
               # docs/wave-a-models-notes.md section 5.
               # Pass 2 (2026-09-25): block tread tyre, shoulder-pod shell on the
               # lid, louvred upper flank, exposed drive motors on the hull.
               # Hero build 58.1k on screen (was 42.1k), under the 60k ceiling.
               "wheel_standard": 5600, "flipper": 7600, "wedge": 11700,
               # Hull pass 2 (2026-09-27): two pressings a side on the lid
               # (8.6k); hero build about 58.7k, still under 60k.
               "plate_wedge_top": 8800, "plate_wedge_top_hdpe": 8800,
               "plate_wedge_sides": 2300, "plate_wedge_sides_hdpe": 2300,
               "plate_wedge_rear": 2400, "plate_wedge_rear_hdpe": 2400}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--no-uv", action="store_true")
    args = ap.parse_args(argv)

    with open(CATALOGUE) as fh:
        cat = json.load(fh)

    wanted = [w.strip() for w in args.only.split(",") if w.strip()] or ORDER
    unknown = [w for w in wanted if w not in REGISTRY]
    if unknown:
        raise SystemExit("unknown part ids: %s" % ", ".join(unknown))

    os.makedirs(args.out, exist_ok=True)
    manifest_path = os.path.join(args.out, "manifest.json")
    manifest = {"schema": 1, "generator": "Tools/blender/build_parts.py",
                "axis": "bot: +X forward, +Y up, +Z right; glTF/Godot coordinates "
                        "are identical to the authored bot coordinates",
                "units": "metres", "origin": "chassis centre on the axle plane "
                                             "(%.3f m above the floor)" % rkit.WHEEL_RADIUS,
                "materials": [m[0] for m in rkit.MATERIALS], "parts": {}}
    if os.path.exists(manifest_path):
        try:
            with open(manifest_path) as fh:
                old = json.load(fh)
            manifest["parts"] = old.get("parts", {})
        except Exception:
            pass

    total_tris = 0
    t0 = time.time()
    for ident in wanted:
        fn, section, key = REGISTRY[ident]
        spec = cat[section][key] if section else None
        t1 = time.time()
        part = fn(spec)
        path, tris = rkit.finish_and_export(part, args.out, uv=not args.no_uv)
        glb = read_glb(path)
        entry = manifest_entry(ident, part.category, path, glb, args.out)
        manifest["parts"][ident] = entry
        total_tris += entry["tris"]
        budget = BUDGET_NOTE.get(ident, BUDGET.get(part.category, 8000))
        flag = "  OVER BUDGET" if entry["tris"] > budget else ""
        print("  %-22s %-8s %6d tris  %6.1f kB  %2d sockets  %4.1fs%s"
              % (ident, part.category, entry["tris"], entry["bytes"] / 1024.0,
                 len(entry["sockets"]), time.time() - t1, flag))
        sys.stdout.flush()

    with open(manifest_path, "w") as fh:
        json.dump(manifest, fh, indent=1, sort_keys=True)
        fh.write("\n")
    size = sum(e["bytes"] for e in manifest["parts"].values())
    print("built %d parts, %d tris, %.2f MB total, %.1fs"
          % (len(wanted), total_tris, size / 1048576.0, time.time() - t0))


if __name__ == "__main__":
    main()
