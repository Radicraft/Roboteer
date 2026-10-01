"""The ten weapons.

Convention: a weapon's ORIGIN is the mount socket (so P2 parents it straight to
`socket_weapon_front|top|shell` with no offset), +X forward, +Y up, +Z right.
Each moving weapon also carries two extra empties for the assembler:

    socket_pivot  the hinge / spin axis centre
    socket_tip    the business end, for impact FX and reach checks

Catalogue numbers (reach, and only reach) drive the sizes.  Original shapes:
no named competitor machine is referenced (brief v3 §3).
"""

import math

from rkit import Part, BEVEL, PLATE_T, rot_pitch, rot_z, rot_roll


def _hinge(P, z, r=0.013, half_w=0.14, bracket=(0.052, 0.072, 0.016)):
    """A pin through two brackets: the standard joint on this machine."""
    for s in (-1.0, 1.0):
        P.box((0.0, 0.0, s * (half_w + bracket[2] * 0.5)), bracket, "dark_metal",
              bevel=0.003, seg=2)
        P.bolt((0.0, -bracket[1] * 0.35, s * (half_w + bracket[2])), (0, 0, s), r=0.007)
    L = 2 * (half_w + bracket[2]) + 0.02
    P.shaft((0, 0, -L * 0.5), (0, 0, L * 0.5), r, "steel", n=10,
            grooves=(0.09, 0.91), step=0.0)


def _ram(P, a, b, body_r=0.024, rod_r=0.011, mat="steel"):
    """A pneumatic / hydraulic ram: barrel, rod, two clevises."""
    ax = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
    L = math.sqrt(sum(v * v for v in ax))
    u = [v / L for v in ax]
    mid = [a[i] + u[i] * L * 0.32 for i in range(3)]
    P.cyl(mid, u, body_r, L * 0.62, mat, n=12, bevel=0.003)
    rod_mid = [a[i] + u[i] * L * 0.80 for i in range(3)]
    P.cyl(rod_mid, u, rod_r, L * 0.40, "titanium", n=8, bevel=0.0)
    for p in (a, b):
        P.cyl(p, u, body_r * 0.62, 0.018, "dark_metal", n=8, bevel=0.002)
    P.cyl([a[i] + u[i] * L * 0.62 for i in range(3)], u, body_r * 0.92, 0.014,
          "dark_metal", n=12, bevel=0.0)


def build_flipper(spec):
    P = Part("flipper", "weapon")
    reach = spec["reach"]                 # 0.40
    hw = 0.145
    _hinge(P, 0.0, half_w=hw)
    # the flipping plate, resting nose-down on the floor line
    P.slab((0.03, 0.012), (reach, -0.030), -hw, hw, 0.016, "titanium",
           outward=(0.25, 1.0), bolts=3, inset=0.05)
    P.deck_tread((reach - 0.035, -0.024), (0.06, 0.007), -hw + 0.045, hw - 0.045,
                 4, 6, "titanium")
    # two ribs under the plate and a hardened leading edge
    for s in (-1.0, 1.0):
        P.slab((0.05, -0.004), (reach - 0.02, -0.044), s * 0.085 - 0.010,
               s * 0.085 + 0.010, 0.020, "steel", outward=(0.25, 1.0))
    P.slab((reach + 0.012, -0.028), (reach - 0.055, -0.041), -hw, hw, 0.010,
           "titanium", outward=(0.8, -0.5))
    # the ram that throws it, and the gas system behind
    _ram(P, (-0.155, -0.048, 0.0), (0.155, 0.012, 0.0))
    P.cyl((-0.245, 0.010, 0.0), (1, 0, 0), 0.042, 0.175, "steel", n=14, bevel=0.004)
    P.cone((-0.335, 0.010, 0.0), (1, 0, 0), 0.030, 0.042, 0.020, "steel", n=14)
    P.cone((-0.152, 0.010, 0.0), (1, 0, 0), 0.042, 0.030, 0.020, "steel", n=14)
    for s in (-1.0, 1.0):
        P.ring((-0.215 + s * 0.055, 0.010, 0.0), (1, 0, 0), 0.047, 0.042, 0.012,
               "dark_metal", n=14)
    P.box((-0.135, 0.055, 0.0), (0.055, 0.055, 0.050), "dark_metal", bevel=0.003, seg=1)
    P.cyl((-0.135, 0.088, 0.0), (0, 1, 0), 0.018, 0.016, "steel", n=8, bevel=0.002)
    P.cyl((-0.108, 0.040, 0.0), (0.6, -0.8, 0.0), 0.007, 0.070, "dark_metal", n=6)
    P.socket("socket_pivot", (0.0, 0.0, 0.0))
    P.socket("socket_tip", (reach + 0.012, -0.030, 0.0))
    return P


def build_horizontal_spinner(spec):
    """Fitment pass 2, round 3: an undercutter.  A thin hardened blade the catalogue
    reach either side (0.35, a 0.70 m bar), with the hub boss (the motor's output
    flange) standing ABOVE the blade only, so the blade can run low under a nose and
    the boss goes up into the weapon block on the machine (bot.gd draws the block).
    Blade 36 mm tall with its tips, centred on the hinge."""
    P = Part("horizontal_spinner", "weapon")
    reach = spec["reach"]                 # 0.35
    bar_t, bar_h = 0.090, 0.026
    tip_h = 0.036
    # hub boss above the blade: flange, boss, cap, bolts
    P.cyl((0, bar_h * 0.5 + 0.004, 0), (0, 1, 0), 0.076, 0.008, "steel", n=18, bevel=0.002)
    P.cyl((0, bar_h * 0.5 + 0.026, 0), (0, 1, 0), 0.052, 0.040, "steel", n=18, bevel=0.003)
    P.cyl((0, bar_h * 0.5 + 0.047, 0), (0, 1, 0), 0.030, 0.006, "dark_metal", n=12, bevel=0.0015)
    for i in range(8):
        a = 2.0 * math.pi * i / 8.0
        P.bolt((0.064 * math.cos(a), bar_h * 0.5 + 0.008, 0.064 * math.sin(a)), (0, 1, 0), r=0.006)
    # the blade, with a ground edge down the leading face
    P.box((0, 0, 0), (2 * (reach - 0.06), bar_h, bar_t), "titanium", bevel=0.004, seg=2)
    for s in (-1.0, 1.0):
        # hardened tip: a swept block with a cutting corner
        P.box((s * (reach - 0.055), 0.0, 0.0), (0.110, tip_h, bar_t + 0.020),
              "steel", bevel=0.005, seg=2)
        P.prism([(s * 0.055, -tip_h * 0.5), (s * 0.055, tip_h * 0.5), (s * 0.0, tip_h * 0.5),
                 (s * -0.010, 0.0)],
                -bar_t * 0.5 - 0.010, bar_t * 0.5 + 0.010, "titanium",
                bevel=0.003, seg=2, at=(s * (reach - 0.055), 0.0, 0.0))
        P.bolt((s * (reach - 0.040), tip_h * 0.5, 0.0), (0, 1, 0), r=0.006)
        P.bolt((s * (reach - 0.080), tip_h * 0.5, 0.0), (0, 1, 0), r=0.006)
        P.seam((s * (reach - 0.112), -bar_h * 0.5, bar_t * 0.5),
               (s * (reach - 0.112), bar_h * 0.5, bar_t * 0.5))
    P.socket("socket_pivot", (0.0, 0.0, 0.0))
    P.socket("socket_tip", (reach, 0.0, 0.0))
    return P


def build_vertical_spinner(spec):
    P = Part("vertical_spinner", "weapon")
    r = 0.112
    w = 0.30
    P.cyl((0, 0, 0), (0, 0, 1), r - 0.024, w, "steel", n=20, bevel=0.004)
    # three rows of hardened teeth
    for row, zc in ((0, -0.105), (1, 0.0), (2, 0.105)):
        for i in range(4):
            a = 2.0 * math.pi * i / 4.0 + row * 0.26
            c, s = math.cos(a), math.sin(a)
            P.box(((r - 0.014) * c, (r - 0.014) * s, zc), (0.042, 0.058, 0.078),
                  "titanium", bevel=0.0035, seg=2, rot=rot_pitch(math.degrees(a)))
            P.bolt(((r - 0.030) * c, (r - 0.030) * s, zc), (c, s, 0.0), r=0.007)
    for s in (-1.0, 1.0):
        P.cyl((0, 0, s * (w * 0.5 + 0.008)), (0, 0, 1), r - 0.020, 0.016,
              "dark_metal", n=18, bevel=0.002)
        P.cyl((0, 0, s * (w * 0.5 + 0.036)), (0, 0, 1), 0.026, 0.045,
              "steel", n=10, bevel=0.002)
        P.ring((0, 0, s * (w * 0.5 + 0.060)), (0, 0, 1), 0.046, 0.028, 0.016,
               "dark_metal", n=12)
    P.socket("socket_pivot", (0.0, 0.0, 0.0))
    P.socket("socket_tip", (r, 0.0, 0.0))
    return P


def build_lifter(spec):
    P = Part("lifter", "weapon")
    reach = spec["reach"]                 # 0.40
    hw = 0.13
    _hinge(P, 0.0, half_w=hw)
    # two forks and the cross tube that ties them
    for s in (-1.0, 1.0):
        P.slab((0.03, 0.004), (reach, -0.026), s * 0.105 - 0.030, s * 0.105 + 0.030,
               0.018, "steel", outward=(0.2, 1.0), bolts=2, inset=0.05)
        P.slab((reach + 0.014, -0.022), (reach - 0.060, -0.036),
               s * 0.105 - 0.030, s * 0.105 + 0.030, 0.009, "titanium",
               outward=(0.8, -0.4))
    P.cyl((0.12, -0.004, 0.0), (0, 0, 1), 0.017, 0.27, "dark_metal", n=10, bevel=0.002)
    P.cyl((0.30, -0.016, 0.0), (0, 0, 1), 0.013, 0.27, "dark_metal", n=8, bevel=0.002)
    # screw actuator: a threaded rod with a travelling nut, plus the motor.
    # Fitment pass 2: the rod and the motor are bolted to the HULL, so they are
    # their own node, `mount` (lifter.gd hangs it on the chassis); the nut and
    # its link ride on the forks.
    P.use("mount")
    P.cyl((-0.10, 0.075, 0.0), (1, 0, 0), 0.015, 0.30, "titanium", n=8, bevel=0.0)
    for i in range(8):
        P.ring((-0.225 + i * 0.036, 0.075, 0.0), (1, 0, 0), 0.024, 0.015, 0.011,
               "titanium", n=10)
    P.cyl((-0.275, 0.075, 0.0), (1, 0, 0), 0.036, 0.090, "dark_metal", n=12, bevel=0.003)
    P.ring((-0.232, 0.075, 0.0), (1, 0, 0), 0.040, 0.036, 0.010, "steel", n=12)
    P.use("body")
    P.box((0.02, 0.075, 0.0), (0.062, 0.064, 0.074), "dark_metal", bevel=0.004, seg=2)
    P.ring((0.02, 0.075, 0.0), (1, 0, 0), 0.030, 0.024, 0.066, "steel", n=10)
    for i in range(4):
        a = 2.0 * math.pi * i / 4.0 + 0.4
        P.hardware_bolt((0.053, 0.075 + 0.040 * math.cos(a), 0.040 * math.sin(a)),
                        (1, 0, 0))
    # the link from the nut down to the forks
    P.slab((0.02, 0.062), (0.10, 0.004), -0.012, 0.012, 0.014, "steel", outward=(1.0, 0.4))
    P.socket("socket_pivot", (0.0, 0.0, 0.0))
    P.socket("socket_tip", (reach + 0.014, -0.026, 0.0))
    return P


def build_crusher(spec):
    P = Part("crusher", "weapon")
    reach = spec["reach"]                 # 0.30
    hw = 0.055
    # Fitment pass 2: the tower, the pin, the anvil bed and the ram's foot are
    # bolted to the HULL, so they are their own node, `mount` (crusher.gd stands
    # it on the deck, upright); only the jaw and its ram turn.
    P.use("mount")
    # the tower the jaw hangs from
    P.box((-0.06, 0.10, 0.0), (0.10, 0.20, 0.13), "dark_metal", bevel=0.004, seg=2)
    P.plate((-0.06, 0.205, 0.0), (0.10, 0.014, 0.13), "steel", axis=(0, 1, 0), inset=0.024)
    for s in (-1.0, 1.0):
        P.box((-0.06, 0.10, s * 0.078), (0.086, 0.17, 0.014), "livery",
              bevel=0.003, seg=2)
    P.cyl((0.0, 0.19, 0.0), (0, 0, 1), 0.016, 0.17, "steel", n=10, bevel=0.0)
    # lower anvil with a matching bed
    P.slab((0.02, -0.030), (reach - 0.02, -0.046), -0.075, 0.075, 0.024,
           "steel", outward=(0.2, 1.0), bolts=2, inset=0.04)
    for s in (-1.0, 1.0):
        P.box((reach - 0.075, -0.014, s * 0.048), (0.055, 0.028, 0.026),
              "titanium", bevel=0.003, seg=1)
    P.box((-0.135, 0.020, 0.0), (0.070, 0.062, 0.090), "dark_metal", bevel=0.003, seg=1)
    P.cyl((-0.115, 0.056, 0.048), (0.4, 0.9, 0.0), 0.008, 0.11, "dark_metal", n=6)
    # hydraulic ram driving the jaw: its cylinder is on the tower, so it stays with
    # the mount (on the jaw it swung its foot down through the deck as the jaw opened)
    _ram(P, (-0.095, 0.028, 0.0), (0.115, 0.152, 0.0), body_r=0.028, rod_r=0.013)
    P.use("body")
    # upper jaw: three segments curving forward and down to two teeth
    pts = [(0.0, 0.19), (0.13, 0.175), (0.235, 0.125), (reach, 0.045)]
    for i in range(3):
        P.slab(pts[i], pts[i + 1], -hw, hw, 0.030, "titanium",
               outward=(0.2, 1.0), bolts=2, inset=0.035)
    for s in (-1.0, 1.0):
        P.prism([(0.0, 0.0), (0.075, 0.0), (0.012, -0.082)],
                s * 0.048 - 0.013, s * 0.048 + 0.013, "steel", bevel=0.003, seg=1,
                at=(reach - 0.055, 0.030, 0.0))
    P.socket("socket_pivot", (0.0, 0.19, 0.0))
    P.socket("socket_tip", (reach, 0.045, 0.0))
    return P


def build_axe(spec):
    P = Part("axe", "weapon")
    reach = spec["reach"]                 # 0.60
    # Fitment pass 2: the tower, its pin and the spring return are bolted to the
    # HULL, so they are their own node, `mount` (axe.gd stands it on the deck,
    # upright); only the arm and the head swing.
    P.use("mount")
    # pivot tower
    P.box((-0.05, 0.115, 0.0), (0.086, 0.23, 0.12), "dark_metal", bevel=0.004, seg=2)
    for s in (-1.0, 1.0):
        P.box((-0.05, 0.115, s * 0.072), (0.074, 0.20, 0.012), "livery", bevel=0.003, seg=2)
        P.bolt((-0.05, 0.030, s * 0.079), (0, 0, s))
    P.cyl((0.0, 0.225, 0.0), (0, 0, 1), 0.017, 0.16, "steel", n=10, bevel=0.0)
    # spring return: a coil plus its anchor
    for i in range(6):
        t = i / 5.0
        P.ring((-0.115 + t * 0.115, 0.045 + t * 0.155, 0.0), (0.60, 0.80, 0.0),
               0.026, 0.020, 0.010, "steel", n=8)
    P.box((-0.135, 0.028, 0.0), (0.050, 0.046, 0.056), "dark_metal", bevel=0.003, seg=1)
    P.use("body")
    # arm, cocked up and forward
    tip = (0.40, 0.52)
    P.slab((0.0, 0.225), tip, -0.026, 0.026, 0.030, "titanium",
           outward=(0.6, -0.8), bolts=3, inset=0.05)
    P.slab((0.012, 0.250), (tip[0] - 0.02, tip[1] + 0.018), -0.014, 0.014, 0.014,
           "steel", outward=(0.6, -0.8))
    # pick head
    P.box((tip[0], tip[1], 0.0), (0.085, 0.075, 0.070), "steel", bevel=0.004, seg=2)
    P.prism([(0.0, 0.040), (0.0, -0.040), (0.115, -0.004)], -0.026, 0.026,
            "titanium", bevel=0.003, seg=2, at=(tip[0] + 0.030, tip[1] - 0.010, 0.0))
    P.prism([(0.0, 0.0), (-0.052, 0.030), (-0.052, -0.030)], -0.024, 0.024,
            "steel", bevel=0.003, seg=1, at=(tip[0] - 0.042, tip[1] + 0.004, 0.0))
    P.bolt_rect((tip[0], tip[1], 0.036), (0.030, 0, 0), (0, 0.026, 0), axis=(0, 0, 1))
    P.cyl((0.010, 0.212, 0.0), (0.60, 0.80, 0.0), 0.010, 0.050, "titanium", n=6)
    P.socket("socket_pivot", (0.0, 0.225, 0.0))
    P.socket("socket_tip", (tip[0] + 0.145, tip[1] - 0.014, 0.0))
    return P


def build_saw(spec):
    P = Part("saw", "weapon")
    r = 0.155
    cx = spec["reach"] - r        # blade centre, so the teeth reach 0.30
    # blade on a lateral shaft, cutting forward
    P.cyl((cx, 0.055, 0.0), (0, 0, 1), r - 0.016, 0.010, "steel", n=24, bevel=0.002)
    P.ring((cx, 0.055, 0.0), (0, 0, 1), r - 0.014, r - 0.046, 0.012, "titanium",
           n=24, bevel=0.0)
    teeth = 18
    for i in range(teeth):
        a = 2.0 * math.pi * i / teeth
        c, s = math.cos(a), math.sin(a)
        P.box((cx + (r - 0.008) * c, 0.055 + (r - 0.008) * s, 0.0),
              (0.020, 0.022, 0.016), "titanium", bevel=0.0015, seg=1,
              rot=rot_pitch(math.degrees(a)))
    P.cyl((cx, 0.055, 0.0), (0, 0, 1), 0.034, 0.030, "dark_metal", n=12, bevel=0.002)
    for i in range(4):
        a = 2.0 * math.pi * i / 4.0
        P.bolt((cx + 0.024 * math.cos(a), 0.055 + 0.024 * math.sin(a), 0.016),
               (0, 0, 1), r=0.006)
    # Wave C fitment: everything below is the MOUNT, which is bolted to the hull and
    # does not turn. It used to share the blade's stream, so saw.gd hung it on the
    # spinning blade body and the guard, the belt covers and the motor went round with
    # the disc, through the nose and out of the deck. The `mount` stream is its own node
    # (as the flipper's gas system is) and saw.gd hands it to the chassis.
    P.use("mount")
    # guard over the top of the blade, front of centre. Wave C: it used to run on
    # round to 156 degrees and stand a 0.2 m back plate up behind the blade, which is
    # inside any hull the blade is bolted to and came out through the deck. It now
    # stops short of the nose (the blade's back edge runs in a slot in the front plate).
    for i in range(8):
        a = math.radians(36.0 + i * 12.0)
        c, s = math.cos(a), math.sin(a)
        P.box((cx + (r + 0.020) * c, 0.055 + (r + 0.020) * s, 0.0),
              (0.016, 0.042, 0.058), "livery", bevel=0.003, seg=1,
              rot=rot_pitch(math.degrees(a)))
    # motor and belt cover
    P.cyl((-0.085, 0.020, 0.0), (0, 0, 1), 0.048, 0.086, "dark_metal", n=14, bevel=0.003)
    P.ring((-0.085, 0.020, 0.0), (0, 0, 1), 0.054, 0.048, 0.060, "steel", n=14)
    P.slab((-0.085, 0.068), (cx, 0.103), -0.020, 0.020, 0.014, "livery", outward=(0, 1))
    P.slab((-0.085, -0.028), (cx, 0.007), -0.020, 0.020, 0.014, "livery", outward=(0, -1))
    P.box((-0.140, 0.020, 0.0), (0.036, 0.056, 0.056), "dark_metal", bevel=0.003, seg=1)
    P.socket("socket_pivot", (cx, 0.055, 0.0))
    P.socket("socket_tip", (cx + r, 0.055, 0.0))
    return P


def build_ram(spec):
    P = Part("ram", "weapon")
    reach = spec["reach"]                 # 0.20
    hw = 0.21
    # a wide sloped plate that gets under, with three spikes
    P.slab((reach, -0.055), (-0.02, 0.065), -hw, hw, 0.020, "steel",
           outward=(0.6, 1.0), bolts=4, inset=0.05)
    P.deck_tread((reach - 0.03, -0.042), (0.0, 0.056), -hw + 0.05, hw - 0.05,
                 3, 6, "steel")
    P.slab((reach + 0.016, -0.050), (reach - 0.070, -0.068), -hw, hw, 0.012,
           "titanium", outward=(0.8, -0.5))
    for z in (-0.13, 0.0, 0.13):
        P.cone((reach + 0.052, 0.014, z), (0.94, 0.34, 0.0), 0.032, 0.004, 0.175,
               "titanium", n=8, bevel=0.0)
        P.cyl((reach - 0.030, -0.016, z), (0.94, 0.34, 0.0), 0.036, 0.040,
              "dark_metal", n=10, bevel=0.0025)
        P.ring((reach + 0.012, 0.0, z), (0.94, 0.34, 0.0), 0.030, 0.024, 0.012,
               "steel", n=10)
    for s in (-1.0, 1.0):
        P.slab((reach - 0.02, -0.048), (-0.02, 0.058), s * hw - 0.009, s * hw + 0.009,
               0.030, "livery", outward=(0.6, 1.0))
        P.box((-0.03, 0.020, s * 0.13), (0.060, 0.090, 0.016), "dark_metal",
              bevel=0.003, seg=1)
    P.seam((-0.02, 0.062, -hw + 0.01), (-0.02, 0.062, hw - 0.01))
    P.socket("socket_tip", (reach + 0.112, 0.030, 0.0))
    return P


def build_flamethrower(spec):
    P = Part("flamethrower", "weapon")
    # fuel bottle lying along the machine
    P.cyl((-0.135, 0.040, 0.0), (1, 0, 0), 0.052, 0.195, "steel", n=16, bevel=0.004)
    P.cone((-0.242, 0.040, 0.0), (1, 0, 0), 0.032, 0.052, 0.022, "steel", n=16)
    P.cone((-0.028, 0.040, 0.0), (1, 0, 0), 0.052, 0.034, 0.022, "steel", n=16)
    for x in (-0.195, -0.075):
        P.ring((x, 0.040, 0.0), (1, 0, 0), 0.058, 0.052, 0.014, "dark_metal", n=16)
        P.bolt((x, 0.100, 0.0), (0, 1, 0), r=0.007)
    P.box((-0.135, -0.020, 0.0), (0.19, 0.030, 0.085), "dark_metal", bevel=0.003, seg=1)
    # regulator and the feed pipe running forward
    P.box((-0.010, 0.058, 0.0), (0.050, 0.050, 0.046), "dark_metal", bevel=0.003, seg=1)
    P.cyl((-0.010, 0.090, 0.0), (0, 1, 0), 0.016, 0.018, "steel", n=8, bevel=0.002)
    P.cyl((0.055, 0.052, 0.0), (1, 0, 0), 0.012, 0.115, "titanium", n=8, bevel=0.0)
    P.cyl((0.112, 0.036, 0.0), (0.0, -1.0, 0.0), 0.012, 0.040, "titanium", n=8, bevel=0.0)
    # nozzle assembly
    P.cyl((0.150, 0.020, 0.0), (1, 0, 0), 0.026, 0.076, "dark_metal", n=12, bevel=0.003)
    P.cone((0.205, 0.020, 0.0), (1, 0, 0), 0.026, 0.014, 0.034, "steel", n=12)
    P.ring((0.235, 0.020, 0.0), (1, 0, 0), 0.020, 0.013, 0.014, "titanium", n=12)
    # ignition electrodes and their lead
    for s in (-1.0, 1.0):
        P.cyl((0.222, 0.020, s * 0.024), (1, 0, 0), 0.004, 0.042, "titanium", n=6)
        P.cyl((0.200, 0.020, s * 0.024), (0, 0, s), 0.004, 0.020, "titanium", n=6)
    P.box((0.120, 0.070, 0.0), (0.044, 0.038, 0.040), "livery", bevel=0.003, seg=1)
    P.cyl((0.150, 0.055, 0.0), (0.0, -0.9, 0.4), 0.005, 0.048, "dark_metal", n=6)
    P.socket("socket_tip", (0.252, 0.020, 0.0))
    return P


def build_full_body_spinner(spec):
    P = Part("full_body_spinner", "weapon")
    r_out = 0.385         # teeth then reach the catalogue 0.45
    r_in = 0.325          # matches the shell chassis `ring` bore
    h = 0.165
    P.ring((0, 0, 0), (0, 1, 0), r_out, r_in, h, "livery", n=30, bevel=0.003)
    P.ring((0, h * 0.5 + 0.010, 0), (0, 1, 0), r_out - 0.004, r_in - 0.006, 0.020,
           "titanium", n=30, bevel=0.0)
    P.ring((0, -h * 0.5 - 0.010, 0), (0, 1, 0), r_out - 0.004, r_in - 0.006, 0.020,
           "titanium", n=30, bevel=0.0)
    # eight hardened teeth, swept back against the direction of spin
    for i in range(8):
        a = 2.0 * math.pi * i / 8.0
        c, s = math.cos(a), math.sin(a)
        P.box(((r_out - 0.010) * c, 0.0, (r_out - 0.010) * s),
              (0.058, h + 0.030, 0.085), "steel", bevel=0.004, seg=2,
              rot=rot_z(math.degrees(-a)))
        P.prism([(0.0, h * 0.5 + 0.014), (0.0, -h * 0.5 - 0.014), (0.062, -0.006)],
                -0.032, 0.032, "titanium", bevel=0.003, seg=2,
                rot=rot_z(math.degrees(-a)), at=((r_out + 0.004) * c, 0.0, (r_out + 0.004) * s))
        P.bolt(((r_out - 0.042) * c, h * 0.5 + 0.022, (r_out - 0.042) * s), (0, 1, 0))
    # the drive ring it turns on
    P.ring((0, -h * 0.5 + 0.016, 0), (0, 1, 0), r_in, r_in - 0.028, 0.032,
           "dark_metal", n=26, bevel=0.0)
    for i in range(10):
        a = 2.0 * math.pi * i / 10.0
        P.bolt(((r_in - 0.014) * math.cos(a), -h * 0.5 + 0.034, (r_in - 0.014) * math.sin(a)),
               (0, 1, 0), r=0.007)
    P.socket("socket_pivot", (0.0, 0.0, 0.0))
    P.socket("socket_tip", (r_out + 0.066, 0.0, 0.0))
    return P


BUILDERS = {
    "flipper": build_flipper,
    "horizontal_spinner": build_horizontal_spinner,
    "vertical_spinner": build_vertical_spinner,
    "lifter": build_lifter,
    "crusher": build_crusher,
    "axe": build_axe,
    "saw": build_saw,
    "ram": build_ram,
    "flamethrower": build_flamethrower,
    "full_body_spinner": build_full_body_spinner,
}


# ---------------------------------------------------------------------------
# Wave P (agent E).  Six weapons, built to the collision bodies D1 already uses,
# so the model and the thing that actually hits are the same size.  The mesh
# requests are docs/wave-p-d1-notes.md, "Mesh requests for agent E".
#
# MOUNT CONVENTION, and it differs from the Stage 4 weapons above.  The four
# welded-head weapons (prod, arc, cannon) are parented by D1 at
# `Vector3(-DEPTH * 0.5, 0, 0)` inside a body whose collision box is centred on
# that body's origin, so their models are authored with the origin on the BACK
# FACE of the head and the geometry running forward from x = 0.  The two spun
# weapons (drill, saw) are parented at `-socket_pivot`, so theirs are authored
# about the spin centre.  The vortex parents at identity on the hull origin.
# ---------------------------------------------------------------------------


def build_shock_prod(spec):
    """A welded prod head: three insulated prongs on ceramic stand-offs with
    copper rods and live tips, a transformer can behind them, and the HV lead
    running back into the bodywork.  No moving parts."""
    P = Part("shock_prod", "weapon")
    d, h, w = 0.10, 0.14, 0.26              # the collision head, exactly
    hh, hw = h * 0.5, w * 0.5

    # backing plate against the hull nose, then the welded frame
    P.plate((0.009, 0.0, 0.0), (0.018, h, w), "livery", axis=(-1, 0, 0),
            inset=0.034, hardware=True)
    P.box((0.026, 0.0, 0.0), (0.024, h - 0.018, w - 0.030), "dark_metal",
          bevel=0.003, seg=2)
    for sz in (-1.0, 1.0):
        P.box((0.026, 0.0, sz * (hw - 0.012)), (0.026, h - 0.020, 0.016),
              "steel", bevel=0.0025, seg=1)
        P.seam((0.018, -hh + 0.016, sz * (hw - 0.020)),
               (0.018, hh - 0.016, sz * (hw - 0.020)))
    # the transformer can, lying across the head where the player can see it
    P.cyl((0.040, -0.030, 0.0), (0, 0, 1), 0.026, w - 0.070, "dark_metal",
          n=12, bevel=0.003)
    for sz in (-1.0, 1.0):
        P.ring((0.040, -0.030, sz * (hw - 0.048)), (0, 0, sz), 0.030, 0.026,
               0.010, "steel", n=12)
    P.ribs((0.040, 0.042, 0.0), (0.0, 0.0, w - 0.080), 5, "steel",
           normal=1, run=0, h=0.007, w=0.011)

    # three prongs: a ribbed ceramic stand-off, a copper rod, a live tip
    for z in (-0.085, 0.0, 0.085):
        y = 0.018 if z == 0.0 else -0.004
        P.boss((0.038, y, z), (1, 0, 0), 0.020, 0.008, "steel")
        for i in range(4):                       # the insulator's sheds
            P.ring((0.050 + i * 0.008, y, z), (1, 0, 0), 0.017 - i * 0.0012,
                   0.0085, 0.0045, "polycarbonate", n=10)
        P.cyl((0.062, y, z), (1, 0, 0), 0.0085, 0.024, "polycarbonate",
              n=10, bevel=0.0)
        P.cyl((0.082, y, z), (1, 0, 0), 0.0072, 0.022, "copper", n=8, bevel=0.0)
        P.cone((0.096, y, z), (1, 0, 0), 0.0085, 0.0028, 0.009, "core_glow", n=8)
    # the bus bar tying the three tops together, and the lead home
    P.box((0.058, 0.052, 0.0), (0.012, 0.010, w - 0.090), "copper",
          bevel=0.0018, seg=1)
    for z in (-0.085, 0.0, 0.085):
        P.cyl((0.058, 0.036, z), (0, 1, 0), 0.0045, 0.030, "copper", n=6)
    P.cable_run([(0.058, 0.058, 0.0), (0.010, 0.058, 0.0)], r=0.0075,
                channel=False)
    P.socket("socket_pivot", (0.0, 0.0, 0.0))
    P.socket("socket_tip", (d, 0.0, 0.0))
    return P


def build_tesla_arc(spec):
    """A resonant coil: ribbed insulator stack, a wound former, a toroid
    electrode on top.  `socket_spark` is where F's bolt leaves from."""
    P = Part("tesla_arc", "weapon")
    d, h, w = 0.14, 0.18, 0.22              # the collision coil, exactly
    hh, hw = h * 0.5, w * 0.5
    cx = 0.070                              # the coil's own axis

    P.plate((0.009, -0.010, 0.0), (0.018, h - 0.030, w), "livery",
            axis=(-1, 0, 0), inset=0.032, hardware=True)
    # base: a heavy earthed plate with the driver box under it
    P.box((0.072, -hh + 0.013, 0.0), (0.116, 0.026, w - 0.026), "steel",
          bevel=0.003, seg=2)
    for su in (-1, 1):
        for sv in (-1, 1):
            P.hardware_bolt((cx + su * 0.044, -hh + 0.026, sv * 0.078), (0, 1, 0))
    P.box((0.040, -hh + 0.048, 0.0), (0.048, 0.044, 0.120), "dark_metal",
          bevel=0.003, seg=2)
    P.louvres((0.040, -hh + 0.048, 0.062), (0.036, 0.010, 0.090), 4)

    # the insulator stack the former stands on
    for i in range(4):
        P.ring((cx, -hh + 0.032 + i * 0.011, 0.0), (0, 1, 0),
               0.040 - i * 0.0025, 0.026, 0.0075, "polycarbonate", n=14)
    # the former, and the winding: real turns, because a smooth drum is a drum
    P.cyl((cx, 0.006, 0.0), (0, 1, 0), 0.030, 0.104, "hdpe", n=14, bevel=0.002)
    for i in range(13):
        P.ring((cx, -0.042 + i * 0.0074, 0.0), (0, 1, 0), 0.0345, 0.030,
               0.0058, "copper", n=14)
    P.cyl((cx, 0.062, 0.0), (0, 1, 0), 0.034, 0.014, "dark_metal", n=14,
          bevel=0.002)
    # the toroid and the discharge ball on top
    P.ring((cx, 0.074, 0.0), (0, 1, 0), 0.046, 0.022, 0.020, "copper", n=16,
           bevel=0.003)
    P.ball((cx, 0.086, 0.0), 0.018, "copper", seg=12, rings=6, squash=0.85)
    P.cone((cx, 0.0965, 0.0), (0, 1, 0), 0.007, 0.0028, 0.012, "core_glow", n=8)
    # the HV lead up the back of the former, and the earth strap
    P.cable_run([(0.022, -hh + 0.030, 0.0), (0.022, 0.055, 0.0),
                 (0.044, 0.074, 0.0)], r=0.0065, channel=False)
    P.box((0.100, -hh + 0.030, 0.0), (0.012, 0.008, 0.070), "copper",
          bevel=0.0018, seg=1)
    P.socket("socket_pivot", (0.0, 0.0, 0.0))
    P.socket("socket_spark", (cx, 0.104, 0.0))
    P.socket("socket_tip", (cx, 0.104, 0.0))
    return P


def build_drill_lance(spec):
    """A tapered fluted lance spinning about its own length at up to 18 rad/s.
    Authored about the SHAFT CENTRE, because that is where D1 hinges it.

    Everything here is rotationally symmetric or helical on purpose: the whole
    model turns with the body, so a motor housing modelled at the root would
    spin with it.  The collar reads as the bearing it is, spinning or not."""
    P = Part("drill_lance", "weapon")
    L = 0.30
    r0 = 0.075                               # root radius, the collision radius
    x0, x1 = -L * 0.5, L * 0.5

    def taper(t):
        # fat at the root, a point at the tip, with a slight ogive
        return r0 * (1.0 - t) ** 0.78

    # the core: a stack of truncated cones, so the taper is a curve not a wedge
    steps = 7
    for i in range(steps):
        a = x0 + L * i / steps
        b = x0 + L * (i + 1) / steps
        P.cone(((a + b) * 0.5, 0.0, 0.0), (1, 0, 0),
               max(taper(i / steps) - 0.012, 0.004),
               max(taper((i + 1) / steps) - 0.012, 0.0028),
               b - a, "steel", n=16, bevel=0.0)
    # three helical flutes standing proud of the core
    P.helix((x0 + 0.012, 0.0, 0.0), (x1 - 0.020, 0.0, 0.0),
            lambda t: max(taper(0.04 + t * 0.90) - 0.010, 0.004),
            turns=1.45, mat="titanium", steps=20, size=(0.030, 0.019), starts=3)
    # the hardened tip and its three cutting lips
    P.cone((x1 - 0.014, 0.0, 0.0), (1, 0, 0), 0.016, 0.0035, 0.028,
           "titanium", n=12)
    for i in range(3):
        a = 2.0 * math.pi * i / 3.0
        P.box((x1 - 0.026, 0.012 * math.cos(a), 0.012 * math.sin(a)),
              (0.030, 0.011, 0.010), "steel", bevel=0.0015, seg=1,
              rot=rot_roll(math.degrees(a)))
    # root: the collar, the bearing race and the drive splines
    P.cyl((x0 + 0.014, 0.0, 0.0), (1, 0, 0), r0 - 0.004, 0.028, "dark_metal",
          n=18, bevel=0.003)
    P.ring((x0 + 0.032, 0.0, 0.0), (1, 0, 0), r0 - 0.002, r0 - 0.020, 0.012,
           "steel", n=18)
    for i in range(10):
        a = 2.0 * math.pi * i / 10.0
        P.box((x0 + 0.014, (r0 - 0.012) * math.cos(a), (r0 - 0.012) * math.sin(a)),
              (0.024, 0.014, 0.011), "steel", bevel=0.0, rot=rot_roll(math.degrees(a)))
        P.bolt((x0 + 0.002, (r0 - 0.030) * math.cos(a), (r0 - 0.030) * math.sin(a)),
               (-1, 0, 0), r=0.0065)
    P.cone((x0, 0.0, 0.0), (1, 0, 0), 0.030, 0.038, 0.010, "dark_metal", n=12)
    P.socket("socket_pivot", (0.0, 0.0, 0.0))
    P.socket("socket_tip", (x1, 0.0, 0.0))
    return P


def build_twin_saw(spec):
    """ONE disc, which D1 instances twice 0.23 m apart.  0.19 m radius, 0.020
    thick, spinning about the bot's Z, authored about the disc centre.

    This is `saw.glb`'s blade at 1.23 times the size and it is meant to read as
    exactly that.  What it does NOT carry is the guard, the motor and the belt
    cover the single saw has: those would be spinning with the disc.  What reads
    as "a bigger deliberate version" here is the tooth count, the thickness and
    the hub, not a repeated bracket."""
    P = Part("twin_saw", "weapon")
    r = 0.19
    t = 0.020

    # the plate: a dished blade with a raised titanium ring, as the saw has
    P.cyl((0, 0, 0), (0, 0, 1), r - 0.020, t - 0.006, "steel", n=28, bevel=0.002)
    for s in (-1.0, 1.0):
        P.ring((0, 0, s * (t * 0.5 - 0.004)), (0, 0, 1), r - 0.018, r - 0.058,
               0.008, "titanium", n=28)
    # expansion slots, the three curved cuts a real blade carries
    for i in range(3):
        a = 2.0 * math.pi * i / 3.0 + 0.4
        P.box(((r - 0.055) * math.cos(a), (r - 0.055) * math.sin(a), 0.0),
              (0.056, 0.010, t + 0.004), "dark_metal", bevel=0.0,
              rot=rot_pitch(math.degrees(a)))
    # 22 carbide teeth, raked forward
    teeth = 22
    for i in range(teeth):
        a = 2.0 * math.pi * i / teeth
        c, s = math.cos(a), math.sin(a)
        P.box(((r - 0.009) * c, (r - 0.009) * s, 0.0), (0.024, 0.026, t + 0.004),
              "titanium", bevel=0.0018, seg=1, rot=rot_pitch(math.degrees(a)))
        P.prism([(0.0, 0.013), (0.014, 0.004), (0.0, -0.011)],
                -(t * 0.5 + 0.002), t * 0.5 + 0.002, "steel", bevel=0.0012, seg=1,
                rot=rot_pitch(math.degrees(a)),
                at=((r - 0.001) * c, (r - 0.001) * s, 0.0))
    # hub boss, flange and the six drive bolts
    P.cyl((0, 0, 0), (0, 0, 1), 0.042, 0.034, "dark_metal", n=14, bevel=0.003)
    for s in (-1.0, 1.0):
        P.ring((0, 0, s * 0.020), (0, 0, 1), 0.048, 0.042, 0.010, "steel", n=14)
        for i in range(6):
            a = 2.0 * math.pi * i / 6.0 + (0.0 if s > 0 else 0.5)
            P.bolt((0.031 * math.cos(a), 0.031 * math.sin(a), s * (t * 0.5 + 0.001)),
                   (0, 0, s), r=0.0068)
    P.socket("socket_pivot", (0.0, 0.0, 0.0))
    P.socket("socket_tip", (r, 0.0, 0.0))
    return P


def build_napalm_cannon(spec):
    """A short mortar tube on a cradle, canted up, with the five charges in a
    rack alongside so the finite ammunition is visible on the machine."""
    P = Part("napalm_cannon", "weapon")
    d, h, w = 0.18, 0.16, 0.18              # the collision tube, exactly
    hh, hw = h * 0.5, w * 0.5
    cant = 9.0                              # degrees, nose up

    P.plate((0.009, -0.012, 0.0), (0.018, h - 0.022, w), "livery",
            axis=(-1, 0, 0), inset=0.028, hardware=True)
    # the cradle the tube sits in
    P.box((0.090, -hh + 0.016, 0.0), (0.150, 0.032, w - 0.024), "dark_metal",
          bevel=0.003, seg=2)
    for sz in (-1.0, 1.0):
        P.prism([(0.030, 0.0), (0.150, 0.0), (0.150, 0.052), (0.030, 0.026)],
                sz * (hw - 0.020) - 0.008, sz * (hw - 0.020) + 0.008,
                "steel", bevel=0.0025, seg=1, at=(0.0, -hh + 0.028, 0.0))
        P.hardware_bolt((0.118, -hh + 0.030, sz * (hw - 0.020)), (0, 1, 0))
    # the tube: a thick-walled mortar, breech end low and aft
    at = (0.098, -0.002, 0.0)
    axis = (math.cos(math.radians(cant)), math.sin(math.radians(cant)), 0.0)
    P.cyl(at, axis, 0.036, 0.130, "steel", n=16, bevel=0.003)
    for f in (-0.044, 0.0, 0.044):
        P.ring((at[0] + axis[0] * f, at[1] + axis[1] * f, 0.0), axis,
               0.041, 0.036, 0.011, "dark_metal", n=16)
    # the breech block and its firing gear at the back of the tube
    P.cone((at[0] - axis[0] * 0.074, at[1] - axis[1] * 0.074, 0.0), axis,
           0.030, 0.038, 0.020, "dark_metal", n=14)
    P.cyl((at[0] - axis[0] * 0.088, at[1] - axis[1] * 0.088, 0.0), axis,
          0.018, 0.016, "steel", n=10, bevel=0.002)
    # muzzle: a flared mouth with a blast ring
    muzzle = (at[0] + axis[0] * 0.078, at[1] + axis[1] * 0.078, 0.0)
    P.cone(muzzle, axis, 0.036, 0.043, 0.016, "steel", n=16)
    P.ring((muzzle[0] + axis[0] * 0.010, muzzle[1] + axis[1] * 0.010, 0.0),
           axis, 0.044, 0.031, 0.008, "titanium", n=16)
    # the five charges, in a rack down the right flank: the ammunition count
    for i in range(5):
        x = 0.046 + i * 0.026
        P.cyl((x, -hh + 0.058, hw - 0.016), (0, 1, 0), 0.010, 0.040,
              "dark_metal", n=8, bevel=0.0)
        P.cone((x, -hh + 0.080, hw - 0.016), (0, 1, 0), 0.010, 0.004, 0.011,
               "copper", n=8)
    P.box((0.098, -hh + 0.036, hw - 0.016), (0.142, 0.012, 0.024), "steel",
          bevel=0.002, seg=1)
    # the fuel bottle for the charges, on the other flank
    P.cyl((0.088, -hh + 0.062, -hw + 0.022), (1, 0, 0), 0.026, 0.100,
          "livery", n=12, bevel=0.003)
    P.cone((0.144, -hh + 0.062, -hw + 0.022), (1, 0, 0), 0.026, 0.016, 0.014,
           "steel", n=12)
    P.cyl((0.026, -hh + 0.062, -hw + 0.022), (1, 0, 0), 0.010, 0.014,
          "dark_metal", n=8)
    P.socket("socket_pivot", (0.0, 0.0, 0.0))
    P.socket("socket_muzzle", (muzzle[0] + axis[0] * 0.016,
                               muzzle[1] + axis[1] * 0.016, 0.0))
    P.socket("socket_tip", (muzzle[0] + axis[0] * 0.016,
                            muzzle[1] + axis[1] * 0.016, 0.0))
    return P


def build_vortex_spinner(spec):
    """The Shell's ring with the teeth raked over: scooped, angled up, so it
    visibly lifts what it hits.  Authored about the hull origin like
    `full_body_spinner`, because D1 parents it at identity.

    It has to read on a hull that is NOT a Shell as well, so the bore is closed
    by a spoked spider rather than left as a hole a wedge's nose shows through."""
    P = Part("vortex_spinner", "weapon")
    reach = spec["reach"]                    # 0.48
    r_out = reach - 0.066                    # teeth then reach the catalogue
    r_in = r_out - 0.062
    h = 0.150

    P.ring((0, 0, 0), (0, 1, 0), r_out, r_in, h, "livery", n=32, bevel=0.003)
    P.ring((0, h * 0.5 + 0.009, 0), (0, 1, 0), r_out - 0.004, r_in - 0.006,
           0.018, "titanium", n=32, bevel=0.0)
    P.ring((0, -h * 0.5 - 0.009, 0), (0, 1, 0), r_out - 0.004, r_in - 0.006,
           0.018, "titanium", n=32, bevel=0.0)

    # TEN raked teeth.  The rake is the whole part: each tooth is a scoop whose
    # face leans back AND tips up, so the bite leaves along the tangent and
    # upward.  The full body spinner's are square blocks with a flat lip.
    for i in range(10):
        a = 2.0 * math.pi * i / 10.0
        c, s = math.cos(a), math.sin(a)
        yaw = rot_z(math.degrees(-a))
        # the root block, canted up 22 degrees
        P.box(((r_out - 0.012) * c, 0.006, (r_out - 0.012) * s),
              (0.056, h + 0.020, 0.082), "steel", bevel=0.004, seg=2,
              rot=yaw @ rot_pitch(22.0))
        # THE SCOOP IS THE WHOLE PART.  A full body spinner's tooth is a square
        # block with a flat lip and it bats; this one is a ramp whose face
        # climbs from BELOW the ring's waist to well above its shoulder, so
        # whatever it catches is carried up the face instead of along it.  The
        # profile is deliberately tall (it spans 1.4 times the ring's height)
        # because at fight distance the only thing that separates the two
        # weapons on screen is that the teeth on this one stick UP.
        P.prism([(0.0, -h * 0.58), (0.0, h * 0.30), (0.030, h * 0.86),
                 (0.068, h * 0.88), (0.076, h * 0.34), (0.040, -h * 0.30)],
                -0.040, 0.040, "titanium", bevel=0.003, seg=2,
                rot=yaw, at=((r_out - 0.004) * c, 0.0, (r_out - 0.004) * s))
        # the hardened lip that actually gets under, tipped up 34 degrees
        P.prism([(0.0, 0.026), (0.0, -0.026), (0.052, 0.004)],
                -0.034, 0.034, "steel", bevel=0.0025, seg=1,
                rot=yaw @ rot_pitch(34.0),
                at=((r_out + 0.028) * c, h * 0.34, (r_out + 0.028) * s))
        # the gullet behind it, which is what makes a scoop read as a scoop
        P.prism([(0.0, h * 0.40), (0.030, h * 0.86), (0.030, h * 0.40)],
                -0.026, 0.026, "dark_metal", bevel=0.002, seg=1,
                rot=yaw, at=((r_out - 0.030) * c, 0.0, (r_out - 0.030) * s))
        P.hardware_bolt(((r_out - 0.042) * c, h * 0.5 + 0.020,
                         (r_out - 0.042) * s), (0, 1, 0))

    # the drive ring, and the six-arm spider that closes the bore
    P.ring((0, -h * 0.5 + 0.014, 0), (0, 1, 0), r_in, r_in - 0.030, 0.030,
           "dark_metal", n=28, bevel=0.0)
    for i in range(6):
        a = 2.0 * math.pi * i / 6.0
        c, s = math.cos(a), math.sin(a)
        P.box((r_in * 0.5 * c, -h * 0.5 + 0.016, r_in * 0.5 * s),
              (r_in, 0.016, 0.052), "steel", bevel=0.0025, seg=1,
              rot=rot_z(math.degrees(-a)))
        P.bolt(((r_in - 0.016) * c, -h * 0.5 + 0.026, (r_in - 0.016) * s),
               (0, 1, 0), r=0.007)
    P.cyl((0, -h * 0.5 + 0.026, 0), (0, 1, 0), 0.060, 0.046, "dark_metal",
          n=14, bevel=0.003)
    P.ring((0, -h * 0.5 + 0.050, 0), (0, 1, 0), 0.066, 0.040, 0.014, "steel", n=14)
    P.socket("socket_pivot", (0.0, 0.0, 0.0))
    P.socket("socket_tip", (reach, 0.0, 0.0))
    return P


BUILDERS.update({
    "shock_prod": build_shock_prod,
    "tesla_arc": build_tesla_arc,
    "drill_lance": build_drill_lance,
    "twin_saw": build_twin_saw,
    "napalm_cannon": build_napalm_cannon,
    "vortex_spinner": build_vortex_spinner,
})
