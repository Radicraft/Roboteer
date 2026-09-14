"""The five arena bosses (brief v3 §8, stage5-spec §4).

Two files each, in `Arena/assets/parts/boss/`:

    <id>.glb        the signature part, origin = the chassis socket it fits,
                    same conventions as every other part (`socket_pivot` at the
                    joint axis, `socket_tip` at the business end, the eight
                    named material slots)
    <id>_hull.glb   a decorative overlay, ONE mesh named `overlay`, authored in
                    the host chassis' own space so it parents to the chassis
                    root at identity and sits a few mm proud of the hull

IP: brief §3 says the resemblance test is SILHOUETTE, not name, and rules out
the house robots.  Each design below is deliberately steered away from the
shape it would otherwise drift into:

  THRESHER  a symmetric PAIR of harvester-style jaws on one cross shaft, not a
            single claw on an arm and no lance.
  GRUDGE    an industrial refinery turret: twin nozzles and an upright fuel
            drum.  No animal face, no claw, no military styling.
  BANDSAW   a continuous BAND blade looping round two small pulleys in a
            slim fore-aft bar carried on posts ABOVE the deck.  Nothing here
            is a circular saw on a swinging arm; the first attempt at this one
            was rejected on exactly that test and rebuilt.
  ANVIL     a full-width riveted wall plus a drop-forge gantry: two uprights
            and a crosshead.  Not a wedge with an axe on a stick.
  CINDER    a wide curved scoop whose throw arm is driven by a visible chain
            and sprockets running along the flank.

Each `<id>.glb` is authored for ONE host chassis, because the boss builds are
fixed (stage5-spec §4).  The host and the socket are named in each builder.
"""

import math

from mathutils import Vector

from rkit import Part, BEVEL, PLATE_T, rot_pitch, rot_z, rot_roll


# ---------------------------------------------------------------- THRESHER
# host: long_low, socket_weapon_front (0.270, 0.012)

def build_thresher(_spec=None):
    P = Part("thresher", "boss")
    hw = 0.19                      # arm centres, so the pair is 0.38 across
    reach = 0.32

    # one cross shaft carrying both arms, in a heavy yoke
    P.shaft((0.0, 0.0, -0.255), (0.0, 0.0, 0.255), 0.021, "steel", n=12,
            grooves=(0.10, 0.90), step=0.0)
    for s in (-1.0, 1.0):
        P.box((-0.020, 0.0, s * 0.235), (0.086, 0.110, 0.026), "dark_metal",
              bevel=0.004, seg=2)
        P.hardware_bolt((-0.050, -0.030, s * 0.235), (0, 0, s))
        P.box((-0.020, 0.0, s * 0.075), (0.078, 0.098, 0.024), "dark_metal",
              bevel=0.004, seg=2)
    P.box((-0.062, 0.0, 0.0), (0.030, 0.120, 0.50), "dark_metal", bevel=0.004, seg=2)
    P.ribs((-0.078, 0.0, 0.0), (0.0, 0.090, 0.44), 5, "steel", normal=0, run=1,
           h=-0.012, w=0.016)

    # the jaw pair: each arm sweeps forward and down onto a fixed serrated bed
    for s in (-1.0, 1.0):
        z0, z1 = s * hw - 0.028, s * hw + 0.028
        pts = [(0.02, 0.055), (0.13, 0.062), (0.235, 0.030), (reach, -0.030)]
        for i in range(3):
            P.slab(pts[i], pts[i + 1], z0, z1, 0.030, "titanium",
                   outward=(0.2, 1.0), bolts=2, inset=0.03)
        # serrations along the closing edge
        for i in range(5):
            t = (i + 0.5) / 5.0
            ax = pts[0][0] + (pts[3][0] - pts[0][0]) * t
            ay = 0.052 - 0.075 * t * t - 0.012 * t
            P.prism([(0.0, 0.0), (0.046, 0.004), (0.020, -0.052)],
                    z0 + 0.004, z1 - 0.004, "steel", bevel=0.0025, seg=1,
                    at=(ax, ay, 0.0))
        # the hydraulic ram that closes it
        P.cyl((-0.030, 0.115, s * hw), (1.0, -0.55, 0.0), 0.026, 0.115,
              "steel", n=12, bevel=0.003)
        P.cyl((0.055, 0.068, s * hw), (1.0, -0.55, 0.0), 0.012, 0.085,
              "titanium", n=8, bevel=0.0)
        P.cyl((-0.085, 0.145, s * hw), (1.0, -0.55, 0.0), 0.017, 0.022,
              "dark_metal", n=8, bevel=0.002)
        P.box((-0.105, 0.150, s * hw), (0.060, 0.055, 0.075), "dark_metal",
              bevel=0.003, seg=1)

    # a cross tie so the two arms read as one tool, not two
    P.box((0.115, 0.072, 0.0), (0.050, 0.030, 2 * hw), "livery", bevel=0.004, seg=2)
    for z in (-0.12, 0.0, 0.12):
        P.hardware_bolt((0.115, 0.088, z), (0, 1, 0))

    # fixed lower bed, also serrated: this is what the jaws squeeze onto
    P.slab((0.03, -0.058), (reach - 0.02, -0.088), -0.225, 0.225, 0.026,
           "steel", outward=(0.2, 1.0), bolts=3, inset=0.05)
    for i in range(7):
        z = -0.18 + i * 0.06
        P.prism([(0.0, 0.0), (0.040, -0.006), (0.016, 0.044)],
                z - 0.011, z + 0.011, "titanium", bevel=0.0025, seg=1,
                at=(0.215, -0.050, 0.0))
    P.socket("socket_pivot", (0.0, 0.0, 0.0))
    P.socket("socket_tip", (reach, -0.030, 0.0))
    return P


def build_thresher_hull(_spec=None):
    """Overlay for long_low: agricultural belt banding and low work lamps."""
    P = Part("thresher_hull", "boss", mesh_name="overlay")
    hl, hw = 0.60, 0.222
    deck = 0.050

    for s in (-1.0, 1.0):
        # two heavy belt bands the length of the flank
        for y in (-0.052, 0.006):
            P.box((0.0, y, s * hw), (2 * hl - 0.08, 0.030, 0.020), "titanium",
                  bevel=0.004, seg=2)
            P.bolt_line((-hl + 0.10, y, s * (hw + 0.011)),
                        (hl - 0.10, y, s * (hw + 0.011)), 7, (0, 0, s), r=0.008)
        # vertical straps tying them together
        for x in (-0.42, -0.14, 0.14, 0.42):
            P.box((x, -0.024, s * (hw - 0.002)), (0.044, 0.100, 0.018),
                  "dark_metal", bevel=0.003, seg=2)
        # a low work lamp at each front corner
        P.cyl((0.505, -0.016, s * (hw - 0.006)), (0.35, 0.0, s), 0.030, 0.034,
              "dark_metal", n=12, bevel=0.003)
        P.cone((0.518, -0.016, s * (hw + 0.005)), (0.35, 0.0, s), 0.026, 0.020,
               0.012, "core_glow", n=12)
        P.ring((0.522, -0.016, s * (hw + 0.008)), (0.35, 0.0, s), 0.032, 0.026,
               0.010, "steel", n=12)

    # a raised spine rail down the deck with mesh infill
    P.box((0.0, deck + 0.016, 0.0), (2 * hl - 0.24, 0.026, 0.070), "dark_metal",
          bevel=0.004, seg=2)
    P.ribs((0.0, deck + 0.030, 0.0), (0.90, 0.0, 0.0), 9, "titanium",
           normal=1, run=2, h=0.010, w=0.018)
    for x in (-0.40, 0.0, 0.40):
        P.hardware_bolt((x, deck + 0.030, 0.046), (0, 1, 0))
        P.hardware_bolt((x, deck + 0.030, -0.046), (0, 1, 0))
    return P


# ------------------------------------------------------------------ GRUDGE
# host: box, socket_weapon_top (0.200, 0.089)

def build_grudge(_spec=None):
    P = Part("grudge", "boss")
    # turret ring it swings on
    P.ring((0.0, 0.012, 0.0), (0, 1, 0), 0.125, 0.098, 0.028, "dark_metal", n=24)
    for i in range(8):
        a = 2.0 * math.pi * i / 8.0
        P.hardware_bolt((0.112 * math.cos(a), 0.026, 0.112 * math.sin(a)), (0, 1, 0))

    # turret body: a chamfered drum, plainly industrial, no face
    P.prism([(0.16, 0.030), (0.16, 0.120), (0.10, 0.175), (-0.13, 0.175),
             (-0.18, 0.120), (-0.18, 0.030)], -0.115, 0.115, "livery",
            bevel=0.005, seg=2)
    P.ribs((-0.02, 0.176, 0.0), (0.26, 0.0, 0.0), 4, "dark_metal",
           normal=1, run=2, h=0.010, w=0.016)
    for s in (-1.0, 1.0):
        P.plate((-0.01, 0.105, s * 0.120), (0.28, 0.110, 0.014), "steel",
                axis=(0, 0, s), inset=0.030, hardware=True)

    # twin nozzles, side by side
    for s in (-1.0, 1.0):
        z = s * 0.062
        P.cyl((0.215, 0.085, z), (1, 0, 0), 0.030, 0.130, "dark_metal", n=12, bevel=0.003)
        P.ring((0.170, 0.085, z), (1, 0, 0), 0.036, 0.030, 0.016, "steel", n=12)
        P.cone((0.288, 0.085, z), (1, 0, 0), 0.030, 0.016, 0.042, "steel", n=12)
        P.ring((0.318, 0.085, z), (1, 0, 0), 0.024, 0.015, 0.016, "titanium", n=12)
        # ignition electrodes, one pair per nozzle
        for t in (-1.0, 1.0):
            P.cyl((0.305, 0.085 + t * 0.026, z), (1, 0, 0), 0.004, 0.046,
                  "titanium", n=6)
        # feed pipe from the manifold
        P.cyl((0.118, 0.085, z), (1, 0, 0), 0.011, 0.090, "titanium", n=8, bevel=0.0)
    P.box((0.062, 0.085, 0.0), (0.052, 0.062, 0.175), "dark_metal", bevel=0.004, seg=2)
    P.cyl((0.062, 0.122, 0.0), (0, 1, 0), 0.017, 0.022, "steel", n=8, bevel=0.002)

    # the fuel drum standing on the back of the turret
    P.cyl((-0.118, 0.290, 0.0), (0, 1, 0), 0.086, 0.215, "steel", n=18, bevel=0.005)
    P.cone((-0.118, 0.404, 0.0), (0, 1, 0), 0.086, 0.060, 0.022, "steel", n=18)
    P.cone((-0.118, 0.176, 0.0), (0, 1, 0), 0.060, 0.086, 0.022, "steel", n=18)
    for y in (0.230, 0.348):
        P.ring((-0.118, y, 0.0), (0, 1, 0), 0.094, 0.086, 0.020, "dark_metal", n=18)
        P.hardware_bolt((-0.118 + 0.094, y, 0.0), (1, 0, 0))
    P.cyl((-0.118, 0.428, 0.0), (0, 1, 0), 0.022, 0.030, "dark_metal", n=10, bevel=0.002)
    P.cyl((-0.118, 0.448, 0.0), (0, 0, 1), 0.008, 0.070, "steel", n=6, bevel=0.0)
    # the run from the drum down to the manifold
    P.cable_run([(-0.118, 0.190, 0.062), (0.010, 0.130, 0.062),
                 (0.062, 0.110, 0.062)], r=0.010, channel=False)
    P.socket("socket_pivot", (0.0, 0.0, 0.0))
    P.socket("socket_tip", (0.330, 0.085, 0.0))
    return P


def build_grudge_hull(_spec=None):
    """Overlay for box: corrugated heat shielding and a wide slit lamp."""
    P = Part("grudge_hull", "boss", mesh_name="overlay")
    cl, hw = 0.386, 0.250
    low, bay_x1, bw = 0.075, -0.030, 0.211

    for s in (-1.0, 1.0):
        # corrugated shield standing off the lower flank
        P.box((0.0, 0.006, s * hw), (2 * cl - 0.06, 0.112, 0.012), "dark_metal",
              bevel=0.003, seg=2)
        P.ribs((0.0, 0.006, s * (hw + 0.006)), (2 * cl - 0.16, 0.0, 0.0), 9,
               "titanium", normal=2, run=1, h=s * 0.012, w=0.020)
        for x in (-0.33, 0.33):
            P.box((x, 0.006, s * (hw + 0.004)), (0.030, 0.128, 0.022), "steel",
                  bevel=0.003, seg=2)
            P.hardware_bolt((x, 0.060, s * (hw + 0.015)), (0, 0, s))
            P.hardware_bolt((x, -0.048, s * (hw + 0.015)), (0, 0, s))
        # shielding up the raised rear bay
        P.box((-0.208, 0.124, s * (bw + 0.006)), (0.330, 0.078, 0.012),
              "dark_metal", bevel=0.003, seg=2)
        P.ribs((-0.208, 0.124, s * (bw + 0.012)), (0.28, 0.0, 0.0), 5,
               "titanium", normal=2, run=1, h=s * 0.010, w=0.018)

    # scorch cowl over the forward deck
    P.slab((cl - 0.010, low + 0.028), (0.140, low + 0.070), -0.215, 0.215, 0.014,
           "steel", outward=(0.7, 1.0), bolts=3, inset=0.05)
    P.ribs((0.250, low + 0.058, 0.0), (0.0, 0.0, 0.38), 3, "dark_metal",
           normal=1, run=0, h=0.011, w=0.020)

    # one wide slit lamp across the front of the raised bay
    P.box((bay_x1 + 0.012, 0.126, 0.0), (0.024, 0.048, 0.270), "dark_metal",
          bevel=0.004, seg=2)
    P.box((bay_x1 + 0.026, 0.126, 0.0), (0.008, 0.022, 0.230), "core_glow",
          bevel=0.002, seg=1)
    for z in (-0.150, 0.150):
        P.hardware_bolt((bay_x1 + 0.020, 0.126, z), (1, 0, 0))
    return P


# ----------------------------------------------------------------- BANDSAW
# host: wedge, socket_weapon_front (0.070, 0.050)

def build_bandsaw(_spec=None):
    """REJECTED AND REBUILT once: the first version sat the loop down inside the
    wedge deck, so only one pulley showed and it read as a toothed disc, which
    is the one silhouette this boss must not have.  The loop now rides entirely
    ABOVE the deck on two posts, long and thin, with both pulleys and both runs
    of the band visible from any angle."""
    P = Part("bandsaw", "boss")
    half, pr = 0.345, 0.058
    cx = half - pr
    cy = 0.132                     # loop centre, above the wedge deck line
    hz = 0.010
    t = 0.009

    path = []
    seg = 8
    for i in range(seg + 1):
        a = -math.pi * 0.5 + math.pi * i / seg
        path.append((cx + pr * math.cos(a), cy + pr * math.sin(a)))
    for i in range(seg + 1):
        a = math.pi * 0.5 + math.pi * i / seg
        path.append((-cx + pr * math.cos(a), cy + pr * math.sin(a)))
    P.band(path, -hz, hz, t, "titanium", bevel=0.0)
    for i in range(len(path)):
        x, y = path[i]
        a = math.atan2(y - cy, x - (cx if x > 0 else -cx))
        P.box((x + 0.007 * math.cos(a), y + 0.007 * math.sin(a), 0.0),
              (0.013, 0.017, 2 * hz), "steel", bevel=0.0,
              rot=rot_pitch(math.degrees(a)))

    for sgn in (1.0, -1.0):
        P.cyl((sgn * cx, cy, 0.0), (0, 0, 1), pr - t - 0.005, 0.038,
              "dark_metal", n=12, bevel=0.003)
        for side in (-1.0, 1.0):
            P.bearing_cap((sgn * cx, cy, side * 0.020), (0, 0, side), 0.020,
                          h=0.010, n=8)

    # slim frame bar hugging the loop, open on the cutting (lower) side
    for sy, mat in ((1.0, "livery"), (-1.0, "livery")):
        P.box((0.0, cy + sy * (pr + 0.024), -0.026), (2 * half - 0.04, 0.022, 0.014),
              mat, bevel=0.004, seg=2)
    for sgn in (1.0, -1.0):
        P.box((sgn * (half - 0.012), cy, -0.026), (0.022, 2 * pr + 0.046, 0.014),
              "livery", bevel=0.004, seg=2)
    P.ribs((0.0, cy + pr + 0.024, -0.034), (2 * half - 0.14, 0.0, 0.0), 5,
           "dark_metal", normal=2, run=0, h=-0.010, w=0.016)
    for x in (-0.24, 0.0, 0.24):
        P.hardware_bolt((x, cy + pr + 0.024, -0.034), (0, 0, -1))
    # guard over the top run only, so the lower run is the cutting edge
    P.box((0.02, cy + pr + 0.030, 0.0), (2 * half - 0.10, 0.014, 0.044),
          "steel", bevel=0.003, seg=2)

    # two posts carrying the bar clear of the deck, and the motor at the base
    for px in (-cx + 0.02, 0.16):
        P.box((px, cy * 0.5 - 0.012, -0.026), (0.046, cy + 0.024, 0.030),
              "dark_metal", bevel=0.004, seg=2)
        P.hardware_bolt((px, 0.004, -0.026), (0, 1, 0))
        P.slab((px + 0.030, 0.010), (px - 0.004, cy - 0.030), -0.036, -0.020,
               0.012, "steel", outward=(1.0, 0.0))
    P.cyl((-cx + 0.02, 0.012, -0.026), (0, 0, 1), 0.044, 0.074, "dark_metal",
          n=14, bevel=0.003)
    P.ring((-cx + 0.02, 0.012, -0.026), (0, 0, 1), 0.050, 0.044, 0.050, "steel", n=14)
    P.slab((-cx + 0.02, cy - pr + 0.006), (-cx + 0.02, 0.056), -0.070, -0.052,
           0.012, "livery", outward=(0, 1))
    P.box((-cx - 0.032, 0.012, -0.026), (0.034, 0.056, 0.056), "dark_metal",
          bevel=0.003, seg=1)
    P.socket("socket_pivot", (cx, cy, 0.0))
    P.socket("socket_tip", (half + 0.008, cy, 0.0))
    return P


def build_bandsaw_hull(_spec=None):
    """Overlay for wedge: an open tube cage and a single lamp on a stalk.
    BANDSAW is the light, fast one, so its skin is skeletal rather than armour."""
    P = Part("bandsaw_hull", "boss", mesh_name="overlay")
    deck, hw = 0.076, 0.248

    # roll cage: four uprights, two longitudinal tubes, two cross tubes
    for s in (-1.0, 1.0):
        for x in (-0.36, 0.06):
            P.cyl((x, deck + 0.055, s * 0.170), (0, 1, 0), 0.011, 0.110,
                  "titanium", n=8, bevel=0.0)
            P.box((x, deck + 0.006, s * 0.170), (0.050, 0.014, 0.050),
                  "dark_metal", bevel=0.002, seg=1)
            P.hardware_bolt((x, deck + 0.013, s * 0.170), (0, 1, 0))
        P.cyl((-0.150, deck + 0.108, s * 0.170), (1, 0, 0), 0.011, 0.420,
              "titanium", n=8, bevel=0.0)
    for x in (-0.36, 0.06):
        P.cyl((x, deck + 0.108, 0.0), (0, 0, 1), 0.011, 0.340, "titanium", n=8, bevel=0.0)
    P.cyl((-0.15, deck + 0.108, 0.0), (0.0, 0.0, 1.0), 0.009, 0.340, "titanium",
          n=6, bevel=0.0)

    # light flank blades, nothing like armour
    for s in (-1.0, 1.0):
        P.slab((0.30, -0.050), (-0.40, 0.010), s * hw - 0.007, s * hw + 0.007,
               0.014, "livery", outward=(0.1, 1.0))
        P.bolt_line((-0.34, -0.024, s * (hw + 0.009)), (0.24, -0.024, s * (hw + 0.009)),
                    5, (0, 0, s), r=0.008)

    # one lamp on a stalk, looking forward over the cage
    P.cyl((-0.395, deck + 0.082, 0.0), (0, 1, 0), 0.013, 0.075, "dark_metal",
          n=8, bevel=0.0)
    P.box((-0.372, deck + 0.122, 0.0), (0.060, 0.044, 0.058), "dark_metal",
          bevel=0.005, seg=2)
    P.cone((-0.340, deck + 0.122, 0.0), (1, 0, 0), 0.018, 0.013, 0.012,
           "core_glow", n=12)
    P.ring((-0.336, deck + 0.122, 0.0), (1, 0, 0), 0.024, 0.018, 0.010, "steel", n=12)
    return P


# ------------------------------------------------------------------- ANVIL
# host: tall_tank.  Origin = socket_weapon_front (0.436, 0.025); the hammer
# gantry is modelled at the offset to socket_weapon_top (0.090, 0.405), i.e.
# local (-0.346, 0.380), so ONE parent at the front socket places both.

HAMMER = (-0.346, 0.380)


def build_anvil(_spec=None):
    P = Part("anvil", "boss")
    hz = 0.345                     # full tall_tank width
    wall_lo, wall_hi = -0.075, 0.275

    # the wall: a full-width riveted plate leaning slightly forward
    P.slab((0.030, wall_lo), (-0.010, wall_hi), -hz, hz, 0.030, "steel",
           outward=(1.0, 0.10))
    for row in range(5):
        y = wall_lo + 0.040 + row * 0.068
        for i in range(11):
            z = -0.300 + i * 0.060
            P.cone((0.034 - 0.0046 * row, y, z), (1.0, 0.10, 0.0),
                   0.0105, 0.0072, 0.0055, "dark_metal", n=6)
    # vertical stiffener channels
    for z in (-0.245, -0.082, 0.082, 0.245):
        P.slab((0.036, wall_lo + 0.010), (-0.004, wall_hi - 0.010),
               z - 0.022, z + 0.022, 0.022, "dark_metal", outward=(1.0, 0.10))
    # rolled top edge and a scraper lip along the bottom
    P.cyl((0.006, wall_hi, 0.0), (0, 0, 1), 0.019, 2 * hz, "steel", n=10, bevel=0.0)
    P.slab((0.040, wall_lo + 0.004), (-0.010, wall_lo - 0.034), -hz, hz, 0.014,
           "titanium", outward=(0.8, -0.6))
    P.drain_slots((0.014, wall_lo - 0.020, -0.26), (0.014, wall_lo - 0.020, 0.26),
                  5, w=0.034, h=0.012, depth=0.036)
    for s in (-1.0, 1.0):
        P.box((0.006, (wall_lo + wall_hi) * 0.5, s * (hz + 0.010)),
              (0.060, wall_hi - wall_lo, 0.020), "livery", bevel=0.004, seg=2)

    # the drop-forge gantry: two uprights and a crosshead
    gx, gy = HAMMER
    for s in (-1.0, 1.0):
        P.box((gx, gy - 0.090, s * 0.155), (0.050, 0.190, 0.040), "dark_metal",
              bevel=0.004, seg=2)
        P.hardware_bolt((gx, gy - 0.175, s * 0.155), (0, 1, 0))
        P.slab((gx + 0.026, gy - 0.170), (gx + 0.026, gy - 0.010),
               s * 0.155 - 0.012, s * 0.155 + 0.012, 0.014, "livery",
               outward=(1.0, 0.0))
    P.box((gx, gy + 0.020, 0.0), (0.076, 0.048, 0.360), "steel", bevel=0.005, seg=2)
    P.ribs((gx, gy + 0.046, 0.0), (0.0, 0.0, 0.30), 4, "dark_metal",
           normal=1, run=0, h=0.010, w=0.018)
    P.shaft((gx, gy, -0.185), (gx, gy, 0.185), 0.020, "steel", n=10,
            grooves=(0.09, 0.91), step=0.0)

    # hammer arm, cocked back and up, ending in a forged head
    tip = (gx - 0.300, gy + 0.180)
    P.slab((gx, gy), tip, -0.046, 0.046, 0.050, "titanium",
           outward=(-0.5, -0.9), bolts=3, inset=0.05)
    P.ribs(((gx + tip[0]) * 0.5, (gy + tip[1]) * 0.5 + 0.030, 0.0),
           (0.0, 0.0, 0.070), 2, "steel", normal=1, run=0, h=0.012, w=0.020)
    P.box((tip[0], tip[1], 0.0), (0.160, 0.140, 0.160), "steel", bevel=0.007, seg=2)
    P.prism([(0.0, 0.068), (0.0, -0.068), (0.078, -0.040), (0.078, 0.040)],
            -0.078, 0.078, "titanium", bevel=0.005, seg=2,
            at=(tip[0] - 0.078, tip[1], 0.0))
    for sz in (-1.0, 1.0):
        P.ribs((tip[0], tip[1], sz * 0.080), (0.110, 0.0, 0.0), 3, "dark_metal",
               normal=2, run=1, h=sz * 0.010, w=0.018)
    for su in (-1, 1):
        for sv in (-1, 1):
            P.hardware_bolt((tip[0] + su * 0.050, tip[1] + 0.072, sv * 0.052),
                            (0, 1, 0))
    P.socket("socket_pivot", (gx, gy, 0.0))
    P.socket("socket_tip", (tip[0] - 0.156, tip[1], 0.0))
    return P


def build_anvil_hull(_spec=None):
    """Overlay for tall_tank: slab armour, buttress ribs and a twin visor slot."""
    P = Part("anvil_hull", "boss", mesh_name="overlay")
    base, split, deck, top = -0.05, 0.16, 0.356, 0.37
    cl, hw, uw, ul = 0.436, 0.312, 0.256, 0.336

    for s in (-1.0, 1.0):
        # slab armour on the lower box, with buttresses
        P.box((0.0, (base + split) * 0.5, s * hw), (2 * cl - 0.05, split - base - 0.02,
              0.016), "dark_metal", bevel=0.004, seg=2)
        for x in (-0.30, -0.10, 0.10, 0.30):
            P.prism([(0.0, 0.0), (0.0, 0.170), (0.052, 0.0)],
                    s * hw - 0.021, s * hw + 0.021, "steel", bevel=0.003, seg=1,
                    at=(x - 0.026, base + 0.012, 0.0))
            P.hardware_bolt((x, base + 0.030, s * (hw + 0.010)), (0, 0, s))
        # upper box side plating
        P.box((-0.02, (split + deck) * 0.5 + 0.02, s * uw),
              (2 * ul - 0.05, deck - split - 0.07, 0.014), "dark_metal",
              bevel=0.004, seg=2)
        P.ribs((-0.02, (split + deck) * 0.5 + 0.02, s * (uw + 0.008)),
               (2 * ul - 0.14, 0.0, 0.0), 4, "livery", normal=2, run=1,
               h=s * 0.012, w=0.022)

    # heavy chamfered brow over the front of the upper box
    P.slab((-0.02 + ul + 0.022, split + 0.060), (-0.02 + ul - 0.050, deck + 0.012),
           -uw + 0.010, uw - 0.010, 0.026, "steel", outward=(1.0, 0.45),
           bolts=3, inset=0.05)
    # twin vertical visor slots, set into the brow
    for s in (-1.0, 1.0):
        P.box((-0.02 + ul + 0.020, 0.268, s * 0.072), (0.024, 0.110, 0.046),
              "dark_metal", bevel=0.004, seg=2)
        P.box((-0.02 + ul + 0.034, 0.268, s * 0.072), (0.008, 0.082, 0.018),
              "core_glow", bevel=0.002, seg=1)
    # a capping band round the top deck
    for s in (-1.0, 1.0):
        P.box((-0.02, top + 0.010, s * (uw - 0.014)), (2 * ul - 0.05, 0.020, 0.022),
              "steel", bevel=0.004, seg=2)
    return P


# ------------------------------------------------------------------ CINDER
# host: box, socket_weapon_front (0.386, -0.005)

def build_cinder(_spec=None):
    P = Part("cinder", "boss")
    hz = 0.36                      # oversized: wider than the chassis
    sprocket_r = 0.092

    # hinge line
    P.shaft((0.0, 0.0, -0.30), (0.0, 0.0, 0.30), 0.020, "steel", n=12,
            grooves=(0.12, 0.88), step=0.0)
    for s in (-1.0, 1.0):
        P.box((-0.030, -0.010, s * 0.275), (0.080, 0.100, 0.028), "dark_metal",
              bevel=0.004, seg=2)
        P.hardware_bolt((-0.058, -0.046, s * 0.275), (0, 0, s))

    # the scoop: a wide curve that is also the throw face
    pts = [(0.335, -0.075), (0.240, -0.072), (0.140, -0.046), (0.062, 0.010),
           (0.018, 0.086), (0.006, 0.160)]
    for i in range(len(pts) - 1):
        P.slab(pts[i], pts[i + 1], -hz, hz, 0.020, "steel",
               outward=(1.0, 0.35), bolts=3 if i % 2 == 0 else 0, inset=0.06)
    for i in (1, 3):
        P.deck_tread(pts[i], pts[i + 1], -hz + 0.06, hz - 0.06, 2, 9, "steel")
    P.slab((0.348, -0.070), (0.272, -0.086), -hz, hz, 0.012, "titanium",
           outward=(0.6, -0.7))
    for s in (-1.0, 1.0):
        P.prism([(0.345, -0.086), (0.345, -0.060), (0.028, 0.176),
                 (-0.020, 0.176), (-0.020, -0.086)],
                s * hz - 0.011, s * hz + 0.011, "livery", bevel=0.005, seg=2)
        P.hardware_bolt((0.140, 0.010, s * (hz + 0.012)), (0, 0, s))
        P.hardware_bolt((0.010, 0.130, s * (hz + 0.012)), (0, 0, s))
    P.ribs((0.120, 0.030, 0.0), (0.0, 0.0, 2 * hz - 0.10), 5, "dark_metal",
           normal=1, run=0, h=-0.014, w=0.022)

    # the chain drive, running along the left flank where it can be seen
    cz = hz + 0.048
    mx, mr = -0.245, 0.040
    chain = []
    for i in range(11):
        a = -math.pi * 0.5 + math.pi * i / 10.0
        chain.append((sprocket_r * math.cos(a), sprocket_r * math.sin(a)))
    for i in range(11):
        a = math.pi * 0.5 + math.pi * i / 10.0
        chain.append((mx + mr * math.cos(a), mr * math.sin(a)))
    P.band(chain, cz - 0.011, cz + 0.011, 0.009, "dark_metal", bevel=0.0)
    for i in range(0, len(chain), 2):
        x, y = chain[i]
        P.box((x, y, cz), (0.020, 0.014, 0.030), "steel", bevel=0.0,
              rot=rot_pitch(math.degrees(math.atan2(y, x - (0.0 if x > mx * 0.5 else mx)))))
    for (px, pr_, n) in ((0.0, sprocket_r - 0.014, 14), (mx, mr - 0.010, 10)):
        P.cyl((px, 0.0, cz), (0, 0, 1), pr_, 0.030, "dark_metal", n=n, bevel=0.002)
        for i in range(n if n < 12 else 12):
            a = 2.0 * math.pi * i / (n if n < 12 else 12)
            P.box((px + (pr_ + 0.008) * math.cos(a), (pr_ + 0.008) * math.sin(a), cz),
                  (0.014, 0.016, 0.026), "steel", bevel=0.0,
                  rot=rot_pitch(math.degrees(a)))
        P.bearing_cap((px, 0.0, cz - 0.019), (0, 0, -1), 0.024, h=0.010, n=8)
    # half guard, so the chain still reads
    P.slab((0.06, sprocket_r + 0.030), (mx, mr + 0.030), cz - 0.028, cz - 0.016,
           0.012, "livery", outward=(0, 1))
    P.cyl((mx - 0.070, 0.0, cz), (1, 0, 0), 0.046, 0.080, "dark_metal", n=14, bevel=0.003)
    P.box((-0.10, -0.052, cz + 0.004), (0.34, 0.030, 0.044), "dark_metal",
          bevel=0.003, seg=2)
    P.socket("socket_pivot", (0.0, 0.0, 0.0))
    P.socket("socket_tip", (0.352, -0.078, 0.0))
    return P


def build_cinder_hull(_spec=None):
    """Overlay for box: a bulky louvred cowl with a crest and a ring lamp."""
    P = Part("cinder_hull", "boss", mesh_name="overlay")
    cl, hw = 0.386, 0.250
    low, bay_x1, bw, deck, top = 0.075, -0.030, 0.211, 0.166, 0.18

    for s in (-1.0, 1.0):
        # deep flank cowls with big louvres
        P.prism([(cl - 0.02, -0.052), (cl - 0.06, 0.062), (-cl + 0.05, 0.062),
                 (-cl + 0.02, -0.052)], s * hw - 0.008, s * hw + 0.008,
                "livery", bevel=0.005, seg=2)
        P.louvres((0.16, 0.010, s * (hw + 0.006)), (0.20, 0.014, 0.090), 4)
        P.louvres((-0.16, 0.010, s * (hw + 0.006)), (0.20, 0.014, 0.090), 4)
        for x in (-0.30, 0.0, 0.30):
            P.hardware_bolt((x, 0.048, s * (hw + 0.010)), (0, 0, s))
        # bay shoulders
        P.slab((bay_x1 - 0.02, deck + 0.028), (-cl + 0.05, deck + 0.028),
               s * bw - 0.010, s * bw + 0.010, 0.016, "dark_metal", outward=(0, 1))

    # a raised crest ridge along the centre of the bay roof
    P.prism([(bay_x1 - 0.010, top + 0.004), (bay_x1 - 0.075, top + 0.062),
             (-cl + 0.090, top + 0.062), (-cl + 0.030, top + 0.004)],
            -0.036, 0.036, "livery", bevel=0.005, seg=2)
    P.ribs((-0.21, top + 0.064, 0.0), (0.22, 0.0, 0.0), 4, "steel",
           normal=1, run=2, h=0.010, w=0.016)
    for x in (-0.30, -0.12):
        P.hardware_bolt((x, top + 0.064, 0.024), (0, 1, 0))
        P.hardware_bolt((x, top + 0.064, -0.024), (0, 1, 0))

    # a ring lamp on the front face of the raised bay
    P.ring((bay_x1 + 0.020, 0.124, 0.0), (1, 0, 0), 0.058, 0.040, 0.026,
           "dark_metal", n=18)
    P.ring((bay_x1 + 0.030, 0.124, 0.0), (1, 0, 0), 0.040, 0.026, 0.012,
           "core_glow", n=18)
    for i in range(6):
        a = 2.0 * math.pi * i / 6.0
        P.bolt((bay_x1 + 0.032, 0.124 + 0.049 * math.cos(a), 0.049 * math.sin(a)),
               (1, 0, 0), r=0.008)
    return P


BUILDERS = {
    "thresher": build_thresher,
    "thresher_hull": build_thresher_hull,
    "grudge": build_grudge,
    "grudge_hull": build_grudge_hull,
    "bandsaw": build_bandsaw,
    "bandsaw_hull": build_bandsaw_hull,
    "anvil": build_anvil,
    "anvil_hull": build_anvil_hull,
    "cinder": build_cinder,
    "cinder_hull": build_cinder_hull,
}

#: which chassis each part is authored against, and the socket it parents to.
HOSTS = {
    "thresher": ("long_low", "socket_weapon_front"),
    "grudge": ("box", "socket_weapon_top"),
    "bandsaw": ("wedge", "socket_weapon_front"),
    "anvil": ("tall_tank", "socket_weapon_front"),
    "cinder": ("box", "socket_weapon_front"),
    "thresher_hull": ("long_low", None),
    "grudge_hull": ("box", None),
    "bandsaw_hull": ("wedge", None),
    "anvil_hull": ("tall_tank", None),
    "cinder_hull": ("box", None),
}
