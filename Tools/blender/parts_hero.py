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
HALF_LEN = 0.45
HALF_WID = 0.30
BODY_TOP = 0.07
BODY_BOTTOM = -0.07
SLOPE_START_X = 0.10
LIP_BOTTOM = -0.095
LIP_TOP = -0.075
PLATE_PROUD = 0.022          # ChassisBase.PLATE_PROUD: outer face above the hull


# =============================================================== wheel

TYRE_R = WHEEL_RADIUS        # 0.110 over the lugs
CARCASS_R = 0.1015           # the tread base
BEAD_R = 0.0690
HALF_W = 0.0300              # carcass half width (catalogue width 0.06)


def build_wheel_standard(_spec=None):
    """A fat pneumatic-look tyre with a chevron lug tread that wraps onto the
    shoulders, on a five-spoke machined rim.  The wheel is symmetric in Z
    because the same model is fitted on both sides of the machine."""
    P = Part("wheel_standard", "drive", v2=True, bake_px=512)
    ax = (0, 0, 1)

    # carcass: rounded shoulders and a sidewall bulge, one closed lathe
    hw = HALF_W
    prof = [(BEAD_R, -hw + 0.001), (0.078, -hw - 0.0012), (0.088, -hw - 0.0016),
            (0.0955, -hw + 0.0008), (0.0990, -hw + 0.0045), (CARCASS_R, -hw + 0.0095),
            (CARCASS_R, hw - 0.0095), (0.0990, hw - 0.0045), (0.0955, hw - 0.0008),
            (0.088, hw + 0.0016), (0.078, hw + 0.0012), (BEAD_R, hw - 0.001)]
    P.lathe(prof, (0, 0, 0), ax, "rubber", n=32, closed=True)

    # chevron lugs: two staggered rows, each lug raked 28 degrees and running
    # off the crown onto the shoulder, which is the silhouette that reads as a
    # tyre rather than a cog
    pitches = 16
    rake = math.radians(30.0)
    for k in range(pitches):
        for side in (-1.0, 1.0):
            th0 = 2.0 * math.pi * (k + (0.5 if side > 0 else 0.0)) / pitches
            _lug(P, th0, side, rake)

    # rim: a barrel with machined flanges standing proud of the bead on both
    # faces, so a bright ring reads round the dark spokes
    P.lathe([(0.0560, -0.0310), (0.0600, -0.0345), (0.0720, -0.0345),
             (0.0745, -0.0335), (0.0745, -0.0300), (0.0690, -0.0260),
             (0.0690, 0.0260), (0.0745, 0.0300), (0.0745, 0.0335),
             (0.0720, 0.0345), (0.0600, 0.0345), (0.0560, 0.0310)],
            (0, 0, 0), ax, "steel", n=28, closed=True)
    # five tapered spokes in the mid-plane, chamfered on both faces
    for i in range(5):
        a = 2.0 * math.pi * i / 5.0 + math.pi / 10.0
        u = Vector((math.cos(a), math.sin(a), 0.0))
        v = Vector((-math.sin(a), math.cos(a), 0.0))
        pts = [(0.018, -0.0100), (0.058, -0.0140), (0.058, 0.0140), (0.018, 0.0100)]
        P.outline(pts, (0, 0, 0.0115), u, v, (0, 0, 1), 0.023, "dark_metal",
                  bevel=0.0028, seg=2)
    # hub: a stepped boss each side with a bearing cap and five lug nuts
    P.lathe([(0.0, -0.0205), (0.0235, -0.0205), (0.0255, -0.0170),
             (0.0255, 0.0170), (0.0235, 0.0205), (0.0, 0.0205)],
            (0, 0, 0), ax, "dark_metal", n=20)
    for side in (-1.0, 1.0):
        s = Vector((0, 0, side))
        P.lathe([(0.0, 0.0), (0.0135, 0.0), (0.0135, 0.0035), (0.0110, 0.0060),
                 (0.0060, 0.0075), (0.0, 0.0078)],
                s * 0.0200, s, "steel", n=12)
        for i in range(5):
            a = 2.0 * math.pi * i / 5.0 + math.pi / 10.0
            p = Vector((0.0185 * math.cos(a), 0.0185 * math.sin(a), side * 0.0200))
            P.hex_nut(p, s, 0.0036, 0.0040, "steel")
    # valve stem on one face, just inside the flange
    P.cyl((0.0, 0.0625, 0.0), (0, 0, 1), 0.0024, 0.056, "dark_metal", n=6, bevel=0.0)
    return P


def _lug(P, th0, side, rake):
    """One tread lug: a raked block from the crown centre out over the
    shoulder, its outer face on r = TYRE_R and its root sunk into the carcass."""
    w = 0.0135                       # lug width, around the tyre
    # axial extents: from just past the crown centre to past the shoulder
    h_in, h_out = 0.0025, HALF_W + 0.0020
    ofs = math.tan(rake) * (h_out - h_in)
    # four corners in (arc length s, axial h) on the tread surface
    quad = [(-w * 0.5, h_in), (w * 0.5, h_in), (w * 0.5 + ofs, h_out),
            (-w * 0.5 + ofs, h_out)]

    def at(s, h, r):
        th = th0 + s / CARCASS_R
        # the lug drops off the shoulder: its outer radius falls past the crown
        edge = max(0.0, h - (HALF_W - 0.0095))
        rr = r - edge * 0.55
        return Vector((rr * math.cos(th), rr * math.sin(th), side * h))

    outer = [at(s, h, TYRE_R) for s, h in quad]
    inner = [at(s, h, CARCASS_R - 0.004) for s, h in quad]
    if side < 0:
        outer, inner = list(reversed(outer)), list(reversed(inner))
    P.loft([inner, outer], "rubber", bevel=0.0016, seg=1, min_angle=25.0)




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
    P.loft([section(-HALF_LEN, -0.060, BODY_TOP, 0.030, 0.022),
            section(-0.36, -0.078, BODY_TOP, 0.030, 0.014),
            section(SLOPE_START_X, -0.080, BODY_TOP, 0.030, 0.014),
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
        prof = [(-0.190, -0.058), (0.128, -0.058), (0.136, -0.040), (0.128, 0.062),
                (-0.182, 0.062), (-0.198, 0.040)]
        z0, z1 = s * (hw - 0.010), s * (0.300 - 0.001)
        ring0 = [Vector((x, y, z0)) for x, y in prof]
        ring1 = []
        cx = sum(p[0] for p in prof) / len(prof)
        cy = sum(p[1] for p in prof) / len(prof)
        for x, y in prof:
            ring1.append(Vector((cx + (x - cx) * 0.97, cy + (y - cy) * 0.90, z1)))
        P.loft([ring0, ring1], "livery", bevel=BEVEL_V2, seg=SEG_V2)
        # a seam line: the sponson is two pressings with a V gap between
        P.box((-0.035, 0.0, z1 - s * 0.020), (0.004, 0.118, 0.042), "dark_metal",
              bevel=0.0012, seg=1)
        # four button bolts on the sponson's top chamfer strip
        for x in (-0.15, -0.06, 0.03, 0.10):
            P.button_bolt((x, 0.0625, s * (hw + 0.030)), (0, 1, 0), r=0.0048, n=8)

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
    pv = (0.1115, 0.0977)
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
    for (x0, x1) in ((-0.43, -0.256), (-0.094, 0.050)):
        P.outline(cut_rect((x1 - x0) * 0.5, hw - 0.022, 0.018),
                  ((x0 + x1) * 0.5, BODY_TOP + 0.003, 0.0), (1, 0, 0), (0, 0, 1),
                  (0, 1, 0), 0.006, "dark_metal", bevel=0.002, seg=2, back=0.0015)
    pc.core_bay(P, bay, BODY_TOP + 0.003, depth=0.030)

    # skid rails under the hull and a rear bumper bar below the rear plate
    for s in (-1.0, 1.0):
        rail = [Vector((-0.40, -0.060 - 0.016, 0)), Vector((0.30, -0.080 - 0.016, 0)),
                Vector((0.30, -0.080, 0)), Vector((-0.40, -0.060, 0))]
        P.loft([[p + Vector((0, 0, s * 0.150 - 0.012)) for p in rail],
                [p + Vector((0, 0, s * 0.150 + 0.012)) for p in rail]], "titanium",
               bevel=BEVEL_V2_SMALL, seg=2)
    P.box((-HALF_LEN - 0.010, -0.066, 0.0), (0.020, 0.014, 0.40), "steel",
          bevel=BEVEL_V2_SMALL, seg=2)

    # motor cable looms from the sponsons into the hull, just visible behind
    # the tyres
    for s in (-1.0, 1.0):
        P.hose([(0.20, 0.030, s * (hw + 0.002)), (0.17, 0.045, s * (hw + 0.012)),
                (0.13, 0.050, s * (hw + 0.016))], 0.0042, "rubber", n=6, per_span=4,
               fittings="dark_metal")
        P.hose([(-0.25, 0.030, s * (hw + 0.002)), (-0.22, 0.045, s * (hw + 0.012)),
                (-0.19, 0.050, s * (hw + 0.016))], 0.0042, "rubber", n=6, per_span=4,
               fittings="dark_metal")

    pc.sockets(P, "wedge", spec, base, top,
               weapon_front=(0.070, deck_v1 - 0.026, 0.0), weapon_top=(0.05, top, 0.0))
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
    for x in (KINK + 0.030, x1 - 0.085):
        for z in (-0.140, 0.0, 0.140):
            P.countersunk((x, top_y + 0.0032, z), (0, 1, 0), r=0.0052, mat="steel")
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


def _plate(ident, hy, hz, corner, hdpe):
    P = Part(ident, "armour", v2=True, bake_px=512)
    if hdpe:
        base_plate(P, hy, hz, corner, T_VIS, "hdpe", bevel=0.009, seg=4, back=0.006)
    else:
        base_plate(P, hy, hz, corner, T_VIS, "steel")
    return P


def build_plate_wedge_top(hdpe=False):
    """The lid: the machine's biggest livery surface, so it carries a ridged
    two-piece cowl with sloped sides and a V seam down the centre line.  Local
    +Y points at the bot's REAR (Basis(BACK, 90 degrees)); the srimech sits on
    the rear third."""
    P = _plate("plate_wedge_top" + ("_hdpe" if hdpe else ""), 0.226, 0.246, 0.034, hdpe)
    for s in (-1.0, 1.0):
        pts = [(-0.188, s * 0.006), (-0.188, s * 0.150), (-0.150, s * 0.200),
               (0.186, s * 0.200), (0.186, s * 0.006)]
        if s < 0:
            pts = list(reversed(pts))
        cowl(P, pts, 0.0, 0.007, 0.014, "livery", crown=0.013, axis=0,
             bevel=BEVEL_V2, seg=SEG_V2)
    bolts = [(y, z) for y in (-0.210, 0.210) for z in (-0.19, -0.095, 0.0, 0.095, 0.19)]
    bolts += [(y, z) for z in (-0.228, 0.228) for y in (-0.10, 0.0, 0.10)]
    _bolt_row(P, bolts, hdpe)
    # two lifting eyes at the front corners of the cowl
    for s in (-1.0, 1.0):
        P.lathe([(0.0, 0.0), (0.009, 0.0), (0.009, 0.004), (0.0, 0.004)],
                (0.0, -0.205, s * 0.160), (1, 0, 0), "dark_metal", n=10)
    P.socket("socket_pivot", (0.0, 0.0, 0.0))
    return P


def build_plate_wedge_sides(hdpe=False):
    """Flank plate between the wheels.  Symmetric in Z: the same model is
    fitted to both flanks with opposite local Z."""
    P = _plate("plate_wedge_sides" + ("_hdpe" if hdpe else ""), 0.048, 0.146, 0.016, hdpe)
    cowl(P, cut_rect(0.030, 0.112, 0.012), 0.0, 0.006, 0.006, "livery",
         bevel=BEVEL_V2_MID, seg=SEG_V2)
    _bolt_row(P, [(y, z) for y in (-0.034, 0.034) for z in (-0.130, 0.130)], hdpe)
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
