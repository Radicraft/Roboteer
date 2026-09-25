"""Wave A hero build: the parts of the first machine in a new garage, rebuilt to
the reference study's target (docs/look/reference-study.md section 3, the
Recraft targets in docs/look/img2/).

    Tinribs = wedge + 4wd (wheel_standard x 4) + flipper + srimech
              + steel front, hdpe sides, polycarbonate rear, titanium top

Every part here is a v2 part (`rkit.Part(v2=True)`): 4 to 8 mm bevels that only
land on real corners, weighted normals, tangents, a second UV set and a baked
edge / AO / cavity mask.  The ids, sockets, origins and envelopes of the v1
parts they replace are kept EXACTLY (see docs/wave-a-models-notes.md section 2),
so no gameplay file, collision shape or socket reading changes.

New ids: the chassis-fitted armour plates `plate_wedge_<face>[_hdpe]`.  The v1
plates are one 0.50 x 0.30 m plate scaled non-uniformly onto every face, which
turns round bolts into ovals and a 6 mm bevel into a 2 mm one on a side plate
(scale 0.33 in Y).  A fitted plate is authored at its face's real size, at
scale 1, with its OUTER face at the origin (see `bot.gd _add_panel_visual`).
Original shapes only (brief v3 section 3).
"""

import math

from mathutils import Matrix, Vector

import rkit
from rkit import (Part, FLOOR_Y, WHEEL_RADIUS, WHEEL_WIDTH, BEVEL_V2, BEVEL_V2_MID,
                  BEVEL_V2_SMALL, SEG_V2, rot_pitch)

# The physics hull of the wedge (Arena/bot/part_meshes.gd).  The visual hull is
# built ON these numbers so the armour anchors, which come from them, land on
# the model's surfaces rather than floating off them.
#
# HERO HULL (2026-09-25, docs/wave-a-hull-notes.md): the wedge rides its own
# 0.14 m wheel, so its floor is DROP (30 mm) lower in bot space; every
# ground-game number moves down by DROP (unchanged against the floor), the tail
# is REAR_X, and the shell (the top plate's pods) crests at CREST_Y, which is
# now the COLLISION top too.
WEDGE_WHEEL_R = 0.14
DROP = WEDGE_WHEEL_R - 0.11
HALF_LEN = 0.45
REAR_X = -0.36
HALF_WID = 0.30
BODY_TOP = 0.07 - DROP
BODY_BOTTOM = -0.07 - DROP
SLOPE_START_X = 0.10
LIP_BOTTOM = -0.095 - DROP
LIP_TOP = -0.075 - DROP
CREST_Y = 0.224              # BotMeshes.CREST_Y: the top plate's outer face
PIVOT = (0.1115, 0.0977 - DROP)   # wedge.gd WEAPON_PIVOT
PLATE_PROUD = 0.022          # ChassisBase.PLATE_PROUD: outer face above the hull


# =============================================================== wheel

TYRE_R = WHEEL_RADIUS        # 0.110 over the tread blocks
CARCASS_R = 0.1035           # the tread base (pass 2: 7 mm deep blocks, was 8.5 mm lugs)
BEAD_R = 0.0690
HALF_W = 0.0380              # carcass half width.  Pass 2: 76 mm (was 60), a
                             # chunkier tyre; visual only, the wheel shape is
                             # the physics code's own cylinder


def build_wheel_standard(_spec=None):
    """A fat, square-shouldered tyre with a deep block tread, on a dark
    six-spoke dished rim.  Pass 2 (2026-09-25): the v2 chevron lugs were small
    and many (32), which at the menu distance read as fur, not as tread; the
    target's tyre is big blocks in two staggered rows across a wide crown.
    The wheel is symmetric in Z because the same model is fitted on both
    sides of the machine.  Contact radius 0.110 m exactly (contract 5.5)."""
    P = Part("wheel_standard", "drive", v2=True, bake_px=512)
    ax = (0, 0, 1)

    # carcass: squarer shoulders and a sidewall bulge, one closed lathe
    hw = HALF_W
    prof = [(BEAD_R, -hw + 0.002), (0.078, -hw - 0.0015), (0.090, -hw - 0.0020),
            (0.0985, -hw + 0.0006), (0.1020, -hw + 0.0040), (CARCASS_R, -hw + 0.0080),
            (CARCASS_R, hw - 0.0080), (0.1020, hw - 0.0040), (0.0985, hw - 0.0006),
            (0.090, hw + 0.0020), (0.078, hw + 0.0015), (BEAD_R, hw - 0.002)]
    P.lathe(prof, (0, 0, 0), ax, "rubber", n=32, closed=True)

    # block tread: 16 pitches, two rows staggered by half a pitch, each block
    # running from near the centre groove over the shoulder
    pitches = 16
    for k in range(pitches):
        for side in (-1.0, 1.0):
            th0 = 2.0 * math.pi * (k + (0.5 if side > 0 else 0.0)) / pitches
            _block(P, th0, side)

    # rim: a dark dished barrel with a thin machined lip proud of the bead
    P.lathe([(0.0560, -0.0350), (0.0620, -0.0395), (0.0720, -0.0395),
             (0.0752, -0.0385), (0.0752, -0.0350), (0.0690, -0.0310),
             (0.0690, 0.0310), (0.0752, 0.0350), (0.0752, 0.0385),
             (0.0720, 0.0395), (0.0620, 0.0395), (0.0560, 0.0350)],
            (0, 0, 0), ax, "dark_metal", n=28, closed=True)
    for side in (-1.0, 1.0):
        # the bright lip: a narrow ring on the flange face
        P.lathe([(0.0668, 0.0), (0.0742, 0.0), (0.0742, 0.0012), (0.0668, 0.0012)],
                (0, 0, side * 0.0392), (0, 0, side), "steel", n=24, closed=True)
    # six spokes, wide at the hub, dished 9 mm in from the flange
    for i in range(6):
        a = 2.0 * math.pi * i / 6.0
        u = Vector((math.cos(a), math.sin(a), 0.0))
        v = Vector((-math.sin(a), math.cos(a), 0.0))
        pts = [(0.020, -0.0125), (0.058, -0.0085), (0.060, 0.0), (0.058, 0.0085),
               (0.020, 0.0125)]
        P.outline(pts, (0, 0, 0.0300), u, v, (0, 0, 1), 0.060, "dark_metal",
                  bevel=0.0030, seg=1)
    # hub: a stepped boss each side, a steel bearing cap and six lug nuts
    P.lathe([(0.0, -0.0330), (0.0240, -0.0330), (0.0265, -0.0290),
             (0.0265, 0.0290), (0.0240, 0.0330), (0.0, 0.0330)],
            (0, 0, 0), ax, "dark_metal", n=24)
    for side in (-1.0, 1.0):
        sv = Vector((0, 0, side))
        P.lathe([(0.0, 0.0), (0.0140, 0.0), (0.0140, 0.0035), (0.0115, 0.0062),
                 (0.0060, 0.0078), (0.0, 0.0081)],
                sv * 0.0325, sv, "steel", n=14)
        for i in range(6):
            a = 2.0 * math.pi * i / 6.0 + math.pi / 6.0
            p = Vector((0.0195 * math.cos(a), 0.0195 * math.sin(a), side * 0.0325))
            P.hex_nut(p, sv, 0.0036, 0.0040, "steel")
    # valve stem on one face, just inside the flange
    P.cyl((0.0, 0.0640, 0.0), (0, 0, 1), 0.0024, 0.070, "dark_metal", n=6, bevel=0.0)
    return P


def _block(P, th0, side):
    """One tread block: from the centre groove to past the shoulder, its outer
    face ON r = TYRE_R (three segments across, so the flat chord never sags
    more than 0.1 mm under the axle; two staggered rows of 27 mm blocks on a
    43 mm pitch always put one under it) and its root sunk into the carcass.  The
    outer end drops off the shoulder, which is what makes the profile read as
    a tyre rather than a gear."""
    w = 0.0270                        # block length, around the tyre
    h_in, h_out = 0.0030, HALF_W + 0.0035
    rake = 0.0035                     # a slight sweep so the blocks are not a grid
    n_s = 3
    near = [(-w * 0.5 + w * i / n_s, h_in) for i in range(n_s + 1)]
    far = [(w * 0.5 - w * i / n_s + rake, h_out) for i in range(n_s + 1)]
    ring = near + far

    def at(sv, h, r):
        th = th0 + sv / TYRE_R
        edge = max(0.0, h - (HALF_W - 0.0080))
        rr = r - edge * 0.60
        return Vector((rr * math.cos(th), rr * math.sin(th), side * h))

    outer = [at(sv, h, TYRE_R) for sv, h in ring]
    inner = [at(sv, h, CARCASS_R - 0.003) for sv, h in ring]
    if side < 0:
        outer, inner = list(reversed(outer)), list(reversed(inner))
    P.loft([inner, outer], "rubber", bevel=0.0018, seg=1, min_angle=25.0)


# =============================================================== helpers

def cowl(P, pts, base, height, inset, mat, crown=None, axis=0, bevel=BEVEL_V2,
         seg=SEG_V2, crown_axis=2):
    """A raised shell panel: the outline `pts` (2D, in the two plate axes other
    than `axis`) sits on the plane `axis` = `base`; its top face is the same
    outline pulled `inset` towards the centroid and lifted by `height`.  With
    `crown` the top is lifted to `crown` along the edge nearest the plate's
    centre line (|coordinate `crown_axis`| small) and to `height` at the outer
    edge, so two mirrored halves make a ridged cowl.  The sloped sides are what
    turn a flat inset panel into a shell that catches a strip light."""
    others = [i for i in range(3) if i != axis]
    cu = sum(p[0] for p in pts) / len(pts)
    cv = sum(p[1] for p in pts) / len(pts)
    lo_ring, hi_ring = [], []
    span = max(abs(p[others.index(crown_axis)]) for p in pts) if crown is not None else 1.0
    lo = min(abs(p[others.index(crown_axis)]) for p in pts) if crown is not None else 0.0
    for p in pts:
        du, dv = p[0] - cu, p[1] - cv
        L = math.hypot(du, dv)
        k = (L - inset) / L if L > 1e-9 else 1.0
        q = (cu + du * k, cv + dv * k)
        h = height
        if crown is not None:
            c = abs(q[others.index(crown_axis)])
            f = (c - lo) / max(span - lo, 1e-6)
            h = crown + (height - crown) * min(max(f, 0.0), 1.0)
        a = Vector((0.0, 0.0, 0.0))
        b = Vector((0.0, 0.0, 0.0))
        a[axis], a[others[0]], a[others[1]] = base, p[0], p[1]
        b[axis], b[others[0]], b[others[1]] = base + h, q[0], q[1]
        lo_ring.append(a)
        hi_ring.append(b)
    P.loft([lo_ring, hi_ring], mat, bevel=bevel, seg=seg)


def cut_rect(hu, hv, c, cu=None):
    """A rectangle +-hu x +-hv with its corners cut at 45 degrees by `c`
    (anticlockwise).  `cu` gives the two +u corners their own cut."""
    c2 = c if cu is None else cu
    return [(-hu + c, -hv), (hu - c2, -hv), (hu, -hv + c2), (hu, hv - c2),
            (hu - c2, hv), (-hu + c, hv), (-hu, hv - c), (-hu, -hv + c)]


def base_plate(P, hu, hv, c, t, mat, bevel=BEVEL_V2, seg=SEG_V2, back=0.004):
    """The plate body in a fitted plate's own frame: outer face ON x = 0,
    +X outward, `t` thick inward, edges chamfered by `back`."""
    P.outline(cut_rect(hu, hv, c), (0, 0, 0), (0, 1, 0), (0, 0, 1), (1, 0, 0),
              t, mat, bevel=bevel, seg=seg, back=back)


# =============================================================== chassis

def build_wedge(spec):
    """The starter wedge.  A lofted, chamfered powder-coat hull built on the
    physics hull's own numbers, livery sponsons between the wheels that the
    side plates bolt to, machined axle bosses, the flipper's hinge brackets on
    the deck, a hardened nose bar and skid rails.  The deck under the top plate
    keeps the control core (brief section 6: visible once the lid comes off)."""
    import parts_chassis as pc
    P = Part("wedge", "chassis", v2=True, bake_px=1024)
    # v1's numbers, so every socket lands exactly where it always has
    base, top = pc.base_top(spec)                   # -0.09 .. 0.09
    deck_v1 = top - rkit.PLATE_T
    hw = pc.hull_half_width(spec)                   # 0.244

    def section(x, yb, yt, ct, cb):
        ct = min(ct, (yt - yb) * 0.35)
        cb = min(cb, (yt - yb) * 0.25)
        return [Vector((x, yb + cb, -hw)), Vector((x, yb, -hw + cb)),
                Vector((x, yb, hw - cb)), Vector((x, yb + cb, hw)),
                Vector((x, yt - ct, hw)), Vector((x, yt, hw - ct)),
                Vector((x, yt, -hw + ct)), Vector((x, yt - ct, -hw))]

    # hull: rear, the ramp break, the lip.  The rear drops a little under the
    # tail (an anti-spinner undercut) and the top is the physics BODY_TOP.
    P.loft([section(REAR_X, -0.060 - DROP, BODY_TOP, 0.030, 0.022),
            section(REAR_X + 0.05, -0.078 - DROP, BODY_TOP, 0.030, 0.014),
            section(SLOPE_START_X, -0.080 - DROP, BODY_TOP, 0.030, 0.014),
            section(HALF_LEN - 0.012, LIP_BOTTOM + 0.001, LIP_TOP - 0.002, 0.004, 0.003)],
           "dark_metal")

    # hardened nose bar across the lip, a chamfered wedge section
    lip = [Vector((HALF_LEN - 0.020, LIP_BOTTOM, 0)), Vector((HALF_LEN + 0.004, LIP_BOTTOM, 0)),
           Vector((HALF_LEN - 0.020, LIP_TOP + 0.004, 0))]
    P.loft([[p + Vector((0, 0, -hw + 0.004)) for p in lip],
            [p + Vector((0, 0, hw - 0.004)) for p in lip]], "titanium",
           bevel=BEVEL_V2_SMALL, seg=2)

    # sponsons between the wheels: the side plates bolt to their faces.  A
    # trapezoid in side view so the ends clear the tyres, livery, chamfered.
    for s in (-1.0, 1.0):
        prof = [(-0.080, -0.058 - DROP), (0.096, -0.058 - DROP), (0.104, -0.040 - DROP),
                (0.096, 0.062 - DROP), (-0.072, 0.062 - DROP), (-0.088, 0.040 - DROP)]
        z0, z1 = s * (hw - 0.010), s * (0.300 - 0.001)
        ring0 = [Vector((x, y, z0)) for x, y in prof]
        ring1 = []
        cx = sum(p[0] for p in prof) / len(prof)
        cy = sum(p[1] for p in prof) / len(prof)
        for x, y in prof:
            ring1.append(Vector((cx + (x - cx) * 0.97, cy + (y - cy) * 0.90, z1)))
        P.loft([ring0, ring1], "livery", bevel=BEVEL_V2, seg=SEG_V2)
        # a seam line: the sponson is two pressings with a V gap between
        P.box((0.008, -DROP, z1 - s * 0.020), (0.004, 0.118, 0.042), "dark_metal",
              bevel=0.0012, seg=1)
        # button bolts on the sponson's top chamfer strip
        for x in (-0.055, 0.070):
            P.button_bolt((x, 0.0625 - DROP, s * (hw + 0.030)), (0, 1, 0), r=0.0048, n=8)

    # axle bosses: a filleted collar from the flank out to the hub, bolt ring
    done = set()
    for (sx, sz) in spec["wheel_slots"]["6wd"] + spec["wheel_slots"]["4wd"] + \
            spec["wheel_slots"]["2wd"]:
        key = (round(sx, 3), round(sz, 3))
        if key in done:
            continue
        done.add(key)
        s = 1.0 if sz > 0 else -1.0
        a = Vector((0, 0, s))
        root = Vector((sx, 0.0, s * (hw - 0.004)))
        P.lathe([(0.0, 0.0), (0.040, 0.0), (0.040, 0.004), (0.031, 0.010),
                 (0.027, 0.020), (0.027, abs(sz) - hw - 0.034), (0.020, abs(sz) - hw - 0.030),
                 (0.0, abs(sz) - hw - 0.030)], root, a, "dark_metal", n=16)
        P.lathe([(0.0, 0.0), (0.012, 0.0), (0.012, abs(sz) - hw - 0.004),
                 (0.0, abs(sz) - hw - 0.004)], root, a, "steel", n=10)
        for i in range(4):
            ang = math.pi / 4.0 + i * math.pi / 2.0
            P.hex_nut(root + Vector((0.0328 * math.cos(ang), 0.0328 * math.sin(ang), 0))
                      + a * 0.004, a, 0.0032, 0.0030, "steel")

    # flipper hinge brackets on the deck, each ending in a knuckle on the pivot
    pv = PIVOT
    for s in (-1.0, 1.0):
        z0, z1 = s * 0.052, s * 0.158
        prof = [(0.062, BODY_TOP - 0.004), (0.150, BODY_TOP - 0.030),
                (0.150, pv[1] - 0.004), (pv[0] + 0.010, pv[1] + 0.017),
                (pv[0] - 0.018, pv[1] + 0.012), (0.070, BODY_TOP + 0.012)]
        P.loft([[Vector((x, y, z0)) for x, y in prof],
                [Vector((x, y, z1)) for x, y in prof]], "steel",
               bevel=BEVEL_V2_MID, seg=SEG_V2)
        P.lathe([(0.0, 0.0), (0.019, 0.0), (0.019, abs(z1 - z0) - 0.004),
                 (0.0, abs(z1 - z0) - 0.004)], (pv[0], pv[1], z0 + s * 0.002),
                (0, 0, s), "steel", n=16)
        for x in (0.080, 0.132):
            P.button_bolt((x, BODY_TOP + 0.010 if x < 0.1 else BODY_TOP - 0.008,
                           (z0 + z1) * 0.5), (0, 1, 0), r=0.0045, n=8, washer=None)

    # deck under the top plate: two pressed panels round the control core
    bay = (-0.25, -0.10, -0.075, 0.075)
    for (x0, x1) in ((REAR_X + 0.02, -0.256), (-0.094, 0.050)):
        P.outline(cut_rect((x1 - x0) * 0.5, hw - 0.022, 0.018),
                  ((x0 + x1) * 0.5, BODY_TOP + 0.003, 0.0), (1, 0, 0), (0, 0, 1),
                  (0, 1, 0), 0.006, "dark_metal", bevel=0.002, seg=2, back=0.0015)
    pc.core_bay(P, bay, BODY_TOP + 0.003, depth=0.030)

    # skid rails under the hull and a rear bumper bar below the rear plate
    for s in (-1.0, 1.0):
        rail = [Vector((REAR_X + 0.04, -0.060 - 0.016 - DROP, 0)),
                Vector((0.30, -0.080 - 0.016 - DROP, 0)),
                Vector((0.30, -0.080 - DROP, 0)), Vector((REAR_X + 0.04, -0.060 - DROP, 0))]
        P.loft([[p + Vector((0, 0, s * 0.150 - 0.012)) for p in rail],
                [p + Vector((0, 0, s * 0.150 + 0.012)) for p in rail]], "titanium",
               bevel=BEVEL_V2_SMALL, seg=2)
    P.box((REAR_X - 0.010, -0.066 - DROP, 0.0), (0.020, 0.014, 0.40), "steel",
          bevel=BEVEL_V2_SMALL, seg=2)

    # motor cable looms from the sponsons into the hull, just visible behind
    # the tyres
    for s in (-1.0, 1.0):
        P.hose([(0.20, 0.030 - DROP, s * (hw + 0.002)), (0.15, 0.045 - DROP, s * (hw + 0.012)),
                (0.10, 0.050 - DROP, s * (hw + 0.016))], 0.0042, "rubber", n=6, per_span=4,
               fittings="dark_metal")
        P.hose([(-0.20, 0.030 - DROP, s * (hw + 0.002)), (-0.14, 0.045 - DROP, s * (hw + 0.012)),
                (-0.085, 0.050 - DROP, s * (hw + 0.016))], 0.0042, "rubber", n=6, per_span=4,
               fittings="dark_metal")

    # pass 2: the drive motors, exposed on the sponson tops under the shell
    # overhang (the top plate's pods stand over them from y 0.119).  Finned
    # cans with machined end bells and a strap each: the mechanicals that show
    # between the panels in the target.  Generic to every drive.
    for s in (-1.0, 1.0):
        zc = s * 0.236
        for (xa, d) in ((-0.040, -1.0), (0.030, 1.0)):
            a = Vector((d, 0.0, 0.0))
            c = Vector((xa, BODY_TOP + 0.024, zc))
            fins = [(0.0, 0.0), (0.0185, 0.0), (0.0195, 0.004)]
            for k in range(3):
                z0 = 0.016 + k * 0.022
                fins += [(0.0205, z0), (0.0228, z0 + 0.002), (0.0228, z0 + 0.010),
                         (0.0205, z0 + 0.012)]
            fins += [(0.0205, 0.084), (0.0190, 0.088), (0.0, 0.088)]
            P.lathe(fins, c, a, "dark_metal", n=12)
            P.lathe([(0.0, 0.0), (0.0175, 0.0), (0.0175, 0.012), (0.0150, 0.016),
                     (0.0070, 0.018), (0.0, 0.018)], c + a * 0.088, a, "steel", n=12)
            strap = c + a * 0.045
            P.lathe([(0.0230, -0.006), (0.0255, -0.006), (0.0255, 0.006),
                     (0.0230, 0.006)], strap, a, "steel", n=12, closed=True)
            P.hex_nut(strap + Vector((0.0, 0.0255, 0.0)), (0, 1, 0), 0.0035, 0.004,
                      "steel")

    # sockets: the hero hull's own (the engine reads wheels from the catalogue
    # and pins the front weapon and the srimech in wedge.gd; these are the same
    # numbers, for the stage, the tools and any reader of the model)
    ws = spec["wheel_slots"]
    for nm, sl in zip(pc.WHEEL_NAMES_6, ws["6wd"]):
        P.socket("socket_wheel_" + nm, (sl[0], 0.0, sl[1]))
    for nm, sl in zip(pc.WHEEL_NAMES_4, ws["4wd"]):
        P.socket("socket_wheel_4wd_" + nm, (sl[0], 0.0, sl[1]))
    for nm, sl in zip(pc.WHEEL_NAMES_2, ws["2wd"]):
        P.socket("socket_wheel_2wd_" + nm, (sl[0], 0.0, sl[1]))
    mid = (BODY_BOTTOM + BODY_TOP) * 0.5
    P.socket("socket_armour_front", (HALF_LEN, mid, 0.0))
    P.socket("socket_armour_rear", (REAR_X, mid, 0.0))
    P.socket("socket_armour_sides_l", (0.0, mid, -HALF_WID))
    P.socket("socket_armour_sides_r", (0.0, mid, HALF_WID))
    P.socket("socket_armour_top", (-0.15, CREST_Y, 0.0))
    P.socket("socket_weapon_front", (PIVOT[0], PIVOT[1], 0.0))
    P.socket("socket_weapon_top", (0.05, CREST_Y, 0.0))
    P.socket("socket_utility_0", (-0.27, CREST_Y, 0.0))
    P.socket("socket_utility_1", (0.2475, BODY_BOTTOM + 0.01, 0.0))
    P.socket("socket_srimech", (-0.30, BODY_TOP + 0.01, 0.0))
    return P


# =============================================================== flipper

#: flipper.gd pitches the model back by MODEL_PITCH_BIAS (6.5 degrees) because
#: the v1 plate was authored sloping 6.5 degrees in its own frame.  The v2 arm
#: is authored level, in the ARM's frame, and turned by the same -6.5 degrees
#: here, so flipper.gd and its signed-off numbers do not change.
MODEL_PITCH_BIAS = 6.5
ARM_LEN = 0.44               # flipper.gd FLIPPER_LEN
ARM_HALF_W = 0.25            # inside FLIPPER_WIDTH 0.52


def build_flipper(spec):
    """A wide flipping plate in brushed titanium with a hardened, bolted lip,
    knuckle hinge, underside ribs and the ram under it.  The gas system (bottle
    in its cradle, regulator and gauge, braided line to the valve block) is a
    SEPARATE node, `mount`, authored in bot orientation relative to the pivot,
    so flipper.gd can hang it on the chassis: a gas bottle does not ride on the
    arm of a real machine and swinging it through the deck read as a toy."""
    P = Part("flipper", "weapon", v2=True, bake_px=1024)
    reach = spec["reach"]
    R = rot_pitch(-MODEL_PITCH_BIAS)

    # --- the arm (authored level in the arm frame, turned at the end) -------
    # A lofted sheet: chamfered top edges, a waist at the hinge end, cut
    # corners at the nose, and a 4 degree press-brake fold at KINK so the two
    # halves catch the strip lights at different angles instead of reading as
    # one flat slab.
    top_y, t = 0.028, 0.014
    x0, x1 = 0.024, ARM_LEN - 0.004
    KINK, BEND = 0.200, 4.0

    def sect(x, w, c=0.005):
        yb = top_y - t
        return [Vector((x, yb, -w)), Vector((x, yb, w)), Vector((x, top_y - c, w)),
                Vector((x, top_y, w - c)), Vector((x, top_y, -w + c)),
                Vector((x, top_y - c, -w))]

    P.loft([sect(x0, 0.205), sect(0.110, ARM_HALF_W), sect(KINK, ARM_HALF_W),
            sect(x1 - 0.034, ARM_HALF_W), sect(x1, ARM_HALF_W - 0.034)],
           "titanium", bevel=BEVEL_V2, seg=SEG_V2)
    # a bolted doubler plate over the working end, stepped 3 mm proud
    P.outline(cut_rect(0.075, 0.170, 0.030), ((KINK + x1 - 0.06) * 0.5 + 0.004,
              top_y + 0.003, 0.0), (1, 0, 0), (0, 0, 1), (0, 1, 0), 0.003,
              "titanium", bevel=0.0025, seg=2, back=0.0015)
    # pass 2: the doubler's fasteners are raised button heads (the target's
    # wedge plate reads by its bolt row; flush heads vanished at menu range)
    for x in (KINK + 0.030, x1 - 0.085):
        for z in (-0.140, -0.070, 0.0, 0.070, 0.140):
            P.button_bolt((x, top_y + 0.0030, z), (0, 1, 0), r=0.0060, mat="steel", n=8)
    # hardened lip: a tapered bar bolted along the leading edge
    lip = [Vector((x1 - 0.050, top_y - t, 0)), Vector((x1 - 0.050, top_y + 0.004, 0)),
           Vector((x1 - 0.004, top_y + 0.002, 0)), Vector((x1 + 0.010, top_y - t + 0.002, 0))]
    P.loft([[p + Vector((0, 0, -ARM_HALF_W + 0.040)) for p in lip],
            [p + Vector((0, 0, ARM_HALF_W - 0.040)) for p in lip]], "steel",
           bevel=BEVEL_V2_MID, seg=2)
    for z in (-0.18, -0.09, 0.0, 0.09, 0.18):
        P.countersunk((x1 - 0.027, top_y + 0.0035, z), (0, 1, 0), r=0.0055, mat="steel")
    # two rows of countersunk fasteners over the ribs, and a lightening panel
    for z in (-0.120, 0.120):
        for x in (0.07, 0.15):
            P.countersunk((x, top_y + 0.0002, z), (0, 1, 0), r=0.0055, mat="steel")
    # underside ribs, tapering to the tip, and a cross member at the hinge
    for z in (-0.120, 0.0, 0.120):
        prof = [(0.020, top_y - t), (x1 - 0.06, top_y - t), (0.070, top_y - t - 0.030),
                (0.020, top_y - t - 0.030)]
        P.loft([[Vector((x, y, z - 0.007)) for x, y in prof],
                [Vector((x, y, z + 0.007)) for x, y in prof]], "dark_metal",
               bevel=BEVEL_V2_SMALL, seg=2)
    # hinge: three knuckles on the arm, the pin, the pin nuts
    for (za, zb) in ((-0.250, -0.166), (-0.044, 0.044), (0.166, 0.250)):
        P.lathe([(0.0, 0.0), (0.017, 0.0), (0.0185, 0.0015), (0.0185, zb - za - 0.0015),
                 (0.017, zb - za), (0.0, zb - za)], (0, 0, za), (0, 0, 1),
                "titanium", n=18)
        P.box((0.016, 0.012, (za + zb) * 0.5), (0.030, 0.026, zb - za - 0.004),
              "titanium", bevel=BEVEL_V2_MID, seg=2)
    P.lathe([(0.0, -0.262), (0.0085, -0.262), (0.0085, 0.262), (0.0, 0.262)],
            (0, 0, 0), (0, 0, 1), "steel", n=10)
    for s in (-1.0, 1.0):
        P.hex_nut((0, 0, s * 0.2515), (0, 0, s), 0.0125, 0.009, "steel")
    # the ram under the plate: clevis on the arm, barrel going back into the hull
    P.lathe([(0.0, 0.0), (0.021, 0.0), (0.023, 0.004), (0.023, 0.100), (0.021, 0.104),
             (0.0, 0.104)], (0.160, -0.004, 0.0), (-0.96, -0.28, 0.0), "steel", n=16)
    P.lathe([(0.0, 0.0), (0.010, 0.0), (0.010, 0.060), (0.0, 0.060)],
            (0.205, 0.010, 0.0), (-0.96, -0.28, 0.0), "titanium", n=10)
    P.box((0.215, 0.008, 0.0), (0.030, 0.020, 0.030), "dark_metal",
          bevel=BEVEL_V2_SMALL, seg=2)
    # pass 2: turned-down side flanges.  The 14 mm sheet read as a thin card
    # from three quarters; a 34 mm folded edge makes it read as a thick plate
    # without touching the slope under it (the flanges ride outside the ribs,
    # inside the 0.52 m collision arm, clear of the front tyres' inner faces)
    for s_ in (-1.0, 1.0):
        prof = [(0.112, top_y - 0.002), (x1 - 0.040, top_y - 0.002),
                (x1 - 0.058, top_y - 0.030), (0.150, top_y - 0.034),
                (0.112, top_y - 0.020)]
        zc = s_ * (ARM_HALF_W - 0.009)
        P.loft([[Vector((x, y, zc - 0.005)) for x, y in prof],
                [Vector((x, y, zc + 0.005)) for x, y in prof]], "titanium",
               bevel=BEVEL_V2_MID, seg=SEG_V2)
        for x in (0.160, 0.240, 0.320, 0.380):
            P.button_bolt((x, top_y - 0.017, s_ * (ARM_HALF_W - 0.0035)), (0, 0, s_),
                          r=0.0048, mat="steel", n=8, washer=None)
    # the fold, then everything authored so far into the model frame
    pivot_k = Vector((KINK, top_y, 0.0))
    Rk = rot_pitch(-BEND)
    for v in P.bm.verts:
        if v.co.x > KINK + 1e-5:
            v.co = pivot_k + (Rk @ (v.co - pivot_k))
    for v in P.bm.verts:
        v.co = R @ v.co

    # --- the gas system: its own node, bot orientation, relative to the pivot
    P.use("mount")
    zb = 0.140                    # off the centre line: the srimech lives there
    by = 0.030                    # bottle axis height above the pivot
    bx0, bx1 = -0.325, -0.150
    r = 0.033
    L = bx1 - bx0
    bottle = [(0.0, 0.0), (0.010, 0.0), (0.010, 0.010), (0.020, 0.016),
              (0.029, 0.026), (r, 0.040), (r, L - 0.040), (0.029, L - 0.026),
              (0.020, L - 0.012), (0.0, L - 0.008)]
    P.lathe(bottle, (bx1, by, zb), (-1, 0, 0), "steel", n=20)
    for x in (bx0 + 0.045, bx1 - 0.045):
        P.lathe([(r + 0.0005, -0.009), (r + 0.004, -0.009), (r + 0.004, 0.009),
                 (r + 0.0005, 0.009)], (x, by, zb), (1, 0, 0), "dark_metal", n=20,
                closed=True)
        P.outline([(-0.012, -0.040), (0.012, -0.040), (0.012, 0.030), (-0.012, 0.030)],
                  (x, by - r - 0.002, zb), (1, 0, 0), (0, 0, 1), (0, 1, 0), 0.006,
                  "dark_metal", bevel=0.002, seg=2)
        P.button_bolt((x, by - r - 0.002, zb + 0.030), (0, 1, 0), r=0.004, n=8,
                      washer=None)
        P.button_bolt((x, by - r - 0.002, zb - 0.034), (0, 1, 0), r=0.004, n=8,
                      washer=None)
    # regulator on the neck, a gauge on it, the valve block at the hinge
    reg = Vector((bx1 + 0.010, by, zb))
    P.box(reg + Vector((0.016, 0, 0)), (0.030, 0.034, 0.030), "steel",
          bevel=BEVEL_V2_SMALL, seg=2)
    P.lathe([(0.0, 0.0), (0.013, 0.0), (0.013, 0.010), (0.011, 0.012), (0.0, 0.012)],
            reg + Vector((0.016, 0.017, 0)), (0, 1, 0), "dark_metal", n=14)
    P.lathe([(0.0, 0.0), (0.010, 0.0), (0.0, 0.0012)],
            reg + Vector((0.016, 0.0292, 0)), (0, 1, 0), "polycarbonate", n=14)
    valve = Vector((-0.050, -0.006, 0.060))
    P.box(valve, (0.030, 0.026, 0.040), "dark_metal", bevel=BEVEL_V2_SMALL, seg=2)
    P.hex_nut(valve + Vector((0, 0.013, 0)), (0, 1, 0), 0.007, 0.006, "steel")
    P.hose([reg + Vector((0.032, 0.0, 0.0)), reg + Vector((0.060, 0.004, -0.030)),
            valve + Vector((-0.010, 0.012, 0.028)), valve + Vector((0.0, 0.002, 0.020))],
           0.0055, "rubber", n=8, per_span=6, fittings="steel")
    P.hose([valve + Vector((0.015, 0.0, -0.012)), valve + Vector((0.040, -0.010, -0.030)),
            Vector((0.010, -0.020, 0.030))], 0.0045, "rubber", n=8, per_span=5,
           fittings="steel")

    P.socket("socket_pivot", (0.0, 0.0, 0.0))
    P.socket("socket_tip", (reach + 0.012, -0.030, 0.0))
    return P


# =============================================================== fitted plates
#
# Frame (bot.gd, ChassisBase.armour_socket): +X OUTWARD, the outer face on
# x = 0 (bot.gd offsets the model by half the box so this holds at every
# thickness), y and z in plane.  The visible depth is ChassisBase.PLATE_PROUD,
# 22 mm, whatever the catalogue thickness: thicker armour grows INWARD into the
# hull, so a fitted plate is authored once, at scale 1.

T_VIS = PLATE_PROUD


def _bolt_row(P, pts, hdpe):
    for (y, z) in pts:
        if hdpe:
            # titanium, never `steel`: bot.gd binds the FACE material to a
            # plate's `steel` slot, and an hdpe plate's face is its `hdpe` slot
            P.countersunk((0.0002, y, z), (1, 0, 0), r=0.0058, mat="titanium")
        else:
            P.button_bolt((0.0, y, z), (1, 0, 0), r=0.0060, mat="titanium", n=8)


def _plate(ident, hy, hz, corner, hdpe, bake_px=512):
    P = Part(ident, "armour", v2=True, bake_px=bake_px)
    if hdpe:
        base_plate(P, hy, hz, corner, T_VIS, "hdpe", bevel=0.009, seg=4, back=0.006)
    else:
        base_plate(P, hy, hz, corner, T_VIS, "steel")
    return P


#: Pass 2 (2026-09-25): the lid carries the machine's SHELL.  The face-off read
#: as a low flat box because nothing rose above the tyres; the target
#: (docs/look/img2/menu-b-faceoff.webp) is a layered armour shell standing over
#: the wheels with the mechanicals exposed between its halves.  So the lid now
#: carries two sculpted shoulder pods, bot-space numbers below:
POD_IN = 0.188          # inner wall (the channel between the pods: srimech +-0.066,
                        # the flipper's gas bottle at z 0.14 +-0.033 sits inside it)
POD_OUT = 0.338         # outer wall: flush with the tyre's outer face
POD_UNDER = 0.149       # underside of the overhang: above every tyre and belt top
                        # (hero hull: wheel tops are y 0.140)
POD_CREST = CREST_Y     # the ridge, 8.4 cm above the tyres.  Hero hull pass: this
                        # IS the collision top now (the top plate's box has its
                        # outer face here, wedge.gd TOP_ANCHOR), so a hit lands on
                        # the shell where it is drawn and, inverted, the machine
                        # rests on its pods (docs/wave-a-hull-notes.md)
TOP_Y = CREST_Y         # the lid's frame origin: the top plate's outer face, bot y
TOP_X = -0.15           # wedge.gd TOP_ANCHOR.x
DECK_Y = BODY_TOP + 0.012   # the deck the pods and the channel stand on


def _lid(bx, by, bz):
    """Bot space -> the top plate's frame (+X up, +Y to the bot's rear)."""
    return Vector((by - TOP_Y, -(bx - TOP_X), bz))


def _pod_profile(crest, inset=0.0, drop=0.0, zi=None, foot=None, under=None):
    """A shoulder pod's cross-section, (bot z, bot y) pairs on the +Z side: an
    overhang whose underside clears the tyres, a vertical outer face, a
    chamfer, then an armour facet rising INWARD to a ridge near the inner wall,
    which drops steeply to the deck.  That is the target's shell: the high
    line is over the machine's shoulder, the outer facets fall away to the
    wheels.  `inset`/`drop` shrink an end section (chamfered prow and tail);
    `zi`/`foot` move the inner wall: on the lid it stands on the deck (foot =
    TOP_Y); forward of the lid the pod is a narrow fender over the front wheel,
    outside the flipper arm's plane (|z| > 0.25), its underside at POD_UNDER."""
    zi = (POD_IN if zi is None else zi) + inset
    zo = POD_OUT - inset
    c = crest - drop
    under = POD_UNDER if under is None else under
    co = max(c - 0.040, under + 0.012)
    foot = DECK_Y if foot is None else foot
    foot = min(foot, under)
    z1 = max(0.241, zi + 0.020)
    z2 = max(0.262, zi + 0.040)
    zr = zi + min(0.045, (zo - zi) * 0.45)
    return [(zi, foot), (z1, foot), (z2, under), (zo, under), (zo, co),
            (zo - 0.018, co + 0.010), (zr, c),
            (zi + min(0.012, (zr - zi) * 0.4), max(c - 0.012, foot + 0.010)),
            (zi, max(c - 0.034, foot + 0.006))]


def _ring(bx, pts, s):
    ring = [_lid(bx, y, s * z) for (z, y) in pts]
    return ring if s > 0 else list(reversed(ring))


def _offset(pts, d, inside):
    """Offset an open 2D polyline by `d` away from the point `inside`."""
    out = []
    for i, p in enumerate(pts):
        nz = ny = 0.0
        for a, b in ((pts[i - 1], p) if i else (None, None), (p, pts[i + 1]) if i < len(pts) - 1 else (None, None)):
            if a is None:
                continue
            tz, ty = b[0] - a[0], b[1] - a[1]
            L = math.hypot(tz, ty)
            cz, cy = -ty / L, tz / L
            mz, my = (a[0] + b[0]) * 0.5 - inside[0], (a[1] + b[1]) * 0.5 - inside[1]
            if cz * mz + cy * my < 0:
                cz, cy = -cz, -cy
            nz, ny = nz + cz, ny + cy
        L = math.hypot(nz, ny)
        out.append((p[0] + nz / L * d, p[1] + ny / L * d))
    return out


def _cap_profile(crest):
    """The overlapping upper pressing: a 9 mm skin over the pod's outer face,
    chamfer, facet and ridge, 7 mm proud, ending in a lip 28 mm down the
    outer face.  It stops mid-pod, so the shell reads as two pressings."""
    pod = _pod_profile(crest)
    zo, co = pod[4]
    skin = [(zo, co - 0.026), pod[4], pod[5], pod[6],
            (pod[6][0] - 0.010, pod[6][1] - 0.008)]
    inside = ((POD_IN + POD_OUT) * 0.5, (POD_UNDER + crest) * 0.5)
    return _offset(skin, 0.007, inside) + list(reversed(_offset(skin, -0.002, inside)))


def build_plate_wedge_top(hdpe=False):
    """The lid: a titanium (or HDPE) deck plate carrying the machine's shell,
    two sculpted livery shoulder pods over the flanks and the rear wheels, each
    with an overlapping upper pressing, a dark mounting rail and bolts.  The
    deck between them stays open: the srimech, the flipper's gas bottle and a
    speed controller sit in that channel, which is the "mechanicals between
    the panels" of the target.  Local +Y points at the bot's REAR
    (Basis(BACK, 90 degrees)); plate x = bot y - TOP_Y (see `_lid`)."""
    P = Part("plate_wedge_top" + ("_hdpe" if hdpe else ""), "armour", v2=True, bake_px=1024)
    # the deck plate the pods stand on, down in the channel (the plate's frame
    # origin is the crest; the plate's outer face in physics is there)
    dx = DECK_Y - TOP_Y
    if hdpe:
        P.outline(cut_rect(0.190, 0.200, 0.030), (dx, 0, 0), (0, 1, 0), (0, 0, 1), (1, 0, 0),
                  0.012, "hdpe", bevel=0.006, seg=3, back=0.004)
    else:
        P.outline(cut_rect(0.190, 0.200, 0.030), (dx, 0, 0), (0, 1, 0), (0, 0, 1), (1, 0, 0),
                  0.012, "steel", bevel=BEVEL_V2_MID, seg=SEG_V2, back=0.003)
    # (bot x, crest, inset, drop): a chamfered prow, a long level back, a tail
    # (bot x, crest, inset, drop, inner wall, foot): a chamfered tail, a long
    # level back over the rear wheel, then the inner wall sweeps out past the
    # flipper arm's plane and the pod runs on as a fender over the front wheel,
    # falling toward a chamfered prow (the target's shell slopes to the front)
    # The underside wraps DOWN in front of the front wheel and behind the rear
    # one (a mudguard hugging the tyre), clear of every wheel slot's tyre
    # (4wd 0.25 / fl 0.28 front, -0.30 rear, r 0.110) by 1 cm or more.
    FZ = 0.262
    U = POD_UNDER
    # Hero hull: the rear tyre (slot -0.23, r 0.14) reaches the tail, so the
    # tail no longer wraps down; the fender wraps down in front of the front
    # tyre (slot 0.25, front of tyre 0.39).
    stations = [(REAR_X, POD_CREST - 0.050, 0.014, 0.0, None, None, U),
                (REAR_X + 0.014, POD_CREST - 0.020, 0.0, 0.0, None, None, U),
                (REAR_X + 0.040, POD_CREST - 0.004, 0.0, 0.0, None, None, U),
                (-0.290, POD_CREST, 0.0, 0.0, None, None, U),
                (-0.100, POD_CREST, 0.0, 0.0, None, None, U),
                (0.020, POD_CREST, 0.0, 0.0, None, None, U),
                (0.072, POD_CREST - 0.012, 0.0, 0.0, FZ, U, U),
                (0.300, POD_CREST - 0.032, 0.0, 0.0, FZ, U, U),
                (0.370, POD_CREST - 0.052, 0.0, 0.0, FZ, U, U),
                (0.405, POD_CREST - 0.080, 0.0, 0.0, FZ, U, 0.100),
                (0.425, POD_CREST - 0.106, 0.010, 0.0, FZ, U, 0.075)]
    for s in (-1.0, 1.0):
        P.loft([_ring(bx, _pod_profile(c, i, d, zi, ft, u), s)
                for (bx, c, i, d, zi, ft, u) in stations], "livery",
               bevel=BEVEL_V2, seg=SEG_V2)
        # the upper pressing over the middle of the pod
        cap = _cap_profile(POD_CREST)
        P.loft([_ring(-0.020, cap, s), _ring(-0.230, cap, s)], "livery",
               bevel=BEVEL_V2_MID, seg=SEG_V2)
        # a dark mounting rail along the pod's inner foot, bolted to the deck
        rail = [(POD_IN - 0.012, DECK_Y), (POD_IN, DECK_Y), (POD_IN, DECK_Y + 0.020),
                (POD_IN - 0.006, DECK_Y + 0.020), (POD_IN - 0.012, DECK_Y + 0.012)]
        ring_a = [_lid(0.030, y, s * z) for (z, y) in rail]
        ring_b = [_lid(REAR_X + 0.02, y, s * z) for (z, y) in rail]
        if s < 0:
            ring_a, ring_b = list(reversed(ring_a)), list(reversed(ring_b))
        P.loft([ring_a, ring_b], "dark_metal", bevel=BEVEL_V2_SMALL, seg=2)
        for bx in (0.000, -0.110, -0.220, -0.320):
            P.button_bolt(_lid(bx, DECK_Y + 0.020, s * (POD_IN - 0.006)), (1, 0, 0),
                          r=0.0050, mat="titanium", n=8, washer=None)
        # a bolt row along the pressing's crest, and three on the outer face
        # (on the pressing's facet: its surface is 7 mm off the pod facet,
        # whose normal is (z 0.224, y 0.975))
        pod = _pod_profile(POD_CREST)
        (za, ya), (zb, yb) = pod[5], pod[6]
        zf = 0.285
        yf = ya + (yb - ya) * (za - zf) / (za - zb)
        for bx in (-0.025, -0.095, -0.165):
            P.button_bolt(_lid(bx, yf + 0.975 * 0.007, s * (zf + 0.224 * 0.007)),
                          (0.975, 0, s * 0.224), r=0.0058, mat="titanium", n=8)
        for bx in (-0.200, -0.260, -0.320):
            P.button_bolt(_lid(bx, (POD_UNDER + pod[4][1]) * 0.5, s * (POD_OUT + 0.0005)),
                          (0, 0, s), r=0.0058, mat="titanium", n=8)
    # deck bolts where the channel shows, and along the plate's rim
    for y in (-0.175, 0.175):
        for z in (-0.160, -0.080, 0.080, 0.160):
            if hdpe:
                P.countersunk((dx + 0.0002, y, z), (1, 0, 0), r=0.0058, mat="titanium")
            else:
                P.button_bolt((dx, y, z), (1, 0, 0), r=0.0060, mat="titanium", n=8)
    # a speed controller in the channel (left of the srimech), finned, wired
    # into the pod: generic, so it reads on any weapon, not just the flipper
    esc = _lid(-0.120, DECK_Y, -0.128)
    P.outline(cut_rect(0.060, 0.030, 0.006), esc + Vector((0.020, 0.0, 0.0)),
              (0, 1, 0), (0, 0, 1), (1, 0, 0), 0.020, "dark_metal",
              bevel=BEVEL_V2_SMALL, seg=2, back=0.002)
    for k in range(6):
        P.box(esc + Vector((0.023, -0.050 + k * 0.020, 0.0)), (0.006, 0.004, 0.052),
              "dark_metal", bevel=0.0008, seg=1)
    P.hose([esc + Vector((0.012, 0.064, 0.012)), _lid(-0.200, DECK_Y + 0.016, -0.150),
            _lid(-0.240, DECK_Y + 0.024, -0.182)], 0.0045, "rubber", n=6, per_span=5,
           fittings="dark_metal")
    P.hose([esc + Vector((0.012, 0.064, -0.012)), _lid(-0.215, DECK_Y + 0.010, -0.120),
            _lid(-0.300, DECK_Y + 0.012, -0.110), _lid(-0.330, DECK_Y + 0.020, -0.182)],
           0.0040, "rubber", n=6, per_span=5, fittings="dark_metal")
    P.socket("socket_pivot", (0.0, 0.0, 0.0))
    return P


def build_plate_wedge_sides(hdpe=False):
    """Flank plate between the wheels.  Symmetric in Z: the same model is
    fitted to both flanks with opposite local Z.  Pass 2: two layers, not one
    rounded box.  A creased livery pressing (a ridge along its length, so its
    upper and lower facets take the strip lights differently) over the plate,
    a dark skid strip along the foot, and a chamfered top edge that leads the
    eye up into the shell overhang above it.  Hero hull pass: 0.19 m long (the
    gap between the 0.14 m tyres, wedge.gd SIDE_SIZE), the louvred upper flank
    runs up to the pods' underside at 0.149."""
    P = _plate("plate_wedge_sides" + ("_hdpe" if hdpe else ""), 0.048, 0.093, 0.014, hdpe)
    for (y0, y1, h0, h1) in ((-0.030, 0.004, 0.005, 0.012), (0.004, 0.040, 0.012, 0.004)):
        a0 = 0.010 if y0 < 0 else 0.0
        a1 = 0.0 if y0 < 0 else 0.012
        ring_l = [Vector((0.0, y0, -0.080 + a0)), Vector((h0, y0, -0.076 + a0)),
                  Vector((h1, y1, -0.076 + a1)), Vector((0.0, y1, -0.080 + a1))]
        ring_r = [Vector((v.x, v.y, -v.z)) for v in ring_l]
        P.loft([ring_l, ring_r], "livery", bevel=BEVEL_V2_MID, seg=SEG_V2)
    strip = [(0.0, -0.046), (0.0, -0.034), (0.008, -0.036), (0.008, -0.044)]
    P.loft([[Vector((x, y, -0.088)) for x, y in strip],
            [Vector((x, y, 0.088)) for x, y in strip]], "dark_metal",
           bevel=BEVEL_V2_SMALL, seg=2)
    for z in (-0.066, 0.0, 0.066):
        P.button_bolt((0.008, -0.040, z), (1, 0, 0), r=0.0045, mat="titanium", n=8,
                      washer=None)
    for z in (-0.084, 0.084):
        for y in (-0.018, 0.024):
            P.button_bolt((0.0, y, z), (1, 0, 0), r=0.0056, mat="titanium", n=8)
    # the upper flank: a dark louvred panel on the plate's top edge, flaring
    # out to meet the pods' overhang (0.149 in bot y), so the flank reads as
    # one tall layered side under the shell
    up = [(-0.012, 0.044), (0.000, 0.044), (0.014, 0.140), (0.002, 0.140)]
    P.loft([[Vector((x, y, -0.074)) for x, y in up],
            [Vector((x, y, 0.074)) for x, y in up]], "dark_metal",
           bevel=BEVEL_V2_MID, seg=SEG_V2)
    for k in range(3):
        z = -0.040 + k * 0.040
        slot = [(0.00235, 0.060, z - 0.011), (0.01170, 0.124, z - 0.011),
                (0.01170, 0.124, z + 0.011), (0.00235, 0.060, z + 0.011)]
        P.loft([[Vector((x - 0.002, y, zz)) for x, y, zz in slot],
                [Vector((x + 0.0008, y, zz)) for x, y, zz in slot]], "rubber",
               bevel=0.0, seg=0)
    for z in (-0.064, 0.064):
        for y in (0.058, 0.126):
            P.button_bolt(((y - 0.044) * 0.146, y, z),
                          (1.0, -0.146, 0.0), r=0.0048, mat="titanium", n=8, washer=None)
    P.socket("socket_pivot", (0.0, 0.0, 0.0))
    return P


def build_plate_wedge_rear(hdpe=False):
    P = _plate("plate_wedge_rear" + ("_hdpe" if hdpe else ""), 0.058, 0.252, 0.022, hdpe)
    for s in (-1.0, 1.0):
        pts = cut_rect(0.028, 0.080, 0.012)
        pts = [(y, z + s * 0.130) for (y, z) in pts]
        cowl(P, pts, 0.0, 0.006, 0.006, "livery", bevel=BEVEL_V2_MID, seg=SEG_V2)
    _bolt_row(P, [(y, z) for y in (-0.043, 0.043) for z in (-0.232, 0.0, 0.232)], hdpe)
    # a tow bar across the middle, between the two livery panels
    P.lathe([(0.0, 0.0), (0.010, 0.0), (0.010, 0.060), (0.0, 0.060)],
            (0.004, 0.0, -0.030), (0, 0, 1), "dark_metal", n=10)
    for s in (-1.0, 1.0):
        P.box((0.004, 0.0, s * 0.036), (0.016, 0.030, 0.012), "dark_metal",
              bevel=BEVEL_V2_SMALL, seg=2)
    P.socket("socket_pivot", (0.0, 0.0, 0.0))
    return P


def build_plate_wedge_front(hdpe=False):
    """The ramp plate at the lip.  Local +Y runs DOWN the slope toward the lip
    (Basis(slope.y, slope.x, -slope.z)), so its leading edge is +Y and is
    tapered to a knife edge that gets under an opponent.  The flipper arm
    lies over most of it; what shows is that edge and the bolt row."""
    P = Part("plate_wedge_front" + ("_hdpe" if hdpe else ""), "armour", v2=True,
             bake_px=512)
    hz = 0.250
    prof = [(0.0, -0.077), (0.0, 0.064), (-0.004, 0.078), (-0.009, 0.080),
            (-T_VIS, 0.040), (-T_VIS, -0.077)]
    mat = "hdpe" if hdpe else "steel"
    P.loft([[Vector((x, y, -hz)) for x, y in prof],
            [Vector((x, y, hz)) for x, y in prof]], mat, bevel=BEVEL_V2, seg=SEG_V2)
    for z in (-0.20, -0.10, 0.0, 0.10, 0.20):
        P.countersunk((0.0002, -0.058, z), (1, 0, 0), r=0.0060, mat="titanium")
    # a hardened titanium strip riveted along the leading edge
    strip = [(0.0, 0.040), (0.0025, 0.042), (0.0025, 0.062), (0.0, 0.066)]
    P.loft([[Vector((x, y, -hz + 0.012)) for x, y in strip],
            [Vector((x, y, hz - 0.012)) for x, y in strip]], "titanium",
           bevel=0.0012, seg=1)
    P.socket("socket_pivot", (0.0, 0.0, 0.0))
    return P


# =============================================================== srimech

def build_srimech(_spec=None):
    """The self-righter, folded forward along the lid: a base bracket with
    cheeks and the shoulder pin, two titanium links on knuckles, a moulded
    HDPE pusher pad and the pneumatic cylinder that throws it, with its line.
    Same pivot, tip and envelope as v1."""
    P = Part("srimech", "utility", v2=True, bake_px=512)
    # base bracket
    P.outline(cut_rect(0.045, 0.055, 0.010), (0.0, 0.034, 0.0), (1, 0, 0), (0, 0, 1),
              (0, 1, 0), 0.034, "dark_metal", bevel=BEVEL_V2_MID, seg=SEG_V2, back=0.004)
    for su in (-1, 1):
        for sv in (-1, 1):
            P.button_bolt((su * 0.030, 0.034, sv * 0.040), (0, 1, 0), r=0.0045, n=8,
                          washer=None)
    for s_ in (-1.0, 1.0):
        prof = [(-0.034, 0.030), (0.034, 0.030), (0.020, 0.090), (-0.020, 0.090)]
        P.loft([[Vector((x, y, s_ * 0.046)) for x, y in prof],
                [Vector((x, y, s_ * 0.058)) for x, y in prof]], "steel",
               bevel=BEVEL_V2_SMALL, seg=2)
    P.lathe([(0.0, -0.064), (0.012, -0.064), (0.012, 0.064), (0.0, 0.064)],
            (0.0, 0.078, 0.0), (0, 0, 1), "steel", n=12)
    for s_ in (-1.0, 1.0):
        P.hex_nut((0.0, 0.078, s_ * 0.060), (0, 0, s_), 0.009, 0.006, "steel")

    def link(a, b, w, t, mat):
        a, b = Vector((a[0], a[1], 0.0)), Vector((b[0], b[1], 0.0))
        d = (b - a).normalized()
        n = Vector((-d.y, d.x, 0.0))
        pts = [a - n * w + d * 0.004, b - n * w * 0.8, b + n * w * 0.8, a + n * w + d * 0.004]
        P.loft([[p + Vector((0, 0, -t)) for p in pts], [p + Vector((0, 0, t)) for p in pts]],
               mat, bevel=BEVEL_V2_MID, seg=SEG_V2)

    link((0.0, 0.078), (0.185, 0.150), 0.017, 0.026, "titanium")
    P.lathe([(0.0, -0.036), (0.020, -0.036), (0.020, 0.036), (0.0, 0.036)],
            (0.185, 0.150, 0.0), (0, 0, 1), "steel", n=16)
    link((0.185, 0.150), (0.325, 0.108), 0.014, 0.020, "titanium")
    # pusher pad: a moulded block with big radii
    P.outline(cut_rect(0.030, 0.057, 0.012), (0.366, 0.100, 0.0), (0, 1, 0), (0, 0, 1),
              (1, 0, 0), 0.042, "hdpe", bevel=0.008, seg=SEG_V2, back=0.004)
    for sv in (-1, 1):
        P.countersunk((0.3662, 0.100, sv * 0.032), (1, 0, 0), r=0.005, mat="steel")
    # the cylinder that throws it, and its line
    cyl_a, cyl_d = Vector((0.140, 0.034, 0.0)), Vector((-1.0, 0.42, 0.0)).normalized()
    P.lathe([(0.0, 0.0), (0.020, 0.0), (0.022, 0.004), (0.022, 0.092), (0.020, 0.096),
             (0.0, 0.096)], cyl_a - cyl_d * 0.010, cyl_d, "steel", n=16)
    P.lathe([(0.0, 0.0), (0.009, 0.0), (0.009, 0.070), (0.0, 0.070)],
            cyl_a + cyl_d * 0.080, cyl_d, "titanium", n=10)
    P.hose([cyl_a + Vector((0.004, 0.020, 0.018)), (0.110, 0.040, 0.050),
            (0.060, 0.022, 0.054)], 0.0040, "rubber", n=6, per_span=5)
    P.socket("socket_pivot", (0.0, 0.078, 0.0))
    P.socket("socket_tip", (0.366, 0.100, 0.0))
    return P


BUILDERS = {
    "srimech": build_srimech,
    "wedge": build_wedge,
    "flipper": build_flipper,
    "wheel_standard": build_wheel_standard,
    "plate_wedge_front": lambda _s=None: build_plate_wedge_front(False),
    "plate_wedge_front_hdpe": lambda _s=None: build_plate_wedge_front(True),
    "plate_wedge_top": lambda _s=None: build_plate_wedge_top(False),
    "plate_wedge_top_hdpe": lambda _s=None: build_plate_wedge_top(True),
    "plate_wedge_sides": lambda _s=None: build_plate_wedge_sides(False),
    "plate_wedge_sides_hdpe": lambda _s=None: build_plate_wedge_sides(True),
    "plate_wedge_rear": lambda _s=None: build_plate_wedge_rear(False),
    "plate_wedge_rear_hdpe": lambda _s=None: build_plate_wedge_rear(True),
}
