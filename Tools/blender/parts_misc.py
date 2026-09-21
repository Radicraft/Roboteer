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

from mathutils import Vector

from rkit import Part, BEVEL, PLATE_T, rot_pitch, rot_z

PLATE_W = 0.50      # across, Z
PLATE_H = 0.30      # up, Y
UNIT = 0.012        # one catalogue thickness unit, along X


# ------------------------------------------------------------------ armour
#
# The plates cover most of a built bot, so they carry more detail than anything
# else per square metre: a rolled chamfered leading edge all round, a visible
# thickness step, edge-following hardware bolts with washers and recessed
# sockets, corner gussets on the inner face, drain slots along the bottom, and
# a raised inset `livery` panel over about 36 % of the face so the player's
# colour survives a fully armoured build.

LIVERY_H = 0.175        # the inset panel: 0.175 x 0.315 = 36 % of 0.30 x 0.50
LIVERY_W = 0.315


def _rolled_edges(P, half_y, half_z, x, r, mat):
    """Half-round lips along all four edges: a cut plate has a rolled edge and
    a bevel alone does not read as one."""
    for sy in (-1.0, 1.0):
        P.cyl((x, sy * half_y, 0.0), (0, 0, 1), r, 2.0 * half_z, mat, n=8, bevel=0.0)
    for sz in (-1.0, 1.0):
        P.cyl((x, 0.0, sz * half_z), (0, 1, 0), r, 2.0 * half_y, mat, n=8, bevel=0.0)


def _gussets(P, half_y, half_z, mat="dark_metal", leg=0.034, w=0.009):
    """Triangular webs behind the four corners."""
    for sz in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            prof = [(0.0, 0.0), (-leg, 0.0), (0.0, -leg * sy)]
            P.prism(prof, sz * (half_z - 0.05) - w, sz * (half_z - 0.05) + w,
                    mat, bevel=0.0018, seg=1,
                    at=(0.0, sy * (half_y - 0.012), 0.0))


def _edge_bolts(P, x, half_y, half_z, axis=(1, 0, 0)):
    """Eight fasteners following the edges, outside the thickness step."""
    for sy in (-1.0, 1.0):
        for z in (-0.150, 0.150):
            P.hardware_bolt((x, sy * (half_y - 0.0125), z), axis)
    for sz in (-1.0, 1.0):
        for y in (-0.062, 0.062):
            P.hardware_bolt((x, y, sz * (half_z - 0.0175)), axis)


def build_plate_flat(_spec=None):
    P = Part("plate_flat", "armour")
    hy, hz = PLATE_H * 0.5, PLATE_W * 0.5
    P.box((UNIT * 0.5, 0.0, 0.0), (UNIT, PLATE_H, PLATE_W), "steel",
          bevel=0.0055, seg=3)
    _rolled_edges(P, hy - 0.004, hz - 0.004, UNIT * 0.5, 0.0068, "steel")

    # the thickness step: a raised frame that also frames the livery panel
    fy, fz = 0.125, 0.215
    for sy in (-1.0, 1.0):
        P.box((UNIT + 0.004, sy * (fy + LIVERY_H * 0.5) * 0.5, 0.0),
              (0.010, fy - LIVERY_H * 0.5, 2.0 * fz), "steel", bevel=0.002, seg=1)
    for sz in (-1.0, 1.0):
        P.box((UNIT + 0.004, 0.0, sz * (fz + LIVERY_W * 0.5) * 0.5),
              (0.010, LIVERY_H, fz - LIVERY_W * 0.5), "steel", bevel=0.002, seg=1)

    # raised inset livery panel
    P.box((UNIT + 0.007, 0.0, 0.0), (0.014, LIVERY_H, LIVERY_W), "livery",
          bevel=0.004, seg=2)

    _gussets(P, hy, hz)
    P.ribs((-0.007, 0.0, 0.0), (0.0, PLATE_H - 0.03, PLATE_W - 0.04),
           3, "dark_metal", normal=0, run=1, h=0.014, w=0.018)
    _edge_bolts(P, UNIT, hy, hz)
    P.drain_slots((UNIT * 0.5, -hy + 0.004, -0.14), (UNIT * 0.5, -hy + 0.004, 0.14),
                  3, w=0.026, h=0.009, depth=UNIT - 0.002)
    P.seam((-0.001, -hy + 0.014, -hz + 0.012), (-0.001, -hy + 0.014, hz - 0.012))
    P.socket("socket_pivot", (0.0, 0.0, 0.0))
    return P


def build_plate_sloped(_spec=None):
    P = Part("plate_sloped", "armour")
    hy, hz = PLATE_H * 0.5, PLATE_W * 0.5
    thick = UNIT * 2.4
    prof = [(0.0, -hy), (thick, -hy), (UNIT, hy), (0.0, hy)]
    P.prism(prof, -hz, hz, "steel", bevel=0.0055, seg=3)

    # rolled lip on the thick leading edge, and along both ends
    P.cyl((thick * 0.5, -hy + 0.004, 0.0), (0, 0, 1), 0.0075, 2.0 * hz - 0.008,
          "steel", n=8, bevel=0.0)
    P.cyl((UNIT * 0.5, hy - 0.004, 0.0), (0, 0, 1), 0.0058, 2.0 * hz - 0.008,
          "steel", n=8, bevel=0.0)

    # the sloping outer face, as a line, so the step and the panel sit on it
    f0 = Vector((thick, -hy, 0.0))
    f1 = Vector((UNIT, hy, 0.0))
    d = (f1 - f0)
    nrm = Vector((d.y, -d.x, 0.0)).normalized()
    if nrm.x < 0.0:
        nrm = -nrm

    def on_face(t, out):
        return f0.lerp(f1, t) + nrm * out

    t0, t1 = 0.5 - LIVERY_H / PLATE_H * 0.5, 0.5 + LIVERY_H / PLATE_H * 0.5
    a = on_face(t0, 0.013)
    b = on_face(t1, 0.013)
    P.slab((a.x, a.y), (b.x, b.y), -LIVERY_W * 0.5, LIVERY_W * 0.5, 0.013,
           "livery", outward=(1.0, 0.0), bevel=0.004)
    # step frame around it
    for tt, hh in ((t0 - 0.085, 0.043), (t1 + 0.085, 0.043)):
        c = on_face(tt, 0.0065)
        P.slab((c.x, c.y), (c.x - 0.0009, c.y + hh), -0.215, 0.215, 0.007,
               "steel", outward=(1.0, 0.0), bevel=0.002, seg=1)
    for sz in (-1.0, 1.0):
        c = on_face(0.5, 0.0065)
        P.box((c.x, c.y, sz * 0.1863), (0.007, LIVERY_H, 0.0575), "steel",
              bevel=0.002, seg=1)

    _gussets(P, hy, hz)
    P.ribs((-0.007, 0.0, 0.0), (0.0, PLATE_H - 0.03, PLATE_W - 0.04),
           3, "dark_metal", normal=0, run=1, h=0.014, w=0.018)
    for sy, tt in ((-1.0, 0.045), (1.0, 0.955)):
        c = on_face(tt, 0.0)
        for z in (-0.150, 0.150):
            P.hardware_bolt((c.x, c.y, z), (1, 0, 0))
    for sz in (-1.0, 1.0):
        for tt in (0.29, 0.71):
            c = on_face(tt, 0.0)
            P.hardware_bolt((c.x, c.y, sz * (hz - 0.0175)), (1, 0, 0))
    P.drain_slots((thick * 0.5, -hy + 0.004, -0.14), (thick * 0.5, -hy + 0.004, 0.14),
                  3, w=0.026, h=0.009, depth=thick - 0.004)
    P.socket("socket_pivot", (0.0, 0.0, 0.0))
    return P


def build_plate_flat_hdpe(_spec=None):
    """The moulded plastic variant: one radiused piece, no rolled steel edge,
    no washers (moulded plastic takes countersunk fasteners), moulded ribs.
    Same 0.50 x 0.30 x 1 unit envelope and the same scaling rule as
    `plate_flat`, so P2 can swap it in wherever the face material is hdpe."""
    P = Part("plate_flat_hdpe", "armour")
    hy, hz = PLATE_H * 0.5, PLATE_W * 0.5
    P.box((UNIT * 0.5, 0.0, 0.0), (UNIT, PLATE_H, PLATE_W), "hdpe",
          bevel=0.0125, seg=4)
    # moulded raised livery panel, radiused like the rest of the moulding
    P.box((UNIT + 0.005, 0.0, 0.0), (0.012, LIVERY_H, LIVERY_W), "livery",
          bevel=0.006, seg=3)
    # moulding ribs on the inner face, both ways
    P.ribs((-0.006, 0.0, 0.0), (0.0, PLATE_H - 0.05, PLATE_W - 0.05),
           4, "hdpe", normal=0, run=1, h=0.012, w=0.014)
    P.ribs((-0.006, 0.0, 0.0), (0.0, PLATE_H - 0.05, PLATE_W - 0.05),
           2, "hdpe", normal=0, run=2, h=0.012, w=0.014)
    # countersunk fasteners: a chamfered seat and a flush head
    for sy in (-1.0, 1.0):
        for z in (-0.150, 0.150):
            P.cone((UNIT - 0.001, sy * (hy - 0.017), z), (1, 0, 0),
                   0.012, 0.0075, 0.004, "hdpe", n=8)
            P.cone((UNIT + 0.0025, sy * (hy - 0.017), z), (1, 0, 0),
                   0.0075, 0.0072, 0.0022, "dark_metal", n=6)
    for sz in (-1.0, 1.0):
        for y in (-0.062, 0.062):
            P.cone((UNIT - 0.001, y, sz * (hz - 0.020)), (1, 0, 0),
                   0.012, 0.0075, 0.004, "hdpe", n=8)
            P.cone((UNIT + 0.0025, y, sz * (hz - 0.020)), (1, 0, 0),
                   0.0075, 0.0072, 0.0022, "dark_metal", n=6)
    P.socket("socket_pivot", (0.0, 0.0, 0.0))
    return P


# ----------------------------------------------------------------- utility

def build_srimech(_spec=None):
    P = Part("srimech", "utility")
    # base bracket and the shoulder pin
    P.box((0.0, 0.020, 0.0), (0.090, 0.040, 0.110), "dark_metal", bevel=0.003, seg=2)
    for su in (-1, 1):
        for sv in (-1, 1):
            P.hardware_bolt((su * 0.032, 0.040, sv * 0.038), (0, 1, 0))
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
    for z in (-0.17, -0.057, 0.057, 0.17):
        P.hardware_bolt((0.030, 0.060, z), (1, 0, 0))
    P.drain_slots((-0.255, -0.064, -0.14), (-0.255, -0.064, 0.14), 3,
                  w=0.028, h=0.009, depth=0.016)
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
        P.ribs((0.0, -0.030, s * (0.27 + 0.008)), (0.52, 0.0, 0.0), 5, "hdpe",
               normal=2, run=1, h=s * 0.007, w=0.014)
        P.drain_slots((-0.24, -0.055, s * 0.27), (0.24, -0.055, s * 0.27), 4,
                      w=0.026, h=0.010, depth=0.020)
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
    for i in (1, 3):
        P.deck_tread(pts[i], pts[i + 1], -hw + 0.05, hw - 0.05, 2, 6, "steel")
    P.box((-0.024, 0.030, 0.0), (0.040, 0.170, 2 * hw - 0.03), "dark_metal",
          bevel=0.003, seg=2)
    for z in (-0.16, -0.055, 0.055, 0.16):
        P.hardware_bolt((-0.044, 0.030, z), (-1, 0, 0))
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
    for su in (-1, 1):
        for sv in (-1, 1):
            P.hardware_bolt((su * 0.070, 0.103, sv * 0.044), (0, 1, 0))
    P.ribs((0.0, 0.045, 0.0), (0.0, 0.0, 0.0), 0, "hdpe")
    P.cable_run([(-0.030, 0.128, 0.0), (0.040, 0.128, 0.0)], r=0.007, channel=False)
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
    for sx in (-1.0, 1.0):
        P.boss((sx * 0.092, 0.070, 0.060), (sx, 0, 0), 0.016, 0.006)
        P.boss((sx * 0.092, 0.070, -0.060), (sx, 0, 0), 0.016, 0.006)
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
    "plate_flat_hdpe": build_plate_flat_hdpe,
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


# ---------------------------------------------------------------------------
# Wave P (agent E).  The overcharge core and the reactive cassette plate.
# Requests in docs/wave-p-d2-notes.md section 5.
# ---------------------------------------------------------------------------

def build_overcharge_core(_spec=None):
    """The Level 90 utility part: faster spin up, harder hits, and it cooks the
    machine while the weapon is at full.  Roughly 0.20 by 0.12 by 0.10, on a
    deck mount, origin at the mount like every other utility part.

    IT HAS TO READ HOT, which is the whole brief for it, and "hot" here is not
    one glowing box: it is a pressure vessel with a `core_glow` seam you can see
    into, copper bus bars leaving it, a finned heat sink on top big enough to
    read as a heat sink, and a blow-off valve.  The emissive is deliberately
    kept to the seam, the bore and the two bus terminals, about 4 per cent of
    the part's surface: the glow threshold in the arena environment blooms
    anything emissive, so a part that is emissive all over becomes a white
    lozenge on a 6.9 inch OLED rather than a machine with a hot core in it."""
    P = Part("overcharge_core", "utility")
    # the casing: a split vessel, upper and lower halves with a seam between
    P.box((0.0, 0.028, 0.0), (0.185, 0.050, 0.115), "dark_metal",
          bevel=0.005, seg=2)
    P.box((0.0, 0.072, 0.0), (0.185, 0.034, 0.115), "steel", bevel=0.005, seg=2)
    # THE SEAM: the gap between the halves, lit from inside
    P.box((0.0, 0.054, 0.0), (0.171, 0.010, 0.121), "core_glow",
          bevel=0.002, seg=1)
    P.box((0.0, 0.054, 0.0), (0.191, 0.010, 0.101), "core_glow",
          bevel=0.002, seg=1)
    # the flange that clamps the two halves shut, with real fasteners
    for sz in (-1.0, 1.0):
        P.box((0.0, 0.054, sz * 0.063), (0.185, 0.022, 0.012), "titanium",
              bevel=0.003, seg=1)
        for x in (-0.062, 0.0, 0.062):
            P.hardware_bolt((x, 0.054, sz * 0.069), (0, 0, sz))
    # the bore in the nose: you can see the core itself down it
    P.ring((0.098, 0.042, 0.0), (1, 0, 0), 0.030, 0.019, 0.016, "titanium", n=14)
    P.cyl((0.100, 0.042, 0.0), (1, 0, 0), 0.018, 0.010, "core_glow", n=14)
    # heat sink on the roof: fins, because this is the part that cooks
    for i in range(9):
        z = (i - 4) * 0.0125
        P.box((-0.006, 0.100, z), (0.140, 0.022, 0.0052), "titanium",
              bevel=0.0012, seg=1)
    P.box((-0.006, 0.090, 0.0), (0.150, 0.008, 0.112), "steel",
          bevel=0.003, seg=1)
    # blow-off valve and its stack, aft
    P.cyl((-0.078, 0.098, 0.0), (0, 1, 0), 0.020, 0.022, "dark_metal",
          n=10, bevel=0.002)
    P.cone((-0.078, 0.114, 0.0), (0, 1, 0), 0.020, 0.013, 0.012, "steel", n=10)
    P.ring((-0.078, 0.122, 0.0), (0, 1, 0), 0.013, 0.008, 0.008, "copper", n=10)
    # copper bus bars off the back, and the pair of terminals
    for sz in (-1.0, 1.0):
        P.box((-0.108, 0.040, sz * 0.032), (0.046, 0.010, 0.016), "copper",
              bevel=0.0018, seg=1)
        P.cyl((-0.128, 0.040, sz * 0.032), (1, 0, 0), 0.011, 0.014,
              "dark_metal", n=8, bevel=0.002)
        P.cone((-0.136, 0.040, sz * 0.032), (-1, 0, 0), 0.008, 0.004, 0.008,
               "core_glow", n=8)
    P.cable_run([(-0.132, 0.040, 0.032), (-0.132, 0.040, -0.032)], r=0.006,
                channel=False)
    # the mount: feet on the deck, so it is bolted down rather than floating
    P.box((0.0, 0.006, 0.0), (0.200, 0.012, 0.125), "dark_metal",
          bevel=0.003, seg=1)
    for sx in (-1, 1):
        for sz in (-1, 1):
            P.hardware_bolt((sx * 0.082, 0.012, sz * 0.048), (0, 1, 0))
    P.socket("socket_pivot", (0.0, 0.0, 0.0))
    P.socket("socket_tip", (0.110, 0.042, 0.0))
    return P


def build_plate_flat_reactive(_spec=None):
    """Reactive armour: cassette blocks bolted to a backing plate, not a sheet.

    Same 0.50 by 0.30 by 1 unit envelope and the same scaling rule as
    `plate_flat`, so `bot.gd` swaps it in wherever the face material is
    `reactive` and nothing else changes.  The cassettes are on the plate's
    `steel` slot, which is the slot `Bot._add_panel_visual` overrides with the
    face material, so they take the reactive PBR set and the backing frame
    stays dark.  The gaps between the cassettes are the read: a spinner sees a
    grid of separate blocks, which is what tells the player why this plate is
    excellent against a spinner and poor against a saw."""
    P = Part("plate_flat_reactive", "armour")
    hy, hz = PLATE_H * 0.5, PLATE_W * 0.5
    # the backing plate: thinner than plate_flat, because the cassettes stand on it
    P.box((UNIT * 0.4, 0.0, 0.0), (UNIT * 0.8, PLATE_H, PLATE_W), "dark_metal",
          bevel=0.004, seg=2)
    _rolled_edges(P, hy - 0.004, hz - 0.004, UNIT * 0.4, 0.0062, "dark_metal")
    # the cassettes: three rows of five, each on its own standoff, with a gap
    cw, ch = 0.088, 0.078
    for iz in range(5):
        for iy in range(3):
            z = (iz - 2) * 0.097
            y = (iy - 1) * 0.092
            P.box((UNIT * 0.8 + 0.006, y, z), (0.012, ch, cw), "dark_metal",
                  bevel=0.002, seg=1)
            P.box((UNIT + 0.004, y, z), (0.014, ch - 0.008, cw - 0.008),
                  "steel", bevel=0.0035, seg=2)
            # the striker face, chamfered, and the two retaining screws
            P.box((UNIT + 0.012, y, z), (0.006, ch - 0.030, cw - 0.030),
                  "steel", bevel=0.003, seg=1)
            for sy in (-1.0, 1.0):
                P.bolt((UNIT + 0.013, y + sy * (ch * 0.5 - 0.013), z),
                       (1, 0, 0), r=0.0062)
    # one cassette in the middle row already fired: an empty box and a scorch
    P.box((UNIT * 0.8 + 0.008, 0.0, 0.0), (0.016, ch - 0.004, cw - 0.004),
          "dark_metal", bevel=0.002, seg=1)
    for sy in (-1.0, 1.0):
        P.box((UNIT + 0.002, sy * (ch * 0.5 - 0.006), 0.0),
              (0.010, 0.012, cw - 0.006), "titanium", bevel=0.002, seg=1)
    # the livery strip: a painted band down the frame, so the colour survives
    for sz in (-1.0, 1.0):
        P.box((UNIT * 0.8 + 0.004, 0.0, sz * (hz - 0.016)),
              (0.010, PLATE_H - 0.02, 0.026), "livery", bevel=0.003, seg=1)
    _gussets(P, hy, hz)
    P.ribs((-0.006, 0.0, 0.0), (0.0, PLATE_H - 0.03, PLATE_W - 0.04),
           3, "dark_metal", normal=0, run=1, h=0.014, w=0.018)
    P.drain_slots((UNIT * 0.4, -hy + 0.004, -0.14), (UNIT * 0.4, -hy + 0.004, 0.14),
                  3, w=0.026, h=0.009, depth=UNIT * 0.8 - 0.002)
    P.socket("socket_pivot", (0.0, 0.0, 0.0))
    return P


BUILDERS.update({
    "overcharge_core": build_overcharge_core,
    "plate_flat_reactive": build_plate_flat_reactive,
})
