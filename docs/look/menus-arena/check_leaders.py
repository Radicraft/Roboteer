#!/usr/bin/env python3
"""Checks the leader lines the app drew against the anchors it was fed (wave C, direction A).

    python3 docs/look/menus-arena/check_leaders.py            # every sim/leaders-*.json
    python3 docs/look/menus-arena/check_leaders.py FILE ...

Each sim/leaders-<screen>-<956|874>.json is what StageLeaderLayer drew during a `-stageAnchors`
capture (Documents/leaders-<screen>.json, copied out by the capture step). It is checked against
stage/built-<screen>-<956|874>.json, the anchors that capture was given:

  1. every leader lands on the part it names, by part id: the label's meaning decides the part
     (4WD / Drive on a wheel or track, Titanium top / Top armour on armour_top, a weapon or
     "mount" on the weapon, a damaged part on that part's own key), never an order in a list;
  2. the point it lands on is that part's anchor (normalised x the window, within 1.5 pt), and
     the part is on the lens's side of the machine;
  3. no two leaders' segments (part to elbow, elbow to tag) intersect, and no leader runs
     through another leader's tag.

Exits 1 on any fault, printing each one.
"""
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def cross(a, b):
    def orient(p, q, r):
        return (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])
    d1, d2 = orient(b[0], b[1], a[0]), orient(b[0], b[1], a[1])
    d3, d4 = orient(a[0], a[1], b[0]), orient(a[0], a[1], b[1])
    return ((d1 > 0 > d2) or (d1 < 0 < d2)) and ((d3 > 0 > d4) or (d3 < 0 < d4))


def through(seg, tag):
    x, y, w, h = tag
    x0, y0, x1, y1 = x + 1, y + 1, x + w - 1, y + h - 1
    inside = lambda p: x0 < p[0] < x1 and y0 < p[1] < y1
    if inside(seg[0]) or inside(seg[1]):
        return True
    edges = [((x0, y0), (x1, y0)), ((x1, y0), (x1, y1)), ((x1, y1), (x0, y1)), ((x0, y1), (x0, y0))]
    return any(cross(seg, e) for e in edges)


def expected(leader):
    """What the label names: ("key", {...}) or ("kind", {...}) or None when free."""
    lid, title = leader["id"], leader["title"].lower()
    first = title.split()[0] if title else ""
    if lid == "drive" or first == "drive" or first.endswith("wd"):
        return ("kind", {"wheel", "track"})
    if lid == "top" or "top" in title:
        return ("key", {"armour_top", "top"})
    if lid == "weapon" or "mount" in title:
        return ("kind", {"weapon"})
    if lid == "opponent":
        return ("key", {"opponent"})
    if lid == "player":
        return ("key", {"top", "centre"})
    if title == "hull":
        return ("key", {"chassis", "core", "centre"})
    if title == "utility":
        return ("key", {"utility", "centre"})
    if "_" in lid:  # a damaged part's own key (match result)
        return ("key", {lid})
    return None


def check(path):
    faults = []
    name = os.path.basename(path)[len("leaders-"):-len(".json")]
    screen, width = name.rsplit("-", 1)
    drawn = json.load(open(path))
    anchors_path = os.path.join(HERE, "stage", f"built-{screen}-{width}.json")
    if not os.path.exists(anchors_path):
        anchors_path = os.path.join(HERE, "stage", f"built-generic-{width}.json")
    anchors = json.load(open(anchors_path))
    w, h = drawn["size"]
    parts = {p["key"]: p for p in anchors.get("parts", [])}
    points = anchors.get("points", {})
    for lead in drawn["leaders"]:
        key, kind = lead["target_key"], lead["target_kind"]
        want = expected(lead)
        if want is not None:
            field, allowed = want
            got = kind if field == "kind" else key
            if got not in allowed and not (field == "kind" and key in allowed):
                faults.append(f"{name}: '{lead['title']}' lands on {key} ({kind}), it names {sorted(allowed)}")
        if kind == "point":
            ref = points.get(key)
        else:
            part = parts.get(key)
            ref = part["at"] if part else None
            if part is not None and not part.get("near", True):
                faults.append(f"{name}: '{lead['title']}' points at {key}, which is behind the machine")
        if ref is None:
            faults.append(f"{name}: '{lead['title']}' lands on {key}, which the anchors do not have")
        else:
            dx = abs(ref[0] * w - lead["at"][0])
            dy = abs(ref[1] * h - lead["at"][1])
            if dx > 1.5 or dy > 1.5:
                faults.append(f"{name}: '{lead['title']}' is {dx:.1f}, {dy:.1f} pt off {key}'s anchor")
    segs = [(lead["title"], [(lead["at"], lead["elbow"]), (lead["elbow"], lead["end"])], lead["tag"])
            for lead in drawn["leaders"]]
    for i in range(len(segs)):
        for j in range(i + 1, len(segs)):
            if any(cross(a, b) for a in segs[i][1] for b in segs[j][1]):
                faults.append(f"{name}: leaders '{segs[i][0]}' and '{segs[j][0]}' cross")
    for i in range(len(segs)):
        for j in range(len(segs)):
            if i != j and any(through(a, segs[j][2]) for a in segs[i][1]):
                faults.append(f"{name}: the '{segs[i][0]}' leader runs through the '{segs[j][0]}' tag")
    return faults, len(drawn["leaders"])


def main():
    files = sys.argv[1:] or sorted(glob.glob(os.path.join(HERE, "sim", "leaders-*.json")))
    all_faults = []
    if not sys.argv[1:]:
        # Coverage: every leader screen at both widths must have been captured and dumped.
        for screen in ("menu", "builder", "shop", "board", "result"):
            for width in ("956", "874"):
                if not os.path.exists(os.path.join(HERE, "sim", f"leaders-{screen}-{width}.json")):
                    all_faults.append(f"{screen}-{width}: no leaders dump (capture it with -stageAnchors)")
    for f in files:
        faults, n = check(f)
        print(f"{'FAIL' if faults else 'PASS'}  {os.path.basename(f)}: {n} leaders")
        all_faults += faults
    for line in all_faults:
        print("  " + line)
    return 1 if all_faults else 0


if __name__ == "__main__":
    sys.exit(main())
