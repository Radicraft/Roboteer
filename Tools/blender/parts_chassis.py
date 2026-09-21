"""The six chassis.  Every hull is a dark structural shell with bolted-on
livery plates, real panel gaps, weld seams along the structural corners and a
recessed core bay under the top plate.  Original silhouettes only (brief v3 §3):
no house-robot or named-competitor shapes.
"""

import math
from mathutils import Vector

from rkit import (Part, FLOOR_Y, WHEEL_RADIUS, WHEEL_WIDTH, PLATE_T, GAP, BEVEL,
                  rot_pitch, rot_z, rot_roll)

WHEEL_NAMES_6 = ["fr", "fl", "mr", "ml", "rr", "rl"]
WHEEL_NAMES_4 = ["fr", "fl", "rr", "rl"]
WHEEL_NAMES_2 = ["rr", "rl"]


# ------------------------------------------------------------------ shared

def base_top(spec):
    b = FLOOR_Y + min(spec["clearance_front"], spec["clearance_rear"])
    return b, b + spec["height"]


def hull_half_width(spec):
    """Keep the hull flank inboard of every catalogue wheel so nothing clips."""
    zs = [abs(s[1]) for group in spec["wheel_slots"].values() for s in group]
    return min(min(zs) - WHEEL_WIDTH * 0.5 - 0.006, spec["footprint"][1] * 0.5)


def core_bay(P, bay, deck_y, depth=0.036, frame="dark_metal"):
    """A recessed electronics bay: walls, floor, a glowing core and a grille."""
    x0, x1, z0, z1 = bay
    cx, cz = (x0 + x1) * 0.5, (z0 + z1) * 0.5
    sx, sz = x1 - x0, z1 - z0
    fy = deck_y - depth * 0.5
    P.box((x0 - 0.007, fy, cz), (0.014, depth, sz + 0.014), frame, bevel=0.002, seg=1)
    P.box((x1 + 0.007, fy, cz), (0.014, depth, sz + 0.014), frame, bevel=0.002, seg=1)
    P.box((cx, fy, z0 - 0.007), (sx, depth, 0.014), frame, bevel=0.002, seg=1)
    P.box((cx, fy, z1 + 0.007), (sx, depth, 0.014), frame, bevel=0.002, seg=1)
    P.box((cx, deck_y - depth, cz), (sx, 0.010, sz), frame, bevel=0.002, seg=1)
    P.box((cx, deck_y - depth + 0.016, cz), (sx * 0.74, 0.022, sz * 0.70),
          "core_glow", bevel=0.003, seg=2)
    for i in range(3):
        t = (i + 0.5) / 3.0
        P.box((x0 + sx * t, deck_y - 0.005, cz), (0.010, 0.009, sz),
              frame, bevel=0.0015, seg=1)
    for su in (-1, 1):
        for sv in (-1, 1):
            P.hardware_bolt((cx + su * (sx * 0.5 + 0.018), deck_y,
                             cz + sv * (sz * 0.5 + 0.018)), (0, 1, 0))


def deck_plates(P, x0, x1, z0, z1, y, bay, mat="livery", t=PLATE_T, seam=True,
                tread=True, rails=True):
    """Top plates laid around the bay opening, each separated by a panel gap,
    with diamond tread on anything big enough to stand on and real hardware."""
    bx0, bx1, bz0, bz1 = bay
    g = GAP
    rects = [
        (bx1 + g, x1, z0, z1),
        (x0, bx0 - g, z0, z1),
        (bx0 - g, bx1 + g, bz1 + g, z1),
        (bx0 - g, bx1 + g, z0, bz0 - g),
    ]
    for (a, b, c, d) in rects:
        if b - a < 0.03 or d - c < 0.03:
            continue
        big = (b - a) > 0.14 and (d - c) > 0.14
        P.plate(((a + b) * 0.5, y + t * 0.5, (c + d) * 0.5), (b - a, t, d - c),
                mat, axis=(0, 1, 0), inset=min(0.030, (b - a) * 0.3, (d - c) * 0.3),
                hardware=big)
        if tread and big:
            P.deck_tread((a + 0.035, y + t), (b - 0.035, y + t), c + 0.032, d - 0.032,
                         max(int((b - a) / 0.055), 2), max(int((d - c) / 0.055), 2),
                         "steel")
    if rails:
        # edge rails: the raised lip that stops anything sliding off the deck
        for sz in (z0, z1):
            P.box(((x0 + x1) * 0.5, y + t + 0.005, sz + (0.008 if sz < 0 else -0.008)),
                  (x1 - x0 - 0.02, 0.016, 0.016), "steel", bevel=0.0025, seg=1)
    if seam:
        # weld beads on the OUTSIDE corner, where they can be seen
        P.seam((x0 + 0.01, y + t * 0.5, z0 - 0.002), (x1 - 0.01, y + t * 0.5, z0 - 0.002))
        P.seam((x0 + 0.01, y + t * 0.5, z1 + 0.002), (x1 - 0.01, y + t * 0.5, z1 + 0.002))


def flank_plates(P, x0, x1, y0, y1, hw, mat="livery", t=PLATE_T, splits=2):
    """Livery plates on both flanks, split into `splits` panels with a gap
    between them.  The plate's outer face IS the hull half-width plane."""
    span = x1 - x0
    for i in range(splits):
        a = x0 + span * i / splits + (GAP * 0.5 if i else 0.0)
        b = x0 + span * (i + 1) / splits - (GAP * 0.5 if i < splits - 1 else 0.0)
        if b - a < 0.04:
            continue
        for s in (-1.0, 1.0):
            P.plate(((a + b) * 0.5, (y0 + y1) * 0.5, s * (hw - t * 0.5)),
                    (b - a, y1 - y0, t), mat, axis=(0, 0, s),
                    inset=min(0.026, (b - a) * 0.3, (y1 - y0) * 0.3))


def corner_brackets(P, x0, x1, y0, y1, hw, mat="steel", w=0.026):
    """L brackets up the four vertical corners, bolted."""
    for sx in (x0, x1):
        dx = w * 0.5 if sx == x0 else -w * 0.5
        for sz in (-hw, hw):
            dz = w * 0.5 if sz < 0 else -w * 0.5
            P.box((sx + dx, (y0 + y1) * 0.5, sz), (w, y1 - y0, 0.012), mat,
                  bevel=0.002, seg=1)
            P.box((sx, (y0 + y1) * 0.5, sz + dz), (0.012, y1 - y0, w), mat,
                  bevel=0.002, seg=1)
            for f in (0.22, 0.78):
                P.bolt((sx + dx, y0 + (y1 - y0) * f, sz), (0, 0, 1 if sz > 0 else -1), r=0.007)


def wheel_gear(P, spec, hw, boss_r=0.030):
    """Axle bosses, stubs and motor pods at every catalogue wheel position."""
    done = set()
    for group in spec["wheel_slots"].values():
        for (sx, sz) in group:
            key = (round(sx, 3), round(sz, 3))
            if key in done:
                continue
            done.add(key)
            s = 1.0 if sz > 0 else -1.0
            inner = s * (hw - 0.02)
            outer = sz - s * 0.006
            L = abs(outer - inner)
            P.cyl((sx, 0.0, (inner + outer) * 0.5), (0, 0, 1), boss_r, L,
                  "dark_metal", n=12, bevel=0.002)
            P.shaft((sx, 0.0, outer), (sx, 0.0, outer + s * 0.026), 0.014,
                    "steel", n=6, grooves=(0.62,), step=0.66)
            P.box((sx, 0.0, s * (hw - 0.055)), (0.10, 0.075, 0.07),
                  "dark_metal", bevel=0.003, seg=1)


def sockets(P, cid, spec, base, top, weapon_front=None, weapon_top=None):
    hl = spec["footprint"][0] * 0.5
    hw = spec["footprint"][1] * 0.5
    mid = (base + top) * 0.5
    ws = spec["wheel_slots"]
    for nm, s in zip(WHEEL_NAMES_6, ws["6wd"]):
        P.socket("socket_wheel_" + nm, (s[0], 0.0, s[1]))
    for nm, s in zip(WHEEL_NAMES_4, ws["4wd"]):
        P.socket("socket_wheel_4wd_" + nm, (s[0], 0.0, s[1]))
    for nm, s in zip(WHEEL_NAMES_2, ws["2wd"]):
        P.socket("socket_wheel_2wd_" + nm, (s[0], 0.0, s[1]))
    P.socket("socket_armour_front", (hl, mid, 0.0))
    P.socket("socket_armour_rear", (-hl, mid, 0.0))
    P.socket("socket_armour_sides_l", (0.0, mid, -hw))
    P.socket("socket_armour_sides_r", (0.0, mid, hw))
    P.socket("socket_armour_top", (0.0, top, 0.0))
    # socket_weapon_front is the weapon's PIVOT, on the front face of the
    # structural hull at mounting height -- not on the outer lip, which on a
    # wedge is 20 mm of plate you could not bolt a flipper to.  Placed so a
    # weapon of catalogue `reach` puts its tip at or just past the nose.
    if cid == "shell":
        P.socket("socket_weapon_shell", (0.0, 0.0, 0.0))
        P.socket("socket_weapon_front", (hl - 0.02, 0.0, 0.0))
    else:
        P.socket("socket_weapon_front", weapon_front)
        P.socket("socket_weapon_top", weapon_top)
    P.socket("socket_utility_0", (-hl * 0.60, top, 0.0))
    P.socket("socket_utility_1", (hl * 0.55, base + 0.03, 0.0))
    P.socket("socket_srimech", (-hl * 0.84, top - 0.01, 0.0))


# ------------------------------------------------------------------ chassis

def build_wedge(spec):
    P = Part("wedge", "chassis")
    base, top = base_top(spec)                    # -0.09 .. 0.09
    hw = hull_half_width(spec)                    # 0.244
    cw = hw - PLATE_T
    deck = top - PLATE_T
    nose = spec["footprint"][0] * 0.5
    lip_b, lip_t = base, base + 0.022
    rear_b = FLOOR_Y + spec["clearance_rear"]

    prof = [(nose, lip_b), (nose, lip_t), (0.04, deck), (-nose, deck),
            (-nose, rear_b), (-nose + 0.12, base)]
    P.prism(prof, -cw, cw, "dark_metal", bevel=BEVEL, seg=2)

    # the working face: a bolted steel ramp over the whole front slope
    P.slab((nose, lip_t), (0.04, deck), -hw + 0.004, hw - 0.004, PLATE_T,
           "steel", outward=(0.35, 1.0), bolts=3, inset=0.045)
    # a pair of raised strakes up the ramp so it reads as a working wedge
    for s in (-1.0, 1.0):
        P.slab((nose - 0.01, lip_t + 0.012), (0.06, deck + 0.012),
               s * 0.12 - 0.011, s * 0.12 + 0.011, 0.012, "titanium",
               outward=(0.35, 1.0))

    P.deck_tread((nose - 0.055, lip_t + 0.0005), (0.085, deck + 0.0005),
                 -hw + 0.045, hw - 0.045, 6, 6, "steel")
    P.cable_run([(-0.40, deck + PLATE_T + 0.006, 0.175),
                 (-0.06, deck + PLATE_T + 0.006, 0.175)], r=0.0055)
    for s_ in (-1.0, 1.0):
        P.drain_slots((-0.38, base + 0.010, s_ * (hw + 0.002)),
                      (0.22, base + 0.010, s_ * (hw + 0.002)), 3,
                      w=0.030, h=0.010, depth=0.014)

    bay = (-0.10, 0.02, -0.105, 0.105)
    deck_plates(P, -nose + 0.02, 0.02, -cw, cw, deck, bay)
    core_bay(P, bay, top)

    # rear electronics bay lid, raised and louvred
    P.plate((-0.27, top + 0.019, 0.0), (0.24, 0.038, 0.30), "livery",
            axis=(0, 1, 0), inset=0.03)
    P.louvres((-0.27, top + 0.040, 0.0), (0.17, 0.008, 0.24), 5)
    P.seam((-0.39, top, -0.15), (-0.39, top, 0.15))
    P.seam((-0.15, top, -0.15), (-0.15, top, 0.15))

    flank_plates(P, -nose + 0.01, nose - 0.06, base + 0.012, deck - 0.006, hw, splits=2)
    # side skirts along the bottom edge of each flank
    for s in (-1.0, 1.0):
        P.plate((-0.02, base + 0.012, s * (hw + 0.008)), (0.74, 0.030, 0.016),
                "hdpe", axis=(0, 0, s), inset=0.05)

    # rear anti-spinner slope plus a bumper bar
    P.slab((-nose, rear_b), (-nose + 0.12, base), -cw + 0.01, cw - 0.01, 0.013,
           "titanium", outward=(-1.0, -0.4))
    P.box((-nose - 0.008, deck - 0.03, 0.0), (0.016, 0.045, 2 * cw - 0.03),
          "steel", bevel=0.003, seg=2)

    wheel_gear(P, spec, hw)
    sockets(P, "wedge", spec, base, top,
            weapon_front=(0.070, deck - 0.026, 0.0), weapon_top=(0.05, top, 0.0))
    return P


def build_box(spec):
    """Stepped: a low forward working deck and a raised rear equipment bay, so
    the silhouette reads as a machine from 3/4 rather than as a cuboid."""
    P = Part("box", "chassis")
    base, top = base_top(spec)                    # -0.06 .. 0.18
    hw = hull_half_width(spec)                    # 0.244
    cw = hw - PLATE_T
    deck = top - PLATE_T                          # rear bay top
    low = base + 0.135                            # forward deck level
    hl = spec["footprint"][0] * 0.5
    cl = hl - PLATE_T
    bay_x0, bay_x1 = -cl, -0.03                   # the raised rear bay
    bw = cw - 0.026

    # lower hull, up to the forward deck
    P.box((0.0, (base + low) * 0.5, 0.0), (2 * cl, low - base, 2 * cw),
          "dark_metal", bevel=BEVEL, seg=2)
    # chamfered upper front corner: the step you can see from anywhere
    P.slab((cl + PLATE_T, low - 0.055), (cl - 0.055, low), -cw, cw, PLATE_T,
           "titanium", outward=(1.0, 1.0), bolts=2, inset=0.05)

    # forward working deck: tread, a cable channel and mounting bosses
    fdeck = [(bay_x1 + GAP, low), (cl, low)]
    P.plate(((bay_x1 + cl) * 0.5, low + PLATE_T * 0.5, 0.0),
            (cl - bay_x1, PLATE_T, 2 * cw), "livery", axis=(0, 1, 0),
            inset=0.032, hardware=True)
    P.deck_tread((bay_x1 + 0.05, low + PLATE_T), (cl - 0.045, low + PLATE_T),
                 -cw + 0.035, cw - 0.035, 4, 5, "steel")
    for s_ in (-1.0, 1.0):
        P.boss((0.24, low + PLATE_T, s_ * 0.13), (0, 1, 0), 0.026, 0.010)
        P.hardware_bolt((0.24, low + PLATE_T + 0.010, s_ * 0.13), (0, 1, 0))
    P.cable_run([(0.03, low + PLATE_T + 0.006, 0.185),
                 (0.30, low + PLATE_T + 0.006, 0.185)], r=0.006)

    # the raised rear bay
    P.box(((bay_x0 + bay_x1) * 0.5, (low + deck) * 0.5, 0.0),
          (bay_x1 - bay_x0, deck - low, 2 * bw), "dark_metal", bevel=BEVEL, seg=2)
    for s_ in (-1.0, 1.0):
        P.plate(((bay_x0 + bay_x1) * 0.5, (low + deck) * 0.5 + 0.006,
                 s_ * (bw - PLATE_T * 0.5)),
                (bay_x1 - bay_x0 - 0.02, deck - low - 0.03, PLATE_T), "livery",
                axis=(0, 0, s_), inset=0.03, hardware=True)
        P.ribs(((bay_x0 + bay_x1) * 0.5, (low + deck) * 0.5 + 0.006, s_ * (bw + 0.004)),
               (bay_x1 - bay_x0 - 0.09, deck - low - 0.05, 0.0), 3, "steel",
               normal=2, run=1, h=s_ * 0.008, w=0.013)
    P.slab((bay_x1, low), (bay_x1, deck), -bw + 0.01, bw - 0.01, PLATE_T,
           "titanium", outward=(1.0, 0.0), bolts=2, inset=0.04)
    P.plate((bay_x0 + PLATE_T * 0.5, (low + deck) * 0.5, 0.0),
            (PLATE_T, deck - low - 0.03, 2 * bw - 0.04), "livery",
            axis=(-1, 0, 0), inset=0.03)
    P.louvres((bay_x0 - 0.004, (low + deck) * 0.5, 0.0), (0.012, deck - low - 0.07, 0.24), 4)

    bay = (-0.30, -0.11, -0.10, 0.10)
    deck_plates(P, bay_x0, bay_x1, -bw, bw, deck, bay, rails=False)
    core_bay(P, bay, top)
    # rails only round the raised bay top
    for sz in (-1.0, 1.0):
        P.box(((bay_x0 + bay_x1) * 0.5, deck + PLATE_T + 0.005, sz * (bw - 0.010)),
              (bay_x1 - bay_x0 - 0.02, 0.016, 0.016), "steel", bevel=0.0025, seg=1)

    flank_plates(P, -cl + 0.01, cl - 0.01, base + 0.014, low - 0.010, hw, splits=2)
    for s_ in (1.0, -1.0):
        P.plate((s_ * (hl - PLATE_T * 0.5), (base + low) * 0.5, 0.0),
                (PLATE_T, low - base - 0.03, 2 * cw - 0.03), "livery",
                axis=(s_, 0, 0), inset=0.03, hardware=True)
    corner_brackets(P, -cl, cl, base + 0.012, low - 0.008, cw)
    for s_ in (-1.0, 1.0):
        P.drain_slots((-0.26, base + 0.012, s_ * (hw + 0.002)),
                      (0.20, base + 0.012, s_ * (hw + 0.002)), 3,
                      w=0.030, h=0.010, depth=0.014)
    # weld beads on the outside corners where the bay meets the deck
    P.seam((bay_x0 + 0.02, low + PLATE_T, -bw - 0.004), (bay_x1 - 0.01, low + PLATE_T, -bw - 0.004))
    P.seam((bay_x0 + 0.02, low + PLATE_T, bw + 0.004), (bay_x1 - 0.01, low + PLATE_T, bw + 0.004))

    P.louvres((0.14, low + 0.006, hw + 0.006), (0.14, 0.012, 0.12), 4)
    wheel_gear(P, spec, hw)
    sockets(P, "box", spec, base, top,
            weapon_front=(hl - PLATE_T, base + 0.055, 0.0),
            weapon_top=(0.20, low + PLATE_T, 0.0))
    return P


def build_pyramid(spec):
    """Symmetric about the axle plane: it reads and drives identically inverted.
    Truncated top and bottom, each with a bolted hatch and edge rails, which is
    what gives it a silhouette from 3/4 instead of a blue lump."""
    P = Part("pyramid", "chassis")
    h = spec["height"] * 0.5                      # 0.13 up and down
    hl = spec["footprint"][0] * 0.5               # 0.40
    hw = hull_half_width(spec)                    # 0.284
    tl, tw = 0.26, 0.20                           # the truncated top / bottom

    for sy in (1.0, -1.0):
        P.slab((hl, 0.0), (tl, sy * (h - PLATE_T)), -hw + 0.02, hw - 0.02,
               PLATE_T, "livery", outward=(1.0, sy * 0.8), bolts=2, inset=0.05)
        P.slab((-hl, 0.0), (-tl, sy * (h - PLATE_T)), -hw + 0.02, hw - 0.02,
               PLATE_T, "livery", outward=(-1.0, sy * 0.8), bolts=2, inset=0.05)
        P.plate((0.0, sy * (h - PLATE_T * 0.5), 0.0), (2 * tl, PLATE_T, 2 * tw),
                "steel" if sy > 0 else "titanium", axis=(0, sy, 0), inset=0.034,
                hardware=True)
        # edge rails round the truncated face
        for sz in (-1.0, 1.0):
            P.box((0.0, sy * (h + 0.004), sz * (tw - 0.012)),
                  (2 * tl - 0.03, 0.018, 0.018), "steel", bevel=0.0028, seg=1)
        for sx in (-1.0, 1.0):
            P.box((sx * (tl - 0.012), sy * (h + 0.004), 0.0),
                  (0.018, 0.018, 2 * tw - 0.048), "steel", bevel=0.0028, seg=1)
        # a bolted hatch forward of centre, with a handle
        P.plate((0.135, sy * (h + 0.008), 0.0), (0.18, 0.016, 0.24), "titanium",
                axis=(0, sy, 0), inset=0.030, hardware=True)
        P.box((0.135, sy * (h + 0.024), 0.0), (0.075, 0.016, 0.018), "steel",
              bevel=0.003, seg=1)
        P.deck_tread((-0.03, sy * (h + 0.0005)), (-0.23, sy * (h + 0.0005)),
                     -tw + 0.035, tw - 0.035, 3, 4, "steel")

    for sz in (1.0, -1.0):
        prof_pts = [(hl - 0.01, 0.0), (tl, h - PLATE_T), (-tl, h - PLATE_T),
                    (-hl + 0.01, 0.0), (-tl, -h + PLATE_T), (tl, -h + PLATE_T)]
        P.prism(prof_pts, sz * (hw - PLATE_T), sz * hw, "livery", bevel=BEVEL, seg=2)
        P.ribs((0.0, 0.0, sz * (hw + 0.005)), (0.40, 0.0, 0.0), 3, "steel",
               normal=2, run=1, h=sz * 0.010, w=0.015)
        for zz in (-0.15, 0.15):
            P.hardware_bolt((zz, 0.0, sz * hw), (0, 0, sz))

    P.box((0.0, 0.0, 0.0), (2 * (hl - 0.10), 2 * (h - 0.035), 2 * (hw - 0.030)),
          "dark_metal", bevel=BEVEL, seg=2)
    for sy in (1.0, -1.0):
        for sz in (-1.0, 1.0):
            P.seam((hl - 0.06, sy * (h - PLATE_T) + sy * 0.002, sz * (hw - 0.022)),
                   (-hl + 0.06, sy * (h - PLATE_T) + sy * 0.002, sz * (hw - 0.022)))

    bay = (-0.21, -0.07, -0.075, 0.075)
    core_bay(P, bay, h - PLATE_T, depth=0.030)

    wheel_gear(P, spec, hw, boss_r=0.034)
    sockets(P, "pyramid", spec, -h, h,
            weapon_front=(0.300, 0.0, 0.0), weapon_top=(0.05, h, 0.0))
    return P


def build_long_low(spec):
    P = Part("long_low", "chassis")
    base, top = base_top(spec)                    # -0.09 .. 0.05
    hw = hull_half_width(spec)                    # 0.204
    cw = hw - PLATE_T
    deck = top - PLATE_T
    hl = spec["footprint"][0] * 0.5               # 0.60
    lip_t = base + 0.020

    prof = [(hl, base), (hl, lip_t), (0.26, deck), (-0.26, deck),
            (-hl, lip_t), (-hl, base)]
    P.prism(prof, -cw, cw, "dark_metal", bevel=BEVEL, seg=2)

    # front and rear ramps, both working faces
    P.slab((hl, lip_t), (0.26, deck), -hw + 0.004, hw - 0.004, PLATE_T,
           "steel", outward=(0.6, 1.0), bolts=2, inset=0.05)
    P.slab((-hl, lip_t), (-0.26, deck), -hw + 0.004, hw - 0.004, PLATE_T,
           "titanium", outward=(-0.6, 1.0), bolts=2, inset=0.05)

    P.deck_tread((hl - 0.05, lip_t + 0.0005), (0.30, deck + 0.0005),
                 -hw + 0.04, hw - 0.04, 5, 4, "steel")
    P.deck_tread((-hl + 0.05, lip_t + 0.0005), (-0.30, deck + 0.0005),
                 -hw + 0.04, hw - 0.04, 5, 4, "titanium")
    bay = (-0.09, 0.09, -0.075, 0.075)
    deck_plates(P, -0.25, 0.25, -cw, cw, deck, bay, rails=False)
    core_bay(P, bay, top, depth=0.028)

    flank_plates(P, -hl + 0.06, hl - 0.06, base + 0.014, deck - 0.004, hw, splits=3)
    # a full-length chassis rail down each flank, the thing that makes it stiff
    for s in (-1.0, 1.0):
        P.box((0.0, base + 0.016, s * (hw + 0.010)), (2 * hl - 0.06, 0.024, 0.020),
              "steel", bevel=0.003, seg=2)
        P.bolt_line((-hl + 0.10, base + 0.016, s * (hw + 0.021)),
                    (hl - 0.10, base + 0.016, s * (hw + 0.021)), 6, (0, 0, s))

    wheel_gear(P, spec, hw, boss_r=0.026)
    sockets(P, "long_low", spec, base, top,
            weapon_front=(0.270, deck - 0.024, 0.0), weapon_top=(0.05, top, 0.0))
    return P


def build_tall_tank(spec):
    P = Part("tall_tank", "chassis")
    base, top = base_top(spec)                    # -0.05 .. 0.37
    hw = hull_half_width(spec)                    # 0.304
    cw = hw - PLATE_T
    hl = spec["footprint"][0] * 0.5               # 0.45
    cl = hl - PLATE_T
    split = base + 0.21                           # where the two boxes meet
    deck = top - PLATE_T
    uw = hw - 0.055                               # the upper box is narrower
    ul = cl - 0.10

    P.box((0.0, (base + split) * 0.5, 0.0), (2 * cl, split - base, 2 * cw),
          "dark_metal", bevel=BEVEL, seg=2)
    P.box((-0.02, (split + deck) * 0.5, 0.0), (2 * ul, deck - split, 2 * (uw - PLATE_T)),
          "dark_metal", bevel=BEVEL, seg=2)

    # lower box: flanks, front, rear
    flank_plates(P, -cl + 0.01, cl - 0.01, base + 0.014, split - 0.008, hw, splits=2)
    for s in (1.0, -1.0):
        P.plate((s * (hl - PLATE_T * 0.5), (base + split) * 0.5, 0.0),
                (PLATE_T, split - base - 0.03, 2 * cw - 0.03), "livery",
                axis=(s, 0, 0), inset=0.03)
    # the shoulder where the upper box sits down on the lower one
    P.plate((-0.02, split + PLATE_T * 0.5, 0.0), (2 * cl - 0.02, PLATE_T, 2 * cw - 0.02),
            "steel", axis=(0, 1, 0), inset=0.035)
    P.seam((-cl + 0.02, split + PLATE_T, -cw - 0.003), (cl - 0.02, split + PLATE_T, -cw - 0.003))
    P.seam((-cl + 0.02, split + PLATE_T, cw + 0.003), (cl - 0.02, split + PLATE_T, cw + 0.003))
    for s_ in (-1.0, 1.0):
        P.deck_tread((cl - 0.05, split + PLATE_T + 0.0005),
                     (cl - 0.16, split + PLATE_T + 0.0005),
                     s_ * 0.20 - 0.05, s_ * 0.20 + 0.05, 2, 2, "steel")
        P.drain_slots((-cl + 0.06, base + 0.012, s_ * (hw + 0.002)),
                      (cl - 0.06, base + 0.012, s_ * (hw + 0.002)), 3,
                      w=0.030, h=0.010, depth=0.014)

    # upper box: flanks and a sloped brow at the front
    for s in (-1.0, 1.0):
        P.plate((-0.02, (split + deck) * 0.5 + 0.01, s * (uw - PLATE_T * 0.5)),
                (2 * ul - 0.02, deck - split - 0.04, PLATE_T), "livery",
                axis=(0, 0, s), inset=0.03)
    for s_ in (-1.0, 1.0):
        P.ribs((-0.02, (split + deck) * 0.5 + 0.01, s_ * (uw + 0.005)),
               (2 * ul - 0.10, 0.0, 0.0), 3, "steel", normal=2, run=1,
               h=s_ * 0.009, w=0.014)
    P.slab((-0.02 + ul, split + 0.02), (-0.02 + ul - 0.06, deck),
           -uw + 0.02, uw - 0.02, PLATE_T, "titanium", outward=(1.0, 0.4), bolts=2, inset=0.04)
    P.plate((-0.02 - ul + PLATE_T * 0.5, (split + deck) * 0.5 + 0.01, 0.0),
            (PLATE_T, deck - split - 0.04, 2 * uw - 0.05), "livery",
            axis=(-1, 0, 0), inset=0.03)

    bay = (-0.20, -0.06, -0.075, 0.075)
    deck_plates(P, -0.02 - ul, -0.02 + ul, -uw + PLATE_T, uw - PLATE_T, deck, bay)
    core_bay(P, bay, top, depth=0.030)

    # the turret ring: where a high weapon mount bolts down
    P.ring((0.09, top + 0.014, 0.0), (0, 1, 0), 0.150, 0.118, 0.028,
           "dark_metal", n=28, bevel=0.002)
    P.ring((0.09, top + 0.030, 0.0), (0, 1, 0), 0.122, 0.100, 0.010,
           "steel", n=24, bevel=0.0)
    for i in range(8):
        a = 2.0 * math.pi * i / 8.0
        P.bolt((0.09 + 0.134 * math.cos(a), top + 0.028, 0.134 * math.sin(a)), (0, 1, 0))

    wheel_gear(P, spec, hw, boss_r=0.034)
    sockets(P, "tall_tank", spec, base, top,
            weapon_front=(hl - PLATE_T, base + 0.075, 0.0),
            weapon_top=(0.09, top + 0.035, 0.0))
    return P


def build_shell(spec):
    """A low drum hub plus a separate outer `ring` mesh for the full-body spinner."""
    P = Part("shell", "chassis")
    base, top = base_top(spec)                    # -0.06 .. 0.22
    hub_r = 0.255
    rim_out = spec["footprint"][1] * 0.5          # 0.40
    rim_in = 0.325

    # hub drum, open underneath so the wheels live inside it
    P.cyl((0.0, (base + top) * 0.5 + 0.02, 0.0), (0, 1, 0), hub_r, top - base - 0.04,
          "dark_metal", n=28, bevel=0.003)
    P.ring((0.0, base + 0.02, 0.0), (0, 1, 0), hub_r, hub_r - 0.030, 0.04,
           "steel", n=28, bevel=0.002)
    # deck plates over the hub, in four segments with panel gaps
    for i in range(4):
        a = math.pi * 0.5 * i + math.pi * 0.25
        P.box((0.14 * math.cos(a), top - PLATE_T * 0.5, 0.14 * math.sin(a)),
              (0.20, PLATE_T, 0.20), "livery", bevel=BEVEL, seg=2,
              rot=rot_z(math.degrees(-a)))
        P.hardware_bolt((0.205 * math.cos(a), top, 0.205 * math.sin(a)), (0, 1, 0))
        P.ribs((0.14 * math.cos(a), top + 0.004, 0.14 * math.sin(a)),
               (0.0, 0.0, 0.0), 0, "steel")
        P.box((0.145 * math.cos(a), top + 0.005, 0.145 * math.sin(a)),
              (0.16, 0.011, 0.016), "steel", bevel=0.0025, seg=1,
              rot=rot_z(math.degrees(-a)))
    bay = (-0.07, 0.07, -0.07, 0.07)
    core_bay(P, bay, top, depth=0.030)
    # the bearing race the ring turns on
    P.ring((0.0, top - 0.09, 0.0), (0, 1, 0), hub_r + 0.022, hub_r, 0.036,
           "steel", n=28, bevel=0.002)
    for i in range(12):
        a = 2.0 * math.pi * i / 12.0
        P.bolt(((hub_r + 0.010) * math.cos(a), top - 0.072, (hub_r + 0.010) * math.sin(a)),
               (0, 1, 0), r=0.007)

    # ------------------------------------------------ the separate ring mesh
    P.use("ring")
    ry = 0.055
    P.ring((0.0, ry, 0.0), (0, 1, 0), rim_out, rim_in, 0.19, "livery", n=36, bevel=0.004)
    P.ring((0.0, ry + 0.095, 0.0), (0, 1, 0), rim_out - 0.004, rim_in - 0.004, 0.020,
           "titanium", n=36, bevel=0.002)
    P.ring((0.0, ry - 0.095, 0.0), (0, 1, 0), rim_out - 0.004, rim_in - 0.004, 0.020,
           "titanium", n=36, bevel=0.002)
    for i in range(16):
        a = 2.0 * math.pi * i / 16.0
        c, s = math.cos(a), math.sin(a)
        P.bolt(((rim_out - 0.001) * c, ry + 0.060, (rim_out - 0.001) * s), (c, 0, s), r=0.009)
        P.bolt(((rim_out - 0.001) * c, ry - 0.060, (rim_out - 0.001) * s), (c, 0, s), r=0.009)
        if i % 2 == 0:
            P.box((0.5 * (rim_out + rim_in) * c, ry, 0.5 * (rim_out + rim_in) * s),
                  (0.05, 0.20, rim_out - rim_in - 0.006), "dark_metal",
                  bevel=0.003, seg=1, rot=rot_z(math.degrees(-a)))
    P.use("body")

    sockets(P, "shell", spec, base, top)
    return P


BUILDERS = {
    "wedge": build_wedge,
    "box": build_box,
    "pyramid": build_pyramid,
    "long_low": build_long_low,
    "tall_tank": build_tall_tank,
    "shell": build_shell,
}


# ---------------------------------------------------------------------------
# Wave P (agent E).  The Apex, brief v5 section 9.5 Level 100.  Request in
# docs/wave-p-d2-notes.md section 5.
# ---------------------------------------------------------------------------

def build_apex(spec):
    """The last hull on the ladder: 1.0 by 0.7, 0.22 tall, and the whole point
    of it is the UNDERCUT -- a bottom that pulls IN under the waist, so a wedge
    climbing it meets an overhang instead of a ramp.

    THE UNDERCUT HAS TO READ ON SCREEN, which is the one thing D2 asked for by
    name, and a 40 mm step alone does not at 235 pixels per metre.  Three things
    carry it: the step itself; a chamfer skirt all round that turns the step
    into a continuous hard shadow line rather than a soft corner; and a
    titanium catch rail along the top of the step, bright against the dark foot,
    so the eye is given an edge to follow.  Nothing in the silhouette above the
    waist is allowed to be wider than the waist, or the read is lost.

    SOCKETS.  `socket_weapon_front` and `socket_weapon_top` are authored at the
    EXACT values `ChassisBase._weapon_fallback` was already handing out, so
    landing this model moves nothing that D2 measured.  They are numbers to
    tune, not numbers this file discovered."""
    P = Part("apex", "chassis")
    base, top = base_top(spec)                    # -0.085 .. 0.135
    hl = spec["footprint"][0] * 0.5               # 0.50
    hw = hull_half_width(spec)                    # 0.284
    cw = hw - PLATE_T
    deck = top - PLATE_T
    lip = base + 0.032                            # the top of the undercut
    shoulder = top - 0.042
    dl = 0.42                                     # the deck, per apex.gd
    dwid = hw * 0.86
    under = 0.044                                 # how far the foot pulls in

    # 1. THE FOOT.  Narrower than the waist all round: this is the undercut.
    P.box((0.0, (base + lip) * 0.5 - 0.004, 0.0),
          (2 * (hl - under), lip - base + 0.008, 2 * (cw - under)),
          "dark_metal", bevel=0.005, seg=2)
    for sz in (-1.0, 1.0):
        P.plate((0.0, (base + lip) * 0.5, sz * (cw - under - 0.006)),
                (2 * (hl - under) - 0.06, lip - base - 0.008, 0.013),
                "titanium", axis=(0, 0, sz), inset=0.05)
    for sx in (-1.0, 1.0):
        P.plate((sx * (hl - under - 0.006), (base + lip) * 0.5, 0.0),
                (0.013, lip - base - 0.008, 2 * (cw - under) - 0.06),
                "titanium", axis=(sx, 0, 0), inset=0.05)
    # skid strips under the foot, which is what it stands on when it is shoved
    for sz in (-1.0, 1.0):
        P.box((0.0, base - 0.004, sz * (cw - under - 0.05)),
              (2 * (hl - under) - 0.10, 0.012, 0.040), "steel",
              bevel=0.003, seg=1)

    # 2. THE CHAMFER SKIRT: the shadow line that makes the step read.
    for sz in (-1.0, 1.0):
        P.box((0.0, lip - 0.012, sz * (cw - under * 0.5 - 0.004)),
              (2 * (hl - under) + 0.02, 0.020, under + 0.020), "dark_metal",
              bevel=0.004, seg=2, rot=rot_roll(sz * 44.0))
    for sx in (-1.0, 1.0):
        P.box((sx * (hl - under * 0.5 - 0.004), lip - 0.012, 0.0),
              (under + 0.020, 0.020, 2 * (cw - under) + 0.02), "dark_metal",
              bevel=0.004, seg=2, rot=rot_pitch(-sx * 44.0))
    # 3. THE CATCH RAIL along the top of the step, bright against the dark foot
    for sz in (-1.0, 1.0):
        P.box((0.0, lip + 0.008, sz * (cw + 0.004)),
              (2 * hl - 0.10, 0.018, 0.020), "titanium", bevel=0.003, seg=1)
        P.bolt_line((-hl + 0.12, lip + 0.008, sz * (cw + 0.015)),
                    (hl - 0.12, lip + 0.008, sz * (cw + 0.015)), 7, (0, 0, sz))
    for sx in (-1.0, 1.0):
        P.box((sx * (hl - 0.006), lip + 0.008, 0.0),
              (0.020, 0.018, 2 * cw - 0.06), "titanium", bevel=0.003, seg=1)

    # 4. THE WAIST: full width, straight sided, and the body of the machine
    prof = [(hl, lip), (hl, shoulder), (dl, top), (-dl, top),
            (-hl, shoulder), (-hl, lip)]
    P.prism(prof, -cw, cw, "dark_metal", bevel=BEVEL, seg=2)
    flank_plates(P, -hl + 0.04, hl - 0.04, lip + 0.026, shoulder - 0.010, hw,
                 splits=3)
    corner_brackets(P, -hl + 0.03, hl - 0.03, lip + 0.020, shoulder, hw)
    for sz in (-1.0, 1.0):
        P.ribs((0.0, (lip + shoulder) * 0.5, sz * (hw + 0.004)),
               (2 * hl - 0.30, 0.0, 0.0), 4, "steel", normal=2, run=1,
               h=sz * 0.009, w=0.016)
        P.drain_slots((-0.34, lip + 0.030, sz * (hw + 0.002)),
                      (0.34, lip + 0.030, sz * (hw + 0.002)), 4,
                      w=0.030, h=0.010, depth=0.014)
    # the shoulders: the sloped band between the waist and the deck
    for sz in (-1.0, 1.0):
        P.box((0.0, shoulder + 0.020, sz * ((cw + dwid) * 0.5)),
              (2 * dl, 0.046, cw - dwid + 0.03), "livery", bevel=0.004, seg=2,
              rot=rot_roll(-sz * 40.0))
    for sx in (-1.0, 1.0):
        P.slab((sx * hl, shoulder), (sx * dl, top), -cw + 0.03, cw - 0.03,
               PLATE_T, "steel", outward=(sx, 1.0), bolts=3, inset=0.06)
        P.deck_tread((sx * (hl - 0.02), shoulder + 0.001),
                     (sx * (dl + 0.01), top + 0.001), -cw + 0.07, cw - 0.07,
                     3, 5, "steel")

    # 5. THE DECK: long and flat, because every weapon in the catalogue fits
    bay = (-0.14, 0.02, -0.115, 0.115)
    deck_plates(P, -dl + 0.02, dl - 0.02, -dwid, dwid, deck, bay)
    core_bay(P, bay, top, depth=0.040)
    P.plate((-0.30, top + 0.020, 0.0), (0.20, 0.040, 0.30), "livery",
            axis=(0, 1, 0), inset=0.034, hardware=True)
    P.louvres((-0.30, top + 0.042, 0.0), (0.15, 0.009, 0.24), 5)
    P.cable_run([(-0.34, deck + PLATE_T + 0.007, 0.205),
                 (0.06, deck + PLATE_T + 0.007, 0.205)], r=0.0058)
    P.seam((-dl + 0.04, top, -dwid - 0.003), (dl - 0.04, top, -dwid - 0.003))
    P.seam((-dl + 0.04, top, dwid + 0.003), (dl - 0.04, top, dwid + 0.003))

    # 6. the nose: a bolted bumper beam, flat, because this hull does not wedge
    P.box((hl - 0.010, (lip + shoulder) * 0.5, 0.0),
          (0.020, shoulder - lip - 0.03, 2 * cw - 0.04), "steel",
          bevel=0.004, seg=2)
    for z in (-0.17, -0.058, 0.058, 0.17):
        P.hardware_bolt((hl + 0.001, (lip + shoulder) * 0.5, z), (1, 0, 0))
    P.box((-hl + 0.010, (lip + shoulder) * 0.5, 0.0),
          (0.020, shoulder - lip - 0.05, 2 * cw - 0.06), "titanium",
          bevel=0.004, seg=2)

    wheel_gear(P, spec, hw, boss_r=0.034)
    # Authored at ChassisBase._weapon_fallback's own numbers: landing the model
    # must not move a weapon D2 already measured.
    sockets(P, "apex", spec, base, top,
            weapon_front=(hl * 0.85, base + spec["height"] * 0.3, 0.0),
            weapon_top=(hl * 0.1, top, 0.0))
    return P


BUILDERS["apex"] = build_apex
