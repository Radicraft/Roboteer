"""Roboteer arena kit: the CROWD CARD ATLAS.

Run (regenerates every output):

    Blender -b --python Tools/blender/arena_kit/crowd_cards.py

Optional arguments after ``--``:

    --variants 0,3,7   only re-render these person variants (others are
                       re-used from the previous run's cell cache)
    --frames 0,2       only re-render these frames
    --samples 48       Cycles samples per cell (default 48)
    --no-crowd         skip the crowd-test preview render
    --crowd-only       only re-render the crowd-test preview
    --sheet            also write a 2x debug sheet of the rendered cells
                       to the cell cache folder

What it builds
--------------
16 procedural people (metaball bodies, one metaball family per material so
clothes, skin, hair and hats each blend smoothly inside themselves), posed
by a small two-bone IK rig written here (no armature needed: every joint
is solved in Python, then the soft body is laid over the joints).  Each
person is rendered in four frames with an ORTHOGRAPHIC camera 40 degrees
above horizontal, neutral soft light, transparent film, 2x supersampled.

Outputs
-------
Arena/arena/kit/crowd/crowd_atlas.png       2048x1024 RGBA, straight alpha,
                                            colour dilated 8 px (then the
                                            cell's mean colour) into the
                                            transparent area
Arena/arena/kit/crowd/crowd_atlas_emit.png  same layout, white = phone
                                            screen glow (CHEER row only)
Arena/arena/kit/crowd/crowd_atlas.json      layout description
docs/aaa/img/wave-a/kit/crowd-atlas-preview.png
docs/aaa/img/wave-a/kit/crowd-atlas-crowd-test.png

Layout: 16 columns (variant c) x 4 rows (frame r: idle, bob, cheer,
flinch) of 128x256 cells.  120 px per metre everywhere, so the cell is
1.0667 m wide and 2.1333 m tall in the camera plane.  The feet contact
point sits at pixel (64, 234) of each cell (x from the left, y from the
top), i.e. 22 px = 0.1833 m above the bottom edge of the card (the toes
of the shoes project below the contact point from this camera angle).
"""

import json
import math
import os
import random
import struct
import sys
import tempfile
import time
import zlib

import bpy
import numpy as np
from mathutils import Euler, Matrix, Quaternion, Vector

# ----------------------------------------------------------------- paths

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT_DIR = os.path.join(REPO, "Arena", "arena", "kit", "crowd")
PREV_DIR = os.path.join(REPO, "docs", "aaa", "img", "wave-a", "kit")
CACHE_DIR = os.path.join(tempfile.gettempdir(), "roboteer_crowd_cells")

# ---------------------------------------------------------------- layout

COLS, ROWS = 16, 4
CELL_W, CELL_H = 128, 256
SS = 2                                  # supersample factor
PX_PER_M = 120.0
WORLD_H = CELL_H / PX_PER_M             # 2.1333 m
WORLD_W = CELL_W / PX_PER_M             # 1.0667 m
ANCHOR_PX = (64, 234)                   # feet contact point in the cell
CAM_ELEV = math.radians(40.0)
FRAMES = ["idle", "bob", "cheer", "flinch"]
DILATE_PX = 8

# ------------------------------------------------------------- arguments


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"variants": None, "frames": None, "samples": 48,
            "crowd": True, "sheet": False}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--variants":
            opts["variants"] = [int(x) for x in argv[i + 1].split(",")]
            i += 1
        elif a == "--frames":
            opts["frames"] = [int(x) for x in argv[i + 1].split(",")]
            i += 1
        elif a == "--samples":
            opts["samples"] = int(argv[i + 1])
            i += 1
        elif a == "--no-crowd":
            opts["crowd"] = False
        elif a == "--crowd-only":
            opts["crowd_only"] = True
        elif a == "--sheet":
            opts["sheet"] = True
        i += 1
    return opts


# ------------------------------------------------------ colour utilities


def lin(c):
    """sRGB triple (0..1) -> linear, for Principled base colours."""
    def f(x):
        return x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4
    return (f(c[0]), f(c[1]), f(c[2]), 1.0)


SKIN = {
    "pale":   (0.93, 0.79, 0.70),
    "light":  (0.88, 0.70, 0.58),
    "lmed":   (0.80, 0.61, 0.47),
    "olive":  (0.72, 0.55, 0.40),
    "tan":    (0.63, 0.45, 0.32),
    "brown":  (0.50, 0.34, 0.23),
    "dark":   (0.37, 0.24, 0.17),
    "deep":   (0.26, 0.17, 0.12),
}

C = {
    "charcoal": (0.20, 0.20, 0.22), "navy": (0.13, 0.17, 0.29),
    "olive": (0.33, 0.35, 0.22), "burgundy": (0.42, 0.13, 0.16),
    "marl": (0.52, 0.52, 0.53), "denim": (0.23, 0.31, 0.46),
    "darkdenim": (0.13, 0.17, 0.27), "black": (0.07, 0.07, 0.08),
    "khaki": (0.60, 0.53, 0.39), "white": (0.86, 0.86, 0.84),
    "forest": (0.16, 0.29, 0.20), "mustard": (0.72, 0.55, 0.18),
    "rust": (0.62, 0.30, 0.15), "hivis": (0.84, 0.95, 0.12),
    "red": (0.78, 0.12, 0.10), "orange": (0.95, 0.45, 0.08),
    "teal": (0.10, 0.47, 0.52), "royal": (0.16, 0.30, 0.72),
    "stone": (0.72, 0.70, 0.66), "brownleather": (0.30, 0.19, 0.12),
    "slate": (0.34, 0.38, 0.43), "cream": (0.83, 0.80, 0.72),
    "plum": (0.30, 0.17, 0.30),
}

HAIRC = {
    "black": (0.05, 0.04, 0.04), "dark": (0.13, 0.09, 0.06),
    "brown": (0.28, 0.18, 0.10), "blonde": (0.72, 0.58, 0.36),
    "ginger": (0.58, 0.28, 0.12), "grey": (0.62, 0.61, 0.60),
    "salt": (0.40, 0.39, 0.38),
}

# ----------------------------------------------------------- the people
#
# h: height (m).  shw: shoulder width, g: girth, belly, hipw: hip width,
# fem: adds a chest.  top: tee | longtee | hoodie | hoodup | jacket |
# jacket_open | vest.  hair: short | buzz | curly | long | pony | bob |
# none.  hat: cap | beanie | None.  poses: idle, bob, cheer, flinch.

VARIANTS = [
    dict(name="hoodie_grey", h=1.80, shw=1.0, g=1.0, belly=0.0, hipw=1.0,
         fem=False, skin="light", hair="short", hairc="brown", beard=False,
         hat=None, top="hoodie", topc="marl", pants="darkdenim",
         shoes="white", scarf=None, phone=False, yaw=6,
         poses=["pockets", "clap", "v_up", "hands_head"]),
    dict(name="cap_tee", h=1.76, shw=0.97, g=0.92, belly=0.0, hipw=0.95,
         fem=False, skin="brown", hair="buzz", hairc="black", beard=False,
         hat="cap", hatc="black", top="tee", topc="navy", pants="khaki",
         shoes="charcoal", scarf=None, phone=True, yaw=-8,
         poses=["relaxed", "clap", "phone", "cover_mouth"]),
    dict(name="jacket_woman", h=1.66, shw=0.9, g=0.9, belly=0.0, hipw=1.08,
         fem=True, skin="pale", hair="long", hairc="blonde", beard=False,
         hat=None, top="jacket_open", topc="burgundy", innerc="white",
         pants="black", shoes="black", scarf=None, phone=True, yaw=10,
         poses=["crossed", "clap_high", "phone", "cover_mouth"]),
    dict(name="heavy_beard", h=1.82, shw=1.08, g=1.22, belly=1.0, hipw=1.1,
         fem=False, skin="tan", hair="none", hairc="dark", beard=True,
         hat=None, top="tee", topc="black", pants="denim", shoes="charcoal",
         scarf="orange", phone=False, yaw=-4,
         poses=["crossed", "fists", "fist_pump", "hands_head"]),
    dict(name="hivis", h=1.78, shw=1.02, g=1.02, belly=0.2, hipw=1.0,
         fem=False, skin="dark", hair="buzz", hairc="black", beard=False,
         hat=None, top="vest", topc="hivis", innerc="charcoal",
         pants="charcoal", shoes="brownleather", scarf=None, phone=False,
         yaw=4, poses=["hips", "clap", "v_up", "recoil"]),
    dict(name="beanie_woman", h=1.63, shw=0.88, g=0.9, belly=0.0, hipw=1.06,
         fem=True, skin="deep", hair="bob", hairc="black", beard=False,
         hat="beanie", hatc="mustard", top="jacket_open", topc="olive",
         innerc="black", pants="denim", shoes="white", scarf=None,
         phone=False, yaw=-10,
         poses=["pockets", "clap", "straight_up", "cheeks"]),
    dict(name="teen_hoodup", h=1.58, shw=0.9, g=0.88, belly=0.0, hipw=0.95,
         fem=False, skin="lmed", hair="short", hairc="dark", beard=False,
         hat=None, top="hoodup", topc="royal", pants="black",
         shoes="white", scarf=None, phone=True, yaw=8,
         poses=["relaxed", "fists", "phone", "recoil"]),
    dict(name="older_man", h=1.74, shw=1.0, g=1.12, belly=0.7, hipw=1.05,
         fem=False, skin="pale", hair="short", hairc="grey", beard=True,
         hat=None, top="jacket_open", topc="navy", innerc="cream",
         pants="khaki", shoes="brownleather", scarf="royal", phone=False,
         yaw=-6, poses=["crossed", "clap", "fist_pump", "cover_mouth"]),
    dict(name="pony_woman", h=1.70, shw=0.92, g=0.94, belly=0.0, hipw=1.08,
         fem=True, skin="olive", hair="pony", hairc="dark", beard=False,
         hat=None, top="tee", topc="teal", pants="slate", shoes="white",
         scarf=None, phone=False, yaw=5,
         poses=["hips", "clap_high", "v_up", "hands_head"]),
    dict(name="hood_black", h=1.84, shw=1.04, g=1.0, belly=0.0, hipw=1.0,
         fem=False, skin="brown", hair="short", hairc="black", beard=True,
         hat=None, top="hoodup", topc="black", pants="marl", shoes="black",
         scarf=None, phone=True, yaw=-5,
         poses=["pockets", "clap", "phone", "recoil"]),
    dict(name="tall_rust", h=1.90, shw=1.0, g=0.9, belly=0.0, hipw=0.96,
         fem=False, skin="tan", hair="curly", hairc="black", beard=False,
         hat=None, top="tee", topc="rust", pants="black", shoes="white",
         scarf=None, phone=False, yaw=7,
         poses=["relaxed", "clap", "straight_up", "hands_head"]),
    dict(name="shorts_cap", h=1.77, shw=1.0, g=1.0, belly=0.1, hipw=1.0,
         fem=False, skin="light", hair="short", hairc="brown", beard=False,
         hat="cap", hatc="red", top="tee", topc="white", pants="khaki",
         shorts=True, shoes="charcoal", scarf=None, phone=False, yaw=-9,
         poses=["relaxed", "fists", "v_up", "cheeks"]),
    dict(name="red_jacket", h=1.68, shw=0.9, g=0.92, belly=0.0, hipw=1.07,
         fem=True, skin="dark", hair="long", hairc="black", beard=False,
         hat=None, top="jacket", topc="red", pants="black", shoes="black",
         scarf=None, phone=True, yaw=6,
         poses=["crossed", "clap", "phone", "cover_mouth"]),
    dict(name="heavy_hoodie", h=1.75, shw=1.06, g=1.25, belly=1.0,
         hipw=1.12, fem=False, skin="lmed", hair="short", hairc="ginger",
         beard=True, hat="beanie", hatc="black", top="hoodie",
         topc="forest", pants="denim", shoes="charcoal", scarf=None,
         phone=False, yaw=-3,
         poses=["pockets", "fists", "fist_pump", "hands_head"]),
    dict(name="scarf_tee", h=1.72, shw=0.98, g=0.96, belly=0.0, hipw=1.0,
         fem=False, skin="olive", hair="short", hairc="dark", beard=False,
         hat=None, top="longtee", topc="charcoal", pants="darkdenim",
         shoes="white", scarf="royal", phone=False, yaw=9,
         poses=["relaxed", "clap", "v_up", "recoil"]),
    dict(name="short_older_woman", h=1.56, shw=0.86, g=1.02, belly=0.4,
         hipw=1.12, fem=True, skin="light", hair="bob", hairc="salt",
         beard=False, hat=None, top="jacket", topc="mustard",
         pants="charcoal", shoes="black", scarf="orange", phone=True, yaw=-7,
         poses=["crossed", "clap_high", "phone", "cheeks"]),
]

assert len(VARIANTS) == COLS

# ---------------------------------------------------------------- poses
#
# Arm targets are WRIST positions in the torso frame, in units of body
# height H, relative to the hip-joint centre: (outward, back(+)/front(-),
# up).  "outward" is mirrored per side.  pole = elbow hint direction in
# the same frame.  hand = hand direction (None = continue the forearm),
# shape = open | fist | pocket | phone.

A = dict  # brevity


def arm(w, pole, hand=None, shape="open", palm=None):
    return A(w=w, pole=pole, hand=hand, shape=shape, palm=palm)


RELAXED = arm((0.128, 0.0, -0.015), (0.35, 1.0, 0.0))

POSES = {
    # ---------------------------------------------------------- idle
    "relaxed": A(lean=0.0, crouch=0.0, shift=0.012, head=(-12, 0, 4),
                 R=RELAXED, L=arm((0.126, 0.01, -0.005), (0.35, 1.0, 0.0))),
    "pockets": A(lean=-2, crouch=0.0, shift=-0.01, head=(-14, 0, -4),
                 R=arm((0.098, -0.035, 0.03), (1.0, 0.8, 0.0), shape="pocket"),
                 L=arm((0.098, -0.035, 0.03), (1.0, 0.8, 0.0), shape="pocket")),
    "crossed": A(lean=-3, crouch=0.0, shift=0.012, head=(-10, 0, 3),
                 R=arm((-0.07, -0.105, 0.205), (0.3, 0.1, -1.0),
                       hand=(-1.0, 0.25, 0.25), shape="fist"),
                 L=arm((-0.075, -0.085, 0.225), (0.3, 0.3, -1.0),
                       hand=(-1.0, 0.4, 0.1), shape="fist")),
    "hips": A(lean=-2, crouch=0.0, shift=0.018, head=(-10, 0, -5),
              R=arm((0.118, -0.01, 0.075), (1.0, 0.35, 0.0),
                    hand=(-0.55, -0.35, -0.6)),
              L=arm((0.118, -0.01, 0.075), (1.0, 0.35, 0.0),
                    hand=(-0.55, -0.35, -0.6))),
    # ----------------------------------------------------------- bob
    "clap": A(lean=4, crouch=0.028, shift=-0.016, head=(-8, 0, -3),
              R=arm((0.018, -0.15, 0.2), (0.7, 0.2, -1.0),
                    hand=(-0.25, -0.45, 1.0), palm=(-1, 0, 0)),
              L=arm((0.018, -0.15, 0.205), (0.7, 0.2, -1.0),
                    hand=(-0.25, -0.45, 1.0), palm=(-1, 0, 0))),
    "clap_high": A(lean=0, crouch=0.024, shift=0.016, head=(-2, 0, 3),
                   R=arm((0.02, -0.14, 0.33), (0.8, 0.3, -1.0),
                         hand=(-0.2, -0.2, 1.0), palm=(-1, 0, 0)),
                   L=arm((0.02, -0.14, 0.335), (0.8, 0.3, -1.0),
                         hand=(-0.2, -0.2, 1.0), palm=(-1, 0, 0))),
    "fists": A(lean=5, crouch=0.035, shift=0.018, head=(-6, 0, 5),
               R=arm((0.075, -0.13, 0.19), (0.6, 0.4, -1.0),
                     hand=(-0.2, -0.6, 0.6), shape="fist"),
               L=arm((0.08, -0.12, 0.16), (0.6, 0.4, -1.0),
                     hand=(-0.2, -0.6, 0.6), shape="fist")),
    # --------------------------------------------------------- cheer
    "v_up": A(lean=-6, crouch=0.0, shift=0.0, head=(8, 0, 0),
              R=arm((0.2, -0.05, 0.63), (1.0, 0.3, -0.3), shape="fist"),
              L=arm((0.2, -0.05, 0.63), (1.0, 0.3, -0.3), shape="fist")),
    "straight_up": A(lean=-5, crouch=0.0, shift=0.01, head=(10, 0, 0),
                     R=arm((0.14, -0.04, 0.64), (1.0, 0.3, -0.2),
                           palm=(0, -1, 0)),
                     L=arm((0.15, -0.03, 0.64), (1.0, 0.3, -0.2),
                           palm=(0, -1, 0))),
    "fist_pump": A(lean=-4, crouch=0.012, shift=-0.016, head=(6, 0, -4),
                   R=arm((0.13, -0.06, 0.64), (1.0, 0.2, -0.3),
                         shape="fist"),
                   L=arm((0.15, -0.12, 0.13), (0.5, 0.6, -1.0),
                         hand=(0.0, -0.5, 1.0), shape="fist")),
    "phone": A(lean=-3, crouch=0.0, shift=0.012, head=(12, 0, 0),
               R=arm((0.1, -0.13, 0.575), (1.0, 0.2, -0.6),
                     hand=(-0.1, 0.25, 1.0), shape="phone",
                     palm=(0, 1, 0)),
               L=arm((0.19, -0.06, 0.6), (1.0, 0.3, -0.3), shape="fist")),
    # -------------------------------------------------------- flinch
    "hands_head": A(lean=-9, crouch=0.01, shift=0.0, head=(8, 0, 0),
                    R=arm((0.078, 0.02, 0.435), (1.0, -0.2, 0.2),
                          hand=(-0.8, 0.45, 0.35), palm=(-0.3, 0, -1)),
                    L=arm((0.078, 0.02, 0.435), (1.0, -0.2, 0.2),
                          hand=(-0.8, 0.45, 0.35), palm=(-0.3, 0, -1))),
    "cover_mouth": A(lean=-8, crouch=0.01, shift=0.012, head=(4, 0, 6),
                     R=arm((0.018, -0.105, 0.33), (0.8, 0.0, -1.0),
                           hand=(-0.25, -0.1, 1.0), palm=(0, 1, 0)),
                     L=arm((-0.03, -0.12, 0.13), (0.5, 0.2, -1.0),
                           hand=(-1.0, 0.1, 0.2), shape="fist")),
    "recoil": A(lean=-11, crouch=0.012, shift=-0.012, head=(4, 0, -5),
                R=arm((0.1, -0.16, 0.32), (0.8, 0.2, -1.0),
                      hand=(0.05, -0.1, 1.0), palm=(0, 1, 0)),
                L=arm((0.12, -0.15, 0.29), (0.8, 0.2, -1.0),
                      hand=(0.1, -0.1, 1.0), palm=(0, 1, 0))),
    "cheeks": A(lean=-7, crouch=0.01, shift=0.01, head=(5, 0, 0),
                R=arm((0.06, -0.075, 0.345), (0.9, 0.1, -1.0),
                      hand=(-0.3, 0.05, 1.0), palm=(-1, 0, 0)),
                L=arm((0.06, -0.075, 0.345), (0.9, 0.1, -1.0),
                      hand=(-0.3, 0.05, 1.0), palm=(-1, 0, 0))),
}

# ------------------------------------------------------ metaball helpers

FIELD_S = 2.0          # element stiffness
THRESH = 0.6           # metaball threshold
K_BALL = math.sqrt(1.0 - (THRESH / FIELD_S) ** (1.0 / 3.0))   # 0.575
CHAIN_SP = 0.3         # ball spacing along a chain, as a fraction of R


def _chain_factor(sp):
    """Effective radius of an infinite chain of R=1 balls spaced sp."""
    def field(d):
        s = 0.0
        for i in range(-12, 13):
            q = 1.0 - (d * d + (i * sp) ** 2)
            if q > 0:
                s += FIELD_S * q ** 3
        return s
    lo, hi = 0.0, 1.0
    for _ in range(50):
        mid = 0.5 * (lo + hi)
        if field(mid) > THRESH:
            lo = mid
        else:
            hi = mid
    return lo


K_CHAIN = _chain_factor(CHAIN_SP)


def frame_quat(z, y_hint):
    z = Vector(z).normalized()
    y_hint = Vector(y_hint)
    x = y_hint.cross(z)
    if x.length < 1e-5:
        x = Vector((1, 0, 0)).cross(z)
        if x.length < 1e-5:
            x = Vector((0, 1, 0)).cross(z)
    x.normalize()
    y = z.cross(x).normalized()
    m = Matrix((x, y, z)).transposed()
    return m.to_quaternion()


class Body:
    """Collects metaball elements per family, then makes the objects."""

    def __init__(self, res):
        self.fams = {}
        self.res = res

    def _mb(self, fam):
        if fam not in self.fams:
            mb = bpy.data.metaballs.new("CC" + fam)
            mb.resolution = self.res
            mb.render_resolution = self.res
            mb.threshold = THRESH
            self.fams[fam] = mb
        return self.fams[fam]

    def ball(self, fam, p, r, neg=False):
        e = self._mb(fam).elements.new(type='BALL')
        e.co = Vector(p)
        e.radius = r / K_BALL
        e.stiffness = FIELD_S
        e.use_negative = neg

    def ell(self, fam, p, semi, q=None, neg=False):
        m = max(semi)
        e = self._mb(fam).elements.new(type='ELLIPSOID')
        e.co = Vector(p)
        e.radius = m / K_BALL
        e.size_x = semi[0] / m
        e.size_y = semi[1] / m
        e.size_z = semi[2] / m
        e.stiffness = FIELD_S
        e.use_negative = neg
        if q is not None:
            e.rotation = q

    def chain(self, fam, a, b, ra, rb, neg=False):
        a, b = Vector(a), Vector(b)
        L = (b - a).length
        rmin = min(ra, rb)
        step = CHAIN_SP * rmin / K_CHAIN
        n = max(2, int(math.ceil(L / max(step, 1e-4))) + 1)
        for i in range(n):
            t = i / (n - 1)
            r = ra + (rb - ra) * t
            e = self._mb(fam).elements.new(type='BALL')
            e.co = a.lerp(b, t)
            e.radius = r / K_CHAIN
            e.stiffness = FIELD_S
            e.use_negative = neg

    def build(self, mats, parent):
        objs = []
        for fam, mb in self.fams.items():
            if fam in mats:
                mb.materials.append(mats[fam])
            ob = bpy.data.objects.new("CC" + fam, mb)
            bpy.context.scene.collection.objects.link(ob)
            ob.parent = parent
            objs.append(ob)
        return objs


# -------------------------------------------------------------- the rig


def two_bone(a, t, l1, l2, pole):
    d_vec = t - a
    d = d_vec.length
    d = min(max(d, abs(l1 - l2) + 1e-4), l1 + l2 - 1e-4)
    dirn = d_vec.normalized()
    tt = a + dirn * d
    x = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
    h = math.sqrt(max(l1 * l1 - x * x, 0.0))
    p = Vector(pole)
    pp = p - dirn * p.dot(dirn)
    if pp.length < 1e-6:
        pp = Vector((0, 1, 0)) - dirn * dirn.y
    pp.normalize()
    mid = a + dirn * x + pp * h
    return mid, tt


def solve(v, pose):
    """Joint positions (Blender space, person faces -Y) for one pose."""
    H = v["h"]
    J = {}
    shift = pose["shift"] * H
    stance = 0.058 * H
    ank_z = 0.045 * H
    J["ankle_R"] = Vector((-stance, 0.004 * H, ank_z))
    J["ankle_L"] = Vector((stance, -0.004 * H, ank_z))
    hipx = 0.072 * H * v["hipw"]
    l_th, l_sh = 0.235 * H, 0.24 * H
    reach = (l_th + l_sh) * 0.997
    horiz = max(abs(shift - hipx + stance), abs(shift + hipx - stance))
    hip_z = ank_z + math.sqrt(reach * reach - horiz * horiz)
    hip_z -= pose["crouch"] * H
    P = Vector((shift, 0.0, hip_z))
    J["pelvis"] = P
    lean = math.radians(pose["lean"])
    roll = -pose["shift"] * 1.4
    # lean>0 leans FORWARD (toward camera, -Y).  Rotation about X by +a
    # tips +Z toward -Y, which is forward for a person facing -Y.
    Rt = Euler((lean, roll, 0.0), 'XYZ').to_matrix()
    J["Rt"] = Rt

    def T(x, y, z):
        return P + Rt @ Vector((x * H, y * H, z * H))
    J["T"] = T
    for side, s in (("R", -1.0), ("L", 1.0)):
        hip = P + Vector((s * hipx, 0.0, 0.0))
        J["hip_" + side] = hip
        knee, ank = two_bone(hip, J["ankle_" + side], l_th, l_sh,
                             Vector((s * 0.04, -1.0, 0.0)))
        J["knee_" + side] = knee
        J["ankle_" + side] = ank
    # spine
    J["waist"] = T(0, 0.004, 0.11)
    J["chest"] = T(0, 0.006, 0.22)
    J["neck0"] = T(0, 0.012, 0.305)
    J["neck1"] = T(0, 0.006, 0.345)
    hp, hr, hy = pose["head"]
    Rh = Rt @ Euler((math.radians(-hp), math.radians(hr),
                     math.radians(hy)), 'XYZ').to_matrix()
    J["Rh"] = Rh
    J["head"] = J["neck1"] + Rh @ Vector((0, -0.006 * H, 0.062 * H))

    def HD(x, y, z):
        return J["head"] + Rh @ Vector((x * H, y * H, z * H))
    J["HD"] = HD
    # arms
    l_up, l_fo = 0.172 * H, 0.155 * H
    for side, s in (("R", -1.0), ("L", 1.0)):
        a = pose[side]
        sh = T(s * 0.097 * v["shw"], 0.008, 0.288)
        wx, wy, wz = a["w"]
        # widen targets a touch with girth so arms clear the body
        wx = wx + (v["g"] - 1.0) * 0.05 * (1 if wz < 0.25 else 0.4)
        tgt = T(s * wx, wy, wz)
        px, py, pz = a["pole"]
        pole = Rt @ Vector((s * px, py, pz))
        elbow, wrist = two_bone(sh, tgt, l_up, l_fo, pole)
        J["sh_" + side] = sh
        J["elbow_" + side] = elbow
        J["wrist_" + side] = wrist
        if a["hand"] is not None:
            hx, hy, hz = a["hand"]
            hd = (Rt @ Vector((s * hx, hy, hz))).normalized()
        else:
            hd = (wrist - elbow).normalized()
        J["hand_" + side] = hd
        if a["palm"] is not None:
            px, py, pz = a["palm"]
            palm = Rt @ Vector((s * px, py, pz))
        else:
            palm = Vector((-s, 0.0, 0.0))
        J["palm_" + side] = palm
        J["shape_" + side] = a["shape"]
    return J


# ------------------------------------------------------------ materials

_MAT_CACHE = {}


def make_mat(name, rgb, rough=0.7, sss=0.0, sheen=0.0, noise=0.08,
             stripes=None, emit=0.0):
    key = (name, tuple(rgb), rough, sss, sheen, noise, stripes, emit)
    if key in _MAT_CACHE:
        return _MAT_CACHE[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bs.outputs["BSDF"], out.inputs["Surface"])
    base = lin(rgb)
    bs.inputs["Roughness"].default_value = rough
    if sss > 0:
        bs.inputs["Subsurface Weight"].default_value = sss
        bs.inputs["Subsurface Radius"].default_value = (0.9, 0.35, 0.2)
        bs.inputs["Subsurface Scale"].default_value = 0.01
    if sheen > 0:
        bs.inputs["Sheen Weight"].default_value = sheen
    if emit > 0:
        bs.inputs["Emission Color"].default_value = base
        bs.inputs["Emission Strength"].default_value = emit
    colour_socket = bs.inputs["Base Color"]
    if noise > 0 or stripes:
        tc = nt.nodes.new("ShaderNodeTexCoord")
        nz = nt.nodes.new("ShaderNodeTexNoise")
        nz.inputs["Scale"].default_value = 22.0
        nz.inputs["Detail"].default_value = 3.0
        nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
        mr = nt.nodes.new("ShaderNodeMapRange")
        mr.inputs["From Min"].default_value = 0.3
        mr.inputs["From Max"].default_value = 0.7
        mr.inputs["To Min"].default_value = 1.0 - noise
        mr.inputs["To Max"].default_value = 1.0 + noise * 0.6
        nt.links.new(nz.outputs["Fac"], mr.inputs["Value"])
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = 'RGBA'
        mul.blend_type = 'MULTIPLY'
        mul.inputs["Factor"].default_value = 1.0
        mul.inputs[6].default_value = base
        comb = nt.nodes.new("ShaderNodeCombineColor")
        for i in range(3):
            nt.links.new(mr.outputs["Result"], comb.inputs[i])
        nt.links.new(comb.outputs["Color"], mul.inputs[7])
        col_out = mul.outputs[2]
        if stripes:
            # reflective bands at absolute heights (hi-vis vest)
            sep = nt.nodes.new("ShaderNodeSeparateXYZ")
            nt.links.new(tc.outputs["Object"], sep.inputs["Vector"])
            acc = None
            for (z0, hw) in stripes:
                sub = nt.nodes.new("ShaderNodeMath")
                sub.operation = 'SUBTRACT'
                nt.links.new(sep.outputs["Z"], sub.inputs[0])
                sub.inputs[1].default_value = z0
                ab = nt.nodes.new("ShaderNodeMath")
                ab.operation = 'ABSOLUTE'
                nt.links.new(sub.outputs[0], ab.inputs[0])
                lt = nt.nodes.new("ShaderNodeMath")
                lt.operation = 'LESS_THAN'
                nt.links.new(ab.outputs[0], lt.inputs[0])
                lt.inputs[1].default_value = hw
                if acc is None:
                    acc = lt
                else:
                    mx = nt.nodes.new("ShaderNodeMath")
                    mx.operation = 'MAXIMUM'
                    nt.links.new(acc.outputs[0], mx.inputs[0])
                    nt.links.new(lt.outputs[0], mx.inputs[1])
                    acc = mx
            mix2 = nt.nodes.new("ShaderNodeMix")
            mix2.data_type = 'RGBA'
            nt.links.new(acc.outputs[0], mix2.inputs["Factor"])
            nt.links.new(col_out, mix2.inputs[6])
            mix2.inputs[7].default_value = lin((0.78, 0.8, 0.82))
            col_out = mix2.outputs[2]
        nt.links.new(col_out, colour_socket)
    else:
        colour_socket.default_value = base
    _MAT_CACHE[key] = m
    return m


def black_mat():
    if "CC_black" in bpy.data.materials:
        return bpy.data.materials["CC_black"]
    m = bpy.data.materials.new("CC_black")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (0, 0, 0, 1)
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return m


def screen_mat(strength):
    m = bpy.data.materials.new("CC_screen")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1)
    em.inputs["Strength"].default_value = strength
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return m


# ------------------------------------------------------ person builder


def build_person(v, pose_name, parent):
    """Builds one posed person under ``parent``.  Returns (objects,
    screen_objects)."""
    H = v["h"]
    pose = POSES[pose_name]
    J = solve(v, pose)
    T, HD, Rt, Rh = J["T"], J["HD"], J["Rt"], J["Rh"]
    qt = Rt.to_quaternion()
    qh = Rh.to_quaternion()
    g = v["g"]
    shw = v["shw"]
    hipw = v["hipw"]
    top = v["top"]
    b = Body(res=0.0055)

    # ----------------------------------------------------- torso family
    torso_fam = "top"
    long_sleeve = top in ("longtee", "hoodie", "hoodup", "jacket",
                          "jacket_open", "vest")

    def torso(fam, k=1.0, arms=True, sleeve_long=True):
        # pelvis/hip mass (under the top: the top hangs to the hip)
        b.ell(fam, T(0, 0.004, 0.035),
              (0.1 * H * hipw * k * (0.9 + 0.1 * g),
               0.066 * H * g * k, 0.06 * H), qt)
        # waist / belly
        b.ell(fam, T(0, 0.002, 0.125),
              (0.094 * H * g * k, 0.062 * H * g * k, 0.078 * H), qt)
        if v["belly"] > 0:
            b.ell(fam, T(0, -0.035 - 0.012 * v["belly"], 0.12),
                  (0.07 * H * g * k, 0.045 * H * (0.7 + 0.5 * v["belly"]) * k,
                   0.065 * H), qt)
        # rib cage / chest
        b.ell(fam, T(0, 0.008, 0.215),
              (0.1 * H * shw * k * (0.85 + 0.15 * g), 0.066 * H * g * k,
               0.085 * H), qt)
        if v["fem"]:
            for s in (-1, 1):
                b.ell(fam, T(s * 0.036, -0.045, 0.205),
                      (0.032 * H * k, 0.026 * H * k, 0.028 * H), qt)
        # upper back / trapezius, shoulder caps
        b.ell(fam, T(0, 0.018, 0.272),
              (0.085 * H * shw * k, 0.045 * H * k, 0.04 * H), qt)
        if arms:
            for side in ("R", "L"):
                sh, el, wr = (J["sh_" + side], J["elbow_" + side],
                              J["wrist_" + side])
                b.ball(fam, sh + Rt @ Vector((0, 0, -0.006 * H)), 0.037 * H * k * (0.9 + 0.1 * g))
                if sleeve_long:
                    b.chain(fam, sh, el, 0.041 * H * k * g ** 0.5,
                            0.032 * H * k)
                    b.chain(fam, el, wr - (wr - el) * 0.06,
                            0.032 * H * k, 0.026 * H * k)
                else:
                    mid = sh.lerp(el, 0.55)
                    b.chain(fam, sh, mid, 0.043 * H * k * g ** 0.5,
                            0.037 * H * k)

    if top == "jacket_open":
        torso("top", k=1.07, sleeve_long=True)
        # the opening: cut a strip out of the jacket's front
        b.ell("top", T(0, -0.1, 0.17), (0.03 * H, 0.05 * H, 0.16 * H),
              qt, neg=True)
        b.ell("top", T(0, -0.1, 0.3), (0.035 * H, 0.05 * H, 0.04 * H),
              qt, neg=True)
        torso("inner", k=0.99, arms=False)
    elif top == "vest":
        torso("inner", k=1.0, sleeve_long=True)
        torso("top", k=1.07, arms=False)
        b.chain("top", T(0, -0.1, 0.24), T(0, -0.1, 0.33),
                0.025 * H, 0.04 * H, neg=True)
        for s in (-1, 1):   # armholes
            b.ball("top", J["sh_R" if s < 0 else "sh_L"], 0.046 * H, neg=True)
    else:
        torso("top", k=1.02 if top in ("hoodie", "hoodup", "jacket") else 1.0,
              sleeve_long=long_sleeve)
    if top in ("hoodie", "hoodup", "jacket"):
        for side in ("R", "L"):
            el, wr = J["elbow_" + side], J["wrist_" + side]
            b.ball("top", el.lerp(wr, 0.9), 0.026 * H)
    if top == "hoodie":
        # hood lying on the back of the shoulders
        b.ell("top", T(0, 0.055, 0.3), (0.07 * H, 0.032 * H, 0.04 * H), qt)
    if top == "hoodup":
        b.ell("top", HD(0, 0.012, 0.012), (0.06 * H, 0.068 * H, 0.068 * H),
              qh)
        b.ell("top", T(0, 0.04, 0.31), (0.06 * H, 0.04 * H, 0.04 * H), qt)
        b.ell("top", HD(0, -0.07, -0.012), (0.043 * H, 0.04 * H, 0.055 * H),
              qh, neg=True)
    if top == "jacket":
        # collar
        b.ell("top", T(0, 0.01, 0.315), (0.05 * H, 0.045 * H, 0.022 * H), qt)

    # ---------------------------------------------------------- skin
    # neck
    b.chain("skin", J["neck0"], J["neck1"] + Rh @ Vector((0, 0, 0.02 * H)),
            0.03 * H * (0.9 + 0.12 * g), 0.029 * H)
    # head: cranium + face + jaw + features
    b.ell("skin", HD(0, 0.006, 0.012), (0.041 * H, 0.05 * H, 0.047 * H), qh)
    b.ell("skin", HD(0, -0.014, -0.022), (0.036 * H * (0.95 + 0.08 * g),
                                           0.04 * H, 0.04 * H), qh)
    b.ball("skin", HD(0, -0.034, -0.052), 0.017 * H)      # chin
    b.ell("skin", HD(0, -0.052, -0.006), (0.0075 * H, 0.01 * H, 0.013 * H),
          qh)                                               # nose
    b.ell("skin", HD(0, -0.044, 0.016), (0.034 * H, 0.011 * H, 0.009 * H),
          qh)                                               # brow
    for s in (-1, 1):
        b.ell("skin", HD(s * 0.042, 0.004, -0.006),
              (0.007 * H, 0.012 * H, 0.016 * H), qh)       # ears
        b.ball("skin", HD(s * 0.017, -0.051, 0.002), 0.0105 * H, neg=True)
    # hands and bare forearms
    for side in ("R", "L"):
        sh, el, wr = J["sh_" + side], J["elbow_" + side], J["wrist_" + side]
        if not long_sleeve:
            b.chain("skin", sh.lerp(el, 0.4), el, 0.034 * H * g ** 0.5,
                    0.028 * H)
            b.chain("skin", el, wr, 0.028 * H, 0.021 * H)
        else:
            b.chain("skin", el.lerp(wr, 0.6), wr, 0.023 * H, 0.02 * H)
        shape = J["shape_" + side]
        hd = J["hand_" + side]
        palm = J["palm_" + side]
        if shape == "pocket":
            continue
        if shape in ("fist", "phone"):
            c = wr + hd * 0.034 * H
            b.ell("skin", c, (0.025 * H, 0.021 * H, 0.03 * H),
                  frame_quat(hd, palm))
            continue
        # open hand: palm + fingers + thumb
        q = frame_quat(hd, palm)
        b.ell("skin", wr + hd * 0.03 * H, (0.025 * H, 0.013 * H, 0.033 * H),
              q)
        b.ell("skin", wr + hd * 0.074 * H, (0.022 * H, 0.009 * H, 0.028 * H),
              q)
        side_ax = q.to_matrix().col[0]
        s = -1.0 if side == "R" else 1.0
        b.ball("skin", wr + hd * 0.035 * H + side_ax * 0.02 * H * s
               + palm.normalized() * 0.006 * H, 0.0085 * H)

    # ---------------------------------------------------------- legs
    shorts = v.get("shorts", False)
    b.ell("pants", J["pelvis"] + Rt @ Vector((0, 0.006 * H, 0.03 * H)),
          (0.1 * H * hipw * (0.9 + 0.1 * g), 0.066 * H * g, 0.07 * H), qt)
    for side in ("R", "L"):
        hip, knee, ank = (J["hip_" + side], J["knee_" + side],
                          J["ankle_" + side])
        rt = 0.056 * H * (0.85 + 0.15 * g) * (1.0 + 0.3 * (hipw - 1))
        if shorts:
            end = hip.lerp(knee, 0.85)
            b.chain("pants", hip, end, rt, 0.047 * H)
            b.chain("skin", hip.lerp(knee, 0.6), knee, 0.042 * H, 0.036 * H)
            b.chain("skin", knee, ank, 0.036 * H, 0.022 * H)
            b.ell("skin", knee.lerp(ank, 0.3) + Vector((0, 0.01 * H, 0)),
                  (0.03 * H, 0.032 * H, 0.06 * H))
        else:
            b.chain("pants", hip, knee, rt * 1.03, 0.046 * H)
            b.chain("pants", knee, ank + Vector((0, 0, 0.01 * H)),
                    0.046 * H, 0.038 * H)
        # shoe
        s = -1.0 if side == "R" else 1.0
        fwd = Vector((s * 0.22, -1.0, 0.0)).normalized()
        qf = frame_quat(fwd, Vector((0, 0, 1)))
        sole = Vector((ank.x, ank.y, 0.0))
        b.ell("shoes", sole + fwd * 0.045 * H + Vector((0, 0, 0.022 * H)),
              (0.028 * H, 0.022 * H, 0.066 * H), qf)
        b.ell("shoes", sole + fwd * 0.005 * H + Vector((0, 0, 0.034 * H)),
              (0.03 * H, 0.03 * H, 0.04 * H), qf)

    # ---------------------------------------------------------- hair
    hair = v["hair"]
    hat = v.get("hat")
    if hair != "none" and top != "hoodup":
        if hair == "buzz":
            b.ell("hair", HD(0, 0.009, 0.017), (0.0425 * H, 0.051 * H,
                                                0.046 * H), qh)
        elif hair == "curly":
            b.ell("hair", HD(0, 0.01, 0.024), (0.047 * H, 0.055 * H,
                                               0.05 * H), qh)
            for s in (-1, 0, 1):
                b.ball("hair", HD(s * 0.025, -0.02, 0.05), 0.022 * H)
        else:
            b.ell("hair", HD(0, 0.012, 0.02), (0.0445 * H, 0.054 * H,
                                               0.049 * H), qh)
            b.ell("hair", HD(0, -0.028, 0.045), (0.036 * H, 0.03 * H,
                                                 0.02 * H), qh)
        # keep the face clear
        b.ell("hair", HD(0, -0.062, -0.018), (0.05 * H, 0.03 * H,
                                              0.045 * H), qh, neg=True)
        if hair in ("long", "bob"):
            drop = 0.13 if hair == "long" else 0.065
            for s in (-1, 1):
                b.chain("hair", HD(s * 0.04, 0.02, 0.0),
                        HD(s * 0.043, 0.028, -drop), 0.02 * H, 0.016 * H)
            b.chain("hair", HD(0, 0.03, 0.0), HD(0, 0.045, -drop),
                    0.04 * H, 0.032 * H)
        if hair == "pony":
            b.ball("hair", HD(0, 0.062, 0.012), 0.017 * H)
            b.chain("hair", HD(0, 0.075, 0.0), HD(0, 0.075, -0.085),
                    0.016 * H, 0.009 * H)
    if v["beard"]:
        b.ell("hair", HD(0, -0.022, -0.04), (0.038 * H, 0.036 * H,
                                              0.03 * H), qh)
        b.ball("hair", HD(0, -0.04, -0.056), 0.016 * H)
        b.ell("hair", HD(0, -0.058, -0.03), (0.013 * H, 0.012 * H,
                                              0.006 * H), qh, neg=True)

    if hat == "cap":
        b.ell("hat", HD(0, 0.004, 0.03), (0.047 * H, 0.054 * H, 0.043 * H),
              qh)
        brim_q = Rh.to_quaternion() @ Euler((math.radians(12), 0, 0)
                                             ).to_quaternion()
        b.ell("hat", HD(0, -0.062, 0.028), (0.037 * H, 0.034 * H,
                                            0.004 * H), brim_q)
    elif hat == "beanie":
        b.ell("hat", HD(0, 0.01, 0.046), (0.047 * H, 0.054 * H, 0.046 * H),
              qh)
        b.ell("hat", HD(0, 0.008, 0.03), (0.049 * H, 0.056 * H, 0.012 * H),
              qh)

    # ---------------------------------------------------------- scarf
    if v.get("scarf"):
        n = 10
        for i in range(n):
            a = 2 * math.pi * i / n
            b.ball("scarf", T(math.sin(a) * 0.042, 0.012 - math.cos(a) * 0.04,
                              0.31), 0.019 * H)
        for s, dz in ((-1, 0.0), (1, 0.02)):
            b.chain("scarf", T(s * 0.022, -0.06, 0.3),
                    T(s * 0.03, -0.075 - 0.02 * v["belly"], 0.17 + dz),
                    0.016 * H, 0.014 * H)

    # ---------------------------------------------------- materials
    skin_rgb = SKIN[v["skin"]]
    mats = {
        "skin": make_mat("skin_" + v["skin"], skin_rgb, rough=0.55,
                         sss=0.15, noise=0.04),
        "top": make_mat("top_" + v["name"], C[v["topc"]],
                        rough=0.62 if top == "jacket" else 0.8,
                        sheen=0.3 if top != "jacket" else 0.0,
                        stripes=((0.6 * H, 0.012 * H), (0.7 * H, 0.012 * H))
                        if top == "vest" else None),
        "pants": make_mat("pants_" + v["pants"], C[v["pants"]], rough=0.8,
                          sheen=0.2),
        "shoes": make_mat("shoes_" + v["shoes"], C[v["shoes"]], rough=0.5,
                          noise=0.03),
        "hair": make_mat("hair_" + v["hairc"], HAIRC[v["hairc"]], rough=0.55,
                         noise=0.2, sheen=0.4),
    }
    if "innerc" in v:
        mats["inner"] = make_mat("inner_" + v["innerc"], C[v["innerc"]],
                                 rough=0.8, sheen=0.3)
    if hat:
        mats["hat"] = make_mat("hat_" + v["hatc"], C[v["hatc"]], rough=0.75,
                               sheen=0.3)
    if v.get("scarf"):
        mats["scarf"] = make_mat("scarf_" + v["scarf"], C[v["scarf"]],
                                 rough=0.85, sheen=0.5)
    objs = b.build(mats, parent)

    # eyes: small dark lenses sitting in the sockets
    eye_mat = make_mat("eye", (0.06, 0.045, 0.04), rough=0.3, noise=0.0)
    if top != "hoodup" or True:
        for s in (-1, 1):
            me = bpy.data.meshes.new("CCeye")
            ob = bpy.data.objects.new("CCeye", me)
            bpy.context.scene.collection.objects.link(ob)
            import bmesh
            bm = bmesh.new()
            bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6,
                                      radius=0.006 * H)
            bm.to_mesh(me)
            bm.free()
            me.materials.append(eye_mat)
            for p in me.polygons:
                p.use_smooth = True
            ob.location = HD(s * 0.017, -0.043, 0.001)
            ob.scale = (1.0, 0.6, 0.75)
            ob.rotation_mode = 'QUATERNION'
            ob.rotation_quaternion = qh
            ob.parent = parent
            objs.append(ob)

    screens = []
    for side in ("R", "L"):
        if J["shape_" + side] != "phone":
            continue
        wr, hd = J["wrist_" + side], J["hand_" + side]
        # phone faces the camera (screen normal toward -Y and up)
        to_cam = Vector((0, -math.cos(CAM_ELEV), math.sin(CAM_ELEV)))
        up = (hd - to_cam * hd.dot(to_cam)).normalized()
        xax = up.cross(to_cam).normalized()
        m = Matrix((xax, up, to_cam)).transposed()
        centre = wr + hd * 0.052 * H + to_cam * 0.012 * H
        import bmesh
        for kind, size, off in (("body", (0.078, 0.158, 0.009), 0.0),
                                ("screen", (0.07, 0.148, 0.001), 0.0052)):
            me = bpy.data.meshes.new("CCphone_" + kind)
            ob = bpy.data.objects.new("CCphone_" + kind, me)
            bpy.context.scene.collection.objects.link(ob)
            bm = bmesh.new()
            bmesh.ops.create_cube(bm, size=1.0)
            bm.to_mesh(me)
            bm.free()
            ob.scale = size
            ob.rotation_mode = 'QUATERNION'
            ob.rotation_quaternion = m.to_quaternion()
            ob.location = centre + to_cam * off
            ob.parent = parent
            if kind == "body":
                me.materials.append(make_mat("phone", (0.05, 0.05, 0.06),
                                             rough=0.3, noise=0.0))
            else:
                me.materials.append(screen_mat(6.0))
                screens.append(ob)
            objs.append(ob)
    return objs, screens


# ------------------------------------------------------------ the scene


def reset_scene():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.metaballs, bpy.data.lights,
                 bpy.data.cameras, bpy.data.images):
        for d in list(coll):
            coll.remove(d)


def clear_person():
    for ob in list(bpy.data.objects):
        if ob.name.startswith("CC"):
            bpy.data.objects.remove(ob, do_unlink=True)
    for d in list(bpy.data.metaballs):
        if d.users == 0:
            bpy.data.metaballs.remove(d)
    for d in list(bpy.data.meshes):
        if d.users == 0:
            bpy.data.meshes.remove(d)
    for d in list(bpy.data.materials):
        if d.users == 0 and d.name.startswith("CC_screen"):
            bpy.data.materials.remove(d)


def sun(name, direction, strength, angle_deg):
    ld = bpy.data.lights.new(name, 'SUN')
    ld.energy = strength
    ld.angle = math.radians(angle_deg)
    ld.color = (1, 1, 1)
    ob = bpy.data.objects.new(name, ld)
    bpy.context.scene.collection.objects.link(ob)
    d = Vector(direction).normalized()
    ob.rotation_mode = 'QUATERNION'
    ob.rotation_quaternion = d.to_track_quat('-Z', 'Y')
    return ob


def dir_from(az_deg, el_deg):
    """Direction light TRAVELS, for a light placed at azimuth az (0 = in
    front of the person, i.e. -Y; +90 = image right, +X) and elevation."""
    az, el = math.radians(az_deg), math.radians(el_deg)
    pos = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el),
                  math.sin(el)))
    return -pos


def setup_card_scene(samples):
    reset_scene()
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    cy = sc.cycles
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = 'METAL'
        prefs.get_devices()
        for dev in prefs.devices:
            dev.use = True
        cy.device = 'GPU'
    except Exception:
        cy.device = 'CPU'
    cy.samples = samples
    cy.use_denoising = True
    cy.max_bounces = 4
    cy.use_adaptive_sampling = True
    sc.render.film_transparent = True
    sc.render.resolution_x = CELL_W * SS
    sc.render.resolution_y = CELL_H * SS
    sc.render.resolution_percentage = 100
    sc.render.pixel_aspect_x = sc.render.pixel_aspect_y = 1
    sc.render.filter_size = 1.2
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'None'
    sc.view_settings.exposure = 0.0
    sc.view_settings.gamma = 1.0
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.render.image_settings.color_depth = '8'
    # neutral grey ambient
    w = bpy.data.worlds.new("CCworld") if not sc.world else sc.world
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.5, 0.5, 0.5, 1)
    bg.inputs["Strength"].default_value = 0.35
    # lights: key above-front (slightly to image left), fill front-right,
    # rim behind-above
    sun("Lkey", dir_from(-30, 52), 3.4, 28)
    sun("Lfill", dir_from(55, 18), 0.9, 60)
    sun("Lrim", dir_from(170, 42), 2.6, 12)
    # camera
    cd = bpy.data.cameras.new("Cam")
    cd.type = 'ORTHO'
    cd.sensor_fit = 'VERTICAL'
    cd.ortho_scale = WORLD_H
    cd.clip_start = 0.1
    cd.clip_end = 100
    cam = bpy.data.objects.new("Cam", cd)
    sc.collection.objects.link(cam)
    cam.rotation_euler = (math.radians(90) - CAM_ELEV, 0, 0)
    fwd = Vector((0, math.cos(CAM_ELEV), -math.sin(CAM_ELEV)))
    up = Vector((0, math.sin(CAM_ELEV), math.cos(CAM_ELEV)))
    right = Vector((1, 0, 0))
    ax, ay = ANCHOR_PX
    centre = (up * ((ay - CELL_H / 2) / PX_PER_M)
              - right * ((ax - CELL_W / 2) / PX_PER_M))
    cam.location = centre - fwd * 20.0
    sc.camera = cam
    root = bpy.data.objects.new("Root", None)
    sc.collection.objects.link(root)
    return root


# ------------------------------------------------------------ image I/O


def load_png(path):
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    arr = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(arr)
    bpy.data.images.remove(img)
    return arr.reshape(h, w, 4)[::-1].copy()      # top row first


def write_png(path, arr):
    """arr: HxWx{1,3,4} float 0..1 (top row first) -> 8-bit PNG."""
    a = np.clip(np.round(arr * 255.0), 0, 255).astype(np.uint8)
    if a.ndim == 2:
        a = a[:, :, None]
    h, w, c = a.shape
    ctype = {1: 0, 3: 2, 4: 6}[c]
    raw = b"".join(b"\x00" + a[y].tobytes() for y in range(h))

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff))
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, ctype, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)


def downsample(rgba, f):
    """Premultiplied box filter, returns straight alpha."""
    h, w, _ = rgba.shape
    a = rgba[:, :, 3:4]
    pm = np.concatenate([rgba[:, :, :3] * a, a], axis=2)
    pm = pm.reshape(h // f, f, w // f, f, 4).mean(axis=(1, 3))
    out = pm.copy()
    al = pm[:, :, 3:4]
    out[:, :, :3] = np.where(al > 1e-5, pm[:, :, :3] / np.maximum(al, 1e-5),
                             0.0)
    return out


def dilate_cell(cell, px):
    """Grow colour into transparent pixels (alpha untouched)."""
    rgb = cell[:, :, :3].copy()
    alpha = cell[:, :, 3]
    valid = alpha >= 0.25
    if not valid.any():
        return cell
    mean = rgb[valid].mean(axis=0)
    for _ in range(px):
        acc = np.zeros_like(rgb)
        cnt = np.zeros(valid.shape, dtype=np.float32)
        vf = valid.astype(np.float32)
        pad_rgb = np.pad(rgb * vf[:, :, None], ((1, 1), (1, 1), (0, 0)))
        pad_v = np.pad(vf, 1)
        h, w = valid.shape
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue
                acc += pad_rgb[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
                cnt += pad_v[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
        grow = (~valid) & (cnt > 0)
        rgb[grow] = acc[grow] / cnt[grow][:, None]
        valid = valid | grow
    rgb[~valid] = mean
    out = cell.copy()
    out[:, :, :3] = rgb
    return out


# --------------------------------------------------------------- render


def cell_path(c, r, kind="col"):
    return os.path.join(CACHE_DIR, "%s_%02d_%d.png" % (kind, c, r))


def render_cells(opts):
    root = setup_card_scene(opts["samples"])
    sc = bpy.context.scene
    vs = opts["variants"] if opts["variants"] is not None else range(COLS)
    fs = opts["frames"] if opts["frames"] is not None else range(ROWS)
    os.makedirs(CACHE_DIR, exist_ok=True)
    t0 = time.time()
    for c in vs:
        v = VARIANTS[c]
        root.rotation_euler = (0, 0, math.radians(v.get("yaw", 0)))
        for r in fs:
            clear_person()
            objs, screens = build_person(v, v["poses"][r], root)
            sc.render.filepath = cell_path(c, r)
            bpy.ops.render.render(write_still=True)
            emit_file = cell_path(c, r, "emit")
            if screens:
                # emission pass: everything black, screens white
                blk = black_mat()
                saved = []
                for ob in objs:
                    if ob in screens:
                        continue
                    data = ob.data
                    saved.append((data, list(data.materials)))
                    for i in range(len(data.materials)):
                        data.materials[i] = blk
                wstr = sc.world.node_tree.nodes["Background"].inputs[
                    "Strength"]
                old = wstr.default_value
                wstr.default_value = 0.0
                hidden = []
                for ob in sc.objects:
                    if ob.type == 'LIGHT':
                        ob.hide_render = True
                        hidden.append(ob)
                sc.render.filepath = emit_file
                bpy.ops.render.render(write_still=True)
                for ob in hidden:
                    ob.hide_render = False
                wstr.default_value = old
                for data, mlist in saved:
                    for i, m in enumerate(mlist):
                        data.materials[i] = m
            elif os.path.exists(emit_file):
                os.remove(emit_file)
            print("[crowd] cell %d/%d (%s %s) %.1fs" % (
                c, r, v["name"], FRAMES[r], time.time() - t0))
    clear_person()
    return time.time() - t0


def assemble(opts):
    atlas = np.zeros((ROWS * CELL_H, COLS * CELL_W, 4), dtype=np.float32)
    emit = np.zeros((ROWS * CELL_H, COLS * CELL_W), dtype=np.float32)
    report = []
    for c in range(COLS):
        for r in range(ROWS):
            p = cell_path(c, r)
            if not os.path.exists(p):
                raise SystemExit("missing cell %s: run without --variants"
                                 % p)
            big = load_png(p)
            cell = downsample(big, SS)
            ys, xs = np.nonzero(cell[:, :, 3] > 0.02)
            report.append((c, r, xs.min(), xs.max(), ys.min(), ys.max()))
            cell = dilate_cell(cell, DILATE_PX)
            atlas[r * CELL_H:(r + 1) * CELL_H,
                  c * CELL_W:(c + 1) * CELL_W] = cell
            ep = cell_path(c, r, "emit")
            if os.path.exists(ep):
                e = load_png(ep)
                lum = e[:, :, :3].max(axis=2) * e[:, :, 3]
                lum = lum.reshape(CELL_H, SS, CELL_W, SS).mean(axis=(1, 3))
                emit[r * CELL_H:(r + 1) * CELL_H,
                     c * CELL_W:(c + 1) * CELL_W] = np.clip(lum * 1.2, 0, 1)
    os.makedirs(OUT_DIR, exist_ok=True)
    write_png(os.path.join(OUT_DIR, "crowd_atlas.png"), atlas)
    write_png(os.path.join(OUT_DIR, "crowd_atlas_emit.png"), emit)
    meta = {
        "cols": COLS, "rows": ROWS, "cell": [CELL_W, CELL_H],
        "world_height_m": round(WORLD_H, 4),
        "world_width_m": round(WORLD_W, 4),
        "px_per_m": PX_PER_M,
        "anchor_px": list(ANCHOR_PX),
        "anchor_note": "feet contact point in each cell, pixels from the "
                       "cell's top-left; 22 px (0.1833 m) above the card's "
                       "bottom edge",
        "camera": "orthographic, 40 deg above horizontal, facing the person",
        "alpha": "straight (not premultiplied); colour dilated into the "
                 "transparent area",
        "frames": FRAMES,
        "emit": "crowd_atlas_emit.png: white = phone screen (cheer row)",
        "variants": [{"name": v["name"], "height_m": v["h"],
                      "phone": v["phone"], "poses": v["poses"]}
                     for v in VARIANTS],
    }
    with open(os.path.join(OUT_DIR, "crowd_atlas.json"), "w") as f:
        json.dump(meta, f, indent=2)
        f.write("\n")
    for c, r, x0, x1, y0, y1 in report:
        flag = ""
        if x0 < 1 or x1 > CELL_W - 2 or y0 < 1 or y1 > CELL_H - 4:
            flag = "  <-- touches the edge"
        print("[crowd] bbox %2d/%d x %3d..%3d y %3d..%3d%s" % (
            c, r, x0, x1, y0, y1, flag))
    return atlas, emit


# -------------------------------------------------------------- previews


def upscale_nn(img, f):
    return img.repeat(f, axis=0).repeat(f, axis=1)


def over(bg_rgb, fg):
    a = fg[:, :, 3:4]
    return fg[:, :, :3] * a + bg_rgb * (1 - a)


def write_preview(atlas, emit):
    grey = np.array([0.24, 0.245, 0.26], dtype=np.float32)
    glow = emit[:, :, None] * np.array([1, 1, 1], dtype=np.float32)
    base = over(np.broadcast_to(grey, atlas.shape[:2] + (3,)), atlas)
    base = np.clip(base + glow * 0.4, 0, 1)
    pad = 24
    pick = [0, 2, 3, 9]
    crop_w = 2 * CELL_W * 2 + pad
    crop_h = 2 * CELL_H * 2 + pad
    W = max(atlas.shape[1] + 2 * pad, pad + len(pick) * crop_w)
    Hh = atlas.shape[0] + 2 * pad + pad + crop_h
    canvas = np.empty((Hh, W, 3), dtype=np.float32)
    canvas[:] = grey
    canvas[pad:pad + atlas.shape[0], pad:pad + atlas.shape[1]] = base
    # 2x crops: 4 variants x 4 frames
    y = pad * 2 + atlas.shape[0]
    x = pad
    for c in pick:
        for r in range(ROWS):
            cell = base[r * CELL_H:(r + 1) * CELL_H,
                        c * CELL_W:(c + 1) * CELL_W]
            big = upscale_nn(cell, 2)
            yy = y + (r // 2) * (CELL_H * 2)
            xx = x + (r % 2) * (CELL_W * 2)
            if yy + big.shape[0] <= Hh and xx + big.shape[1] <= W:
                canvas[yy:yy + big.shape[0], xx:xx + big.shape[1]] = big
        x += crop_w
    write_png(os.path.join(PREV_DIR, "crowd-atlas-preview.png"), canvas)


def render_crowd_test(samples=64):
    """~60 cards on five steps under warm light, seen at 45 degrees
    through a 28 degree lens (the fight camera)."""
    reset_scene()
    sc = bpy.context.scene
    sc.render.film_transparent = False
    sc.render.resolution_x = 1920
    sc.render.resolution_y = 1080
    sc.cycles.samples = samples
    sc.view_settings.view_transform = 'AgX'
    try:
        sc.view_settings.look = 'AgX - Medium High Contrast'
    except TypeError:
        sc.view_settings.look = 'None'
    w = sc.world
    bg = w.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.02, 0.025, 0.04, 1)
    bg.inputs["Strength"].default_value = 1.0
    # stands
    import bmesh
    step_d, step_h, width = 0.85, 0.42, 13.0
    concrete = make_mat("concrete", (0.2, 0.2, 0.21), rough=0.9, noise=0.2)
    for i in range(6):
        me = bpy.data.meshes.new("step")
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new("step", me)
        sc.collection.objects.link(ob)
        ob.scale = (width, step_d * (6 - i), step_h)
        ob.location = (0, i * step_d + step_d * (6 - i) / 2, (i + 0.5)
                       * step_h)
        me.materials.append(concrete)
    # a barrier wall in front
    me = bpy.data.meshes.new("wall")
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("wall", me)
    sc.collection.objects.link(ob)
    ob.scale = (width, 0.25, 1.1)
    ob.location = (0, -0.6, 0.55)
    me.materials.append(concrete)
    floor = bpy.data.meshes.new("floor")
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=30)
    bm.to_mesh(floor)
    bm.free()
    fo = bpy.data.objects.new("floor", floor)
    sc.collection.objects.link(fo)
    fo.location = (0, -10, 0)
    floor.materials.append(make_mat("floor", (0.2, 0.2, 0.21), rough=0.8,
                                    noise=0.2))
    # camera: 45 deg down, 28 deg vertical field of view
    cd = bpy.data.cameras.new("Cam")
    cd.sensor_fit = 'VERTICAL'
    cd.angle = math.radians(28)
    cam = bpy.data.objects.new("Cam", cd)
    sc.collection.objects.link(cam)
    el = math.radians(45)
    fwd = Vector((0, math.cos(el), -math.sin(el)))
    target = Vector((0, 2.3, 1.6))
    cam.location = target - fwd * 19.0
    cam.rotation_euler = (math.radians(90) - el, 0, 0)
    sc.camera = cam
    up = Vector((0, math.sin(el), math.cos(el)))
    # atlas material
    img = bpy.data.images.load(os.path.join(OUT_DIR, "crowd_atlas.png"))
    img.alpha_mode = 'STRAIGHT'
    eimg = bpy.data.images.load(os.path.join(OUT_DIR,
                                             "crowd_atlas_emit.png"))
    eimg.colorspace_settings.name = 'Non-Color'
    m = bpy.data.materials.new("cards")
    m.use_nodes = True
    nt = m.node_tree
    bs = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = 'Linear'
    etex = nt.nodes.new("ShaderNodeTexImage")
    etex.image = eimg
    nt.links.new(tex.outputs["Color"], bs.inputs["Base Color"])
    nt.links.new(tex.outputs["Alpha"], bs.inputs["Alpha"])
    nt.links.new(etex.outputs["Color"], bs.inputs["Emission Color"])
    bs.inputs["Emission Strength"].default_value = 3.0
    bs.inputs["Roughness"].default_value = 0.8
    rng = random.Random(7)
    cards = 0
    for row in range(5):
        n = 12
        for i in range(n):
            x = -width / 2 + 0.6 + (i + rng.uniform(-0.25, 0.25)) * \
                (width - 1.2) / (n - 1)
            y = row * step_d + 0.4 + rng.uniform(-0.12, 0.12)
            z = (row + 1) * step_h
            c = rng.randrange(COLS)
            r = rng.choice([0, 0, 1, 1, 2, 2, 2, 3])
            feet = Vector((x, y, z))
            # Depth offset: slide the card 1.5 m toward the camera along
            # the view ray through the feet and shrink it to match, so the
            # leaning card never cuts into the step behind it.
            ray = feet - cam.location
            t = 1.0 - 1.5 / ray.length
            feet = cam.location + ray * t
            centre = feet + up * ((ANCHOR_PX[1] - CELL_H / 2) / PX_PER_M) * t
            me = bpy.data.meshes.new("card")
            hw, hh = WORLD_W / 2 * t, WORLD_H / 2 * t
            rx = Vector((1, 0, 0))
            verts = [centre - rx * hw - up * hh, centre + rx * hw - up * hh,
                     centre + rx * hw + up * hh, centre - rx * hw + up * hh]
            me.from_pydata([tuple(p) for p in verts], [], [(0, 1, 2, 3)])
            uv = me.uv_layers.new()
            u0, u1 = c / COLS, (c + 1) / COLS
            v0, v1 = 1 - (r + 1) / ROWS, 1 - r / ROWS
            for li, (uu, vv) in enumerate([(u0, v0), (u1, v0), (u1, v1),
                                           (u0, v1)]):
                uv.data[li].uv = (uu, vv)
            me.materials.append(m)
            ob = bpy.data.objects.new("card", me)
            ob.visible_shadow = False
            sc.collection.objects.link(ob)
            cards += 1
    # warm orange floodlight from the arena side + cool dim fill
    ld = bpy.data.lights.new("warm", 'AREA')
    ld.energy = 5200
    ld.size = 4.0
    ld.color = (1.0, 0.55, 0.25)
    lo = bpy.data.objects.new("warm", ld)
    sc.collection.objects.link(lo)
    lo.location = (-6, -9, 10)
    lo.rotation_mode = 'QUATERNION'
    lo.rotation_quaternion = (Vector((0, 2.5, 1.5)) - lo.location
                              ).to_track_quat('-Z', 'Y')
    s2 = sun("cool", dir_from(160, 35), 0.35, 20)
    s2.data.color = (0.5, 0.65, 1.0)
    sc.render.filepath = os.path.join(PREV_DIR, "crowd-atlas-crowd-test.png")
    sc.render.image_settings.color_mode = 'RGB'
    bpy.ops.render.render(write_still=True)
    print("[crowd] crowd test: %d cards" % cards)


def main():
    opts = parse_args()
    if opts.get("crowd_only"):
        setup_card_scene(opts["samples"])
        render_crowd_test()
        return
    t = render_cells(opts)
    print("[crowd] cells rendered in %.1fs" % t)
    atlas, emit = assemble(opts)
    write_preview(atlas, emit)
    if opts["sheet"]:
        write_png(os.path.join(CACHE_DIR, "sheet.png"),
                  over(np.array([0.24, 0.245, 0.26], dtype=np.float32),
                       atlas))
    if opts["crowd"]:
        render_crowd_test()
    print("[crowd] done in %.1fs" % t)


if __name__ == "__main__":
    main()
