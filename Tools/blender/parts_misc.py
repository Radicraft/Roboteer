"""Armour plates, utility parts and the two FX scraps.

ARMOUR
  Both plates are authored 0.50 m wide (Z) by 0.30 m tall (Y) at ONE thickness
  unit = 0.012 m along X, with the outward face at +X.  P2 scales:
      scale.x = thickness_units      (1..4 from the catalogue)
      scale.y, scale.z              to fit the chassis armour socket
  and assigns the face material (`steel`, `titanium`, `hdpe`, `polycarbonate`)
  onto the plate's single body slot.  The default slot is `steel`.

UTILITY
  Origin is the mount socket.  `srimech` sits on `socket_srimech`, everything
  else on `socket_utility_0|1`.
"""

import math

from rkit import Part, BEVEL, PLATE_T, rot_pitch, rot_z

PLATE_W = 0.50      # across, Z
PLATE_H = 0.30      # up, Y
UNIT = 0.012        # one catalogue thickness unit, along X


# ------------------------------------------------------------------ armour

def build_plate_flat(_spec=None):
    P = Part("plate_flat", "armour")
    P.box((UNIT * 0.5, 0.0, 0.0), (UNIT, PLATE_H, PLATE_W), "steel", bevel=BEVEL, seg=2)
    # stiffening ribs on the inner face
    for z in (-0.16, 0.0, 0.16):
        P.box((-0.008, 0.0, z), (0.016, PLATE_H - 0.03, 0.020), "dark_metal",
              bevel=0.002, seg=1)
    P.box((-0.008, 0.0, 0.0), (0.016, 0.020, PLATE_W - 0.03), "dark_metal",
          bevel=0.002, seg=1)
    for zz in (-0.215, -0.072, 0.072, 0.215):
        for yy in (-0.118, 0.118):
            P.bolt((UNIT, yy, zz), (1, 0, 0))
    P.seam((UNIT * 0.5, -PLATE_H * 0.5, -PLATE_W * 0.5 + 0.01),
           (UNIT * 0.5, -PLATE_H * 0.5, PLATE_W * 0.5 - 0.01))
    P.socket("socket_pivot", (0.0, 0.0, 0.0))
    return P


def build_plate_sloped(_spec=None):
    P = Part("plate_sloped", "armour")
    # thick at the bottom, tapering up: the classic anti-wedge face
    prof = [(0.0, -PLATE_H * 0.5), (UNIT * 2.4, -PLATE_H * 0.5),
            (UNIT, PLATE_H * 0.5), (0.0, PLATE_H * 0.5)]
    P.prism(prof, -PLATE_W * 0.5, PLATE_W * 0.5, "steel", bevel=BEVEL, seg=2)
    for z in (-0.16, 0.0, 0.16):
        P.box((-0.008, 0.0, z), (0.016, PLATE_H - 0.03, 0.020), "dark_metal",
              bevel=0.002, seg=1)
    for zz in (-0.215, -0.072, 0.072, 0.215):
        P.bolt((UNIT * 2.2, -0.112, zz), (1, 0, 0))
        P.bolt((UNIT * 0.95, 0.112, zz), (1, 0, 0))
    P.socket("socket_pivot", (0.0, 0.0, 0.0))
    return P


# ----------------------------------------------------------------- utility

def build_srimech(_spec=None):
    P = Part("srimech", "utility")
    # base bracket and the shoulder pin
    P.box((0.0, 0.020, 0.0), (0.090, 0.040, 0.110), "dark_metal", bevel=0.003, seg=2)
    for s in (-1.0, 1.0):
        P.box((0.0, 0.055, s * 0.052), (0.062, 0.070, 0.014), "steel", bevel=0.003, seg=2)
        P.bolt((0.0, 0.010, s * 0.060), (0, 0, s), r=0.007)
    P.cyl((0.0, 0.078, 0.0), (0, 0, 1), 0.014, 0.13, "steel", n=10, bevel=0.0)
    # link one, folded forward along the deck (it swings back and down to right the bot)
    P.slab((0.0, 0.078), (0.185, 0.150), -0.030, 0.030, 0.024, "titanium",
           outward=(0.0, 1.0), bolts=2, inset=0.035)
    P.cyl((0.185, 0.150, 0.0), (0, 0, 1), 0.013, 0.085, "steel", n=8, bevel=0.0)
    # link two plus the pusher pad
    P.slab((0.185, 0.150), (0.325, 0.108), -0.024, 0.024, 0.020, "titanium",
           outward=(0.0, 1.0), bolts=2, inset=0.03)
    P.box((0.345, 0.100, 0.0), (0.040, 0.060, 0.115), "hdpe", bevel=0.004, seg=2)
    P.bolt_rect((0.366, 0.100, 0.0), (0, 0.018, 0), (0, 0, 0.040), axis=(1, 0, 0))
    # the pneumatic cylinder that throws it
    P.cyl((0.075, 0.062, 0.0), (-1.0, 0.42, 0.0), 0.023, 0.115, "steel", n=12, bevel=0.003)
    P.cyl((0.010, 0.090, 0.0), (-1.0, 0.42, 0.0), 0.010, 0.075, "titanium", n=8, bevel=0.0)
    P.cyl((0.140, 0.034, 0.0), (-1.0, 0.42, 0.0), 0.016, 0.020, "dark_metal", n=8, bevel=0.002)
    P.cyl((0.118, 0.048, 0.0), (0.0, -0.8, 0.6), 0.005, 0.052, "dark_metal", n=6)
    P.socket("socket_pivot", (0.0, 0.078, 0.0))
    P.socket("socket_tip", (0.366, 0.100, 0.0))
    return P


def build_rear_wedge(_spec=None):
    P = Part("rear_wedge", "utility")
    hw = 0.23
    # slopes down and back: a spinner hitting this climbs instead of biting
    P.slab((0.0, 0.075), (-0.215, -0.062), -hw, hw, 0.018, "titanium",
           outward=(-0.55, 1.0), bolts=4, inset=0.05)
    P.slab((-0.215, -0.056), (-0.262, -0.070), -hw, hw, 0.010, "steel",
           outward=(-0.5, -0.5))
    for s in (-1.0, 1.0):
        P.slab((0.0, 0.068), (-0.212, -0.058), s * hw - 0.009, s * hw + 0.009,
               0.034, "livery", outward=(-0.55, 1.0))
    for z in (-0.115, 0.0, 0.115):
        P.slab((-0.02, 0.062), (-0.200, -0.050), z - 0.011, z + 0.011, 0.026,
               "dark_metal", outward=(-0.55, 1.0))
    P.box((0.010, 0.060, 0.0), (0.040, 0.048, 2 * hw - 0.02), "dark_metal",
          bevel=0.003, seg=2)
    P.bolt_line((0.026, 0.060, -hw + 0.03), (0.026, 0.060, hw - 0.03), 5, (1, 0, 0))
    P.socket("socket_tip", (-0.262, -0.064, 0.0))
    return P


def build_skirts(_spec=None):
    P = Part("skirts", "utility")
    # one pair of hinged HDPE strips; P2 scales along X per chassis
    for s in (-1.0, 1.0):
        P.box((0.0, -0.030, s * 0.27), (0.62, 0.070, 0.016), "hdpe", bevel=0.004, seg=2)
        P.box((0.0, 0.012, s * 0.27), (0.64, 0.022, 0.024), "dark_metal", bevel=0.003, seg=2)
        P.bolt_line((-0.28, 0.012, s * 0.283), (0.28, 0.012, s * 0.283), 6, (0, 0, s))
        # the hinge knuckles the strip swings on
        for x in (-0.24, -0.08, 0.08, 0.24):
            P.cyl((x, 0.012, s * 0.27), (1, 0, 0), 0.013, 0.050, "steel", n=8, bevel=0.0)
        # a scuff rail along the bottom edge
        P.box((0.0, -0.062, s * 0.27), (0.60, 0.012, 0.022), "titanium", bevel=0.003, seg=1)
    P.socket("socket_tip", (0.0, -0.066, 0.0))
    return P


def build_magnets(_spec=None):
    P = Part("magnets", "utility")
    for s in (-1.0, 1.0):
        z = s * 0.145
        P.cyl((0.0, -0.030, z), (0, 1, 0), 0.070, 0.055, "dark_metal", n=18, bevel=0.004)
        P.ring((0.0, -0.030, z), (0, 1, 0), 0.076, 0.070, 0.046, "steel", n=18, bevel=0.002)
        P.cyl((0.0, -0.060, z), (0, 1, 0), 0.060, 0.008, "titanium", n=18, bevel=0.002)
        P.box((0.0, 0.010, z), (0.125, 0.030, 0.125), "steel", bevel=0.003, seg=2)
        P.bolt_rect((0.0, 0.026, z), (0.046, 0, 0), (0, 0, 0.046), axis=(0, 1, 0))
        for i in range(6):
            a = 2.0 * math.pi * i / 6.0
            P.bolt((0.062 * math.cos(a), -0.003, z + 0.062 * math.sin(a)), (0, 1, 0), r=0.007)
        P.cyl((0.0, 0.030, z), (0.0, 1.0, 0.0), 0.010, 0.030, "dark_metal", n=6)
    P.box((0.0, 0.020, 0.0), (0.060, 0.026, 0.180), "dark_metal", bevel=0.003, seg=1)
    P.socket("socket_tip", (0.0, -0.064, 0.0))
    return P


def build_scoop(_spec=None):
    P = Part("scoop", "utility")
    hw = 0.235
    # a curve swept up from the floor line, in five bolted segments
    pts = [(0.26, -0.062), (0.175, -0.060), (0.095, -0.038), (0.035, 0.008),
           (0.004, 0.072), (0.0, 0.135)]
    for i in range(len(pts) - 1):
        P.slab(pts[i], pts[i + 1], -hw, hw, 0.016, "steel",
               outward=(1.0, 0.35), bolts=2 if i % 2 == 0 else 0, inset=0.05)
    # side cheeks that stop things sliding off
    for s in (-1.0, 1.0):
        P.prism([(0.27, -0.070), (0.27, -0.048), (0.02, 0.150), (-0.02, 0.150),
                 (-0.02, -0.070)], s * hw - 0.009, s * hw + 0.009, "livery",
                bevel=0.004, seg=2)
        P.bolt((0.10, 0.020, s * (hw + 0.010)), (0, 0, s))
        P.bolt((-0.005, 0.110, s * (hw + 0.010)), (0, 0, s))
    # hardened lip
    P.slab((0.272, -0.058), (0.205, -0.070), -hw, hw, 0.010, "titanium",
           outward=(0.6, -0.7))
    P.box((-0.024, 0.030, 0.0), (0.040, 0.170, 2 * hw - 0.03), "dark_metal",
          bevel=0.003, seg=2)
    P.bolt_line((-0.044, 0.030, -hw + 0.04), (-0.044, 0.030, hw - 0.04), 4, (-1, 0, 0))
    P.socket("socket_tip", (0.272, -0.062, 0.0))
    return P


def build_spare_battery(_spec=None):
    P = Part("spare_battery", "utility")
    P.box((0.0, 0.045, 0.0), (0.19, 0.090, 0.135), "dark_metal", bevel=0.004, seg=2)
    P.plate((0.0, 0.096, 0.0), (0.17, 0.014, 0.115), "livery", axis=(0, 1, 0), inset=0.026)
    for s in (-1.0, 1.0):
        P.plate((0.0, 0.045, s * 0.074), (0.165, 0.070, 0.014), "hdpe",
                axis=(0, 0, s), inset=0.026)
    # cells showing through the end, then the terminals and the loom
    for i in range(3):
        P.cyl((0.098, 0.030 + i * 0.024, 0.0), (1, 0, 0), 0.020, 0.020,
              "steel", n=10, bevel=0.002)
    for s in (-1.0, 1.0):
        P.cyl((-0.070, 0.106, s * 0.030), (0, 1, 0), 0.009, 0.024, "titanium", n=8)
        P.cyl((-0.070, 0.118, s * 0.030), (0, 1, 0), 0.014, 0.008, "dark_metal", n=8)
    P.cyl((-0.030, 0.124, 0.0), (1, 0, 0), 0.008, 0.090, "dark_metal", n=6)
    P.cyl((0.020, 0.112, 0.0), (0.3, -0.95, 0.0), 0.008, 0.040, "dark_metal", n=6)
    P.box((0.050, 0.100, 0.0), (0.040, 0.030, 0.050), "dark_metal", bevel=0.003, seg=1)
    P.bolt_rect((0.0, 0.103, 0.0), (0.070, 0, 0), (0, 0, 0.044), axis=(0, 1, 0))
    P.socket("socket_tip", (0.050, 0.115, 0.0))
    return P


def build_counterweight(_spec=None):
    P = Part("counterweight", "utility")
    # a cast lead block in a steel cradle
    P.box((0.0, 0.042, 0.0), (0.155, 0.084, 0.155), "dark_metal", bevel=0.005, seg=2)
    P.box((0.0, 0.005, 0.0), (0.185, 0.014, 0.185), "steel", bevel=0.003, seg=2)
    for s in (-1.0, 1.0):
        P.box((s * 0.085, 0.045, 0.0), (0.014, 0.080, 0.165), "steel", bevel=0.003, seg=2)
        P.bolt((s * 0.092, 0.070, 0.060), (s, 0, 0))
        P.bolt((s * 0.092, 0.070, -0.060), (s, 0, 0))
        P.bolt((s * 0.092, 0.022, 0.0), (s, 0, 0))
    # cast ribs on the face, then the lifting eye
    for z in (-0.045, 0.045):
        P.box((0.0, 0.042, z), (0.135, 0.064, 0.012), "dark_metal", bevel=0.003, seg=1)
    P.box((0.0, 0.092, 0.0), (0.050, 0.020, 0.050), "steel", bevel=0.003, seg=2)
    P.ring((0.0, 0.122, 0.0), (0, 0, 1), 0.030, 0.018, 0.016, "steel", n=14, bevel=0.002)
    P.socket("socket_tip", (0.0, 0.140, 0.0))
    return P


# ---------------------------------------------------------------------- fx

def build_debris_bolt(_spec=None):
    """The shorn fastener for the bolt shower.  Kept as small as a closed solid
    can go: a capped hex prism is 20 tris (12 sides + 2 x 4 cap triangles)."""
    P = Part("debris_bolt", "fx")
    P.cone((0, 0, 0), (0, 1, 0), 0.011, 0.0095, 0.009, "core_glow", n=6, bevel=0.0)
    return P


def build_spark_chip(_spec=None):
    """A tapered sliver for spark and grind debris: 8 tris, closed."""
    P = Part("spark_chip", "fx")
    P.cone((0, 0, 0), (1, 0, 0), 0.0022, 0.0006, 0.016, "core_glow", n=3, bevel=0.0)
    return P


BUILDERS = {
    "plate_flat": build_plate_flat,
    "plate_sloped": build_plate_sloped,
    "srimech": build_srimech,
    "rear_wedge": build_rear_wedge,
    "skirts": build_skirts,
    "magnets": build_magnets,
    "scoop": build_scoop,
    "spare_battery": build_spare_battery,
    "counterweight": build_counterweight,
    "debris_bolt": build_debris_bolt,
    "spark_chip": build_spark_chip,
}
