"""Arena kit: the BROADCAST and DRESSING props, as reproducible Blender Python.

    ~/Applications/Blender.app/Contents/MacOS/Blender -b --python \\
        Tools/blender/arena_kit/kit_props.py [-- --only a,b] [--sheet] [--no-build]

Writes Arena/arena/kit/models/<name>.glb for every piece below, then verifies
each file by reading the exported glTF back (bounds in Godot space, triangle
count, material slots, the screen UVs) and prints a table.  `--sheet` also
renders the review contact sheet docs/aaa/img/wave-a/kit/kit-props-sheet.png
(tiles in Blender, composed by system python3 + PIL, as render_contact_sheet
does for the parts library).

Every number here is GODOT space (+Y up, front = +Z); see propslib.py for why
that is exactly the kit convention (Blender Z-up, front = Blender -Y,
export_yup=True).
"""

import json
import math
import os
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(REPO, "Arena", "arena", "kit", "models")
SHEET = os.path.join(REPO, "docs", "aaa", "img", "wave-a", "kit", "kit-props-sheet.png")

try:
    import bpy
    from mathutils import Matrix, Vector
    sys.path.insert(0, HERE)
    import propslib as pl
    from propslib import Mesh, V, rx, ry, rz
    IN_BLENDER = True
except ImportError:
    IN_BLENDER = False

BUDGET = {
    "truss_span_2m": 1200, "truss_corner": 300, "truss_tower_leg": 2500,
    "moving_head": 1200, "screen_frame": 2000, "beacon": 600,
    "pyro_launcher": 900, "flight_case_stack": 1500, "cable_drum": 800,
    "scrap_pile_a": 4000, "scrap_pile_b": 4000, "crane_skyline": 3000,
    "camera_crane": 2000,
}

TRUSS_HALF = 0.125      # chord centre offset: 0.30 m section outside the tubes
CHORD_R = 0.025
LACE_R = 0.0095

PYRO_MOUTH_Y = 0.62


# =============================================================== shared bits

def box_truss(m, p0, p1, u, v, pitch=0.32, end_inset=0.04, chord_n=10,
              lace_n=6, chord_ext=0.0):
    """A square box truss from p0 to p1.  u, v: unit side vectors.
    Chords at +-TRUSS_HALF on u and v; end ladders at end_inset in from each
    end; zig-zag lacing on all four faces between them."""
    p0, p1, u, v = V(p0), V(p1), V(u), V(v)
    d = (p1 - p0)
    L = d.length
    f = d / L
    h = TRUSS_HALF
    corners = [u * h + v * h, u * h - v * h, -u * h - v * h, -u * h + v * h]
    for c in corners:
        m.rod(p0 + c - f * chord_ext, p1 + c + f * chord_ext, CHORD_R, "aluminium",
              n=chord_n, cap=True)
    t0, t1 = end_inset, L - end_inset
    k = max(2, int(round((t1 - t0) / pitch)))
    if k % 2:
        k += 1                              # even count: symmetric, tiles
    for i in range(4):
        A, B = corners[i], corners[(i + 1) % 4]
        # end ladders
        for t in (t0, t1):
            m.rod(p0 + f * t + A, p0 + f * t + B, LACE_R * 1.1, "aluminium", n=lace_n, cap=False)
        for s in range(k):
            ta = t0 + (t1 - t0) * s / k
            tb = t0 + (t1 - t0) * (s + 1) / k
            a, b = (A, B) if (s + i) % 2 == 0 else (B, A)
            m.rod(p0 + f * ta + a, p0 + f * tb + b, LACE_R, "aluminium", n=lace_n, cap=False)
    return corners


def flight_case(m, base, w, h, d, yaw=0.0, handles=True, latches=2, lid=0.62):
    """A road case sitting with its base centre at `base` (Godot space)."""
    m.push(Matrix.Translation(V(base)) @ ry(yaw))
    m.box((0, h / 2, 0), (w - 0.01, h - 0.01, d - 0.01), "flight_case", bevel=0.006)
    t = 0.022
    # vertical extrusions on the four edges
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.box((sx * (w / 2 - t / 2 + 0.002), h / 2, sz * (d / 2 - t / 2 + 0.002)),
                  (t, h - 0.05, t), "galv_steel", bevel=0.0)
    # lid seam band (the valance) all round
    y = h * lid
    m.box((0, y, d / 2 + 0.001), (w - 0.05, 0.028, 0.012), "galv_steel", bevel=0.0)
    m.box((0, y, -d / 2 - 0.001), (w - 0.05, 0.028, 0.012), "galv_steel", bevel=0.0)
    m.box((w / 2 + 0.001, y, 0), (0.012, 0.028, d - 0.05), "galv_steel", bevel=0.0)
    m.box((-w / 2 - 0.001, y, 0), (0.012, 0.028, d - 0.05), "galv_steel", bevel=0.0)
    # ball-corner caps
    c = 0.05
    for sx in (-1, 1):
        for sy in (0, 1):
            for sz in (-1, 1):
                m.box((sx * (w / 2 - c / 2 + 0.006), sy * h + (c / 2 - 0.004 if sy == 0 else -c / 2 + 0.004),
                       sz * (d / 2 - c / 2 + 0.006)), (c, c, c), "galv_steel", bevel=0.0)
    # butterfly latches on the front
    for i in range(latches):
        x = (-0.5 + (i + 0.5) / latches) * (w * 0.7)
        m.box((x, y, d / 2 + 0.008), (0.07, 0.085, 0.012), "galv_steel", bevel=0.0)
        m.box((x, y - 0.012, d / 2 + 0.017), (0.045, 0.028, 0.012), "galv_steel", bevel=0.0)
    if handles:
        for sx in (-1, 1):
            m.box((sx * (w / 2 + 0.004), y - h * 0.22, 0), (0.012, 0.07, 0.16), "galv_steel", bevel=0.0)
            m.box((sx * (w / 2 + 0.016), y - h * 0.22 - 0.012, 0), (0.016, 0.024, 0.13), "rubber", bevel=0.0)
    m.pop()


# =============================================================== 1-3 truss

def truss_span_2m():
    m = Mesh("truss_span_2m")
    box_truss(m, (-1.0, 0, 0), (1.0, 0, 0), V(0, 1, 0), V(0, 0, 1), pitch=0.32,
              end_inset=0.045)
    # half conical couplers on every chord end: two pieces butted end to end
    # read as one coupler with its pin.
    h = TRUSS_HALF
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                c = V(sx * (1.0 - 0.019), sy * h, sz * h)
                m.box(c, (0.038, 0.062, 0.062), "aluminium", bevel=0.006)
                m.rod(c + V(0, 0, -0.04), c + V(0, 0, 0.04), 0.008, "galv_steel", n=6)
    return [m]


def truss_corner():
    m = Mesh("truss_corner")
    m.box((0, 0, 0), (0.30, 0.30, 0.30), "aluminium", bevel=0.012)
    h = TRUSS_HALF
    # coupler bosses where the chords of a span land, on the four side faces
    for axis in (V(1, 0, 0), V(-1, 0, 0), V(0, 0, 1), V(0, 0, -1)):
        side = V(0, 0, 1) if abs(axis.x) > 0.5 else V(1, 0, 0)
        for sy in (-1, 1):
            for ss in (-1, 1):
                m.box(axis * 0.154 + V(0, sy * h, 0) + side * ss * h,
                      (0.055 if abs(axis.x) < 0.5 else 0.012, 0.055,
                       0.055 if abs(axis.z) < 0.5 else 0.012), "aluminium", bevel=0.0)
    # top and bottom access plates
    for sy in (-1, 1):
        m.box((0, sy * 0.153, 0), (0.17, 0.008, 0.17), "aluminium", bevel=0.0)
    return [m]


def truss_tower_leg():
    m = Mesh("truss_tower_leg")
    # base plate, gussets and anchors
    m.box((0, 0.0125, 0), (0.62, 0.025, 0.62), "galv_steel", bevel=0.006)
    for a in range(4):
        R = ry(45 + 90 * a)
        m.push(R)
        prof = [(0.17, 0), (0.30, 0), (0.17, 0.16)]
        m.prism(prof, -0.008, 0.008, "galv_steel", M=Matrix.Translation((0, 0.025, 0)), bevel=0.0)
        m.bolt((0.265, 0.025, 0.0), (0, 1, 0), r=0.018, h=0.02, n=6)
        m.pop()
    # the leg
    box_truss(m, (0, 0.025, 0), (0, 6.0, 0), V(1, 0, 0), V(0, 0, 1), pitch=0.36,
              end_inset=0.14)
    # base couplers
    h = TRUSS_HALF
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.box((sx * h, 0.07, sz * h), (0.07, 0.09, 0.07), "aluminium", bevel=0.006)
    # sleeve block at the top: rides the leg, carries the roof truss
    m.box((0, 5.62, 0), (0.42, 0.56, 0.42), "aluminium", bevel=0.014)
    for face in (V(1, 0, 0), V(-1, 0, 0), V(0, 0, 1), V(0, 0, -1)):
        side = V(0, 0, 1) if abs(face.x) > 0.5 else V(1, 0, 0)
        plate = (0.30, 0.40, 0.008) if abs(face.z) > 0.5 else (0.008, 0.40, 0.30)
        m.box(face * 0.212 + V(0, 5.62, 0), plate, "aluminium", bevel=0.0)
        for sy in (-1, 1):
            for ss in (-1, 1):
                m.bolt(face * 0.216 + V(0, 5.62 + sy * 0.14, 0) + side * ss * 0.11, face,
                       r=0.016, h=0.012, n=6)
    # top cap
    m.box((0, 5.985, 0), (0.32, 0.03, 0.32), "aluminium", bevel=0.006)
    return [m]


# =============================================================== 4 moving head

MH_TILT_Y = -0.46


def moving_head():
    y = Mesh("mh_yoke")
    # base: 0.35 x 0.2 x 0.35, top face at y = 0
    y.box((0, -0.10, 0), (0.35, 0.20, 0.35), "dark_metal", bevel=0.018, seg=1)
    # mounting plate + omega bracket bolts flush with the top face
    y.box((0, -0.006, 0), (0.24, 0.012, 0.10), "galv_steel", bevel=0.0)
    for sx in (-1, 1):
        y.bolt((sx * 0.09, -0.012, 0), (0, -1, 0), r=0.013, h=0.006)
    # vents on the sides, display on the front
    for sx in (-1, 1):
        for i in range(3):
            y.box((sx * 0.176, -0.07 - i * 0.035, 0), (0.008, 0.016, 0.20), "galv_steel", bevel=0.0)
    y.box((0, -0.10, 0.176), (0.12, 0.06, 0.006), "lamp_strip", bevel=0.0)
    # pan bearing
    y.cyl((0, -0.212, 0), (0, 1, 0), 0.11, 0.025, "galv_steel", n=14)
    # yoke: crossbar + two arms ending in tilt hubs
    y.box((0, -0.240, 0), (0.46, 0.034, 0.13), "dark_metal", bevel=0.01)
    for sx in (-1, 1):
        y.box((sx * 0.205, -0.35, 0), (0.042, 0.23, 0.13), "dark_metal", bevel=0.01)
        y.cyl((sx * 0.205, MH_TILT_Y, 0), (1, 0, 0), 0.065, 0.042, "dark_metal", n=12)
        y.cyl((sx * 0.232, MH_TILT_Y, 0), (1, 0, 0), 0.035, 0.014, "galv_steel", n=10)

    h = Mesh("mh_head", origin=(0, MH_TILT_Y, 0), parent="mh_yoke")
    c = V(0, MH_TILT_Y, 0)
    # head body, axis pointing straight down (-Y); profile along the beam axis
    prof = [(0.0, -0.145), (0.075, -0.145), (0.105, -0.13), (0.122, -0.10),
            (0.125, 0.12), (0.132, 0.13), (0.132, 0.215), (0.112, 0.215),
            (0.104, 0.20)]
    h.lathe(prof, c, (0, -1, 0), "dark_metal", n=18, cap=True, bevel=0.0)
    # cooling rings on the body
    for t in (0.0, 0.05):
        h.cyl(c + V(0, -t, 0), (0, 1, 0), 0.129, 0.018, "galv_steel", n=18, cap=False)
    # lens
    h.lathe([(0.0, 0.206), (0.100, 0.199)], c, (0, -1, 0), "lamp_white", n=18, cap=False)
    # tilt motor hubs meeting the yoke arms
    for sx in (-1, 1):
        h.cyl(c + V(sx * 0.155, 0, 0), (1, 0, 0), 0.05, 0.05, "galv_steel", n=10)
    return [y, h]


# =============================================================== 5 screen

SCREEN_W, SCREEN_H = 4.8, 2.7


def screen_frame():
    m = Mesh("screen_frame")
    W, H = SCREEN_W, SCREEN_H
    bw, z0, z1 = 0.15, -0.08, 0.04          # border width, frame depth 0.12
    # bezel border (four bevelled bars) sitting proud of the display
    m.box((0, H / 2 + bw / 2, (z0 + z1) / 2), (W + 2 * bw, bw, z1 - z0), "dark_metal", bevel=0.012)
    m.box((0, -H / 2 - bw / 2, (z0 + z1) / 2), (W + 2 * bw, bw, z1 - z0), "dark_metal", bevel=0.012)
    for sx in (-1, 1):
        m.box((sx * (W / 2 + bw / 2), 0, (z0 + z1) / 2), (bw, H, z1 - z0), "dark_metal", bevel=0.012)
    # LED cabinet behind the opening: its front is the inner lip at z = -0.01
    m.box((0, 0, -0.07), (W + 0.02, H + 0.02, 0.12), "dark_metal", bevel=0.0)
    # cabinet seams on the back (6 x 3 tiles of 0.8 x 0.9)
    for i in range(1, 6):
        m.box((-W / 2 + i * 0.8, 0, -0.132), (0.02, H, 0.006), "galv_steel", bevel=0.0)
    for j in (1, 2):
        m.box((0, -H / 2 + j * 0.9, -0.132), (W, 0.02, 0.006), "galv_steel", bevel=0.0)
    # rear ladder truss (flybar) along top and bottom, with verticals
    zt = -0.30
    for yy in (H / 2 - 0.15, -H / 2 + 0.15):
        m.rod((-W / 2 - 0.05, yy + 0.10, zt), (W / 2 + 0.05, yy + 0.10, zt), 0.024, "aluminium", n=8)
        m.rod((-W / 2 - 0.05, yy - 0.10, zt), (W / 2 + 0.05, yy - 0.10, zt), 0.024, "aluminium", n=8)
        k = 12
        for i in range(k):
            xa = -W / 2 + W * i / k
            xb = -W / 2 + W * (i + 1) / k
            ya, yb = (yy + 0.10, yy - 0.10) if i % 2 == 0 else (yy - 0.10, yy + 0.10)
            m.rod((xa, ya, zt), (xb, yb, zt), 0.01, "aluminium", n=5, cap=False)
    # vertical back braces tying the ladders to the cabinet
    for x in (-2.0, -0.8, 0.8, 2.0):
        m.box((x, 0, zt + 0.02), (0.07, H - 0.1, 0.05), "dark_metal", bevel=0.0)
        for yy in (H / 2 - 0.25, -H / 2 + 0.25):
            m.box((x, yy, (zt - 0.13) / 2), (0.05, 0.12, -0.13 - zt), "dark_metal", bevel=0.0)
    # rigging: top corner lugs, shackles, chain hoists, cables to y = +4.0
    for sx in (-1, 1):
        x = sx * (W / 2 - 0.05)
        m.box((x, H / 2 + bw + 0.04, -0.02), (0.08, 0.08, 0.02), "galv_steel", bevel=0.004)
        m.torus((x, H / 2 + bw + 0.10, -0.02), (0, 0, 1), 0.035, 0.009, "galv_steel", nu=8, nv=4)
        m.rod((x, H / 2 + bw + 0.13, -0.02), (x, 3.05, -0.02), 0.010, "cable", n=6)
        # chain hoist body + hook block
        m.box((x, 3.20, -0.02), (0.16, 0.26, 0.20), "dark_metal", bevel=0.015)
        m.cyl((x, 3.20, 0.085), (0, 0, 1), 0.07, 0.03, "galv_steel", n=10)
        m.rod((x, 3.33, -0.02), (x, 4.0, -0.02), 0.012, "cable", n=6)
        m.box((x, 3.985, -0.02), (0.08, 0.03, 0.08), "galv_steel", bevel=0.0)
        # loose chain tail hanging off the hoist
        m.sweep([(x + sx * 0.06, 3.08, 0.05), (x + sx * 0.08, 2.7, 0.06),
                 (x + sx * 0.05, 2.45, 0.03)], 0.008, "cable", n=4)
    # the display face: ONE quad, exactly the opening, 1 cm in front of the lip
    m.quad([(-W / 2, H / 2, 0.0), (-W / 2, -H / 2, 0.0), (W / 2, -H / 2, 0.0), (W / 2, H / 2, 0.0)],
           "screen", uv=((0, 0), (0, 1), (1, 1), (1, 0)))
    return [m]


# =============================================================== 6 beacon

def beacon():
    m = Mesh("beacon")
    # mounting bracket: foot plate with an upright tab behind
    m.box((0, 0.006, -0.02), (0.18, 0.012, 0.22), "galv_steel", bevel=0.003)
    m.box((0, 0.06, -0.125), (0.14, 0.10, 0.012), "galv_steel", bevel=0.003)
    for sx in (-1, 1):
        m.bolt((sx * 0.07, 0.012, 0.06), (0, 1, 0), r=0.009, h=0.006, n=5)
        m.bolt((sx * 0.045, 0.085, -0.119), (0, 0, 1), r=0.009, h=0.006, n=5)
    # base
    prof = [(0.0, 0.012), (0.07, 0.012), (0.07, 0.048), (0.062, 0.060)]
    m.lathe(prof, (0, 0, 0), (0, 1, 0), "dark_metal", n=16, cap=True)
    # dome: 0.16 m tall, straight wall then a rounded top
    dp = [(0.058, 0.060), (0.058, 0.170)]
    for i in range(1, 3):
        a = math.radians(90 * i / 3)
        dp.append((0.058 * math.cos(a), 0.170 + 0.05 * math.sin(a)))
    dp.append((0.0, 0.220))
    m.lathe(dp, (0, 0, 0), (0, 1, 0), "lamp_amber", n=16, cap=False)
    # inner reflector (reads through the dome)
    m.box((0, 0.12, 0), (0.07, 0.07, 0.006), "galv_steel", bevel=0.0)
    # guard cage: two rings + four wires arching over
    for yy in (0.085, 0.160):
        m.torus((0, yy, 0), (0, 1, 0), 0.068, 0.004, "galv_steel", nu=10, nv=3)
    for a in (45, 135):
        t = math.radians(a)
        dx, dz = math.cos(t), math.sin(t)
        pts = []
        for i in range(5):
            ang = math.pi * i / 4
            r = 0.068
            if 0 < i < 4:
                pts.append((dx * r * math.cos(ang), 0.175 + 0.058 * math.sin(ang), dz * r * math.cos(ang)))
            else:
                pts.append((dx * r * math.cos(ang), 0.055, dz * r * math.cos(ang)))
        pts.insert(1, (dx * 0.068, 0.175, dz * 0.068))
        pts.insert(-1, (-dx * 0.068, 0.175, -dz * 0.068))
        m.sweep(pts, 0.004, "galv_steel", n=4)
    return [m]


# =============================================================== 7 pyro

def pyro_launcher():
    m = Mesh("pyro_launcher")
    W, Hh, D = 0.5, 0.45, 0.5
    flight_case(m, (0, 0, 0), W, Hh, D, handles=True, latches=2, lid=0.78)
    # control / warning plate on the front
    m.quad([(-0.14, 0.24, D / 2 + 0.004), (-0.14, 0.12, D / 2 + 0.004),
            (0.14, 0.12, D / 2 + 0.004), (0.14, 0.24, D / 2 + 0.004)], "sign",
           uv=((0, 0), (0, 1), (1, 1), (1, 0)))
    m.box((0.18, 0.18, D / 2 + 0.006), (0.04, 0.04, 0.012), "lamp_amber", bevel=0.0)
    # nozzle: flange, barrel, flared mouth with an open bore; mouth at 0.62
    y0 = Hh
    prof = [(0.0, y0), (0.095, y0), (0.095, y0 + 0.018), (0.052, y0 + 0.024),
            (0.045, y0 + 0.04), (0.045, 0.585), (0.060, 0.610),
            (0.060, PYRO_MOUTH_Y), (0.040, PYRO_MOUTH_Y), (0.034, 0.58),
            (0.0, 0.58)]
    m.lathe(prof, (0, 0, 0), (0, 1, 0), "galv_steel", n=16, cap=False)
    for a in range(4):
        t = math.radians(45 + 90 * a)
        m.bolt((0.075 * math.cos(t), y0 + 0.018, 0.075 * math.sin(t)), (0, 1, 0), r=0.008, h=0.006)
    # igniter / solenoid box on the barrel
    m.box((0.075, 0.53, 0), (0.05, 0.06, 0.05), "dark_metal", bevel=0.004)
    m.sweep([(0.1, 0.53, 0), (0.16, 0.52, 0), (0.2, 0.47, 0.0)], 0.007, "cable", n=5)
    # power / DMX cable out of the back, down to the floor, trailing
    m.box((0.12, 0.22, -D / 2 - 0.01), (0.06, 0.05, 0.02), "dark_metal", bevel=0.0)
    m.sweep([(0.12, 0.22, -D / 2 - 0.02), (0.12, 0.2, -0.33), (0.13, 0.08, -0.40),
             (0.16, 0.015, -0.48), (0.24, 0.012, -0.70), (0.38, 0.012, -0.86),
             (0.36, 0.012, -1.10)], 0.012, "cable", n=6)
    return [m]


# =============================================================== 8 cases

def flight_case_stack():
    m = Mesh("flight_case_stack")
    wh = 0.11
    # castor wheels under the bottom case
    for sx in (-1, 1):
        for sz in (-1, 1):
            p = V(sx * 0.50, 0, sz * 0.27)
            m.box(p + V(0, wh - 0.005, 0), (0.09, 0.01, 0.09), "galv_steel", bevel=0.0)
            m.box(p + V(0, wh - 0.035, 0), (0.05, 0.05, 0.075), "galv_steel", bevel=0.0)
            m.cyl(p + V(0, 0.045, 0), (0, 0, 1), 0.045, 0.035, "rubber", n=10)
    flight_case(m, (0, wh, 0), 1.20, 0.50, 0.70, latches=3, lid=0.70)
    flight_case(m, (0.05, wh + 0.50, -0.02), 0.96, 0.40, 0.60, yaw=4.0, latches=2, lid=0.70)
    flight_case(m, (-0.14, wh + 0.90, 0.03), 0.62, 0.29, 0.48, yaw=-7.0, latches=2, lid=0.65)
    return [m]


# =============================================================== 9 drum

def cable_drum():
    m = Mesh("cable_drum")
    R, Wd = 0.6, 0.9
    cy = R
    for sx in (-1, 1):
        # flange: planked disc with a chamfered rim
        m.cyl((sx * (Wd / 2 - 0.025), cy, 0), (1, 0, 0), R, 0.05, "wood", n=18)
        # battens across the outer face
        for a in (0, 90):
            m.push(Matrix.Translation((sx * (Wd / 2 + 0.008), cy, 0)) @ rx(a + 15))
            m.box((0, 0, 0), (0.018, 1.02, 0.09), "wood", bevel=0.0)
            m.pop()
        # steel hub ring
        m.tube_ring((sx * (Wd / 2 + 0.02), cy, 0), (1, 0, 0), 0.10, 0.055, 0.03, "galv_steel", n=10)
    # wound cable with lay ridges
    prof = []
    xs = [-0.40, -0.30, -0.20, -0.10, 0.0, 0.10, 0.20, 0.30, 0.40]
    for i, x in enumerate(xs):
        prof.append((0.44 if i % 2 == 0 else 0.46, x))
    m.lathe(prof, (0, cy, 0), (1, 0, 0), "cable", n=16, cap=True)
    # the free end, over the top and down to the floor at the front
    m.sweep([(0.1, cy + 0.44, -0.05), (0.14, cy + 0.44, 0.25), (0.16, cy + 0.30, 0.46),
             (0.17, 0.35, 0.58), (0.19, 0.08, 0.70), (0.25, 0.02, 0.85), (0.45, 0.02, 1.02),
             (0.62, 0.02, 1.05)], 0.02, "cable", n=6)
    return [m]


# =============================================================== 10 scrap

def _place(m, pos, yaw=0.0, pitch=0.0, roll=0.0):
    m.push(Matrix.Translation(V(pos)) @ ry(yaw) @ rz(roll) @ rx(pitch))


_CRUMPLE = [0]


def _slab(m, pos, size, yaw, pitch, roll, mat, bend=0.0, amp=0.055):
    """A crushed sheet: subdivided and pushed about with seeded noise."""
    _place(m, pos, yaw, pitch, roll)
    _CRUMPLE[0] += 1
    if bend == 0.0:
        f = m.box((0, 0, 0), size, mat, bevel=0.0)
        m.crumple(f, amp, seed=_CRUMPLE[0], freq=2.4, cuts=2)
    else:
        L = size[0]
        f = m.box((-L / 4, 0, 0), (L / 2 + 0.01, size[1], size[2]), mat, bevel=0.0)
        m.crumple(f, amp, seed=_CRUMPLE[0], freq=2.4, cuts=1)
        m.push(rz(bend))
        f = m.box((L / 4, 0, 0), (L / 2, size[1], size[2]), mat, bevel=0.0)
        m.crumple(f, amp, seed=_CRUMPLE[0] + 50, freq=2.4, cuts=1)
        m.pop()
    m.pop()


def _tyre(m, pos, yaw=0.0, pitch=0.0, roll=0.0, R=0.30, r=0.11, rim=False):
    _place(m, pos, yaw, pitch, roll)
    m.torus((0, 0, 0), (0, 1, 0), R, r, "rubber", nu=14, nv=6, phase=0.0)
    if rim:
        prof = [(0.0, 0.03), (0.07, 0.03), (0.09, 0.0), (0.21, 0.0), (0.23, 0.06), (0.23, -0.06)]
        m.lathe(prof, (0, 0, 0), (0, 1, 0), "galv_steel", n=14, cap=False)
    m.pop()


def _ibeam(m, a, b, H=0.24, B=0.14, tw=0.012, tf=0.018, mat="rust"):
    a, b = V(a), V(b)
    d = b - a
    prof = [(-B / 2, -H / 2), (B / 2, -H / 2), (B / 2, -H / 2 + tf), (tw / 2, -H / 2 + tf),
            (tw / 2, H / 2 - tf), (B / 2, H / 2 - tf), (B / 2, H / 2), (-B / 2, H / 2),
            (-B / 2, H / 2 - tf), (-tw / 2, H / 2 - tf), (-tw / 2, -H / 2 + tf),
            (-B / 2, -H / 2 + tf)]
    M = Matrix.Translation(a) @ pl.align_z(d)
    m.prism(prof, 0, d.length, mat, M=M, bevel=0.0)


def _pipe(m, a, b, r, mat="rust", n=10):
    a, b = V(a), V(b)
    d = b - a
    m.tube_ring((a + b) / 2, d, r, r * 0.8, d.length, mat, n=n)


def _barrel(m, pos, axis, mat="rust"):
    prof = [(0.0, -0.44), (0.27, -0.44), (0.285, -0.43), (0.285, -0.16), (0.30, -0.15),
            (0.285, -0.14), (0.285, 0.14), (0.30, 0.15), (0.285, 0.16), (0.285, 0.43),
            (0.27, 0.44), (0.0, 0.44)]
    m.lathe(prof, pos, axis, mat, n=16, cap=False)


def _car_door(m, pos, yaw, pitch, roll, mat="dark_metal"):
    _place(m, pos, yaw, pitch, roll)
    body = [(0.0, 0.0), (1.05, 0.0), (1.12, 0.22), (1.10, 0.52), (0.02, 0.55), (-0.05, 0.30)]
    m.prism(body, -0.05, 0.05, mat, bevel=0.012)
    m.sweep([(0.03, 0.55, 0), (0.12, 0.92, 0), (0.62, 0.98, 0), (1.05, 0.55, 0)], 0.028,
            mat, n=4, twist=math.pi / 4)
    # handle recess + a rust scab
    m.box((0.85, 0.42, 0.052), (0.14, 0.04, 0.01), "galv_steel", bevel=0.0)
    m.box((0.35, 0.14, 0.051), (0.40, 0.18, 0.01), "rust", bevel=0.0)
    m.pop()


def _rebar(m, rnd, base, n=3, reach=0.9):
    for _ in range(n):
        p = V(base) + V(rnd.uniform(-0.2, 0.2), 0, rnd.uniform(-0.2, 0.2))
        d = V(rnd.uniform(-0.6, 0.6), 1.0, rnd.uniform(-0.6, 0.6)).normalized()
        k = V(rnd.uniform(-1, 1), rnd.uniform(-0.2, 0.3), rnd.uniform(-1, 1)).normalized()
        pts = [p, p + d * reach * 0.45, p + d * reach * 0.62 + k * 0.12,
               p + d * reach * 0.78 + k * 0.35, p + d * reach * 0.8 + k * 0.55]
        m.sweep(pts, 0.011, "rust", n=4)


def _bale(m, pos, size, yaw, rnd):
    """A crushed-car bale: stacked compressed layers with ragged offsets."""
    w, h, d = size
    n = 4
    for i in range(n):
        mat = "rust" if rnd.random() < 0.6 else "dark_metal"
        _place(m, V(pos) + V(rnd.uniform(-0.04, 0.04), h * (i + 0.5) / n, rnd.uniform(-0.04, 0.04)),
               yaw + rnd.uniform(-3, 3), rnd.uniform(-2, 2), rnd.uniform(-2, 2))
        f = m.box((0, 0, 0), (w * rnd.uniform(0.94, 1.03), h / n * 0.96, d * rnd.uniform(0.94, 1.03)),
                  mat, bevel=0.0)
        m.crumple(f, 0.03, seed=rnd.randint(0, 999), freq=3.0, cuts=2)
        m.pop()


def _scatter(m, rnd, count, rx_=1.45, rz_=0.95):
    """Small crushed offcuts and pipe stubs round the foot of a heap, so its
    edge breaks up instead of ending in a clean outline."""
    for i in range(count):
        a = rnd.uniform(0, 2 * math.pi)
        r = rnd.uniform(0.75, 1.0)
        p = V(math.cos(a) * rx_ * r, 0.03, math.sin(a) * rz_ * r)
        k = rnd.random()
        if k < 0.6:
            mat = ("rust", "dark_metal", "galv_steel")[rnd.randint(0, 2)]
            _slab(m, p + V(0, 0.02, 0), (rnd.uniform(0.2, 0.45), 0.025, rnd.uniform(0.15, 0.3)),
                  rnd.uniform(0, 180), rnd.uniform(-8, 8), rnd.uniform(-8, 8), mat, amp=0.03)
        else:
            d = V(math.cos(a + 1.3), 0, math.sin(a + 1.3)) * rnd.uniform(0.25, 0.5)
            _pipe(m, p + V(0, 0.05, 0) - d / 2, p + V(0, 0.05, 0) + d / 2, 0.045, n=8)


def scrap_pile_a():
    _CRUMPLE[0] = 100
    rnd = pl.rng(4101)
    m = Mesh("scrap_pile_a")
    j = lambda s=0.05: rnd.uniform(-s, s)
    # the mound: crushed sheet slabs, some bent
    _slab(m, (-0.45, 0.14, 0.15), (1.3, 0.16, 0.95), 12 + j(5), 6, 4, "rust")
    _slab(m, (0.55, 0.16, -0.10), (1.2, 0.20, 1.0), -20, -5, -8, "dark_metal", bend=14)
    _slab(m, (0.05, 0.13, -0.60), (1.5, 0.14, 0.7), 5, 9, 3, "rust")
    _slab(m, (-0.10, 0.42, -0.15), (1.1, 0.05, 0.8), 30, 10, -12, "rust", bend=-18)
    _slab(m, (0.40, 0.55, 0.05), (0.9, 0.05, 0.7), -35, -14, 16, "dark_metal")
    _slab(m, (-0.25, 0.75, -0.25), (0.8, 0.045, 0.6), 55, 20, 8, "rust", bend=22)
    _slab(m, (1.10, 0.10, 0.45), (0.6, 0.12, 0.5), 40, 0, -6, "rust")
    # barrel lying across the top
    _barrel(m, (0.15, 1.00, -0.05), (0.95, 0.25, 0.35))
    # tyre stack on the left, one tyre leaning on the front of the mound
    for i in range(3):
        _tyre(m, (-1.12 + j(0.04), 0.11 + i * 0.215, 0.35 + j(0.04)), yaw=j(20), pitch=j(4))
    _tyre(m, (0.72, 0.36, 0.70), yaw=15, pitch=68, rim=True)
    # I-beam spiking out of the heap: the silhouette's high point
    _ibeam(m, (-0.3, 0.2, -0.55), (1.15, 1.62, -0.35))
    # pipes lying across the front
    _pipe(m, (-0.9, 0.09, 0.78), (0.55, 0.09, 0.95), 0.085)
    _pipe(m, (-0.6, 0.23, 0.70), (0.35, 0.30, 0.82), 0.06)
    _pipe(m, (-1.45, 0.07, -0.55), (-0.4, 0.40, -0.75), 0.11)
    # car door flat on the back of the heap
    _car_door(m, (-1.2, 0.30, 0.0), yaw=20, pitch=-70, roll=10)
    _rebar(m, rnd, (-0.2, 0.75, -0.2), n=4, reach=0.8)
    _slab(m, (0.35, 0.95, 0.30), (0.7, 0.03, 0.45), -60, -30, 25, "galv_steel", amp=0.04)
    _scatter(m, rnd, 9)
    return [m]


def scrap_pile_b():
    _CRUMPLE[0] = 200
    rnd = pl.rng(5202)
    m = Mesh("scrap_pile_b")
    j = lambda s=0.05: rnd.uniform(-s, s)
    # two crushed-car bales stacked on the right: a tall blocky shoulder
    _bale(m, (0.75, 0.0, -0.15), (1.25, 0.62, 0.85), -8, rnd)
    _bale(m, (0.80, 0.62, -0.20), (1.10, 0.55, 0.78), 6, rnd)
    # low slabs spilling to the left
    _slab(m, (-0.55, 0.10, 0.05), (1.3, 0.14, 1.1), -10, 4, 6, "rust")
    _slab(m, (-0.85, 0.30, -0.25), (0.9, 0.05, 0.7), 25, 12, -15, "dark_metal", bend=20)
    _slab(m, (-0.10, 0.26, 0.40), (0.8, 0.045, 0.6), -40, -8, 22, "rust")
    _slab(m, (0.70, 1.26, -0.10), (1.0, 0.05, 0.75), 20, 6, -10, "rust", bend=-16)
    # car door standing against the bale
    _car_door(m, (-0.40, 0.02, 0.42), yaw=-8, pitch=-11, roll=0)
    # upright barrel front left, a second knocked over
    _barrel(m, (-1.15, 0.44, 0.55), (0.03, 1, 0.02))
    _barrel(m, (-1.05, 0.29, -0.55), (1, 0.05, -0.4), mat="dark_metal")
    # tyres: one on top of the bales, one leaning on the front
    _tyre(m, (0.95, 1.43, 0.0), yaw=10, pitch=6, R=0.33, r=0.12)
    _tyre(m, (1.08, 0.36, 0.64), yaw=5, pitch=72, rim=True)
    # pipe bundle leaning up the bales: the peak at ~1.8 m
    for i, (r, dz) in enumerate(((0.07, -0.12), (0.055, 0.0), (0.08, 0.13))):
        _pipe(m, (-0.2 + dz * 0.3, 0.07, -0.55 + dz), (1.20 + j(0.1), 1.72 + i * 0.03, -0.45 + dz), r)
    # I-beam across the front foot
    _ibeam(m, (-0.4, 0.12, 0.85), (1.3, 0.12, 0.62), H=0.20, B=0.12)
    _rebar(m, rnd, (0.8, 1.2, -0.2), n=4, reach=0.7)
    _rebar(m, rnd, (-0.7, 0.3, -0.1), n=2, reach=0.6)
    _slab(m, (-0.55, 0.50, -0.45), (0.8, 0.03, 0.5), 70, 35, -10, "galv_steel", amp=0.04)
    _scatter(m, rnd, 9)
    return [m]


# =============================================================== 11 crane

def _lattice_boom(m, foot, tip, d0, d1, w0, w1, pitch=1.3):
    foot, tip = V(foot), V(tip)
    f = (tip - foot)
    L = f.length
    f.normalize()
    nrm = V(-f.y, f.x, 0)
    zz = V(0, 0, 1)

    def P(t, sn, sz):
        s = t / L
        d = d0 + (d1 - d0) * s
        w = w0 + (w1 - w0) * s
        return foot + f * t + nrm * (sn * d / 2) + zz * (sz * w / 2)

    for sn in (-1, 1):
        for sz in (-1, 1):
            m.beam(P(0, sn, sz), P(L, sn, sz), 0.14, 0.14, "dark_metal", up=zz)
    k = int(L / pitch)
    for sz in (-1, 1):          # the two side faces: the silhouette
        for i in range(k):
            ta, tb = L * i / k, L * (i + 1) / k
            a, b = (1, -1) if i % 2 == 0 else (-1, 1)
            m.beam(P(ta, a, sz), P(tb, b, sz), 0.07, 0.07, "dark_metal", up=zz)
    for i in range(0, k + 1, 2):  # ties across the top and bottom faces
        t = L * i / k
        for sn in (-1, 1):
            m.beam(P(t, sn, -1), P(t, sn, 1), 0.06, 0.06, "dark_metal", up=nrm)
    return P


def crane_skyline():
    m = Mesh("crane_skyline")
    # crawler tracks
    for sz in (-1, 1):
        m.box((0.4, 0.5, sz * 1.55), (5.2, 1.0, 0.95), "dark_metal", bevel=0.08)
        for sx in (-1, 1):
            m.cyl((0.4 + sx * 2.3, 0.5, sz * 1.55), (0, 0, 1), 0.48, 1.0, "dark_metal", n=12)
    m.box((0.4, 1.15, 0), (2.4, 0.4, 2.2), "dark_metal", bevel=0.05)
    # superstructure, counterweight, cab
    m.box((-0.2, 1.95, 0), (4.4, 1.3, 2.8), "dark_metal", bevel=0.06)
    m.box((-2.7, 1.9, 0), (1.2, 1.6, 3.0), "dark_metal", bevel=0.06)
    m.box((1.7, 3.05, 1.05), (1.3, 1.0, 1.0), "dark_metal", bevel=0.05)
    m.box((1.6, 3.9, -0.6), (0.2, 0.9, 0.2), "dark_metal", bevel=0.0)    # exhaust stack
    # gantry (A-frame)
    apex = V(-1.4, 6.8, 0)
    for sz in (-1, 1):
        m.beam((-2.4, 2.6, sz * 1.0), apex + V(0, 0, sz * 0.6), 0.22, 0.22, "dark_metal")
        m.beam((0.2, 2.6, sz * 1.0), apex + V(0, 0, sz * 0.6), 0.22, 0.22, "dark_metal")
    m.beam(apex + V(0, 0, -0.7), apex + V(0, 0, 0.7), 0.25, 0.25, "dark_metal")
    # the boom
    foot = V(1.3, 2.7, 0)
    ang = math.radians(66)
    L = 16.6
    tip = foot + V(math.cos(ang), math.sin(ang), 0) * L
    _lattice_boom(m, foot, tip, 1.0, 0.55, 1.2, 0.6, pitch=1.25)
    # boom head sheaves
    m.cyl(tip + V(0.25, 0.1, 0), (0, 0, 1), 0.38, 0.5, "dark_metal", n=12)
    # pendant lines, gantry to boom head
    for sz in (-1, 1):
        m.beam(apex + V(0, 0.1, sz * 0.5), tip + V(-0.2, 0.3, sz * 0.25), 0.05, 0.05, "cable")
    # hoist lines down to the grab
    gx = tip.x + 0.35
    gy = 6.3
    for dz in (-0.12, 0.12):
        m.beam((gx, tip.y, dz), (gx, gy + 0.8, dz), 0.05, 0.05, "cable")
    # orange-peel grab: head, hub, five tines, and a crushed slab in its claws
    m.box((gx, gy + 0.55, 0), (0.7, 0.5, 0.7), "dark_metal", bevel=0.05)
    m.cyl((gx, gy + 0.1, 0), (0, 1, 0), 0.45, 0.5, "dark_metal", n=10)
    for i in range(5):
        t = 2 * math.pi * i / 5 + 0.3
        dx, dz = math.cos(t), math.sin(t)
        pts = [(0.35, 0.0), (0.95, -0.55), (0.95, -1.35), (0.45, -1.85)]
        prev = None
        for (r, y) in pts:
            p = V(gx + dx * r, gy + y, dz * r)
            if prev is not None:
                m.beam(prev, p, 0.24, 0.10, "dark_metal", up=(dx, 0, dz))
            prev = p
    m.box((gx, gy - 1.05, 0), (1.3, 0.5, 0.9), "rust", bevel=0.05, rot=rz(12))
    # aircraft warning lamps: boom head and gantry apex
    m.sphere(tip + V(0.25, 0.55, 0), 0.14, "lamp_red", seg=8, rings=4)
    m.sphere(apex + V(0, 0.25, 0), 0.12, "lamp_red", seg=8, rings=4)
    return [m]


# =============================================================== 12 camera crane

def camera_crane():
    m = Mesh("camera_crane")
    hub_y = 0.34
    # tripod: hub, three legs, castors
    m.cyl((0, hub_y, 0), (0, 1, 0), 0.09, 0.12, "dark_metal", n=10)
    for i in range(3):
        t = math.radians(90 + 120 * i)
        dx, dz = math.cos(t), math.sin(t)
        foot = V(dx * 0.78, 0.13, dz * 0.78)
        m.beam(V(dx * 0.06, hub_y, dz * 0.06), foot, 0.05, 0.05, "dark_metal")
        m.box(foot, (0.08, 0.04, 0.08), "galv_steel", bevel=0.004)
        m.box(foot + V(0, -0.045, 0), (0.035, 0.05, 0.05), "galv_steel", bevel=0.0)
        m.cyl(foot + V(0, -0.075, 0), (-dz, 0, dx), 0.05, 0.04, "rubber", n=10)
        # spreader brace to the column
        m.rod(V(dx * 0.45, 0.20, dz * 0.45), V(0, 0.62, 0), 0.013, "aluminium", n=6)
    # column with clamp collars
    m.rod((0, hub_y, 0), (0, 1.36, 0), 0.048, "aluminium", n=10)
    for yy in (0.62, 1.05):
        m.cyl((0, yy, 0), (0, 1, 0), 0.062, 0.05, "dark_metal", n=10)
        m.rod((0.06, yy, 0), (0.14, yy, 0), 0.01, "galv_steel", n=6)
    # fulcrum head
    m.cyl((0, 1.38, 0), (0, 1, 0), 0.08, 0.05, "dark_metal", n=10)
    for sz in (-1, 1):
        m.box((0, 1.47, sz * 0.07), (0.18, 0.16, 0.02), "dark_metal", bevel=0.004)
    m.cyl((0, 1.49, 0), (0, 0, 1), 0.03, 0.18, "galv_steel", n=10)
    # the arm: 3 m forward (+X), 1 m back, tipped up 10 degrees
    piv = V(0, 1.49, 0)
    ang = math.radians(10)
    f = V(math.cos(ang), math.sin(ang), 0)
    up = V(-math.sin(ang), math.cos(ang), 0)
    front = piv + f * 3.0
    back = piv - f * 1.05
    m.beam(back, front, 0.075, 0.075, "aluminium", up=up, bevel=0.006)
    # section joints along the arm
    for t in (-0.6, 0.9, 2.0):
        m.beam(piv + f * (t - 0.05), piv + f * (t + 0.05), 0.095, 0.095, "dark_metal", up=up)
    # king post and tension cables
    kp = piv + up * 0.50
    m.beam(piv + up * 0.04, kp, 0.04, 0.04, "aluminium", up=f, bevel=0.0)
    m.rod(kp, front + up * 0.04, 0.0055, "cable", n=4)
    m.rod(kp, back + up * 0.04, 0.0055, "cable", n=4)
    # counterweights on the back end + push handle
    for i in range(3):
        m.cyl(back + f * (0.08 + i * 0.05), f, 0.12, 0.045, "dark_metal", n=12)
    m.beam(back, back - f * 0.25 - up * 0.1, 0.03, 0.03, "galv_steel", up=up)
    # remote head: yoke hanging off the front, camera looking +Z (the arena)
    head = front - up * 0.02
    m.cyl(head - V(0, 0.06, 0), (0, 1, 0), 0.05, 0.08, "dark_metal", n=10)
    m.box(head - V(0, 0.12, 0), (0.05, 0.03, 0.30), "dark_metal", bevel=0.004)
    m.box(head - V(0, 0.25, -0.14), (0.05, 0.26, 0.03), "dark_metal", bevel=0.004)
    cam = head - V(0, 0.31, 0)
    m.box(cam, (0.14, 0.16, 0.26), "dark_metal", bevel=0.01)
    m.cyl(cam + V(0, 0.01, 0.20), (0, 0, 1), 0.055, 0.15, "dark_metal", n=12, bevel=0.004)
    m.lathe([(0.066, 0.0), (0.066, 0.05), (0.0, 0.05)], cam + V(0, 0.01, 0.27), (0, 0, 1),
            "dark_metal", n=12)
    m.lathe([(0.05, 0.0), (0.0, 0.0)], cam + V(0, 0.01, 0.322), (0, 0, 1), "lamp_white",
            n=12, cap=False)
    m.box(cam + V(0, 0.10, -0.04), (0.10, 0.04, 0.12), "dark_metal", bevel=0.004)
    # operator monitor on the back of the arm
    mon = back + f * 0.35 + up * 0.14
    m.box(mon, (0.035, 0.16, 0.24), "dark_metal", bevel=0.006)
    m.quad([mon + V(-0.019, 0.065, -0.10), mon + V(-0.019, -0.065, -0.10),
            mon + V(-0.019, -0.065, 0.10), mon + V(-0.019, 0.065, 0.10)], "screen",
           uv=((0, 0), (0, 1), (1, 1), (1, 0)))
    # cable loom from the camera back along the arm and down the column
    m.sweep([cam + V(0, 0.08, -0.13), head + V(-0.1, 0.02, -0.06), piv + f * 1.5 + V(0, -0.06, -0.05),
             piv + V(0.05, -0.08, -0.06), V(0.06, 1.0, -0.06), V(0.07, 0.5, -0.07),
             V(0.2, 0.03, -0.3), V(0.5, 0.02, -0.9)], 0.011, "cable", n=5)
    return [m]


PIECES = [
    ("truss_span_2m", truss_span_2m), ("truss_corner", truss_corner),
    ("truss_tower_leg", truss_tower_leg), ("moving_head", moving_head),
    ("screen_frame", screen_frame), ("beacon", beacon),
    ("pyro_launcher", pyro_launcher), ("flight_case_stack", flight_case_stack),
    ("cable_drum", cable_drum), ("scrap_pile_a", scrap_pile_a),
    ("scrap_pile_b", scrap_pile_b), ("crane_skyline", crane_skyline),
    ("camera_crane", camera_crane),
]


# =============================================================== verification

def read_glb(path):
    with open(path, "rb") as fh:
        data = fh.read()
    magic, ver, total = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67
    off = 12
    js, binc = None, b""
    while off < total:
        ln, typ = struct.unpack_from("<II", data, off)
        chunk = data[off + 8: off + 8 + ln]
        if typ == 0x4E4F534A:
            js = json.loads(chunk.decode("utf8"))
        else:
            binc = chunk
        off += 8 + ln
    return js, binc


def _acc(js, binc, i):
    a = js["accessors"][i]
    bv = js["bufferViews"][a["bufferView"]]
    comp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    fmt = {5126: "f", 5123: "H", 5125: "I", 5121: "B"}[a["componentType"]]
    size = struct.calcsize(fmt)
    stride = bv.get("byteStride", size * comp)
    base = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    out = []
    for k in range(a["count"]):
        out.append(struct.unpack_from("<" + fmt * comp, binc, base + k * stride))
    return out


def verify(name):
    path = os.path.join(OUT, name + ".glb")
    js, binc = read_glb(path)
    nodes = js["nodes"]
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i

    def world_t(i):
        t = [0.0, 0.0, 0.0]
        while i is not None:
            tr = nodes[i].get("translation", [0, 0, 0])
            assert "rotation" not in nodes[i] and "scale" not in nodes[i], "unapplied transform"
            t = [t[k] + tr[k] for k in range(3)]
            i = parent.get(i)
        return t

    lo, hi = [1e9] * 3, [-1e9] * 3
    tris, slots, info = 0, [], {}
    for i, n in enumerate(nodes):
        if "mesh" not in n:
            continue
        t = world_t(i)
        info[n["name"]] = {"translation": [round(x, 4) for x in n.get("translation", [0, 0, 0])],
                           "parent": nodes[parent[i]]["name"] if i in parent else None}
        for p in js["meshes"][n["mesh"]]["primitives"]:
            a = js["accessors"][p["attributes"]["POSITION"]]
            for k in range(3):
                lo[k] = min(lo[k], a["min"][k] + t[k])
                hi[k] = max(hi[k], a["max"][k] + t[k])
            tris += js["accessors"][p["indices"]]["count"] // 3
            mname = js["materials"][p["material"]]["name"]
            if mname not in slots:
                slots.append(mname)
            if mname == "screen":
                pos = _acc(js, binc, p["attributes"]["POSITION"])
                uv = _acc(js, binc, p["attributes"]["TEXCOORD_0"])
                nr = _acc(js, binc, p["attributes"]["NORMAL"])[0]
                # viewer looks along -normal with +Y up: right = -n x up
                right = (nr[2], 0.0, -nr[0])
                us = [q[0] * right[0] + q[2] * right[2] for q in pos]
                ys = [q[1] for q in pos]
                ok = True
                for q, w, uu in zip(pos, uv, us):
                    eu = (uu - min(us)) / (max(us) - min(us))
                    ev = (max(ys) - q[1]) / (max(ys) - min(ys))
                    if abs(w[0] - eu) > 1e-4 or abs(w[1] - ev) > 1e-4:
                        ok = False
                xs = [q[0] for q in pos]
                zs = [q[2] for q in pos]
                info.setdefault("screen_uv", []).append({
                    "ok": ok, "tris": js["accessors"][p["indices"]]["count"] // 3,
                    "normal": [round(c, 3) for c in nr],
                    "x": (round(min(xs) + t[0], 4), round(max(xs) + t[0], 4)),
                    "y": (round(min(ys) + t[1], 4), round(max(ys) + t[1], 4)),
                    "z": (round(min(zs) + t[2], 4), round(max(zs) + t[2], 4))})
    cams = len(js.get("cameras", [])) + len(js.get("extensions", {}).get("KHR_lights_punctual", {}).get("lights", []))
    return {"name": name, "min": [round(x, 3) for x in lo], "max": [round(x, 3) for x in hi],
            "tris": tris, "budget": BUDGET[name], "slots": slots, "nodes": info,
            "cams_lights": cams, "bytes": os.path.getsize(path)}


# =============================================================== contact sheet

def _sheet_tiles(tmp, tile_w, tile_h):
    """Render one tile per piece under Blender."""
    meta = []
    for name, _ in PIECES:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        sc = bpy.context.scene
        bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, name + ".glb"))
        objs = [o for o in sc.objects if o.type == 'MESH']
        roots = [o for o in sc.objects if o.parent is None]
        lift = 0.0
        extra = None
        if name in ("truss_span_2m", "truss_corner"):
            lift = 0.15
        if name == "screen_frame":
            lift = 1.35 + 0.15 + 0.25
        if name == "moving_head":
            lift = 1.3
            # hang it under a span, and tilt the head to prove the pivot
            bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, "truss_span_2m.glb"))
            for o in sc.objects:
                if o.parent is None and o not in roots:
                    o.location.z += lift + 0.15
            for o in sc.objects:
                if o.name.startswith("mh_head"):
                    o.rotation_mode = 'XYZ'
                    o.rotation_euler.x += math.radians(50)
                if o.name.startswith("mh_yoke"):
                    o.rotation_mode = 'XYZ'
                    o.rotation_euler.z += math.radians(60)
        for o in roots:
            o.location.z += lift
        bpy.context.view_layer.update()
        # screen: an LED dot grid with a UV gradient, so orientation is visible
        scr = bpy.data.materials.get("screen")
        if scr is not None:
            nt = scr.node_tree
            bsdf = nt.nodes.get("Principled BSDF")
            tc = nt.nodes.new("ShaderNodeTexCoord")
            sep = nt.nodes.new("ShaderNodeSeparateXYZ")
            nt.links.new(tc.outputs["UV"], sep.inputs[0])
            comb = nt.nodes.new("ShaderNodeCombineXYZ")
            nt.links.new(sep.outputs[0], comb.inputs[0])       # U -> red (right)
            nt.links.new(sep.outputs[1], comb.inputs[2])       # Blender V -> blue (top)
            comb.inputs[1].default_value = 0.25
            chk = nt.nodes.new("ShaderNodeTexBrick")
            chk.inputs["Scale"].default_value = 60
            chk.inputs["Mortar Size"].default_value = 0.03
            nt.links.new(tc.outputs["UV"], chk.inputs["Vector"])
            mul = nt.nodes.new("ShaderNodeVectorMath")
            mul.operation = 'MULTIPLY'
            nt.links.new(comb.outputs[0], mul.inputs[0])
            nt.links.new(chk.outputs["Fac"], mul.inputs[1])
            nt.links.new(mul.outputs[0], bsdf.inputs["Emission Color"])
            bsdf.inputs["Emission Strength"].default_value = 1.2
        # bounds
        lo = Vector((1e9, 1e9, 1e9))
        hi = -lo
        for o in sc.objects:
            if o.type != 'MESH':
                continue
            for c in o.bound_box:
                w = o.matrix_world @ Vector(c)
                lo = Vector(map(min, lo, w))
                hi = Vector(map(max, hi, w))
        ctr = (lo + hi) / 2
        rad = (hi - lo).length / 2
        # ground
        bpy.ops.mesh.primitive_plane_add(size=max(40.0, rad * 12), location=(ctr.x, ctr.y, 0))
        g = bpy.context.active_object
        gm = bpy.data.materials.new("ground")
        gm.use_nodes = True
        gb = gm.node_tree.nodes.get("Principled BSDF")
        gb.inputs["Base Color"].default_value = (0.022, 0.023, 0.025, 1)
        gb.inputs["Roughness"].default_value = 0.8
        g.data.materials.append(gm)
        # lights (suns: scale free)
        for rot, e, ang in (((math.radians(50), 0, math.radians(35)), 3.2, 12),
                            ((math.radians(65), 0, math.radians(-120)), 1.0, 25),
                            ((math.radians(70), 0, math.radians(170)), 2.0, 8)):
            ld = bpy.data.lights.new("sun", 'SUN')
            ld.energy = e
            ld.angle = math.radians(ang)
            lo_ = bpy.data.objects.new("sun", ld)
            lo_.rotation_euler = rot
            sc.collection.objects.link(lo_)
        w = bpy.data.worlds.new("w")
        w.use_nodes = True
        w.node_tree.nodes["Background"].inputs[0].default_value = (0.10, 0.105, 0.11, 1)
        w.node_tree.nodes["Background"].inputs[1].default_value = 1.0
        sc.world = w
        # camera: 3/4 from the front (Blender -Y) and above
        yaw, pitch = math.radians(32), math.radians(24)
        fov = math.radians(32)
        dirv = Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
        right = Vector((math.cos(yaw), math.sin(yaw), 0.0))
        upv = (Vector((0, 0, 1)) - dirv * dirv.z).normalized()
        th = math.tan(fov / 2) * 0.90
        tv = th * tile_h / tile_w
        dist = 0.0
        for cx_ in (lo.x, hi.x):
            for cy_ in (lo.y, hi.y):
                for cz_ in (lo.z, hi.z):
                    p = Vector((cx_, cy_, cz_)) - ctr
                    z = p.dot(dirv)
                    dist = max(dist, z + abs(p.dot(right)) / th, z + abs(p.dot(upv)) / tv)
        cd = bpy.data.cameras.new("cam")
        cd.sensor_fit = 'HORIZONTAL'
        cd.angle = fov
        cd.clip_end = dist * 10
        co = bpy.data.objects.new("cam", cd)
        co.location = ctr + dirv * dist
        co.rotation_euler = (-dirv).to_track_quat('-Z', 'Y').to_euler()
        sc.collection.objects.link(co)
        sc.camera = co
        sc.render.engine = 'BLENDER_EEVEE_NEXT'
        sc.eevee.taa_render_samples = 64
        try:
            sc.eevee.use_shadows = True
            sc.eevee.use_raytracing = True
        except Exception:
            pass
        sc.view_settings.view_transform = 'Standard'
        sc.render.resolution_x = tile_w
        sc.render.resolution_y = tile_h
        sc.render.film_transparent = False
        out = os.path.join(tmp, name + ".png")
        sc.render.filepath = out
        bpy.ops.render.render(write_still=True)
        meta.append(name)
    return meta


def compose(tmp, results):
    from PIL import Image, ImageDraw, ImageFont
    cols, tw, th, lab = 4, 480, 360, 46
    rows = (len(results) + cols - 1) // cols
    head = 64
    W, H = cols * tw, head + rows * (th + lab)
    sheet = Image.new("RGB", (W, H), (22, 23, 25))
    d = ImageDraw.Draw(sheet)

    def font(sz):
        for p in ("/System/Library/Fonts/Supplemental/Arial Bold.ttf",
                  "/System/Library/Fonts/Helvetica.ttc"):
            try:
                return ImageFont.truetype(p, sz)
            except Exception:
                pass
        return ImageFont.load_default()

    f1, f2, f3 = font(26), font(17), font(13)
    d.text((18, 18), "Arena kit: broadcast and dressing props (kit_props.py)", fill=(230, 230, 230), font=f1)
    for i, r in enumerate(results):
        cx, cy = (i % cols) * tw, head + (i // cols) * (th + lab)
        im = Image.open(os.path.join(tmp, r["name"] + ".png")).convert("RGB").resize((tw, th), Image.LANCZOS)
        sheet.paste(im, (cx, cy))
        size = [r["max"][k] - r["min"][k] for k in range(3)]
        d.text((cx + 10, cy + th + 4), r["name"], fill=(240, 240, 240), font=f2)
        d.text((cx + 10, cy + th + 25), "%.2f x %.2f x %.2f m   %d / %d tris" %
               (size[0], size[1], size[2], r["tris"], r["budget"]), fill=(160, 165, 170), font=f3)
    os.makedirs(os.path.dirname(SHEET), exist_ok=True)
    sheet.save(SHEET)
    print("sheet ->", SHEET, sheet.size)


# =============================================================== main

def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    if "--only" in argv:
        only = set(argv[argv.index("--only") + 1].split(","))
    if "--no-build" not in argv:
        for name, fn in PIECES:
            if only and name not in only:
                continue
            pl.build(fn(), os.path.join(OUT, name + ".glb"))
    results = []
    print("\n%-18s %-26s %-26s %6s %6s  %s" % ("piece", "min (godot)", "max (godot)", "tris", "budget", "slots"))
    for name, _ in PIECES:
        if not os.path.exists(os.path.join(OUT, name + ".glb")):
            continue
        r = verify(name)
        results.append(r)
        flag = "" if r["tris"] <= r["budget"] else "  OVER"
        print("%-18s %-26s %-26s %6d %6d  %s%s" % (name, r["min"], r["max"], r["tris"], r["budget"],
                                                   ",".join(r["slots"]), flag))
        if len(r["nodes"]) > 1 or "screen_uv" in r["nodes"]:
            print("    nodes:", json.dumps(r["nodes"]))
        assert r["cams_lights"] == 0
    import tempfile
    tmp = tempfile.mkdtemp(prefix="kitprops_")
    vjson = os.path.join(tmp, "verify.json")
    with open(vjson, "w") as fh:
        json.dump(results, fh, indent=1)
    if "--sheet" in argv:
        _sheet_tiles(tmp, 960, 720)
        subprocess.check_call(["/usr/bin/env", "python3", os.path.abspath(__file__), "--compose", tmp,
                               vjson],
                              env={k: v for k, v in os.environ.items() if not k.startswith("PYTHON")})


if __name__ == "__main__":
    if IN_BLENDER:
        main()
    elif "--compose" in sys.argv:
        i = sys.argv.index("--compose")
        with open(sys.argv[i + 2]) as fh:
            compose(sys.argv[i + 1], json.load(fh))
