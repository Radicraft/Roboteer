#!/usr/bin/env python3
"""Write the `y` of every deck slot in Arena/data/fitment.json from the drawn geometry.

    python3 Tools/fitment/seat_utilities.py DUMP_DIR

DUMP_DIR is a dump from `Arena/qa/fitment_dump.gd ... armour` (every chassis, every
armour material and thickness). For each chassis the top surface of the drawn hull and
plates is taken over every material and thickness (the plates' outer face does not move
with either, see Bot._generic_plate_fit), and each deck slot's y is the 85th percentile of
the surface heights under the largest deck part's footprint at that slot's scale. The part's own origin is
its base (the utility models are authored standing on y = 0), so it sits ON that point.
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fitment_check as fc  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FITMENT = os.path.join(REPO, "Arena", "data", "fitment.json")
MANIFEST = os.path.join(REPO, "Arena", "assets", "parts", "manifest.json")
DECK_PARTS = ("spare_battery", "counterweight", "overcharge_core")
SEAT_PERCENTILE = 85


def _seat(slot, groups, half_x, half_z):
    s = float(slot.get("scale", 1.0))
    lo = np.array([int(np.floor((slot["x"] - half_x * s) / fc.H)), -200,
                   int(np.floor((slot["z"] - half_z * s) / fc.H))])
    hi = np.array([int(np.ceil((slot["x"] + half_x * s) / fc.H)), 400,
                   int(np.ceil((slot["z"] + half_z * s) / fc.H))])
    top = -1.0
    for g in groups:
        a = g.window(lo, hi)
        cols = a.any(axis=1)
        if not cols.any():
            continue
        # top of each (x, z) column, then the slot's percentile of them: the part stands
        # on the deck, and a rail or a bolt head under one edge goes into its base
        # rather than holding it up in the air.
        first = a.shape[1] - 1 - np.argmax(a[:, ::-1, :], axis=1)
        heights = (lo[1] + first[cols] + 1) * fc.H
        pct = float(slot.get("seat_percentile", SEAT_PERCENTILE))
        top = max(top, float(np.percentile(heights, pct)))
    return top


def main():
    dump = sys.argv[1]
    fc.load_meshes(os.path.join(dump, "meshes.json"))
    manifest = json.load(open(MANIFEST))["parts"]
    # The footprint that must sit ON the deck: the base of every deck part (their
    # authored origin is the base centre). The overcharge core's aabb runs to -0.14 in x
    # for a cable stub at its top; the base block is the battery's size.
    half_x = max(max(abs(manifest[p]["aabb_min"][0]), abs(manifest[p]["aabb_max"][0])) for p in DECK_PARTS)
    half_z = max(max(abs(manifest[p]["aabb_min"][2]), abs(manifest[p]["aabb_max"][2])) for p in DECK_PARTS)
    # Two surfaces per chassis: under a chassis-FITTED top plate (plate_<chassis>_top,
    # the wedge's crest over its pods) and under the GENERIC top plate some materials
    # fall back to (reactive armour on the wedge: a flat plate over the whole deck).
    surfaces = {}
    for line in open(os.path.join(dump, "configs.jsonl")):
        row = json.loads(line)
        cfg = row["config"]
        occs = []
        kind = "fitted"
        for m in row["meshes"]:
            g, _ = fc.classify(m, cfg)
            if g in ("hull", "armour"):
                occs.append(fc.vox_mesh(m["key"], m["xf"]))
            if m["body"] == "PanelTop" and m["model"].startswith("plate_") \
                    and not m["model"].startswith("plate_%s_" % cfg["chassis"]):
                kind = "generic"
        surfaces.setdefault(cfg["chassis"], {}).setdefault(kind, []).append(fc.Group(occs))
    fit = json.load(open(FITMENT))
    for chassis, kinds in surfaces.items():
        row = fit["chassis"].get(chassis)
        if row is None:
            continue
        for slot in row.get("deck", []):
            slot.pop("y_generic_top", None)
            for kind, groups in kinds.items():
                top = _seat(slot, groups, half_x, half_z)
                key = "y" if kind == "fitted" or len(kinds) == 1 else "y_generic_top"
                slot[key] = round(top, 4)
                print("%-10s deck (%.3f, %.3f) x%.2f %-7s -> y %.4f" % (
                    chassis, slot["x"], slot["z"], slot.get("scale", 1.0), kind, top))
    with open(FITMENT, "w") as fh:
        json.dump(fit, fh, indent=1)
        fh.write("\n")


if __name__ == "__main__":
    main()
