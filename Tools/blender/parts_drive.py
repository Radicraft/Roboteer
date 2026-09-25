"""Drive parts.

Every wheel spins about its own local +Z (the bot's left-right axis) and its
origin is the axle centre, so P2 drops it straight onto a `socket_wheel_*`
empty with no rotation.  The track unit is 0.70 m long, centred on the origin,
0.09 m wide, and P2 scales it along X per chassis footprint.
"""

import math

from mathutils import Vector

from rkit import Part, WHEEL_RADIUS, WHEEL_WIDTH, rot_pitch, rot_z


def build_wheel_standard(_spec=None):
    P = Part("wheel_standard", "drive")
    r = WHEEL_RADIUS
    w = WHEEL_WIDTH
    tyre_in = 0.074

    # tyre carcass: a ring so the hub shows through from both sides
    P.ring((0, 0, 0), (0, 0, 1), r - 0.012, tyre_in, w, "rubber", n=16, bevel=0.0)
    # chunky tread cleats
    cleats = 8
    for i in range(cleats):
        a = 2.0 * math.pi * i / cleats
        c, s = math.cos(a), math.sin(a)
        P.box(((r - 0.004) * c, (r - 0.004) * s, 0.0), (0.020, 0.038, w + 0.004),
              "rubber", bevel=0.0025, seg=1, rot=rot_pitch(math.degrees(a)))
    # rim, spokes and hub
    P.cyl((0, 0, 0), (0, 0, 1), 0.026, w - 0.006, "steel", n=10, bevel=0.002)
    for i in range(6):
        a = 2.0 * math.pi * i / 6.0
        c, s = math.cos(a), math.sin(a)
        P.box((0.048 * c, 0.048 * s, 0.0), (0.050, 0.018, w - 0.018),
              "titanium", bevel=0.0, rot=rot_pitch(math.degrees(a)))
    for side in (-1.0, 1.0):
        for i in range(3):
            a = 2.0 * math.pi * i / 3.0 + 0.3
            P.bolt((0.040 * math.cos(a), 0.040 * math.sin(a), side * (w * 0.5 - 0.004)),
                   (0, 0, side), r=0.0068)
        P.bearing_cap((0, 0, side * (w * 0.5 - 0.006)), (0, 0, side), 0.024,
                      h=0.011, n=8)
    # valve stem
    P.cyl((0.0, tyre_in + 0.004, w * 0.5 - 0.006), (0, 1, 0), 0.005, 0.016,
          "dark_metal", n=6, bevel=0.0)
    return P


def build_wheel_omni(_spec=None):
    P = Part("wheel_omni", "drive")
    w = WHEEL_WIDTH + 0.01
    roller_r = 0.031
    ring_r = WHEEL_RADIUS - roller_r          # 0.079

    for side in (-1.0, 1.0):
        P.cyl((0, 0, side * (w * 0.5 - 0.007)), (0, 0, 1), ring_r + 0.006, 0.014,
              "titanium", n=13, bevel=0.0)
    P.cyl((0, 0, 0), (0, 0, 1), 0.028, w - 0.006, "steel", n=8, bevel=0.002)
    for i in range(6):
        a = 2.0 * math.pi * i / 6.0
        P.box((0.052 * math.cos(a), 0.052 * math.sin(a), 0.0),
              (0.058, 0.016, w - 0.024), "steel", bevel=0.0,
              rot=rot_pitch(math.degrees(a)))
    # the barrel rollers, axes tangential
    rollers = 8
    for i in range(rollers):
        a = 2.0 * math.pi * i / rollers
        c, s = math.cos(a), math.sin(a)
        cen = (ring_r * c, ring_r * s, 0.0)
        tangent = (-s, c, 0.0)
        P.cone(cen, tangent, roller_r * 0.74, roller_r, 0.021, "rubber", n=8, bevel=0.0)
        P.cone((cen[0] - tangent[0] * 0.021, cen[1] - tangent[1] * 0.021, 0.0),
               tangent, roller_r, roller_r * 0.74, 0.021, "rubber", n=8, bevel=0.0)
        # roller pin
        P.cyl(cen, tangent, 0.005, 0.056, "dark_metal", n=5, bevel=0.0)
    for side in (-1.0, 1.0):
        for i in range(3):
            a = 2.0 * math.pi * i / 3.0 + 0.4
            P.bolt((0.044 * math.cos(a), 0.044 * math.sin(a), side * (w * 0.5 - 0.003)),
                   (0, 0, side), r=0.0065)
    return P


def build_track_unit(_spec=None):
    P = Part("track_unit", "drive")
    half = 0.35
    rr = 0.10                # sprocket radius
    cx = half - rr           # 0.25
    hz = 0.045               # half width
    t = 0.016                # track skin thickness

    # rounded-rectangle path, anticlockwise, outer surface of the belt
    path = []
    seg = 8
    for i in range(seg + 1):                      # front nose
        a = -math.pi * 0.5 + math.pi * i / seg
        path.append((cx + rr * math.cos(a), rr * math.sin(a)))
    for i in range(seg + 1):                      # rear nose
        a = math.pi * 0.5 + math.pi * i / seg
        path.append((-cx + rr * math.cos(a), rr * math.sin(a)))
    P.band(path, -hz, hz, t, "rubber", bevel=0.0)

    # cleats on the outside of the belt
    for i in range(0, len(path), 2):
        x, y = path[i]
        n = math.hypot(x - (cx if x > 0 else -cx), y)
        if n < 1e-6:
            continue
        a = math.atan2(y, x - (cx if x > 0 else -cx))
        # Wave A pass 2: the cleat crowns sit ON the wheel radius (0.110), as the
        # physics wheels they wrap do.  They stood 10 mm proud (crown 0.120), so
        # the belt drew 10 mm into the floor (stage lead's measurement).
        P.box((x + 0.005 * math.cos(a), y + 0.005 * math.sin(a), 0.0),
              (0.010, 0.046, 2 * hz + 0.004), "rubber", bevel=0.0025, seg=1,
              rot=rot_pitch(math.degrees(a)))

    # sprockets, with teeth that engage the belt, and the road wheels
    for sgn in (1.0, -1.0):
        P.cyl((sgn * cx, 0, 0), (0, 0, 1), rr - t - 0.016, 2 * hz - 0.016,
              "dark_metal", n=12, bevel=0.002)
        for i in range(9):
            a = 2.0 * math.pi * i / 9.0
            P.box((sgn * cx + (rr - t - 0.008) * math.cos(a),
                   (rr - t - 0.008) * math.sin(a), 0.0),
                  (0.016, 0.022, 2 * hz - 0.022), "steel", bevel=0.0,
                  rot=rot_pitch(math.degrees(a)))
        P.bearing_cap((sgn * cx, 0, -(hz + 0.034)), (0, 0, -1), 0.028, h=0.012, n=8)
    for x in (-0.085, 0.085):
        P.cyl((x, -0.028, 0), (0, 0, 1), 0.048, 2 * hz - 0.020, "dark_metal",
              n=12, bevel=0.002)
    for x in (-0.17, 0.17):
        P.cyl((x, -0.030, 0), (0, 0, 1), 0.044, 2 * hz - 0.020, "dark_metal",
              n=12, bevel=0.002)

    # inboard side frame, bolted, with the tensioner
    P.plate((0.0, -0.012, -(hz + 0.010)), (2 * half - 0.05, 0.115, 0.014),
            "steel", axis=(0, 0, -1), inset=0.04)
    P.bolt_line((-0.26, -0.012, -(hz + 0.024)), (0.26, -0.012, -(hz + 0.024)), 5, (0, 0, -1))
    for sgn in (1.0, -1.0):
        P.cyl((sgn * cx, 0, -(hz + 0.022)), (0, 0, -1), 0.030, 0.024,
              "dark_metal", n=10, bevel=0.002)
    P.ribs((0.0, -0.012, -(hz + 0.019)), (2 * half - 0.18, 0.0, 0.0), 4, "steel",
           normal=2, run=1, h=-0.008, w=0.014)
    P.seam((-0.28, 0.058, -(hz + 0.017)), (0.28, 0.058, -(hz + 0.017)))
    return P


BUILDERS = {
    "wheel_standard": build_wheel_standard,
    "wheel_omni": build_wheel_omni,
    "track_unit": build_track_unit,
}


# ---------------------------------------------------------------------------
# Wave P (agent E).  The three drives of brief v5 section 9.5.  Requests in
# docs/wave-p-d2-notes.md section 5.
# ---------------------------------------------------------------------------

#: `legs.glb` is ONE leg, authored at this height, which `legs.gd` scales in Y to
#: the hull it is under (the drop from `floor_y()` to the sole is 0.05 to 0.09 m
#: depending on the hull).  Only the shin and the ram stretch visibly; the hip
#: housing and the foot pad are shallow enough that the squash does not read.
LEG_HEIGHT = 0.090
#: `hover.glb` is authored around a wedge's footprint and `hover.gd` scales it in
#: X and Z to the hull it is under.  Nothing about the skirt is circular, so the
#: two scales are independent and neither distorts a round thing.
HOVER_HALF_LEN = 0.45
HOVER_HALF_WID = 0.30
#: How deep the skirt hangs below `floor_y()`.  `hover.gd` reads the same number.
SKIRT_DEPTH = 0.115


def _leg_ram(P, a, b, body_r=0.016, rod_r=0.007):
    """A short hydraulic strut with a dust boot: the thing that makes a walker
    read as hydraulic rather than as a bent stick."""
    a, b = Vector(a), Vector(b)
    d = b - a
    L = d.length
    if L < 1e-6:
        return
    u = d / L
    P.cyl(a + u * (L * 0.30), u, body_r, L * 0.58, "steel", n=10, bevel=0.002)
    P.cyl(a + u * (L * 0.78), u, rod_r, L * 0.40, "titanium", n=8, bevel=0.0)
    P.ring(a + u * (L * 0.64), u, body_r * 0.86, rod_r, 0.007, "rubber", n=8)
    for p in (a, b):
        P.cyl(p, u, body_r * 0.66, 0.014, "dark_metal", n=8, bevel=0.0018)


def build_legs(_spec=None):
    """ONE hydraulic leg, hung from the hull underside at the origin and
    reaching the floor at y = -LEG_HEIGHT.  `legs.gd` fits four, one per 4WD
    wheel slot, and strides them.

    It articulates FORE AND AFT, in the X/Y plane, for two reasons: that is the
    plane a stride happens in, so the animation is one rotation about the hip
    pin and nothing has to be re-rigged; and it keeps the foot under the mount,
    which is where D2's collision box for the foot actually is.

    PROPORTION IS THE WHOLE PROBLEM HERE and the first cut got it wrong.  The
    drop from the hull to the floor is only 0.05 to 0.09 m, so a hip housing
    built to the width of the collision box (0.12 m across) is WIDER than the
    leg is tall and the part reads as a block with a plate under it, not as a
    leg.  Everything structural is therefore narrow -- 0.058 m across the hip,
    0.036 across the knee -- and the members are kept OUTSIDE the housing where
    the silhouette can see them.  The foot is dark, not bright steel: at fight
    distance the brightest thing wins the read, and that should be the machine."""
    P = Part("legs", "drive")
    h = LEG_HEIGHT

    # hip: a narrow cast housing bolted up into the hull floor
    P.box((0.006, -0.011, 0.0), (0.044, 0.022, 0.058), "dark_metal",
          bevel=0.003, seg=2)
    P.plate((0.006, 0.003, 0.0), (0.040, 0.011, 0.052), "livery",
            axis=(0, 1, 0), inset=0.012)
    # the two shoulder cheeks the pin runs through, proud of the housing
    for sz in (-1.0, 1.0):
        P.box((0.004, -0.026, sz * 0.036), (0.038, 0.034, 0.011), "steel",
              bevel=0.0025, seg=1)
        P.bolt((0.004, -0.016, sz * 0.042), (0, 0, sz), r=0.0058)
    P.shaft((0.0, -0.030, -0.048), (0.0, -0.030, 0.048), 0.0098, "steel",
            n=10, grooves=(0.12, 0.88), step=0.0)

    knee = (-0.060, -0.028 - 0.026 * (h / 0.090))
    ankle = (0.020, -h + 0.014)

    # thigh: a pair of narrow links either side of the pin, swept back to the
    # knee, so the pin reads as a pin and the knee reads as a joint
    for sz in (-1.0, 1.0):
        P.slab((0.0, -0.030), knee, sz * 0.021 - 0.007, sz * 0.021 + 0.007,
               0.017, "titanium", outward=(-1.0, 0.5), bolts=2, inset=0.009)
    P.cyl((knee[0], knee[1], 0.0), (0, 0, 1), 0.013, 0.062, "dark_metal",
          n=10, bevel=0.002)
    for sz in (-1.0, 1.0):
        P.bearing_cap((knee[0], knee[1], sz * 0.034), (0, 0, sz), 0.012,
                      h=0.008, n=6)

    # shin: one heavier member, forward and down to the ankle
    P.slab(knee, ankle, -0.013, 0.013, 0.021, "steel", outward=(1.0, 0.5),
           bolts=2, inset=0.008)

    # the ram that drives the knee: on the OUTSIDE, where it can be seen
    _leg_ram(P, (0.026, -0.014, 0.0), (ankle[0] - 0.004, ankle[1] + 0.017, 0.0))

    # ankle, foot pad and a rubber sole: what actually meets the floor
    P.cyl((ankle[0], ankle[1], 0.0), (0, 0, 1), 0.011, 0.048, "dark_metal",
          n=8, bevel=0.002)
    P.box((ankle[0] - 0.008, -h + 0.008, 0.0), (0.064, 0.010, 0.050),
          "dark_metal", bevel=0.003, seg=2)
    P.prism([(-0.030, 0.0), (0.030, 0.0), (0.014, 0.016), (-0.014, 0.016)],
            -0.019, 0.019, "dark_metal", bevel=0.0025, seg=1,
            at=(ankle[0] - 0.008, -h + 0.013, 0.0))
    for sx in (-1.0, 1.0):
        P.prism([(0.0, 0.0), (sx * 0.020, 0.0), (0.0, 0.013)], -0.021, 0.021,
                "titanium", bevel=0.002, seg=1,
                at=(ankle[0] - 0.008 + sx * 0.032, -h + 0.012, 0.0))
    P.box((ankle[0] - 0.008, -h + 0.0015, 0.0), (0.060, 0.006, 0.046),
          "rubber", bevel=0.0025, seg=1)
    for sx in (-1, 1):
        P.box((ankle[0] - 0.008 + sx * 0.017, -h + 0.0005, 0.0),
              (0.022, 0.005, 0.040), "rubber", bevel=0.002, seg=1)
    P.cable_run([(0.022, -0.004, 0.024), (0.022, -0.004, -0.024)], r=0.0042,
                channel=False)
    P.socket("socket_hip", (0.0, -0.030, 0.0))
    P.socket("socket_pivot", (0.0, -0.030, 0.0))
    P.socket("socket_tip", (ankle[0] - 0.008, -h, 0.0))
    return P

def _thruster_pod(P, at, r=0.082):
    """A ducted fan hanging inside the skirt: shroud, stator vanes, hub, and a
    `glow` disc in the throat that agent F lights with the lift.

    Twelve segments, not sixteen: four of these sit on one machine and at the
    fight camera's 235 px per metre a 0.16 m duct is 39 pixels across, where the
    twelve-sided silhouette and the sixteen-sided one are the same picture."""
    x, y, z = at
    P.ring((x, y, z), (0, 1, 0), r, r - 0.020, 0.088, "dark_metal", n=12,
           bevel=0.004)
    P.ring((x, y + 0.050, z), (0, 1, 0), r + 0.007, r - 0.026, 0.016, "steel", n=12)
    P.ring((x, y - 0.050, z), (0, 1, 0), r + 0.003, r - 0.026, 0.013,
           "titanium", n=12)
    # stator vanes across the throat, and the motor can they carry
    for i in range(4):
        a = 2.0 * math.pi * i / 4.0
        P.box((x + (r - 0.034) * 0.5 * math.cos(a), y - 0.008,
               z + (r - 0.034) * 0.5 * math.sin(a)),
              (r - 0.034, 0.010, 0.018), "steel", bevel=0.0, seg=1,
              rot=rot_z(math.degrees(-a)))
    P.cyl((x, y - 0.002, z), (0, 1, 0), 0.026, 0.060, "dark_metal", n=8,
          bevel=0.002)
    P.bearing_cap((x, y + 0.032, z), (0, 1, 0), 0.020, h=0.011, n=6)
    for i in range(2):
        a = math.pi * i + 0.4
        P.hardware_bolt((x + (r - 0.010) * math.cos(a), y + 0.058,
                         z + (r - 0.010) * math.sin(a)), (0, 1, 0))
    # the glow: its own mesh node, so F can find it by name and drive it
    P.use("glow")
    P.cyl((x, y - 0.038, z), (0, 1, 0), r - 0.025, 0.010, "core_glow", n=12,
          bevel=0.0)
    P.use("body")

def build_hover(_spec=None):
    """The skirt and four thruster pods.  Authored around a wedge's footprint
    (HOVER_HALF_LEN by HOVER_HALF_WID) with the skirt's TOP at y = 0, so
    `hover.gd` hangs it straight off `floor_y()` and it fills the gap under the
    machine; `hover.gd` scales it in X and Z to the hull.

    The skirt is a stadium of straight runs and corner posts rather than a
    cylinder, because the hull it seals against is a rectangle and a round ring
    under a square machine reads as a mistake.

    DEPTH IS THE READ, and the first cut got it wrong.  A hover rides 0.20 m off
    the floor; a 0.05 m band under a hull that high is a picture frame with
    daylight under it, which is exactly what it looked like.  The skirt is
    SKIRT_DEPTH deep, its lower two thirds are a rubber curtain rather than
    structure, and a perforated plenum floor closes the middle so you cannot see
    the arena through the machine."""
    # uv_scale 3.0: this is the largest part in the kit by surface area and the
    # only one whose unwrap lands below the texel density floor.  See the long
    # note on `Part.uv_scale` in rkit.py.
    P = Part("hover", "drive", uv_scale=3.0)
    hl, hw = HOVER_HALF_LEN, HOVER_HALF_WID
    d = SKIRT_DEPTH
    t = 0.040                                   # the band's own thickness
    cr = 0.058                                  # corner post radius
    rail_y = -0.018                             # centre of the structural rail
    curt_y = -d * 0.66                          # centre of the rubber curtain

    # the four straight runs: a stiff structural rail with a rubber curtain hung
    # under it, the curtain proud of the rail so it reads as a separate thing
    for sz in (-1.0, 1.0):
        P.box((0.0, rail_y, sz * (hw - t * 0.5)), (2 * (hl - cr), 0.036, t),
              "livery", bevel=0.004, seg=2)
        P.box((0.0, curt_y, sz * (hw - t * 0.5 + 0.004)),
              (2 * (hl - cr) + 0.004, d * 0.62, t * 0.62), "rubber",
              bevel=0.004, seg=2)
        P.bolt_line((-(hl - cr) + 0.06, rail_y, sz * (hw - t)),
                    ((hl - cr) - 0.06, rail_y, sz * (hw - t)), 5, (0, 0, sz))
        P.ribs((0.0, curt_y, sz * (hw - 0.002)),
               (2 * (hl - cr) - 0.12, 0.0, 0.0), 7, "rubber",
               normal=2, run=0, h=sz * 0.008, w=0.016)
        # the hem: the wear strip that actually touches down
        P.box((0.0, -d + 0.009, sz * (hw - t * 0.5 + 0.004)),
              (2 * (hl - cr) + 0.010, 0.018, t * 0.78), "titanium",
              bevel=0.003, seg=1)
    for sx in (-1.0, 1.0):
        P.box((sx * (hl - t * 0.5), rail_y, 0.0), (t, 0.036, 2 * (hw - cr)),
              "livery", bevel=0.004, seg=2)
        P.box((sx * (hl - t * 0.5 + 0.004), curt_y, 0.0),
              (t * 0.62, d * 0.62, 2 * (hw - cr) + 0.004), "rubber",
              bevel=0.004, seg=2)
        P.bolt_line((sx * (hl - t), rail_y, -(hw - cr) + 0.05),
                    (sx * (hl - t), rail_y, (hw - cr) - 0.05), 4, (sx, 0, 0))
        P.box((sx * (hl - t * 0.5 + 0.004), -d + 0.009, 0.0),
              (t * 0.78, 0.018, 2 * (hw - cr) + 0.010), "titanium",
              bevel=0.003, seg=1)

    # the plenum floor, perforated: the cushion needs somewhere to be
    P.box((0.0, -d * 0.40, 0.0), (2 * (hl - cr) + 0.02, 0.012,
                                  2 * (hw - cr) + 0.02), "dark_metal",
          bevel=0.003, seg=1)
    for ix in range(4):
        for iz in range(3):
            P.cyl(((ix - 1.5) * 0.19, -d * 0.40 + 0.008, (iz - 1.0) * 0.14),
                  (0, 1, 0), 0.026, 0.010, "steel", n=8, bevel=0.0)
    P.ribs((0.0, -d * 0.40 - 0.008, 0.0), (0.0, 0.0, 2 * (hw - cr) - 0.04), 5,
           "steel", normal=1, run=2, h=-0.010, w=0.016)

    # corner posts, which are also where the pods hang
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            cx, cz = sx * (hl - cr), sz * (hw - cr)
            P.cyl((cx, rail_y, cz), (0, 1, 0), cr, 0.036, "livery", n=12,
                  bevel=0.004)
            P.cyl((cx, curt_y, cz), (0, 1, 0), cr * 0.90, d * 0.62, "rubber",
                  n=12, bevel=0.004)
            P.cyl((cx, -d + 0.009, cz), (0, 1, 0), cr * 0.96, 0.018,
                  "titanium", n=12, bevel=0.003)
            P.ring((cx, 0.002, cz), (0, 1, 0), cr, cr - 0.014, 0.014, "steel",
                   n=12)
            _thruster_pod(P, (cx, -d * 0.44, cz))
            # the duct that feeds the pod from inside the machine
            P.cyl((cx - sx * 0.022, -0.008, cz - sz * 0.022), (0, 1, 0), 0.024,
                  0.044, "dark_metal", n=8, bevel=0.002)
    P.socket("socket_tip", (0.0, -d, 0.0))
    return P

def build_adaptive_tracks(_spec=None):
    """The segmented belt.  Same envelope as `track_unit` (0.70 long, centred,
    0.09 across, inboard frame plate on -Z) so `tracks.gd` can scale and place
    it with the code it already has, and a different BELT: discrete link plates
    on pins instead of one moulded skin, which is the visible half of "the belts
    are segmented and cannot be torn off".

    The sprockets and the road wheels are streams opened with their own origins
    and named `spin_*`, so `PartVisuals` gives them a `PartAnim` and they turn
    with the machine's road speed."""
    P = Part("adaptive_tracks", "drive")
    half = 0.35
    rr = 0.10
    cx = half - rr
    hz = 0.045
    t = 0.016

    # the belt path, as track_unit's, then the links laid on it
    path = []
    seg = 7
    for i in range(seg + 1):
        a = -math.pi * 0.5 + math.pi * i / seg
        path.append((cx + rr * math.cos(a), rr * math.sin(a)))
    for i in range(seg + 1):
        a = math.pi * 0.5 + math.pi * i / seg
        path.append((-cx + rr * math.cos(a), rr * math.sin(a)))

    for i, (x, y) in enumerate(path):
        ox = cx if x > 0 else -cx
        a = math.atan2(y, x - ox)
        c, s = math.cos(a), math.sin(a)
        # one link plate, standing off the pitch line, with its pin either side
        P.box((x - c * t * 0.5, y - s * t * 0.5, 0.0),
              (0.030, t, 2 * hz - 0.004), "steel", bevel=0.0025, seg=1,
              rot=rot_pitch(math.degrees(a)))
        if i % 2 == 0:
            # grouser crown ON the wheel radius, 0.110 (was 0.1195, wave A pass 2)
            P.box((x + c * 0.0045, y + s * 0.0045, 0.0),
                  (0.011, 0.030, 2 * hz + 0.006), "titanium", bevel=0.003, seg=1,
                  rot=rot_pitch(math.degrees(a)))
        if i % 2 == 0:
            for sz in (-1.0, 1.0):
                P.cyl((x - c * 0.004, y - s * 0.004, sz * (hz + 0.002)),
                      (0, 0, sz), 0.0072, 0.010, "dark_metal", n=6, bevel=0.0)

    # sprockets: their own nodes, on their own axes, so they can turn
    for sgn, nm in ((1.0, "spin_sprocket_f"), (-1.0, "spin_sprocket_r")):
        P.use(nm, origin=(sgn * cx, 0.0, 0.0))
        P.cyl((0, 0, 0), (0, 0, 1), rr - t - 0.012, 2 * hz - 0.016,
              "dark_metal", n=12, bevel=0.002)
        for i in range(8):
            a = 2.0 * math.pi * i / 8.0
            P.box(((rr - t - 0.004) * math.cos(a), (rr - t - 0.004) * math.sin(a), 0.0),
                  (0.018, 0.026, 2 * hz - 0.024), "steel", bevel=0.0,
                  rot=rot_pitch(math.degrees(a)))
        for sz in (-1.0, 1.0):
            P.ring((0, 0, sz * (hz - 0.012)), (0, 0, sz), rr - t - 0.030,
                   0.020, 0.010, "titanium", n=12)
        P.bearing_cap((0, 0, -(hz + 0.030)), (0, 0, -1), 0.026, h=0.012, n=8)
    P.use("body")

    # four road wheels, likewise on their own axes
    for i, x in enumerate((-0.185, -0.062, 0.062, 0.185)):
        r = 0.050 if abs(x) < 0.12 else 0.046
        P.use("spin_roller_%d" % i, origin=(x, -0.028, 0.0))
        P.cyl((0, 0, 0), (0, 0, 1), r, 2 * hz - 0.020, "dark_metal", n=10,
              bevel=0.002)
        P.ring((0, 0, 0), (0, 0, 1), r - 0.008, r - 0.022, 2 * hz - 0.014,
               "rubber", n=10)
        for sz in (-1.0, 1.0):
            P.bolt((0.0, r - 0.018, sz * (hz - 0.012)), (0, 0, sz), r=0.006)
    P.use("body")

    # inboard frame: heavier than the plain track's, with the torsion bars and
    # the segment tensioners that are why this belt stays on
    P.plate((0.0, -0.012, -(hz + 0.011)), (2 * half - 0.04, 0.125, 0.016),
            "steel", axis=(0, 0, -1), inset=0.042, hardware=True)
    P.ribs((0.0, -0.012, -(hz + 0.021)), (2 * half - 0.16, 0.0, 0.0), 5,
           "steel", normal=2, run=1, h=-0.009, w=0.016)
    for x in (-0.185, -0.062, 0.062, 0.185):
        P.cyl((x, -0.028, -(hz + 0.026)), (0, 0, -1), 0.022, 0.022,
              "dark_metal", n=10, bevel=0.002)
        P.boss((x, -0.028, -(hz + 0.036)), (0, 0, -1), 0.013, 0.007)
    for sgn in (1.0, -1.0):
        P.cyl((sgn * cx, 0.0, -(hz + 0.024)), (0, 0, -1), 0.030, 0.026,
              "dark_metal", n=10, bevel=0.002)
        # the tensioner: a screw and its lock nut on the idler end
        P.cyl((sgn * (cx + 0.036), 0.052, -(hz + 0.014)), (sgn, 0, 0), 0.008,
              0.050, "titanium", n=8)
        P.ring((sgn * (cx + 0.018), 0.052, -(hz + 0.014)), (sgn, 0, 0), 0.014,
               0.008, 0.010, "steel", n=8)
    P.box((0.0, 0.060, -(hz + 0.014)), (2 * half - 0.16, 0.022, 0.022),
          "livery", bevel=0.003, seg=2)
    P.drain_slots((-0.20, -0.082, -(hz + 0.012)), (0.20, -0.082, -(hz + 0.012)),
                  4, w=0.026, h=0.010, depth=0.018)
    P.seam((-0.29, 0.062, -(hz + 0.019)), (0.29, 0.062, -(hz + 0.019)))
    return P


BUILDERS.update({
    "legs": build_legs,
    "hover": build_hover,
    "adaptive_tracks": build_adaptive_tracks,
})
