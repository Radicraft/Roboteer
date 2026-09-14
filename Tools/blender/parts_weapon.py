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
    P = Part("horizontal_spinner", "weapon")
    reach = spec["reach"]                 # 0.55
    bar_t, bar_h = 0.085, 0.052
    # hub on a vertical shaft
    P.cyl((0, 0, 0), (0, 1, 0), 0.076, 0.088, "steel", n=18, bevel=0.004)
    P.cyl((0, 0.058, 0), (0, 1, 0), 0.034, 0.048, "dark_metal", n=12, bevel=0.002)
    for i in range(8):
        a = 2.0 * math.pi * i / 8.0
        P.bolt((0.056 * math.cos(a), 0.044, 0.056 * math.sin(a)), (0, 1, 0))
    # the bar itself
    P.box((0, 0, 0), (2 * (reach - 0.09), bar_h, bar_t), "titanium",
          bevel=0.005, seg=2)
    for s in (-1.0, 1.0):
        # hardened tip: a swept block with a cutting corner
        P.box((s * (reach - 0.070), 0.0, 0.0), (0.140, bar_h + 0.030, bar_t + 0.026),
              "steel", bevel=0.006, seg=2)
        P.prism([(s * 0.070, -0.048), (s * 0.070, 0.048), (s * 0.0, 0.048),
                 (s * -0.010, 0.0)],
                -bar_t * 0.5 - 0.013, bar_t * 0.5 + 0.013, "titanium",
                bevel=0.0035, seg=2, at=(s * (reach - 0.070), 0.0, 0.0))
        P.hardware_bolt((s * (reach - 0.108), bar_h * 0.5 + 0.015, 0.0), (0, 1, 0))
        P.bolt((s * (reach - 0.060), bar_h * 0.5 + 0.007, 0.0), (0, 1, 0))
        P.bolt((s * (reach - 0.098), bar_h * 0.5 + 0.007, 0.0), (0, 1, 0))
        P.seam((s * (reach - 0.096), -bar_h * 0.5, bar_t * 0.5),
               (s * (reach - 0.096), bar_h * 0.5, bar_t * 0.5))
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
    # screw actuator: a threaded rod with a travelling nut, plus the motor
    P.cyl((-0.10, 0.075, 0.0), (1, 0, 0), 0.015, 0.30, "titanium", n=8, bevel=0.0)
    for i in range(8):
        P.ring((-0.225 + i * 0.036, 0.075, 0.0), (1, 0, 0), 0.024, 0.015, 0.011,
               "titanium", n=10)
    P.box((0.02, 0.075, 0.0), (0.062, 0.064, 0.074), "dark_metal", bevel=0.004, seg=2)
    P.ring((0.02, 0.075, 0.0), (1, 0, 0), 0.030, 0.024, 0.066, "steel", n=10)
    for i in range(4):
        a = 2.0 * math.pi * i / 4.0 + 0.4
        P.hardware_bolt((0.053, 0.075 + 0.040 * math.cos(a), 0.040 * math.sin(a)),
                        (1, 0, 0))
    P.cyl((-0.275, 0.075, 0.0), (1, 0, 0), 0.036, 0.090, "dark_metal", n=12, bevel=0.003)
    P.ring((-0.232, 0.075, 0.0), (1, 0, 0), 0.040, 0.036, 0.010, "steel", n=12)
    # the link from the nut down to the forks
    P.slab((0.02, 0.062), (0.10, 0.004), -0.012, 0.012, 0.014, "steel", outward=(1.0, 0.4))
    P.socket("socket_pivot", (0.0, 0.0, 0.0))
    P.socket("socket_tip", (reach + 0.014, -0.026, 0.0))
    return P


def build_crusher(spec):
    P = Part("crusher", "weapon")
    reach = spec["reach"]                 # 0.30
    hw = 0.055
    # the tower the jaw hangs from
    P.box((-0.06, 0.10, 0.0), (0.10, 0.20, 0.13), "dark_metal", bevel=0.004, seg=2)
    P.plate((-0.06, 0.205, 0.0), (0.10, 0.014, 0.13), "steel", axis=(0, 1, 0), inset=0.024)
    for s in (-1.0, 1.0):
        P.box((-0.06, 0.10, s * 0.078), (0.086, 0.17, 0.014), "livery",
              bevel=0.003, seg=2)
    P.cyl((0.0, 0.19, 0.0), (0, 0, 1), 0.016, 0.17, "steel", n=10, bevel=0.0)
    # upper jaw: three segments curving forward and down to two teeth
    pts = [(0.0, 0.19), (0.13, 0.175), (0.235, 0.125), (reach, 0.045)]
    for i in range(3):
        P.slab(pts[i], pts[i + 1], -hw, hw, 0.030, "titanium",
               outward=(0.2, 1.0), bolts=2, inset=0.035)
    for s in (-1.0, 1.0):
        P.prism([(0.0, 0.0), (0.075, 0.0), (0.012, -0.082)],
                s * 0.048 - 0.013, s * 0.048 + 0.013, "steel", bevel=0.003, seg=1,
                at=(reach - 0.055, 0.030, 0.0))
    # lower anvil with a matching bed
    P.slab((0.02, -0.030), (reach - 0.02, -0.046), -0.075, 0.075, 0.024,
           "steel", outward=(0.2, 1.0), bolts=2, inset=0.04)
    for s in (-1.0, 1.0):
        P.box((reach - 0.075, -0.014, s * 0.048), (0.055, 0.028, 0.026),
              "titanium", bevel=0.003, seg=1)
    # hydraulic ram driving the jaw
    _ram(P, (-0.095, 0.028, 0.0), (0.115, 0.152, 0.0), body_r=0.028, rod_r=0.013)
    P.box((-0.135, 0.020, 0.0), (0.070, 0.062, 0.090), "dark_metal", bevel=0.003, seg=1)
    P.cyl((-0.115, 0.056, 0.048), (0.4, 0.9, 0.0), 0.008, 0.11, "dark_metal", n=6)
    P.socket("socket_pivot", (0.0, 0.19, 0.0))
    P.socket("socket_tip", (reach, 0.045, 0.0))
    return P


def build_axe(spec):
    P = Part("axe", "weapon")
    reach = spec["reach"]                 # 0.60
    # pivot tower
    P.box((-0.05, 0.115, 0.0), (0.086, 0.23, 0.12), "dark_metal", bevel=0.004, seg=2)
    for s in (-1.0, 1.0):
        P.box((-0.05, 0.115, s * 0.072), (0.074, 0.20, 0.012), "livery", bevel=0.003, seg=2)
        P.bolt((-0.05, 0.030, s * 0.079), (0, 0, s))
    P.cyl((0.0, 0.225, 0.0), (0, 0, 1), 0.017, 0.16, "steel", n=10, bevel=0.0)
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
    # spring return: a coil plus its anchor
    for i in range(6):
        t = i / 5.0
        P.ring((-0.115 + t * 0.115, 0.045 + t * 0.155, 0.0), (0.60, 0.80, 0.0),
               0.026, 0.020, 0.010, "steel", n=8)
    P.box((-0.135, 0.028, 0.0), (0.050, 0.046, 0.056), "dark_metal", bevel=0.003, seg=1)
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
    # guard over the top rear quadrant
    for i in range(9):
        a = math.radians(60.0 + i * 12.0)
        c, s = math.cos(a), math.sin(a)
        P.box((cx + (r + 0.020) * c, 0.055 + (r + 0.020) * s, 0.0),
              (0.016, 0.042, 0.058), "livery", bevel=0.003, seg=1,
              rot=rot_pitch(math.degrees(a)))
    P.slab((cx - r - 0.040, 0.055), (cx - r - 0.040, 0.055 + r + 0.040),
           -0.029, 0.029, 0.012, "livery", outward=(-1.0, 0.0))
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
