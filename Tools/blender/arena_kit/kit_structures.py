"""Arena kit: the STRUCTURAL pieces (scaffold stand, containers, flood tower,
stair, fence, crowd barrier, fighters' entrance gate).

    ~/Applications/Blender.app/Contents/MacOS/Blender -b --python \\
        Tools/blender/arena_kit/kit_structures.py [-- --no-sheet] [-- --only name,name]

writes Arena/arena/kit/models/<name>.glb for every piece, prints the glTF
accessor bounds of each (Godot space) and renders the review contact sheet
docs/aaa/img/wave-a/kit/kit-structures-sheet.png.

Everything is authored in GODOT space (+Y up, +Z = the front, the arena side),
see kitlib.py.  Origins sit at the base centre of each piece on the ground.
"""

import math
import os
import subprocess
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import importlib  # noqa: E402
import kitlib  # noqa: E402
importlib.reload(kitlib)
from kitlib import Kit, X, Y, Z, rot_x, rot_y, rot_z, export_kit, glb_info  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(REPO, "Arena", "arena", "kit", "models")
SHEET = os.path.join(REPO, "docs", "aaa", "img", "wave-a", "kit", "kit-structures-sheet.png")

V = Vector
TUBE_R = 0.024          # 48.3 mm scaffold tube


def about(pivot, M):
    """Rotation M about a pivot point (4x4)."""
    p = V(pivot)
    return Matrix.Translation(p) @ M @ Matrix.Translation(-p)


# =================================================================== 1. stand

def tread_y(i):
    return 0.55 + 0.5 * i


def line_z(k):
    return -0.75 * k


def _stand_side(K, xs, endcap):
    """Standards, side ledgers, side braces, couplers and base plates in the
    plane x = xs."""
    r = TUBE_R
    zs = []
    for k in range(7):
        z = line_z(k)
        if k == 0:
            z -= 0.04
        if k == 6:
            z += 0.04
        zs.append(z)
    # standard tops
    tops = []
    for k in range(7):
        if k == 0:
            h = tread_y(0) + 1.0
        elif k == 6:
            h = tread_y(5) + 1.1
        else:
            h = tread_y(k) + 1.0 if endcap else tread_y(k) - 0.045
        tops.append(h)
    for k, z in enumerate(zs):
        K.tube((xs, 0.07, z), (xs, tops[k], z), r, "galv_steel", sides=8)
        # base jack + plate + sole board
        K.box((xs, 0.045, z), (0.05, 0.05, 0.05), "dark_metal", bevel=0.0)
        K.box((xs, 0.01, z), (0.16, 0.02, 0.16), "dark_metal", bevel=0.004)
    # side ledgers (along Z)
    K.tube((xs, 0.22, zs[0]), (xs, 0.22, zs[6]), r, "galv_steel", sides=8)
    K.tube((xs, 1.45, zs[2]), (xs, 1.45, zs[6]), r, "galv_steel", sides=8)
    K.tube((xs, 2.45, zs[4]), (xs, 2.45, zs[6]), r, "galv_steel", sides=8)
    # tread-carrying ledgers: one per tier, just under the tread, in the side plane
    for i in range(6):
        y = tread_y(i) - 0.075
        K.tube((xs, y, zs[i] + 0.06), (xs, y, zs[i + 1] - 0.06), r, "galv_steel", sides=8)
    # side braces
    braces = [((zs[0], 0.22), (zs[1], tread_y(0) - 0.075)),
              ((zs[1], 0.22), (zs[2], 1.45)),
              ((zs[3], 0.22), (zs[4], 1.45)),
              ((zs[5], 0.22), (zs[6], 1.45)),
              ((zs[4], 1.45), (zs[5], 2.45)),
              ((zs[5], 2.45), (zs[6], 3.5))]
    for (za, ya), (zb, yb) in braces:
        off = 0.05 if xs < 0 else -0.05
        K.tube((xs + off, ya, za), (xs + off, yb, zb), r, "galv_steel", sides=6)
    # couplers on the standards at every ledger crossing
    cz = []
    for k, z in enumerate(zs):
        ys = [0.22]
        if k >= 2:
            ys.append(1.45)
        if k >= 4:
            ys.append(2.45)
        if k < 6:
            ys.append(tread_y(k) - 0.075)
        if k > 0:
            ys.append(tread_y(k - 1) - 0.075)
        for y in ys:
            if y < tops[k]:
                cz.append((xs, y, z))
    for c in cz:
        K.box(c, (0.075, 0.07, 0.075), "galv_steel", bevel=0.0)
    if endcap:
        # raked side guard rail following the tiers
        top_pts = [(zs[k], tops[k]) for k in range(7)]
        top_pts[6] = (zs[6], tread_y(5) + 1.1)
        rail = [(xs, top_pts[0][1], zs[0]), (xs, tread_y(5) + 1.0, zs[5] - 0.2),
                (xs, tread_y(5) + 1.1, zs[6])]
        K.tube(rail[0], V(rail[1]), r, "galv_steel", sides=8)
        K.tube(rail[1], rail[2], r, "galv_steel", sides=8)
        mid = [(p[0], p[1] - 0.5, p[2]) for p in rail]
        K.tube(mid[0], mid[1], r * 0.9, "galv_steel", sides=6)
        K.tube(mid[1], mid[2], r * 0.9, "galv_steel", sides=6)
        # the stepped end skirt: a dark kick plate on each tier edge
        for i in range(6):
            K.box((xs - 0.03, tread_y(i) + 0.075, (line_z(i) + line_z(i + 1)) * 0.5),
                  (0.012, 0.15, 0.75), "galv_steel", bevel=0.004)


def stand_scaffold(endcap=False):
    K = Kit("stand_scaffold_endcap" if endcap else "stand_scaffold_bay")
    xs = 1.0 if endcap else -1.0
    _stand_side(K, xs, endcap)
    if endcap:
        return K
    r = TUBE_R
    x0, x1 = -1.0, 1.0
    # --- treads: three planks per tier, with a steel bearer at each edge
    for i in range(6):
        yt = tread_y(i)
        zf, zb = line_z(i), line_z(i + 1)
        depth = zf - zb
        n = 3
        gap = 0.012
        pd = (depth - gap * (n + 1)) / n
        for j in range(n):
            zc = zf - gap - pd * 0.5 - j * (pd + gap)
            K.box((0.0, yt - 0.02, zc), (1.994, 0.04, pd), "wood", bevel=0.007)
        # bearers along X under front and back of the tread
        for zz in (zf - 0.06, zb + 0.06):
            K.tube((x0, yt - 0.075, zz), (x1, yt - 0.075, zz), r, "galv_steel", sides=8)
        # mid-span board clamp strip (galv) across the planks at x = 0
        K.box((0.0, yt + 0.002, (zf + zb) * 0.5), (0.05, 0.008, depth - 0.02), "galv_steel",
              bevel=0.0)
        # riser / kick plate at the front edge of each tier
        y_lo = 0.03 if i == 0 else tread_y(i - 1)
        K.box((0.0, (y_lo + yt - 0.04) * 0.5, zf - 0.008), (1.998, yt - 0.04 - y_lo, 0.014),
              "galv_steel" if i == 0 else "dark_metal", bevel=0.004)
        # bolts along the riser top edge
        for bx in (-0.5, 0.5):
            K.bolt((bx, yt - 0.09, zf - 0.001), Z, "galv_steel", r=0.014, h=0.01)
    # --- front skirt stiffener ribs (pressed), tier 0
    for bx in (-0.5, 0.5):
        K.box((bx, 0.28, 0.004), (0.06, 0.44, 0.012), "galv_steel", bevel=0.003)
    # --- front guard rail (tier 0, 1.0 m above the tread)
    zr = line_z(0) - 0.04
    K.tube((x0, tread_y(0) + 1.0, zr), (x1, tread_y(0) + 1.0, zr), r, "galv_steel", sides=8)
    K.tube((x0, tread_y(0) + 0.5, zr), (x1, tread_y(0) + 0.5, zr), r, "galv_steel", sides=8)
    K.box((0.0, tread_y(0) + 0.075, zr + 0.03), (1.998, 0.15, 0.02), "galv_steel", bevel=0.004)
    for y in (tread_y(0) + 1.0, tread_y(0) + 0.5):
        K.box((x0, y, zr), (0.075, 0.07, 0.075), "galv_steel", bevel=0.0)
    # --- back guard rail (top tier, 1.1 m)
    zb = line_z(6) + 0.04
    K.tube((x0, tread_y(5) + 1.1, zb), (x1, tread_y(5) + 1.1, zb), r, "galv_steel", sides=8)
    K.tube((x0, tread_y(5) + 0.55, zb), (x1, tread_y(5) + 0.55, zb), r, "galv_steel", sides=8)
    K.box((0.0, tread_y(5) + 0.075, zb - 0.03), (1.998, 0.15, 0.02), "galv_steel", bevel=0.004)
    for y in (tread_y(5) + 1.1, tread_y(5) + 0.55):
        K.box((x0, y, zb), (0.075, 0.07, 0.075), "galv_steel", bevel=0.0)
    # --- base ledgers along X, front and back, and a back facade brace
    K.tube((x0, 0.22, line_z(0) - 0.04), (x1, 0.22, line_z(0) - 0.04), r, "galv_steel", sides=8)
    K.tube((x0, 0.22, zb), (x1, 0.22, zb), r, "galv_steel", sides=8)
    K.tube((x0, 1.45, zb), (x1, 1.45, zb), r, "galv_steel", sides=8)
    K.tube((x0, 2.45, zb), (x1, 2.45, zb), r, "galv_steel", sides=8)
    K.tube((x0 + 0.04, 0.22, zb - 0.05), (x1 - 0.04, 2.45, zb - 0.05), r, "galv_steel", sides=6)
    # plan brace under tier 2 (reads from above between treads? no: stiffens the look from front)
    K.tube((x0 + 0.04, 0.22, line_z(1)), (x1 - 0.04, tread_y(0) - 0.12, line_z(1)), r,
           "galv_steel", sides=6)
    return K


# =================================================================== 2. container

CL, CH, CW = 6.058, 2.591, 2.438


def container(open_doors=False):
    K = Kit("container_20ft_open" if open_doors else "container_20ft")
    hx, hz = CL / 2, CW / 2
    cast = (0.178, 0.118, 0.162)
    # corner castings
    for sx in (-1, 1):
        for sz in (-1, 1):
            for y in (cast[1] / 2, CH - cast[1] / 2):
                c = (sx * (hx - cast[0] / 2), y, sz * (hz - cast[2] / 2))
                K.box(c, cast, "dark_metal", bevel=0.012)
    # corner posts
    for sx in (-1, 1):
        for sz in (-1, 1):
            K.box((sx * (hx - 0.085), CH / 2, sz * (hz - 0.08)), (0.15, CH - 2 * cast[1], 0.15),
                  "container_paint", bevel=0.015)
    # side rails (bottom, top) along X
    for sz in (-1, 1):
        K.box((0, 0.1, sz * (hz - 0.06)), (CL - 2 * cast[0], 0.17, 0.11), "container_paint",
              bevel=0.012)
        K.box((0, CH - 0.06, sz * (hz - 0.06)), (CL - 2 * cast[0], 0.1, 0.11), "container_paint",
              bevel=0.012)
    # end rails along Z (front end -X: sill + header; door end +X: sill + header)
    for sx in (-1, 1):
        K.box((sx * (hx - 0.07), 0.1, 0), (0.13, 0.17, CW - 2 * cast[2]), "container_paint",
              bevel=0.012)
        K.box((sx * (hx - 0.07), CH - 0.1, 0), (0.13, 0.18, CW - 2 * cast[2]), "container_paint",
              bevel=0.012)
    # underside: a dark floor pan with cross members + forklift-pocket lips
    K.box((0, 0.1, 0), (CL - 0.4, 0.12, CW - 0.24), "dark_metal", bevel=0.0)
    for x in (-1.0, 1.0):
        for sz in (-1, 1):
            K.box((x, 0.1, sz * (hz - 0.035)), (0.36, 0.13, 0.03), "dark_metal", bevel=0.0)
    # side walls: trapezoidal corrugation, ribs vertical
    y0, y1 = 0.185, CH - 0.11
    xw0, xw1 = -hx + 0.16, hx - 0.16
    for sz in (-1, 1):
        o = V((xw0, y0, sz * (hz - 0.075)))
        K.corrugated(o, X, Y, xw1 - xw0, y1 - y0, "container_paint", pitch=0.278, depth=0.045,
                     out=V((0, 0, sz)))
        # backing plate to close the sheet from inside
        K.box((0, (y0 + y1) / 2, sz * (hz - 0.09)), (xw1 - xw0, y1 - y0, 0.01), "container_paint",
              bevel=0.0)
    # front end wall (-X), ribs vertical
    zw0, zw1 = -hz + 0.16, hz - 0.16
    K.corrugated(V((-hx + 0.075, y0, zw1)), -Z, Y, zw1 - zw0, y1 - y0, "container_paint",
                 pitch=0.3, depth=0.045, out=-X)
    K.box((-hx + 0.09, (y0 + y1) / 2, 0), (0.01, y1 - y0, zw1 - zw0), "container_paint", bevel=0.0)
    # roof: shallow corrugation, ribs across (along Z)
    K.corrugated(V((xw0, CH - 0.07, -hz + 0.1)), X, Z, xw1 - xw0, CW - 0.2, "container_paint",
                 pitch=0.45, depth=0.025, crest=0.5, flank=0.1, out=Y)
    # hinges and cam keepers on the frame (do not move)
    hinge_z = hz - 0.12
    for sz in (-1, 1):
        for y in (0.45, 1.05, 1.65, 2.25):
            K.box((hx + 0.005, y, sz * hinge_z), (0.06, 0.1, 0.07), "dark_metal", bevel=0.0)
    bar_z = (0.3, 0.8)
    for sz in (-1, 1):
        for bz in bar_z:
            for y in (0.2, CH - 0.2):
                K.box((hx + 0.03, y, sz * bz), (0.07, 0.07, 0.09), "dark_metal", bevel=0.0)
    # doors
    for sz in (-1, 1):
        hinge = V((hx + 0.005, 0, sz * hinge_z))
        if open_doors:
            ang = -100.0 if sz > 0 else 100.0
            K.xform = about(hinge, rot_y(ang))
        z_in, z_out = sz * 0.006, sz * (hz - 0.165)
        zc = (z_in + z_out) / 2
        dw = abs(z_out - z_in)
        dy0, dy1 = 0.2, CH - 0.2
        K.box((hx - 0.045, (dy0 + dy1) / 2, zc), (0.05, dy1 - dy0, dw), "container_paint",
              bevel=0.012)
        # door corrugation (vertical ribs) inside a border
        zlo = min(z_in, z_out) + 0.06
        K.corrugated(V((hx - 0.02, dy0 + 0.1, zlo)), Z, Y, dw - 0.12, dy1 - dy0 - 0.2,
                     "container_paint", pitch=0.25, depth=0.045, out=X)
        # locking bars with guides and handles
        for bz in bar_z:
            z = sz * bz
            K.tube((hx + 0.035, 0.16, z), (hx + 0.035, CH - 0.16, z), 0.017, "dark_metal", sides=6)
            for y in (0.7, 1.9):
                K.box((hx + 0.02, y, z), (0.04, 0.06, 0.07), "dark_metal", bevel=0.0)
            # handle hanging down, with its retainer
            K.box_between((hx + 0.06, 1.25, z), (hx + 0.06, 0.95, z - sz * 0.06), 0.03, 0.02,
                          "dark_metal", bevel=0.0)
            K.box((hx + 0.03, 0.93, z - sz * 0.07), (0.03, 0.05, 0.05), "dark_metal", bevel=0.0)
        # hinge knuckles on the leaf
        for y in (0.45, 1.05, 1.65, 2.25):
            K.box((hx - 0.01, y, sz * (hinge_z - 0.08)), (0.03, 0.08, 0.12), "dark_metal",
                  bevel=0.0)
        K.xform = None
    if open_doors:
        # dark interior, faces pointing inward, open to +X
        ix0, ix1 = -hx + 0.1, hx - 0.07
        iy0, iy1 = 0.17, CH - 0.12
        iz = hz - 0.1
        m = "dark_metal"
        # floor (visible from above +Y)
        K.quad((ix0, iy0, iz), (ix0, iy0, -iz), (ix1, iy0, -iz), (ix1, iy0, iz), m)
        # ceiling (visible from below)
        K.quad((ix0, iy1, -iz), (ix0, iy1, iz), (ix1, iy1, iz), (ix1, iy1, -iz), m)
        # back wall (visible from +X)
        K.quad((ix0, iy0, iz), (ix0, iy1, iz), (ix0, iy1, -iz), (ix0, iy0, -iz), m)
        # side walls
        K.quad((ix0, iy0, -iz), (ix0, iy1, -iz), (ix1, iy1, -iz), (ix1, iy0, -iz), m)
        K.quad((ix1, iy0, iz), (ix1, iy1, iz), (ix0, iy1, iz), (ix0, iy0, iz), m)
        # floor planks read as wood strips near the door
        for j in range(5):
            z = -iz + 0.2 + j * ((2 * iz - 0.4) / 4)
            K.box(((ix0 + ix1) / 2, iy0 + 0.005, z), (ix1 - ix0, 0.01, 0.04), "dark_metal",
                  bevel=0.0)
    return K


# =================================================================== 3. flood tower

LAMP_CENTRE = V((0.0, 9.25, 0.45))
LAMP_TILT = 35.0


def flood_tower():
    K = Kit("flood_tower")
    # ballast block
    K.box((0, 0.3, 0), (1.2, 0.6, 1.2), "concrete", bevel=0.03, seg=2)
    # forklift slots in the block (dark insets front/back)
    for x in (-0.33, 0.33):
        K.box((x, 0.1, 0), (0.22, 0.1, 1.205), "dark_metal", bevel=0.0)
    # lifting eyes
    for sx in (-1, 1):
        for sz in (-1, 1):
            K.box((sx * 0.48, 0.63, sz * 0.48), (0.06, 0.06, 0.02), "galv_steel", bevel=0.0)
    # mast base plate + bolts + gussets
    K.box((0, 0.615, 0), (0.7, 0.03, 0.7), "galv_steel", bevel=0.006)
    for sx in (-1, 1):
        for sz in (-1, 1):
            K.bolt((sx * 0.3, 0.63, sz * 0.3), Y, "galv_steel", r=0.022, h=0.03)
            K.box_between((sx * 0.25, 0.63, sz * 0.25), (sx * 0.25, 0.9, sz * 0.25), 0.012, 0.18,
                          "galv_steel", bevel=0.0, up=V((sx, 0, -sz)))
    # lattice mast
    w = 0.25
    y0, y1 = 0.63, 8.6
    corners = [(-w, -w), (w, -w), (w, w), (-w, w)]
    for cx, cz in corners:
        K.tube((cx, y0, cz), (cx, y1, cz), 0.034, "galv_steel", sides=6)
    nb = 8
    bay = (y1 - y0) / nb
    for f in range(4):
        (ax, az), (bx, bz) = corners[f], corners[(f + 1) % 4]
        for k in range(nb + 1):
            y = y0 + k * bay
            K.box_between((ax, y, az), (bx, y, bz), 0.03, 0.03, "galv_steel", bevel=0.0)
        for k in range(nb):
            ya, yb = y0 + k * bay, y0 + (k + 1) * bay
            if k % 2 == 0:
                K.box_between((ax, ya, az), (bx, yb, bz), 0.025, 0.025, "galv_steel", bevel=0.0)
            else:
                K.box_between((bx, ya, bz), (ax, yb, az), 0.025, 0.025, "galv_steel", bevel=0.0)
    # service ladder on the back face (-Z) with a hoop cage near the top
    lz = -w - 0.22
    for sx in (-1, 1):
        K.box_between((sx * 0.2, 0.63, lz), (sx * 0.2, y1 + 0.9, lz), 0.05, 0.012, "galv_steel",
                      bevel=0.0, up=Z)
    for k in range(int((y1 - 0.9) / 0.35) + 1):
        y = 0.9 + k * 0.35
        K.box_between((-0.2, y, lz), (0.2, y, lz), 0.022, 0.022, "galv_steel", bevel=0.0)
    for y in (1.2, 3.2, 5.2, 7.2):
        for sx in (-1, 1):
            K.box_between((sx * 0.2, y, lz), (sx * 0.2, y, -w), 0.04, 0.01, "galv_steel",
                          bevel=0.0)
    # rest platform at the top of the mast
    K.box((0, y1 + 0.015, -0.1), (0.9, 0.03, 1.0), "grating", bevel=0.0)
    K.box((0, y1 - 0.04, -0.1), (0.94, 0.08, 1.04), "galv_steel", bevel=0.0)
    K.tube((-0.45, y1, -0.6), (-0.45, y1 + 0.9, -0.6), 0.02, "galv_steel", sides=6)
    K.tube((0.45, y1, -0.6), (0.45, y1 + 0.9, -0.6), 0.02, "galv_steel", sides=6)
    K.tube((-0.45, y1 + 0.9, -0.6), (0.45, y1 + 0.9, -0.6), 0.02, "galv_steel", sides=6)
    # head: king post + tilted frame
    R = rot_x(LAMP_TILT)

    def head(p):
        return LAMP_CENTRE + (R @ V(p))

    K.tube((0, y1, 0.1), head((0, 0.1, -0.2)), 0.06, "galv_steel", sides=8)
    for sx in (-1, 1):
        K.tube((sx * 0.25, y1, 0.2), head((sx * 0.55, -0.62, -0.2)), 0.03, "galv_steel", sides=6)
        K.tube((sx * 0.25, y1, -0.25), head((sx * 0.9, 0.62, -0.2)), 0.025, "galv_steel", sides=6)
    # frame bars (behind the lamps)
    for ly in (-0.62, 0.0, 0.62):
        K.box_between(head((-1.12, ly, -0.2)), head((1.12, ly, -0.2)), 0.06, 0.06, "galv_steel",
                      bevel=0.0, up=R @ Z)
    for lx in (-1.12, 1.12):
        K.box_between(head((lx, -0.65, -0.2)), head((lx, 0.65, -0.2)), 0.06, 0.06, "galv_steel",
                      bevel=0.0, up=R @ Z)
    # 2 x 3 lamps
    lamp_w, lamp_h, lamp_d = 0.6, 0.48, 0.2
    lamp_pos = []
    for row, ly in enumerate((-0.31, 0.31)):
        for lx in (-0.72, 0.0, 0.72):
            c = head((lx, ly, 0.0))
            lamp_pos.append(c)
            K.box(c, (lamp_w, lamp_h, lamp_d), "dark_metal", bevel=0.02, rot=R)
            # lens
            K.box(head((lx, ly, lamp_d / 2 + 0.004)), (lamp_w - 0.08, lamp_h - 0.08, 0.02),
                  "lamp_warm", bevel=0.0, rot=R)
            # bezel bars (top/bottom) framing the lens
            K.box(head((lx, ly + lamp_h / 2 - 0.02, lamp_d / 2 + 0.03)), (lamp_w, 0.04, 0.06),
                  "dark_metal", bevel=0.0, rot=R)
            # yoke brackets to the frame
            for sx in (-1, 1):
                K.box(head((lx + sx * (lamp_w / 2 + 0.02), ly, -0.08)), (0.025, 0.12, 0.2),
                      "galv_steel", bevel=0.0, rot=R)
    # cables: each lamp to a head junction box, then down the mast
    jb = V((0.0, y1 + 0.35, -0.12))
    K.box(jb, (0.34, 0.3, 0.14), "dark_metal", bevel=0.012)
    for c in lamp_pos:
        back = c + R @ V((0, 0, -lamp_d / 2 - 0.02))
        mid = (back + jb) * 0.5 + V((0, -0.22, 0))
        K.polyline_tube([back, mid, jb + V((0, -0.1, 0))], 0.012, "rubber", sides=5)
    cx = -w - 0.05
    run = [jb + V((-0.1, -0.15, 0)), V((cx, y1 - 0.2, 0.0)), V((cx, 1.0, 0.0)),
           V((cx - 0.05, 0.75, 0.2)), V((-0.42, 0.78, 0.38))]
    K.polyline_tube(run, 0.02, "rubber", sides=6)
    run2 = [p + V((0, 0, 0.06)) for p in run[1:4]]
    K.polyline_tube(run2, 0.016, "rubber", sides=6)
    for y in (1.5, 3.0, 4.5, 6.0, 7.5):
        K.box((cx + 0.02, y, 0.03), (0.07, 0.04, 0.14), "dark_metal", bevel=0.0)
    # ground distribution box on the block
    K.box((-0.4, 0.8, 0.38), (0.3, 0.4, 0.2), "dark_metal", bevel=0.015)
    K.box((-0.4, 1.02, 0.38), (0.34, 0.03, 0.24), "dark_metal", bevel=0.006)
    K.empty("lamp_array_centre", LAMP_CENTRE)
    return K


# =================================================================== 4. stair

def stair_scaffold():
    K = Kit("stair_scaffold")
    x0 = -2.0
    rise, going, n = 0.2, 0.22, 15
    x_land = x0 + going * (n - 1)      # 1.08
    x_end = 2.0
    zw = 0.5
    # stringers (channel beams) both sides
    for sz in (-1, 1):
        z = sz * (zw + 0.03)
        a = V((x0 + 0.02, 0.17, z))
        b = V((x_land + 0.02, 3.0 - 0.13, z))
        K.box_between(a, b, 0.05, 0.22, "galv_steel", bevel=0.008, up=V((0, 1, 0)))
        # channel flanges
        K.box_between(a + V((0, 0, sz * 0.02)), b + V((0, 0, sz * 0.02)), 0.06, 0.03,
                      "galv_steel", bevel=0.004)
        # foot plate
        K.box((x0 + 0.05, 0.012, z), (0.3, 0.024, 0.14), "dark_metal", bevel=0.005)
    # treads
    for k in range(1, n):
        xf = x0 + going * (k - 1)
        y = rise * k
        K.box((xf + going / 2, y - 0.015, 0), (going - 0.01, 0.03, 2 * zw - 0.02), "grating",
              bevel=0.0)
        K.box((xf + 0.015, y - 0.02, 0), (0.03, 0.04, 2 * zw - 0.02), "galv_steel", bevel=0.0)
    # landing deck + frame
    lx = (x_land + x_end) / 2
    ll = x_end - x_land
    K.box((lx, 3.0 - 0.015, 0), (ll - 0.04, 0.03, 2 * zw - 0.04), "grating", bevel=0.004)
    for sz in (-1, 1):
        K.box((lx, 3.0 - 0.07, sz * (zw - 0.02)), (ll, 0.14, 0.05), "galv_steel", bevel=0.008)
    for xx in (x_land + 0.025, x_end - 0.025):
        K.box((xx, 3.0 - 0.07, 0), (0.05, 0.14, 2 * zw), "galv_steel", bevel=0.008)
    # landing posts + bracing
    posts = [(x_land + 0.04, -zw + 0.04), (x_land + 0.04, zw - 0.04),
             (x_end - 0.04, -zw + 0.04), (x_end - 0.04, zw - 0.04)]
    for px, pz in posts:
        K.box((px, 1.47, pz), (0.07, 2.94, 0.07), "galv_steel", bevel=0.008)
        K.box((px, 0.012, pz), (0.18, 0.024, 0.18), "dark_metal", bevel=0.005)
    for sz in (-1, 1):
        z = sz * (zw - 0.04)
        K.tube((x_land + 0.04, 0.3, z), (x_end - 0.04, 1.6, z), 0.022, "galv_steel", sides=6)
        K.tube((x_land + 0.04, 1.6, z), (x_end - 0.04, 2.8, z), 0.022, "galv_steel", sides=6)
        K.tube((x_land + 0.04, 1.6, z), (x_end - 0.04, 1.6, z), 0.022, "galv_steel", sides=6)
    K.tube((x_end - 0.04, 0.3, -zw + 0.04), (x_end - 0.04, 2.8, zw - 0.04), 0.022, "galv_steel",
           sides=6)
    # hand rails
    def nose_y(x):
        return rise + (x - x0) * rise / going

    for sz in (-1, 1):
        z = sz * (zw + 0.06)
        post_x = [x0 + 0.15, x0 + 1.15, x0 + 2.15]
        for px in post_x:
            yb = nose_y(px) - 0.05
            K.tube((px, yb, z), (px, yb + 0.95, z), 0.022, "galv_steel", sides=6)
        top_a = V((x0 + 0.1, nose_y(x0 + 0.1) + 0.9, z))
        top_b = V((x_land, 3.0 + 1.0, z))
        K.tube(top_a, top_b, 0.024, "galv_steel", sides=8)
        K.tube(top_a - V((0, 0.45, 0)), top_b - V((0, 0.5, 0)), 0.02, "galv_steel", sides=6)
        # landing rail
        K.tube((x_land, 4.0, z), (x_end - 0.02, 4.0, z), 0.024, "galv_steel", sides=8)
        K.tube((x_land, 3.5, z), (x_end - 0.02, 3.5, z), 0.02, "galv_steel", sides=6)
        for px in (x_land, x_end - 0.02):
            K.tube((px, 2.95, z), (px, 4.0, z), 0.022, "galv_steel", sides=6)
        K.box((lx, 3.07, sz * (zw + 0.01)), (ll, 0.14, 0.015), "galv_steel", bevel=0.003)
    return K


# =================================================================== 5. fence

def fence_panel():
    K = Kit("fence_panel")
    hw = 1.17
    for sx in (-1, 1):
        K.box((sx * 1.18, 0.07, 0), (0.2, 0.14, 0.6), "concrete", bevel=0.02, seg=1)
        K.tube((sx * hw, 0.1, 0), (sx * hw, 2.0, 0), 0.021, "galv_steel", sides=6)
        # top clamp
        K.box((sx * (hw + 0.02), 1.8, 0), (0.07, 0.08, 0.05), "galv_steel", bevel=0.0)
    K.tube((-hw, 1.975, 0), (hw, 1.975, 0), 0.019, "galv_steel", sides=6)
    K.tube((-hw, 0.14, 0), (hw, 0.14, 0), 0.019, "galv_steel", sides=6)
    K.tube((-hw, 1.2, 0), (hw, 1.2, 0), 0.012, "galv_steel", sides=5)
    # infill: one quad, UV 0..1, U left -> right seen from the front (+Z)
    iy0, iy1 = 0.16, 1.955
    K.quad((-hw, iy0, 0), (hw, iy0, 0), (hw, iy1, 0), (-hw, iy1, 0), "grating",
           uvs=((0, 0), (1, 0), (1, 1), (0, 1)))
    return K


# =================================================================== 6. crowd barrier

def crowd_barrier():
    K = Kit("crowd_barrier")
    hw = 1.0
    # foot plate on the front (arena) side
    K.box((0, 0.008, 0.28), (2 * hw - 0.01, 0.016, 0.62), "galv_steel", bevel=0.004)
    # tread-plate studs on the foot plate
    for x in (-0.6, 0.0, 0.6):
        K.box((x, 0.02, 0.35), (0.3, 0.008, 0.4), "galv_steel", bevel=0.0)
    # sloped front plate
    lo = V((0, 0.06, 0.5))
    hi = V((0, 1.12, 0.03))
    d = (hi - lo).normalized()
    nrm = V((0, d.z, -d.y)) * -1        # outward (toward +Z / up)
    if nrm.z < 0:
        nrm = -nrm
    plate_c = (lo + hi) * 0.5
    ang = math.degrees(math.atan2(hi.z - lo.z, hi.y - lo.y))  # tilt about X
    Rp = rot_x(ang)
    K.box(plate_c, (2 * hw - 0.01, (hi - lo).length, 0.012), "galv_steel", bevel=0.004, rot=Rp)
    # pressed ribs across the plate
    for t in (0.3, 0.65):
        p = lo + (hi - lo) * t + nrm * 0.012
        K.box(p, (2 * hw - 0.1, 0.05, 0.015), "galv_steel", bevel=0.005, rot=Rp)
    # bolts along the plate sides
    for sx in (-1, 1):
        for t in (0.15, 0.85):
            p = lo + (hi - lo) * t + nrm * 0.006
            K.bolt((sx * (hw - 0.06), p.y, p.z), nrm, "galv_steel", r=0.014, h=0.01)
    # top tube
    K.tube((-hw, 1.16, 0.03), (hw, 1.16, 0.03), 0.05, "galv_steel", sides=8)
    # rear A-frames + ground rail
    for x in (-0.75, 0.75):
        K.box_between((x, 1.13, 0.0), (x, 0.04, -0.6), 0.06, 0.06, "galv_steel", bevel=0.006)
        K.box_between((x, 0.03, 0.5), (x, 0.03, -0.62), 0.06, 0.06, "galv_steel", bevel=0.006)
        K.box_between((x, 0.55, -0.3), (x, 0.55, 0.3), 0.04, 0.04, "galv_steel", bevel=0.004)
        K.box((x, 0.012, -0.6), (0.14, 0.024, 0.14), "rubber", bevel=0.004)
    K.box_between((-hw + 0.02, 0.05, -0.6), (hw - 0.02, 0.05, -0.6), 0.05, 0.05, "galv_steel",
                  bevel=0.005)
    # section connectors: hinge lugs + pins at each end of the top tube
    for sx in (-1, 1):
        for dy in (0.0,):
            K.box((sx * (hw - 0.03), 1.16, -0.06), (0.05, 0.08, 0.1), "galv_steel", bevel=0.0)
        K.tube((sx * (hw - 0.03), 1.08, -0.1), (sx * (hw - 0.03), 1.26, -0.1), 0.012, "dark_metal",
               sides=6)
    return K


# =================================================================== 7. entrance gate

GATE_PEDESTALS = [V((-2.0, 0.9, 0.55)), V((2.0, 0.9, 0.55))]


def entrance_gate():
    K = Kit("entrance_gate")
    ow, oh = 1.5, 2.6            # opening half width, height
    fw, fh = 2.6, 3.95            # facade half width, height
    fz0, fz1 = -0.35, 0.0         # facade depth
    td = 4.0                      # tunnel depth behind facade front
    tw = 1.62                     # tunnel outer half width
    # --- facade jambs: container-steel blocks with corrugated faces
    for sx in (-1, 1):
        xa, xb = sx * ow, sx * fw
        xc, xl = (xa + xb) / 2, abs(xb - xa)
        K.box((xc, oh / 2 + 0.3, (fz0 + fz1) / 2 - 0.02), (xl, oh + 0.6, fz1 - fz0 - 0.04),
              "container_paint", bevel=0.012)
        # corrugated face between the hazard edge and the corner post
        u0 = sx * 1.84
        u1 = sx * 2.46
        o = V((min(u0, u1), 0.12, -0.04))
        K.corrugated(o, X, Y, abs(u1 - u0), oh + 0.9, "container_paint", pitch=0.2, depth=0.035,
                     out=Z)
        # corner post with castings
        K.box((sx * (fw - 0.08), fh / 2, -0.16), (0.17, fh - 0.24, 0.36), "container_paint",
              bevel=0.015)
        for y in (0.06, fh - 0.06):
            K.box((sx * (fw - 0.09), y, -0.16), (0.18, 0.12, 0.38), "dark_metal", bevel=0.012)
        # rust streak plates at the foot
        K.box((sx * 2.15, 0.12, -0.01), (0.62, 0.22, 0.06), "rust", bevel=0.01)
    # --- header
    K.box((0, (oh + fh) / 2, -0.19), (2 * fw - 0.3, fh - oh, 0.3), "container_paint", bevel=0.015)
    K.corrugated(V((-ow - 0.3, oh + 0.3, -0.04)), X, Y, 2 * ow + 0.6, 0.02, "container_paint",
                 pitch=0.2, depth=0.02, out=Z)
    K.box((0, fh - 0.05, -0.16), (2 * fw, 0.1, 0.4), "dark_metal", bevel=0.012)
    # --- hazard striped portal edges (U along each strip)
    hz_w = 0.22
    for sx in (-1, 1):
        xc = sx * (ow + 0.08 + hz_w / 2)
        K.hazard_box((xc, (oh + 0.08 + hz_w) / 2, 0.0), (hz_w, oh + 0.08 + hz_w, 0.07), Y)
    K.hazard_box((0, oh + 0.08 + hz_w / 2, 0.0), (2 * (ow + 0.08), hz_w, 0.07), X)
    # hazard reveal skins on the inner jamb faces (seen when looking into the mouth)
    for sx in (-1, 1):
        K.hazard_box((sx * (ow + 0.01), oh / 2, -0.17), (0.02, oh, 0.32), Y, bevel=0.0)
    # --- lamp strip framing the opening (one continuous U, UV U = 0..1 along it)
    sw = 0.08
    sz0, sz1 = 0.0, 0.035
    xi, xo = ow, ow + sw
    yi, yo = oh, oh + sw
    pts_out = [(-xo, 0.0), (-xo, yo), (xo, yo), (xo, 0.0)]
    pts_in = [(-xi, 0.0), (-xi, yi), (xi, yi), (xi, 0.0)]
    # arc lengths along the centre line
    centre = [((a[0] + b[0]) / 2, (a[1] + b[1]) / 2) for a, b in zip(pts_out, pts_in)]
    seg = [0.0]
    for p, q in zip(centre[:-1], centre[1:]):
        seg.append(seg[-1] + math.hypot(q[0] - p[0], q[1] - p[1]))
    total = seg[-1]
    us = [s / total for s in seg]
    for i in range(3):
        a_o, b_o = pts_out[i], pts_out[i + 1]
        a_i, b_i = pts_in[i], pts_in[i + 1]
        ua, ub = us[i], us[i + 1]
        # front face (+Z): CCW seen from the front
        quad = [(a_i[0], a_i[1], sz1), (b_i[0], b_i[1], sz1), (b_o[0], b_o[1], sz1),
                (a_o[0], a_o[1], sz1)]
        uvq = [(ua, 0.0), (ub, 0.0), (ub, 1.0), (ua, 1.0)]
        # orientation check: normal must be +Z
        e1 = V(quad[1]) - V(quad[0])
        e2 = V(quad[2]) - V(quad[0])
        if e1.cross(e2).z < 0:
            quad = list(reversed(quad))
            uvq = list(reversed(uvq))
        K.quad(*quad, "lamp_strip", uvs=uvq)
        # inner edge face (facing into the opening)
        qi = [(a_i[0], a_i[1], sz0), (b_i[0], b_i[1], sz0), (b_i[0], b_i[1], sz1),
              (a_i[0], a_i[1], sz1)]
        uvi = [(ua, 0.0), (ub, 0.0), (ub, 0.2), (ua, 0.2)]
        mid = V(((a_i[0] + b_i[0]) / 2, (a_i[1] + b_i[1]) / 2, 0))
        e1 = V(qi[1]) - V(qi[0])
        e2 = V(qi[2]) - V(qi[0])
        nrm = e1.cross(e2)
        inward = V((0, 0, 0)) - mid
        inward.z = 0
        if i == 1:
            inward = V((0, -1, 0))
        if nrm.dot(inward) < 0:
            qi = list(reversed(qi))
            uvi = list(reversed(uvi))
        K.quad(*qi, "lamp_strip", uvs=uvi)
    # --- sign plate 2.4 x 0.6 above the opening, in a dark frame, UV 0..1
    sy0 = oh + 0.08 + hz_w + 0.2
    sy1 = sy0 + 0.6
    K.box((0, (sy0 + sy1) / 2, 0.0), (2.52, 0.72, 0.06), "dark_metal", bevel=0.012)
    K.quad((-1.2, sy0, 0.032), (1.2, sy0, 0.032), (1.2, sy1, 0.032), (-1.2, sy1, 0.032), "sign",
           uvs=((0, 0), (1, 0), (1, 1), (0, 1)))
    for sx in (-1, 1):
        for y in (sy0 - 0.03, sy1 + 0.03):
            K.bolt((sx * 1.22, y, 0.03), Z, "galv_steel", r=0.016, h=0.01)
    # two gooseneck sign lamps
    for sx in (-1, 1):
        base = V((sx * 0.8, sy1 + 0.12, 0.02))
        K.tube(base, base + V((0, 0.12, 0.25)), 0.018, "dark_metal", sides=6)
        head = base + V((0, 0.12, 0.3))
        K.box(head, (0.22, 0.07, 0.14), "dark_metal", bevel=0.01, rot=rot_x(25))
        K.box(head + V((0, -0.04, 0.0)), (0.18, 0.012, 0.1), "lamp_white", bevel=0.0,
              rot=rot_x(25))
    # --- tunnel behind the facade (container steel), 4.0 m deep to -Z
    tz0, tz1 = fz0, -td
    tl = tz0 - tz1
    tcz = (tz0 + tz1) / 2
    for sx in (-1, 1):
        # outer skin (corrugated, ribs vertical)
        o = V((sx * tw, 0.12, tz0 if sx > 0 else tz1))
        u = -Z if sx > 0 else Z
        K.corrugated(o, u, Y, tl, oh + 0.08, "container_paint", pitch=0.278, depth=0.04,
                     out=V((sx, 0, 0)))
        # inner skin (corrugated, facing into the tunnel)
        o = V((sx * (ow + 0.02), 0.02, tz1 if sx > 0 else tz0))
        u = Z if sx > 0 else -Z
        K.corrugated(o, u, Y, tl, oh - 0.02, "container_paint", pitch=0.278, depth=0.03,
                     out=V((-sx, 0, 0)))
        # bottom and top rails
        K.box((sx * (tw - 0.03), 0.07, tcz), (0.14, 0.14, tl), "container_paint", bevel=0.012)
        K.box((sx * (tw - 0.03), oh + 0.15, tcz), (0.14, 0.14, tl), "container_paint",
              bevel=0.012)
        # rear corner post + castings
        K.box((sx * (tw - 0.07), (oh + 0.22) / 2, tz1 + 0.07), (0.15, oh + 0.22, 0.15),
              "container_paint", bevel=0.012)
        for y in (0.06, oh + 0.16):
            K.box((sx * (tw - 0.07), y, tz1 + 0.07), (0.17, 0.12, 0.17), "dark_metal",
                  bevel=0.01)
    # roof (corrugated, ribs across) + ceiling
    K.corrugated(V((-tw + 0.06, oh + 0.16, tz0)), -Z, X, tl, 2 * tw - 0.12, "container_paint",
                 pitch=0.45, depth=0.025, crest=0.5, flank=0.1, out=Y)
    K.quad((-ow, oh, tz0), (ow, oh, tz0), (ow, oh, tz1), (-ow, oh, tz1), "dark_metal")
    # floor plate + back wall (dark)
    K.box((0, 0.015, tcz), (2 * ow + 0.1, 0.03, tl), "dark_metal", bevel=0.006)
    K.box((0, (oh + 0.22) / 2, tz1 + 0.02), (2 * tw - 0.1, oh + 0.22, 0.04), "dark_metal",
          bevel=0.01)
    # interior bulkhead lamps
    for z in (-1.6, -3.2):
        K.box((0, oh - 0.04, z), (0.34, 0.08, 0.16), "dark_metal", bevel=0.012)
        K.box((0, oh - 0.085, z), (0.28, 0.012, 0.11), "lamp_white", bevel=0.0)
    # --- roll-up shutter, half raised, just inside the mouth
    shz = -0.55
    K.tube((-ow + 0.02, oh - 0.2, shz - 0.05), (ow - 0.02, oh - 0.2, shz - 0.05), 0.19,
           "dark_metal", sides=12)
    K.box((0, oh - 0.2, shz - 0.05), (2 * ow - 0.02, 0.36, 0.2), "dark_metal", bevel=0.012,
          rot=None)
    for sx in (-1, 1):
        K.box((sx * (ow - 0.05), (oh - 0.2) / 2, shz), (0.1, oh - 0.2, 0.12), "dark_metal",
              bevel=0.01)
    curtain_bottom = 1.3
    K.corrugated(V((-ow + 0.08, oh - 0.38, shz + 0.02)), -Y, X, oh - 0.38 - curtain_bottom,
                 2 * ow - 0.16, "dark_metal", pitch=0.09, depth=0.02, crest=0.4, flank=0.2,
                 out=Z)
    K.box((0, (curtain_bottom + oh - 0.38) / 2, shz), (2 * ow - 0.16, oh - 0.38 - curtain_bottom,
                                                       0.01), "dark_metal", bevel=0.0)
    K.box((0, curtain_bottom - 0.03, shz + 0.02), (2 * ow - 0.14, 0.07, 0.07), "hazard_paint",
          bevel=0.01)
    K.box((0, curtain_bottom - 0.08, shz + 0.02), (2 * ow - 0.14, 0.04, 0.08), "rubber",
          bevel=0.006)
    # --- pyro pedestals either side of the mouth
    for p in GATE_PEDESTALS:
        K.box((p.x, 0.43, p.z), (0.56, 0.86, 0.56), "dark_metal", bevel=0.02)
        K.hazard_box((p.x, 0.72, p.z), (0.58, 0.1, 0.58), X, bevel=0.006)
        K.box((p.x, 0.885, p.z), (0.62, 0.03, 0.62), "galv_steel", bevel=0.006)
        for sx in (-1, 1):
            for sz in (-1, 1):
                K.bolt((p.x + sx * 0.25, 0.9, p.z + sz * 0.25), Y, "galv_steel", r=0.016, h=0.008)
        # cable into the pedestal back
        K.polyline_tube([V((p.x, 0.25, p.z - 0.28)), V((p.x, 0.04, p.z - 0.45)),
                         V((p.x * 0.9, 0.04, -0.1))], 0.018, "rubber", sides=5)
        K.empty("pyro_pedestal_" + ("l" if p.x < 0 else "r"), p)
    return K


# =================================================================== main

BUILDERS = [
    ("stand_scaffold_bay", lambda: stand_scaffold(False)),
    ("stand_scaffold_endcap", lambda: stand_scaffold(True)),
    ("container_20ft", lambda: container(False)),
    ("container_20ft_open", lambda: container(True)),
    ("flood_tower", flood_tower),
    ("stair_scaffold", stair_scaffold),
    ("fence_panel", fence_panel),
    ("crowd_barrier", crowd_barrier),
    ("entrance_gate", entrance_gate),
]

BUDGET = {"stand_scaffold_bay": 3500, "stand_scaffold_endcap": 3500, "container_20ft": 2500,
          "container_20ft_open": 2500, "flood_tower": 3000, "stair_scaffold": 2000,
          "fence_panel": 400, "crowd_barrier": 800, "entrance_gate": 4000}


def _args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    sheet = "--no-sheet" not in argv
    if "--only" in argv:
        only = set(argv[argv.index("--only") + 1].split(","))
    return only, sheet


def main():
    only, sheet = _args()
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--sheet-only" in argv:
        render_sheet()
        return
    rows = []
    for name, fn in BUILDERS:
        if only and name not in only:
            continue
        kit = fn()
        path, tris = export_kit(kit, OUT)
        info = glb_info(path)
        rows.append((name, info))
        lo, hi = info["min"], info["max"]
        flag = "" if info["tris"] <= BUDGET[name] else "  OVER BUDGET"
        print("KIT %-22s tris %5d / %5d  x[%6.3f %6.3f] y[%6.3f %6.3f] z[%6.3f %6.3f]  "
              "size %.3f x %.3f x %.3f  mats %s%s" % (
                  name, info["tris"], BUDGET[name], lo[0], hi[0], lo[1], hi[1], lo[2], hi[2],
                  hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2], ",".join(info["materials"]), flag))
        for nn, t in info["nodes"].items():
            if nn != name:
                print("     node %-20s at (%.3f, %.3f, %.3f)" % (nn, t[0], t[1], t[2]))
    if sheet and not only:
        render_sheet()


# =================================================================== contact sheet

SHEET_LAYOUT = [
    # name, godot position (x, z), label, label position (x, z)
    ("stand", (-11.0, -2.2), "stand_scaffold_bay x3 + endcap", (-12.2, 0.9)),
    ("container_20ft", (-1.4, -1.8), "container_20ft", (-4.2, 0.6)),
    ("container_20ft_open", (6.6, -1.8), "container_20ft_open", (3.8, 0.6)),
    ("flood_tower", (13.0, -2.4), "flood_tower", (11.6, 0.6)),
    ("entrance_gate", (-9.4, 10.2), "entrance_gate", (-11.2, 12.2)),
    ("stair_scaffold", (-1.4, 9.6), "stair_scaffold", (-3.2, 12.2)),
    ("fence_panel", (4.4, 10.2), "fence_panel", (3.2, 12.2)),
    ("crowd_barrier", (9.2, 10.2), "crowd_barrier", (8.0, 12.2)),
]


def _preview_materials():
    """Give the UV-driven slots a stand-in pattern so the sheet proves their
    UVs: chevrons on hazard_paint, a left-to-right gradient + border on the
    sign, a diagonal mesh on grating, a chase gradient on lamp_strip."""
    for m in bpy.data.materials:
        base = m.name.split(".")[0]
        if base not in ("hazard_paint", "sign", "grating", "lamp_strip"):
            continue
        nt = m.node_tree
        bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
        uv = nt.nodes.new("ShaderNodeUVMap")
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(uv.outputs["UV"], sep.inputs[0])
        if base == "hazard_paint":
            add = nt.nodes.new("ShaderNodeMath"); add.operation = 'ADD'
            nt.links.new(sep.outputs[0], add.inputs[0]); nt.links.new(sep.outputs[1], add.inputs[1])
            fr = nt.nodes.new("ShaderNodeMath"); fr.operation = 'FRACT'
            nt.links.new(add.outputs[0], fr.inputs[0])
            gt = nt.nodes.new("ShaderNodeMath"); gt.operation = 'GREATER_THAN'
            gt.inputs[1].default_value = 0.5
            nt.links.new(fr.outputs[0], gt.inputs[0])
            mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = 'RGBA'
            mix.inputs["A"].default_value = (0.9, 0.62, 0.02, 1)
            mix.inputs["B"].default_value = (0.02, 0.02, 0.02, 1)
            nt.links.new(gt.outputs[0], mix.inputs["Factor"])
            nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
        elif base == "sign":
            mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = 'RGBA'
            mix.inputs["A"].default_value = (0.8, 0.1, 0.05, 1)
            mix.inputs["B"].default_value = (0.05, 0.25, 0.9, 1)
            nt.links.new(sep.outputs[0], mix.inputs["Factor"])
            nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
            nt.links.new(mix.outputs["Result"], bsdf.inputs["Emission Color"])
            bsdf.inputs["Emission Strength"].default_value = 0.6
        elif base == "grating":
            mp = nt.nodes.new("ShaderNodeMapping")
            mp.inputs["Rotation"].default_value[2] = math.radians(45)
            mp.inputs["Scale"].default_value = (30, 30, 1)
            nt.links.new(uv.outputs["UV"], mp.inputs[0])
            ck = nt.nodes.new("ShaderNodeTexBrick")
            ck.inputs["Mortar Size"].default_value = 0.08
            ck.offset = 0.0
            nt.links.new(mp.outputs[0], ck.inputs["Vector"])
            inv = nt.nodes.new("ShaderNodeMath"); inv.operation = 'SUBTRACT'
            inv.inputs[0].default_value = 1.0
            nt.links.new(ck.outputs["Fac"], inv.inputs[1])
            nt.links.new(ck.outputs["Fac"], bsdf.inputs["Alpha"])
            m.surface_render_method = 'DITHERED'
        elif base == "lamp_strip":
            ramp = nt.nodes.new("ShaderNodeValToRGB")
            ramp.color_ramp.elements[0].color = (0.0, 0.3, 1.0, 1)
            ramp.color_ramp.elements[1].color = (1.0, 0.2, 0.9, 1)
            nt.links.new(sep.outputs[0], ramp.inputs[0])
            nt.links.new(ramp.outputs[0], bsdf.inputs["Emission Color"])
            bsdf.inputs["Emission Strength"].default_value = 4.0


def _import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def _place(objs, x, z, yaw=0.0):
    """Move imported objects to Godot (x, 0, z); Blender = (x, -z, 0)."""
    for o in objs:
        if o.parent is None:
            o.location = (o.location.x + x, o.location.y - z, o.location.z)
            o.rotation_euler.z += math.radians(yaw)


def render_sheet():
    kitlib.reset_scene()
    scn = bpy.context.scene
    # pieces
    for name, (x, z), label, lp in SHEET_LAYOUT:
        if name == "stand":
            for i in range(3):
                _place(_import_glb(os.path.join(OUT, "stand_scaffold_bay.glb")), x + 2.0 * i, z)
            _place(_import_glb(os.path.join(OUT, "stand_scaffold_endcap.glb")), x + 2.0 * 2, z)
        else:
            _place(_import_glb(os.path.join(OUT, name + ".glb")), x, z)
    for o in list(bpy.data.objects):
        if o.type == 'EMPTY':
            bpy.data.objects.remove(o)
    _preview_materials()
    # labels, flat on the ground in front of each piece
    lm = bpy.data.materials.new("label")
    lm.use_nodes = True
    b = lm.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.85, 0.85, 0.85, 1)
    b.inputs["Emission Color"].default_value = (0.85, 0.85, 0.85, 1)
    b.inputs["Emission Strength"].default_value = 0.8
    for name, (x, z), label, (lx, lz) in SHEET_LAYOUT:
        bpy.ops.object.text_add(location=(lx, -lz, 0.01))
        t = bpy.context.object
        t.data.body = label
        t.data.size = 0.5
        t.data.materials.append(lm)
    # ground
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, 0))
    g = bpy.context.object
    gm = bpy.data.materials.new("ground")
    gm.use_nodes = True
    gb = gm.node_tree.nodes["Principled BSDF"]
    gb.inputs["Base Color"].default_value = (0.035, 0.035, 0.038, 1)
    gb.inputs["Roughness"].default_value = 0.8
    g.data.materials.append(gm)
    # world
    world = bpy.data.worlds.new("w")
    scn.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.16, 0.165, 0.175, 1)
    bg.inputs["Strength"].default_value = 0.35
    # lights: key area + sun fill
    bpy.ops.object.light_add(type='SUN', rotation=(math.radians(50), math.radians(-10),
                                                     math.radians(-35)))
    sun = bpy.context.object
    sun.data.energy = 2.2
    sun.data.angle = math.radians(12)
    bpy.ops.object.light_add(type='AREA', location=(-6, -18, 22))
    a = bpy.context.object
    a.data.energy = 6000
    a.data.size = 18
    a.rotation_euler = (math.radians(40), 0, math.radians(-15))
    # camera: 3/4 from the front (-Y in Blender) and above
    bpy.ops.object.camera_add()
    cam = bpy.context.object
    scn.camera = cam
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = 34.5
    target = V((0.8, -4.2, 3.2))
    direction = V((0.42, -1.0, 0.72)).normalized()
    cam.location = target + direction * 60
    cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
    cam.data.clip_end = 200
    scn.render.resolution_x = 1920
    scn.render.resolution_y = 1080
    scn.render.film_transparent = False
    try:
        scn.render.engine = 'BLENDER_EEVEE_NEXT'
    except TypeError:
        scn.render.engine = 'BLENDER_EEVEE'
    ee = scn.eevee
    for attr, val in (("taa_render_samples", 64), ("use_shadows", True),
                      ("use_raytracing", True)):
        if hasattr(ee, attr):
            setattr(ee, attr, val)
    scn.view_settings.view_transform = 'AgX'
    scn.view_settings.look = 'AgX - Medium High Contrast'
    os.makedirs(os.path.dirname(SHEET), exist_ok=True)
    scn.render.filepath = SHEET
    bpy.ops.render.render(write_still=True)
    print("SHEET", SHEET)


if __name__ == "__main__":
    main()
