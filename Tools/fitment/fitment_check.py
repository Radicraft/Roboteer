#!/usr/bin/env python3
"""Wave C fitment harness, half 2 of 2: judge the dump `Arena/qa/fitment_dump.gd` wrote.

    python3 Tools/fitment/fitment_check.py DUMP_DIR [--md docs/qa/fitment.md]
                                           [--json OUT.json] [--label before]

Every drawn mesh of every assembled machine is voxelised on one bot-space lattice
(3 mm) as a SOLID, using a signed crossing count along all three axes (a winding
number per column, so overlapping closed shells add instead of cancelling, and an
open column is outvoted by the other two axes). Then, per part:

  gap      mm of air between the part and what it is bolted to (hull + plates). A
           part with more than GAP_MM of air round it is FLOATING.
  buried   how much of the part is inside the hull or a plate (fraction of its
           volume, and the deepest point in mm). A deck part sunk to its waist, a
           blade whose back half is inside the nose.
  clash    cm^3 of overlap with another fitted part (a utility inside a weapon, a
           wheel through a plate, two utilities in one place).
  sweep    for every weapon body on a hinge: the volume it sweeps (spin through a
           full turn; a limited hinge through its limits) against the hull, the
           plates, the wheels and the utilities. This is "the saw pokes through".
  mirror   a part at +z with no copy of itself at -z.
  collider how far each body's collision shapes and its drawn mesh disagree.

Results are ranked worst first into a markdown table. Nothing here imports Godot.
"""
from __future__ import annotations

import argparse
import collections
import json
import math
import re
import os
import sys

import numpy as np
from scipy import ndimage

H = 0.003                      # voxel edge, metres
EPS = 0.000137                 # lattice offset: keeps columns off shared edges
GAP_MM = 5.0                   # more air than this = floating
GAP_WINDOW = 12                # voxels searched for a support (36 mm)
CLASH_CM3 = 2.0                # overlap worth reporting between two parts
SPIN_STEPS = 24

# ---------------------------------------------------------------------------
# Meshes and voxels
# ---------------------------------------------------------------------------
_MESHES: dict = {}


def load_meshes(path):
    raw = json.load(open(path))
    for k, m in raw.items():
        v = np.asarray(m["v"], dtype=np.float64).reshape(-1, 3)
        i = np.asarray(m["i"], dtype=np.int64).reshape(-1, 3)
        tri = v[i]
        # Godot's front faces are clockwise; do not trust either convention, measure
        # it: a closed outward shell has positive signed volume.
        vol = np.einsum("ij,ij->i", tri[:, 0], np.cross(tri[:, 1], tri[:, 2])).sum() / 6.0
        _MESHES[k] = (tri, 1.0 if vol >= 0 else -1.0)


def xf_of(row):
    b = np.array(row[:9], dtype=np.float64).reshape(3, 3)  # rows = basis x, y, z columns
    basis = b.T                                            # columns are the axes
    origin = np.array(row[9:12], dtype=np.float64)
    return basis, origin


def world_tris(key, xf):
    tri, orient = _MESHES[key]
    basis, origin = xf_of(xf)
    w = tri @ basis.T + origin
    if np.linalg.det(basis) < 0:
        orient = -orient
    return w, orient


class Occ:
    """A solid on the global lattice: `lo` is the index of arr[0,0,0]."""

    __slots__ = ("lo", "arr", "_depth")

    def __init__(self, lo, arr):
        self.lo = np.asarray(lo, dtype=np.int64)
        self.arr = arr
        self._depth = None

    @property
    def hi(self):
        return self.lo + np.array(self.arr.shape)

    def count(self):
        return int(self.arr.sum())

    def empty(self):
        return self.arr.size == 0 or not self.arr.any()

    def window(self, lo, hi):
        """This solid's voxels inside [lo, hi), zeros elsewhere."""
        shape = tuple(int(x) for x in (hi - lo))
        out = np.zeros(shape, dtype=bool)
        a0 = np.maximum(lo, self.lo)
        a1 = np.minimum(hi, self.hi)
        if np.any(a1 <= a0):
            return out
        src = tuple(slice(int(a0[d] - self.lo[d]), int(a1[d] - self.lo[d])) for d in range(3))
        dst = tuple(slice(int(a0[d] - lo[d]), int(a1[d] - lo[d])) for d in range(3))
        out[dst] = self.arr[src]
        return out

    def depth(self):
        """Voxels from each inside voxel to the nearest outside one (0 outside)."""
        if self._depth is None:
            padded = np.pad(self.arr, 1)
            self._depth = ndimage.distance_transform_edt(padded)[1:-1, 1:-1, 1:-1]
        return self._depth


class Group:
    """A lazy union of solids: nothing is allocated until a window is asked for."""

    __slots__ = ("members", "lo", "hi", "_count")

    def __init__(self, members):
        self.members = members
        self.lo = np.min([o.lo for o in members], axis=0)
        self.hi = np.max([o.hi for o in members], axis=0)
        self._count = None

    @property
    def arr(self):
        return self.window(self.lo, self.hi)

    def window(self, lo, hi):
        shape = tuple(int(x) for x in (hi - lo))
        out = np.zeros(shape, dtype=bool)
        for o in self.members:
            if np.any(np.minimum(hi, o.hi) <= np.maximum(lo, o.lo)):
                continue
            out |= o.window(lo, hi)
        return out

    def count(self):
        if self._count is None:
            self._count = int(self.arr.sum())
        return self._count

    def empty(self):
        return self.count() == 0


def union(occs):
    flat = []
    for o in occs:
        if o is None:
            continue
        if isinstance(o, Group):
            flat.extend(o.members)
        elif o.arr.size:
            flat.append(o)
    if not flat:
        return None
    return Group(flat)


def voxelise(tri, orient):
    """Solid occupancy of a triangle soup, by per-axis winding columns + a vote."""
    if len(tri) == 0:
        return Occ((0, 0, 0), np.zeros((0, 0, 0), dtype=bool))
    mn = tri.reshape(-1, 3).min(axis=0)
    mx = tri.reshape(-1, 3).max(axis=0)
    lo = np.floor((mn - EPS) / H).astype(np.int64) - 1
    hi = np.ceil((mx - EPS) / H).astype(np.int64) + 2
    shape = tuple(int(x) for x in hi - lo)
    votes = np.zeros(shape, dtype=np.int8)
    reliable = np.zeros(shape, dtype=np.int8)
    n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]) * orient
    for a in range(3):
        u, v = [d for d in range(3) if d != a]
        s = np.sign(n[:, a])
        keep = s != 0
        t = tri[keep]
        sa = s[keep]
        if len(t) == 0:
            continue
        # candidate columns per triangle
        pu = t[:, :, u]
        pv = t[:, :, v]
        cu0 = np.ceil((pu.min(1) - EPS) / H - 0.5).astype(np.int64)
        cu1 = np.floor((pu.max(1) - EPS) / H - 0.5).astype(np.int64)
        cv0 = np.ceil((pv.min(1) - EPS) / H - 0.5).astype(np.int64)
        cv1 = np.floor((pv.max(1) - EPS) / H - 0.5).astype(np.int64)
        nu = np.maximum(cu1 - cu0 + 1, 0)
        nv = np.maximum(cv1 - cv0 + 1, 0)
        cnt = nu * nv
        tot = int(cnt.sum())
        if tot == 0:
            continue
        idx = np.repeat(np.arange(len(t)), cnt)
        start = np.repeat(np.cumsum(cnt) - cnt, cnt)
        local = np.arange(tot) - start
        nvr = nv[idx]
        iu = cu0[idx] + local // np.maximum(nvr, 1)
        iv = cv0[idx] + local % np.maximum(nvr, 1)
        qu = (iu + 0.5) * H + EPS
        qv = (iv + 0.5) * H + EPS
        A = t[idx]
        # barycentric in the (u, v) projection
        x0, y0 = A[:, 0, u], A[:, 0, v]
        x1, y1 = A[:, 1, u], A[:, 1, v]
        x2, y2 = A[:, 2, u], A[:, 2, v]
        den = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
        ok = np.abs(den) > 1e-18
        den = np.where(ok, den, 1.0)
        l0 = ((y1 - y2) * (qu - x2) + (x2 - x1) * (qv - y2)) / den
        l1 = ((y2 - y0) * (qu - x2) + (x0 - x2) * (qv - y2)) / den
        l2 = 1.0 - l0 - l1
        inside = ok & (l0 >= 0) & (l1 >= 0) & (l2 >= 0)
        if not inside.any():
            continue
        ta = (l0 * A[:, 0, a] + l1 * A[:, 1, a] + l2 * A[:, 2, a])[inside]
        iu = iu[inside] - lo[u]
        iv = iv[inside] - lo[v]
        sg = sa[idx][inside]
        # first voxel centre past the crossing
        it = np.ceil((ta - EPS) / H - 0.5).astype(np.int64) - lo[a]
        it = np.clip(it, 0, shape[a])
        dshape = list(shape)
        dshape[a] += 1
        D = np.zeros(dshape, dtype=np.int32)
        index = [None, None, None]
        index[a] = it
        index[u] = iu
        index[v] = iv
        # entering a solid crosses a face whose outward normal points against +a
        np.add.at(D, tuple(index), (-sg).astype(np.int32))
        W = np.cumsum(D, axis=a)
        total = np.take(W, [shape[a]], axis=a)
        W = np.take(W, np.arange(shape[a]), axis=a)
        closed = (total == 0)
        closed_b = np.broadcast_to(closed, shape)
        votes += ((W > 0) & closed_b).astype(np.int8)
        reliable += closed_b.astype(np.int8)
    occ = np.where(reliable > 0, votes * 2 > reliable, False)
    return Occ(lo, occ)


_VOX_CACHE: dict = {}


def vox_mesh(key, xf):
    ck = (key, tuple(round(x, 5) for x in xf))
    o = _VOX_CACHE.get(ck)
    if o is None:
        tri, orient = world_tris(key, xf)
        o = voxelise(tri, orient)
        _VOX_CACHE[ck] = o
    return o


def rot_about(axis, angle):
    axis = axis / np.linalg.norm(axis)
    x, y, z = axis
    c, s = math.cos(angle), math.sin(angle)
    C = 1 - c
    return np.array([[c + x * x * C, x * y * C - z * s, x * z * C + y * s],
                     [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
                     [z * x * C - y * s, z * y * C + x * s, c + z * z * C]])


def xf_rotated(xf, pivot, axis, angle):
    basis, origin = xf_of(xf)
    R = rot_about(axis, angle)
    nb = R @ basis
    no = R @ (origin - pivot) + pivot
    return list(nb.T.reshape(-1)) + list(no)


# ---------------------------------------------------------------------------
# Measures
# ---------------------------------------------------------------------------
_MEMO: dict = {}


def _ids(o):
    if o is None:
        return None
    if isinstance(o, Group):
        return tuple(sorted(id(m) for m in o.members))
    return (id(o),)


def memo(fn):
    def wrapped(a, b, *rest):
        k = (fn.__name__, _ids(a), _ids(b)) + rest
        if k not in _MEMO:
            _MEMO[k] = fn(a, b, *rest)
        return _MEMO[k]
    wrapped.__name__ = fn.__name__
    return wrapped


@memo
def overlap_count(a, b):
    if a is None or b is None:
        return 0
    lo = np.maximum(a.lo, b.lo)
    hi = np.minimum(a.hi, b.hi)
    if np.any(hi <= lo):
        return 0
    return int((a.window(lo, hi) & b.window(lo, hi)).sum())


DEPTH_CAP = 20                 # voxels: depths are exact up to 60 mm, capped beyond


@memo
def buried(part, solid):
    """(fraction of part inside solid, deepest inside point in mm, capped at 60)."""
    if part is None or solid is None or part.empty():
        return 0.0, 0.0
    lo = np.maximum(part.lo, solid.lo)
    hi = np.minimum(part.hi, solid.hi)
    if np.any(hi <= lo):
        return 0.0, 0.0
    p = part.window(lo, hi)
    s = solid.window(lo, hi)
    both = p & s
    n = int(both.sum())
    if n == 0:
        return 0.0, 0.0
    wlo = lo - DEPTH_CAP
    whi = hi + DEPTH_CAP
    sw = np.pad(solid.window(wlo, whi), 1)
    d = ndimage.distance_transform_edt(sw)[1:-1, 1:-1, 1:-1]
    inner = tuple(slice(DEPTH_CAP, DEPTH_CAP + int(hi[k] - lo[k])) for k in range(3))
    depth = min(float(d[inner][both].max()), DEPTH_CAP) * H * 1000.0
    return n / max(part.count(), 1), depth


@memo
def gap_mm(part, support):
    """mm of air from the part to the nearest support voxel (0 = touching)."""
    if part is None or part.empty():
        return None
    if support is None:
        return 99.0
    lo = part.lo - GAP_WINDOW
    hi = part.hi + GAP_WINDOW
    s = support.window(lo, hi)
    if not s.any():
        return 99.0
    p = part.window(lo, hi)
    if (p & s).any():
        return 0.0
    d = ndimage.distance_transform_edt(~s)
    m = float(d[p].min())
    return max(m - 1.0, 0.0) * H * 1000.0


@memo
def unsupported_fraction(part, support, reach_vox=6):
    """Deck parts: fraction of the part's footprint columns with nothing under them."""
    if part is None or part.empty():
        return 0.0
    lo = part.lo.copy()
    hi = part.hi.copy()
    lo[1] -= reach_vox + 1
    p = part.window(lo, hi)
    s = support.window(lo, hi) if support is not None else np.zeros_like(p)
    cols = p.any(axis=1)
    if not cols.any():
        return 0.0
    # lowest part voxel per column
    first = np.argmax(p, axis=1)
    ok = np.zeros_like(cols)
    xs, zs = np.nonzero(cols)
    for x, z in zip(xs, zs):
        y = first[x, z]
        y0 = max(y - reach_vox - 1, 0)
        ok[x, z] = s[x, y0:y + 2, z].any()
    return 1.0 - ok[cols].sum() / cols.sum()


def shape_occ(shape):
    """Voxelise a collision shape analytically (box, cylinder, sphere, convex)."""
    basis, origin = xf_of(shape["xf"])
    t = shape["type"]
    if t == "box":
        e = np.array(shape["size"]) * 0.5
        corners = np.array([[sx, sy, sz] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]) * e
    elif t == "cylinder":
        r, hh = shape["radius"], shape["height"] * 0.5
        corners = np.array([[sx * r, sy * hh, sz * r] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)])
    elif t == "sphere":
        r = shape["radius"]
        corners = np.array([[sx * r, sy * r, sz * r] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)])
    elif t == "convex":
        corners = np.array(shape["points"]).reshape(-1, 3)
    else:
        return None
    w = corners @ basis.T + origin
    lo = np.floor((w.min(0) - EPS) / H).astype(np.int64) - 1
    hi = np.ceil((w.max(0) - EPS) / H).astype(np.int64) + 2
    idx = np.stack(np.meshgrid(*[np.arange(lo[d], hi[d]) for d in range(3)], indexing="ij"), -1)
    c = (idx + 0.5) * H + EPS
    local = (c - origin) @ basis        # basis columns orthonormal (scaled is fine for these)
    if t == "box":
        e = np.array(shape["size"]) * 0.5
        occ = np.all(np.abs(local) <= e, axis=-1)
    elif t == "cylinder":
        occ = (local[..., 0] ** 2 + local[..., 2] ** 2 <= shape["radius"] ** 2) & \
              (np.abs(local[..., 1]) <= shape["height"] * 0.5)
    elif t == "sphere":
        occ = (local ** 2).sum(-1) <= shape["radius"] ** 2
    else:
        from scipy.spatial import ConvexHull
        hull = ConvexHull(corners)
        eq = hull.equations
        occ = np.all(local @ eq[:, :3].T + eq[:, 3] <= 1e-9, axis=-1)
    return Occ(lo, occ)


# ---------------------------------------------------------------------------
# One machine
# ---------------------------------------------------------------------------
UTILITY_IDS = {"srimech", "rear_wedge", "skirts", "magnets", "scoop", "spare_battery",
               "counterweight", "overcharge_core"}
SPINNING = {"SawBlade", "SawBlade0", "SawBlade1", "SpinnerBar", "SpinnerDrum",
            "SpinnerRing", "DrillLance"}


def category(key):
    if key.startswith("res://assets/parts/"):
        return key.split("/")[4]
    return ""


def classify(m, cfg):
    """(group, name) for one drawn mesh."""
    key, body, model = m["key"], m["body"], m["model"]
    cat = category(key)
    if body.startswith("Panel"):
        if model == "srimech":
            return "utility", "srimech"
        if model == "scoop":
            return "utility", "scoop"
        return "armour", body[5:]
    if cat == "chassis" or (body == "Chassis" and model == cfg["chassis"]):
        return "hull", cfg["chassis"]
    if cat == "utility" or model in UTILITY_IDS:
        return "utility", model or m["node"]
    if cat == "drive" or body.startswith(("Wheel", "Leg", "Track", "Fan")):
        return "drive", body if body != "Chassis" else (model or m["node"])
    if cat == "weapon" or cat == "boss":
        return "weapon", body
    if body == "Chassis":
        return "hull", "procedural:" + m["node"]
    return "weapon", body


_SWEEP_CACHE: dict = {}
_COLLIDER_SEEN: set = set()


def analyse(row, with_colliders=True):
    cfg = row["config"]
    groups = collections.defaultdict(list)      # (group, name) -> [mesh rows]
    for m in row["meshes"]:
        groups[classify(m, cfg)].append(m)

    def occ_of(ms):
        return union([vox_mesh(m["key"], m["xf"]) for m in ms])

    occ = {k: occ_of(v) for k, v in groups.items()}
    hull = union([o for (g, _), o in occ.items() if g == "hull"])
    plates = {n: o for (g, n), o in occ.items() if g == "armour"}
    plates_all = union(list(plates.values()))
    support = union([hull, plates_all])
    utils = {n: o for (g, n), o in occ.items() if g == "utility"}
    drives = {n: o for (g, n), o in occ.items() if g == "drive"}
    weapon_bodies = {n: o for (g, n), o in occ.items() if g == "weapon"}
    weapon_all = union(list(weapon_bodies.values()))
    drive_all = union(list(drives.values()))

    findings = []

    def add(part, check, value, unit, severity, note=""):
        findings.append({"part": part, "check": check, "value": round(value, 1),
                         "unit": unit, "severity": round(severity, 2), "note": note})

    # --- utilities --------------------------------------------------------
    for name, o in utils.items():
        if name == "scoop":
            sup = union([hull] + [p for n, p in plates.items() if n != "Front"])
        else:
            sup = union([support, drive_all]) if name in ("skirts", "magnets") else support
        g = gap_mm(o, sup)
        if g is not None and g > GAP_MM:
            add("utility:" + name, "floating", g, "mm", g / GAP_MM,
                "air between the part and the hull or plate it sits on")
        frac, depth = buried(o, support if name != "scoop" else sup)
        # Belly magnets are recessed into the hull by design (a 0.11 m block under a
        # 0.05 m clearance); what matters for them is the floor check below.
        if frac > 0.30 and name != "magnets":
            add("utility:" + name, "buried", frac * 100, "% inside", frac * 3,
                "deepest %.0f mm inside the hull/plates" % depth)
        if name in ("spare_battery", "counterweight", "overcharge_core"):
            uf = unsupported_fraction(o, support)
            if uf > 0.25:
                add("utility:" + name, "overhang", uf * 100, "% footprint", uf * 2,
                    "footprint with nothing under it")
        for n2, u in utils.items():
            if n2 <= name:
                continue
            c = overlap_count(o, u) * (H * 100) ** 3
            if c > CLASH_CM3:
                add("utility:%s+%s" % (name, n2), "clash", c, "cm3", c / CLASH_CM3)
        c = overlap_count(o, weapon_all) * (H * 100) ** 3
        if c > CLASH_CM3:
            add("utility:" + name, "clash weapon", c, "cm3", c / CLASH_CM3)
        c = overlap_count(o, drive_all) * (H * 100) ** 3
        if c > CLASH_CM3 and name not in ("skirts",):
            add("utility:" + name, "clash drive", c, "cm3", c / CLASH_CM3)

    # --- weapon at rest -----------------------------------------------------
    joints = {j.get("body", ""): j for j in row.get("joints", [])}
    wname = "weapon:" + cfg["weapon"]
    for body, o in weapon_bodies.items():
        if o is None or o.empty():
            continue
        moving = body in joints
        frac, depth = buried(o, hull)
        if moving and frac > 0.10 and depth > 6:
            add(wname + "/" + body, "rest in hull", frac * 100, "% inside", frac * 4,
                "deepest %.0f mm" % depth)
        pc = overlap_count(o, plates_all) * (H * 100) ** 3
        if moving and pc > CLASH_CM3:
            add(wname + "/" + body, "rest in plates", pc, "cm3", pc / CLASH_CM3)
        dc = overlap_count(o, drive_all) * (H * 100) ** 3
        if dc > CLASH_CM3:
            add(wname + "/" + body, "rest in drive", dc, "cm3", dc / CLASH_CM3)
    if weapon_all is not None:
        g = gap_mm(weapon_all, union([support, drive_all]))
        if g is not None and g > GAP_MM:
            add(wname, "floating", g, "mm", g / GAP_MM, "no drawn part of the weapon touches the machine")

    # --- weapon sweep -------------------------------------------------------
    for body, j in joints.items():
        if body not in weapon_bodies:
            continue
        ms = groups[("weapon", body)]
        basis, origin = xf_of(j["xf"])
        axis = basis[:, 2]
        if body in SPINNING or not j.get("limit"):
            angles = np.linspace(0, 2 * math.pi, SPIN_STEPS, endpoint=False)
            label = "spin"
        else:
            lo_a, hi_a = float(j["lower"]), float(j["upper"])
            angles = np.linspace(lo_a, hi_a, 9)
            label = "swing"
        sk = (tuple((m["key"], tuple(round(x, 5) for x in m["xf"])) for m in ms),
              tuple(round(x, 5) for x in j["xf"]), label)
        sw = _SWEEP_CACHE.get(sk)
        if sw is None:
            parts = []
            for a in angles:
                for m in ms:
                    # Godot's hinge angle runs opposite to a right hand turn about the
                    # joint's +Z (checked by rendering the flipper at +80 and -80).
                    tri, orient = world_tris(m["key"], xf_rotated(m["xf"], origin, axis, -float(a)))
                    parts.append(voxelise(tri, orient))
            g = Group(parts)
            sw = Occ(g.lo, g.arr)
            _SWEEP_CACHE[sk] = sw
        rest = weapon_bodies[body]
        extra = [(hull, "hull"), (plates_all, "plates"), (drive_all, "drive")]
        extra += [(u, "utility:" + n) for n, u in utils.items()]
        for other, oname in extra:
            if other is None:
                continue
            c = overlap_count(sw, other) * (H * 100) ** 3
            c_rest = overlap_count(rest, other) * (H * 100) ** 3
            if c - c_rest > CLASH_CM3 * 2:
                frac, depth = buried(sw, other)
                add(wname + "/" + body, "%s through %s" % (label, oname), c, "cm3",
                    c / (CLASH_CM3 * 2), "deepest %.0f mm" % depth)

    # --- drive --------------------------------------------------------------
    for name, o in drives.items():
        frac, depth = buried(o, hull)
        if frac > 0.25 and depth > 10:
            add("drive:" + name, "in hull", frac * 100, "% inside", frac * 2,
                "deepest %.0f mm" % depth)
        pc = overlap_count(o, plates_all) * (H * 100) ** 3
        if pc > CLASH_CM3 * 2:
            add("drive:" + name, "through plates", pc, "cm3", pc / (CLASH_CM3 * 2))
        g = gap_mm(o, union([support] + [d for n2, d in drives.items() if n2 != name]))
        if g is not None and g > 15:
            add("drive:" + name, "floating", g, "mm", g / 15.0, "wheel/unit well clear of the hull")

    # --- the floor ----------------------------------------------------------
    floor = -float(row["info"].get("ride_height", 0.11))
    floor_k = int(math.floor((floor - EPS) / H))
    for (g, n), o in occ.items():
        if g in ("drive",) or o is None or o.empty():
            continue
        layers = np.nonzero(o.arr.any(axis=(0, 2)))[0]
        if layers.size == 0:
            continue
        below = int(floor_k - (o.lo[1] + layers[0]))
        if below <= 0:
            continue
        depth_mm = below * H * 1000.0
        if depth_mm > 4.0:
            add("%s:%s" % (g, n), "below floor", depth_mm, "mm", depth_mm / 4.0,
                "drawn below the arena floor at rest")

    # --- armour -------------------------------------------------------------
    for name, o in plates.items():
        g = gap_mm(o, hull)
        if g is not None and g > GAP_MM:
            add("armour:" + name, "floating", g, "mm", g / GAP_MM, "air between plate and hull")

    # --- mirror -------------------------------------------------------------
    placed = collections.defaultdict(list)
    for m in row["meshes"]:
        # twin by GEOMETRY (the content hash after '#'), not by node: a track unit is
        # the other side's unit turned round, so its front sprocket is the other's rear
        # one, the same mesh under another name.
        geo = m["key"].split("#")[-1] if "#" in m["key"] else m["key"]
        placed[geo].append(np.array(m["xf"][9:12]))
    for key, pts in placed.items():
        for p in pts:
            if abs(p[2]) < 0.004:
                continue
            twin = [q for q in pts if abs(q[0] - p[0]) < 0.003 and abs(q[1] - p[1]) < 0.003
                    and abs(q[2] + p[2]) < 0.003]
            if not twin:
                add("mirror:" + key.split("/")[-1][:40], "no mirror twin", abs(p[2]) * 1000,
                    "mm off axis", 0.5, "at (%.3f, %.3f, %.3f)" % tuple(p))

    # --- collider vs mesh -------------------------------------------------
    by_body = collections.defaultdict(list)
    for s in row["shapes"]:
        by_body[s["body"]].append(s)
    body_mesh = collections.defaultdict(list)
    for m in row["meshes"]:
        body_mesh[m["body"]].append(m)
    colliders = []
    for body, shapes in (by_body.items() if with_colliders else []):
        ck = (cfg["chassis"], cfg["weapon"], body if not body.startswith("Wheel") else "Wheel",
              tuple(round(x, 4) for s in shapes for x in s["xf"]))
        if ck in _COLLIDER_SEEN:
            continue
        _COLLIDER_SEEN.add(ck)
        so = union([shape_occ(s) for s in shapes])
        mo = union([vox_mesh(m["key"], m["xf"]) for m in body_mesh.get(body, [])])
        if so is None or mo is None:
            continue
        inter = overlap_count(so, mo)
        sc, mc = so.count(), mo.count()
        colliders.append({"body": body, "collider_cm3": sc * (H * 100) ** 3,
                          "mesh_cm3": mc * (H * 100) ** 3,
                          "collider_uncovered": 1 - inter / max(sc, 1),
                          "mesh_outside": 1 - inter / max(mc, 1)})
    return findings, colliders


def cfg_label(cfg):
    u = "+".join(cfg.get("utility", [])) or "-"
    t = cfg["armour"]["front"]["thickness"]
    m = cfg["armour"]["front"]["material"]
    return "%s / %s / %s / %s / %s x%d" % (cfg["chassis"], cfg["drive"], cfg["weapon"], u, m, t)


def _work(job):
    dump, chassis, sweep, grep, with_colliders = job
    load_meshes(os.path.join(dump, "meshes.json"))
    results, collider_rows = [], {}
    with open(os.path.join(dump, "configs.jsonl")) as f:
        for line in f:
            if '"chassis":"%s"' % chassis not in line and '"chassis": "%s"' % chassis not in line:
                continue
            row = json.loads(line)
            if row["config"]["chassis"] != chassis:
                continue
            if sweep and row["sweep"] != sweep:
                continue
            if grep and grep not in cfg_label(row["config"]):
                continue
            findings, colliders = analyse(row, with_colliders)
            results.append({"sweep": row["sweep"], "config": row["config"],
                            "label": cfg_label(row["config"]), "findings": findings})
            for c in colliders:
                collider_rows[(chassis, row["config"]["weapon"], c["body"])] = c
    print("  %s: %d machines" % (chassis, len(results)), file=sys.stderr, flush=True)
    return results, collider_rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dump")
    ap.add_argument("--md")
    ap.add_argument("--json")
    ap.add_argument("--label", default="")
    ap.add_argument("--sweep", default="")
    ap.add_argument("--grep", default="")
    ap.add_argument("--chassis", default="")
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--no-colliders", action="store_true")
    args = ap.parse_args()
    chassis = set()
    with open(os.path.join(args.dump, "configs.jsonl")) as f:
        for line in f:
            m = re.search(r'"chassis": ?"([a-z_]+)"', line)
            chassis.add(m.group(1))
    if args.chassis:
        chassis = set(args.chassis.split(","))
    jobs = [(args.dump, c, args.sweep, args.grep, not args.no_colliders) for c in sorted(chassis)]
    import multiprocessing as mp
    with mp.get_context("spawn").Pool(min(args.jobs, len(jobs)), maxtasksperchild=1) as pool:
        outs = pool.map(_work, jobs)
    results, collider_rows = [], {}
    for r, c in outs:
        results.extend(r)
        collider_rows.update(c)
    out = {"label": args.label, "machines": len(results), "results": results,
           "colliders": [dict(zip(("chassis", "weapon", "body"), k), **v)
                         for k, v in collider_rows.items()]}
    if args.json:
        json.dump(out, open(args.json, "w"))
    summarise(out, args.md)


def summarise(out, md_path=None):
    results = out["results"]
    failing = [r for r in results if r["findings"]]
    # distinct problems: (chassis, part, check) worst value first
    problems = {}
    for r in results:
        cfg = r["config"]
        for f in r["findings"]:
            k = (cfg["chassis"], f["part"], f["check"])
            if k not in problems or f["severity"] > problems[k]["severity"]:
                problems[k] = dict(f, chassis=cfg["chassis"], example=r["label"], count=0)
            problems[k]["count"] += 1
    ranked = sorted(problems.values(), key=lambda p: -p["severity"])
    print("%s: %d machines, %d with a finding, %d distinct problems" % (
        out.get("label", ""), len(results), len(failing), len(ranked)))
    for p in ranked[:60]:
        print("  %5.1f  %-10s %-38s %-22s %7.1f %-10s x%-4d %s" % (
            p["severity"], p["chassis"], p["part"][:38], p["check"][:22], p["value"],
            p["unit"], p["count"], p["note"]))
    if md_path:
        write_md(out, ranked, md_path)
    return ranked


def write_md(out, ranked, path):
    results = out["results"]
    lines = []
    lines.append("# Fitment table (%s)" % (out.get("label") or "latest"))
    lines.append("")
    lines.append("Generated by `Tools/fitment/fitment_check.py` from the dump written by "
                 "`Arena/qa/fitment_dump.gd`. %d machines assembled with `Bot.setup`, "
                 "%d with at least one finding, %d distinct problems "
                 "(chassis x part x check), worst first." % (
                     len(results), sum(1 for r in results if r["findings"]), len(ranked)))
    lines.append("")
    lines.append("Checks: floating = more than %.0f mm of air to the surface the part "
                 "mounts on; buried = share of the part inside the hull or plates; "
                 "clash = cm3 of overlap between two fitted parts; spin/swing through = "
                 "cm3 the weapon's moving body sweeps through something it should not; "
                 "overhang = share of a deck part's footprint with nothing under it; "
                 "mirror = a part at +z with no copy at -z. Voxels are 3 mm." % GAP_MM)
    lines.append("")
    lines.append("| # | chassis | part | check | value | seen in | example build |")
    lines.append("|---|---|---|---|---|---|---|")
    for i, p in enumerate(ranked, 1):
        lines.append("| %d | %s | %s | %s | %.1f %s | %d | %s |" % (
            i, p["chassis"], p["part"], p["check"], p["value"], p["unit"], p["count"],
            p["example"] + (" (" + p["note"] + ")" if p["note"] else "")))
    if not ranked:
        lines.append("| - | - | - | none | - | - | - |")
    lines.append("")
    cols = out.get("colliders", [])
    if cols:
        agg = {}
        for c in cols:
            b = c["body"]
            b = "Wheel" if b.startswith("Wheel") else b
            k = (c["chassis"], b)
            if k not in agg or c["collider_uncovered"] + c["mesh_outside"] > \
                    agg[k]["collider_uncovered"] + agg[k]["mesh_outside"]:
                agg[k] = c
        lines.append("## Collider vs drawn mesh (per chassis x body, worst weapon)")
        lines.append("")
        lines.append("collider uncovered = share of the collision volume with no drawn mesh "
                     "in it (hits land on thin air); mesh outside = share of the drawn "
                     "volume no collider covers (blows pass through what you can see). "
                     "Informational: shapes are physics and move fight hashes.")
        lines.append("")
        lines.append("| chassis | body | weapon | collider cm3 | mesh cm3 | collider uncovered | mesh outside |")
        lines.append("|---|---|---|---|---|---|---|")
        for k, c in sorted(agg.items(), key=lambda kv: -(kv[1]["collider_uncovered"] + kv[1]["mesh_outside"])):
            lines.append("| %s | %s | %s | %.0f | %.0f | %.0f %% | %.0f %% |" % (
                k[0], k[1], c["weapon"], c["collider_cm3"], c["mesh_cm3"],
                c["collider_uncovered"] * 100, c["mesh_outside"] * 100))
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    open(path, "w").write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
