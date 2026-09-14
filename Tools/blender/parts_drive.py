"""Drive parts.

Every wheel spins about its own local +Z (the bot's left-right axis) and its
origin is the axle centre, so P2 drops it straight onto a `socket_wheel_*`
empty with no rotation.  The track unit is 0.70 m long, centred on the origin,
0.09 m wide, and P2 scales it along X per chassis footprint.
"""

import math

from rkit import Part, WHEEL_RADIUS, WHEEL_WIDTH, rot_pitch


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
        P.box((x + 0.010 * math.cos(a), y + 0.010 * math.sin(a), 0.0),
              (0.020, 0.046, 2 * hz + 0.004), "rubber", bevel=0.0025, seg=1,
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
