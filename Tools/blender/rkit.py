"""Roboteer part toolkit (agent G3).

AUTHORING SPACE IS *BOT* SPACE, the convention in docs/graphics-bar.md:

    +X forward (the nose)   +Y up   +Z right

and the origin sits at the chassis centre on the AXLE PLANE, which is
WHEEL_RADIUS (0.11 m) above the arena floor. So the floor is y = -0.11.

THE AXIS RULE (verified, see docs/graphics-models-notes.md)
-----------------------------------------------------------
Blender is Z-up / Y-forward; glTF and Godot are both Y-up / -Z-forward.
The glTF exporter with ``export_yup=True`` maps Blender (x, y, z) to
glTF (x, z, -y).  We therefore build in Bot space and apply BOT2BL
(Bot -> Blender: (x, y, z) -> (x, -z, y)) once, at object creation.
Composing the two gives the identity:

    bot (x, y, z) -> blender (x, -z, y) -> gltf (x, y, z)

so the numbers you author here are *exactly* the numbers Godot sees.
Nothing is mirrored (det(BOT2BL) = +1).  `verify_parts.py` proves it by
reading the exported POSITION accessor min/max back out of the .glb.
"""

import math
import os

import bpy
import bmesh
from mathutils import Matrix, Vector

# ---------------------------------------------------------------- constants

WHEEL_RADIUS = 0.11
WHEEL_WIDTH = 0.06
FLOOR_Y = -WHEEL_RADIUS

BEVEL = 0.0035          # 3.5 mm, inside the 2-4 mm bar
BEVEL_SMALL = 0.002
PLATE_T = 0.014         # bolted-on armour / body plate thickness
GAP = 0.006             # panel gap between adjacent plates
BOLT_R = 0.0085
BOLT_H = 0.0055
SEAM_R = 0.0042

# ---- wave A (v2) finishing.  docs/look/reference-study.md 3.3: "bevels 4 to 8 mm
# on major plate edges (today 2 to 4 mm, which is 2 to 4 px at the menu distance
# and too thin to hold a rim highlight), weighted normals".
BEVEL_V2 = 0.006        # major plate and hull edges
BEVEL_V2_MID = 0.004    # brackets, knuckles, secondary panels
BEVEL_V2_SMALL = 0.0022 # hardware and small detail
SEG_V2 = 3              # three segments: a round, not a chamfer, at 1 px per mm
V2_BEVEL_MIN_ANGLE = 20.0   # degrees; flatter edges are loft seams, not corners
V2_SHARP_ANGLE = 50.0       # split normals above this; weighted normals do the rest

# Bot -> Blender.  det = +1, no mirroring.
BOT2BL = Matrix(((1, 0, 0, 0),
                 (0, 0, -1, 0),
                 (0, 1, 0, 0),
                 (0, 0, 0, 1)))

#: name, base colour, metallic, roughness, emission strength
MATERIALS = [
    ("livery",        (0.85, 0.33, 0.07, 1.0), 0.00, 0.40, 0.0),
    ("steel",         (0.60, 0.62, 0.65, 1.0), 1.00, 0.34, 0.0),
    ("titanium",      (0.52, 0.52, 0.55, 1.0), 1.00, 0.26, 0.0),
    ("hdpe",          (0.88, 0.86, 0.80, 1.0), 0.00, 0.58, 0.0),
    ("polycarbonate", (0.72, 0.78, 0.84, 1.0), 0.00, 0.10, 0.0),
    ("rubber",        (0.055, 0.055, 0.062, 1.0), 0.00, 0.86, 0.0),
    ("dark_metal",    (0.115, 0.12, 0.130, 1.0), 1.00, 0.52, 0.0),
    ("core_glow",     (0.10, 0.90, 0.78, 1.0), 0.00, 0.30, 3.0),
    # Wave P, agent E.  APPENDED, never inserted: MAT_INDEX is keyed by name but
    # the EXPORTED slot order follows this list, so an insertion would shift the
    # slot order of every part already on disk.  Copper exists because three of
    # wave P's parts are electrical (the prod's tips, the tesla coil's winding and
    # its electrode, the overcharge core's bus bars) and "it should read as
    # electrical at a glance" was the brief for two of them.  Bare steel does not
    # read that way; a warm metal beside dark steel does, and a slot costs nothing
    # where a texture set would have cost a megabyte.
    ("copper",        (0.68, 0.33, 0.15, 1.0), 1.00, 0.35, 0.0),
]
MAT_INDEX = {m[0]: i for i, m in enumerate(MATERIALS)}

X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))


# ---------------------------------------------------------------- helpers

def _align_z(axis):
    """Rotation taking local +Z onto `axis` (bot space)."""
    a = Vector(axis).normalized()
    d = a.dot(Z)
    if d > 0.999999:
        return Matrix.Identity(4)
    if d < -0.999999:
        return Matrix.Rotation(math.pi, 4, 'X')
    return Z.rotation_difference(a).to_matrix().to_4x4()


def rot_z(deg):
    """Rotation about bot up (+Y) -- yaw."""
    return Matrix.Rotation(math.radians(deg), 4, 'Y')


def rot_pitch(deg):
    """Rotation about bot right (+Z) -- pitch, nose up positive."""
    return Matrix.Rotation(math.radians(deg), 4, 'Z')


def rot_roll(deg):
    """Rotation about bot forward (+X) -- roll."""
    return Matrix.Rotation(math.radians(deg), 4, 'X')


# ---------------------------------------------------------------- Part

class Part:
    """Accumulates bmesh geometry (in Bot space) plus socket empties."""

    def __init__(self, ident, category, mesh_name="body", uv_scale=1.0, v2=False,
                 bake_px=0):
        self.ident = ident
        self.category = category
        # WAVE A (hard-surface pass).  A v2 part opts into the finishing that the
        # reference study (docs/look/reference-study.md 3.3) asks for, without
        # changing a single byte of the 40-odd v1 parts when they are rebuilt:
        #   * bevel filtering by dihedral angle in `_stamp` (flat seams between
        #     loft stations are left alone, so a 6 mm, 3-segment bevel only lands
        #     on edges that are real corners),
        #   * a WeightedNormal modifier on export, so the big flat faces shade
        #     dead flat and ALL the shading turn happens inside the bevel, which
        #     is what makes an edge catch a thin bright line,
        #   * tangents in the glTF (anisotropic brushed steel needs them),
        #   * a second UV set (TEXCOORD_1, Godot UV2) that is the unscaled
        #     non-overlapping unwrap, and a baked edge/AO/cavity mask on it when
        #     `bake_px` > 0 (see `bake_masks` and docs/wave-a-contracts.md).
        # See docs/wave-a-models-notes.md for how to move a v1 part over.
        self.v2 = bool(v2)
        self.bake_px = int(bake_px)
        # UV DENSITY (wave P, agent E).  `smart_project` packs whatever it is
        # given into the 0..1 square, so a physically LARGE part comes out with
        # a LOW texel density and the same unwrap on a small part comes out
        # high: measured across the kit the spread is eightfold, which is what
        # `PartVisuals.density_matched` exists to paper over at runtime by
        # picking a `uv1_scale` per surface.  That runtime fix has a ceiling
        # (the largest step is 8x) and `hover.glb`, which is 0.96 m by 0.62 m
        # of mostly rubber against a 512 px rubber set, is the first part in
        # the kit to hit it: 0.183 uv/m x 8 x 512 = 750 texels per metre,
        # under the 900 floor `texel_density_test.gd` asserts.
        #
        # This is the fix at the source: the UVs are scaled here, once, at
        # export, so the part LEAVES Blender at a sane density and the runtime
        # step lands near 1.0 the way part_visuals.gd says it should.  It is
        # set per part rather than derived from surface area on purpose --
        # deriving it would change all 41 parts already on disk, and every one
        # of them already passes.
        self.uv_scale = float(uv_scale)
        self.objs = {}
        self.order = []
        self.origins = {}
        self.sockets = []
        self.bm = None
        # The primary mesh object is called `body`, so the Godot glTF importer
        # can name the scene root after the part id without a clash.  Boss hull
        # skins pass mesh_name="overlay" because that is what the assembler
        # looks for when it drapes one over a chassis.
        self.use(mesh_name)

    # -- object streams (a part may hold more than one mesh, e.g. shell/ring)
    def use(self, name, origin=None):
        """Switch to (or open) a named mesh stream.  Each becomes its own
        MeshInstance3D under the part's scene root, named exactly `name`.

        `origin` (wave P, agent E) puts that stream's NODE at a point instead of
        at identity, and the geometry you then author is measured from that point.
        It exists so a sub-assembly that has to TURN in Godot -- a track sprocket,
        a road wheel -- exports with its node origin on its own axis, because a
        node can only rotate about its own origin.  `PartVisuals.instantiate`
        animates any stream whose name begins with `spin_`.  Streams with no
        origin behave exactly as they always did."""
        if name not in self.objs:
            self.objs[name] = bmesh.new()
            self.order.append(name)
            if origin is not None:
                self.origins[name] = Vector(origin)
        self.bm = self.objs[name]
        return self

    def at(self, name):
        """The origin of a stream, as a Vector, so a builder can author relative
        geometry with absolute numbers: `P.at("spin_x") + Vector((0, 0, 0.02))`."""
        return self.origins.get(name, Vector((0.0, 0.0, 0.0)))

    # -- internals
    def _stamp(self, before, mat, bevel, seg, min_angle=None):
        new = [f for f in self.bm.faces if f not in before]
        if bevel and bevel > 0.0 and seg > 0:
            if min_angle is None and self.v2:
                min_angle = V2_BEVEL_MIN_ANGLE
            if min_angle:
                bmesh.ops.recalc_face_normals(self.bm, faces=new)
                for f in new:
                    f.normal_update()
            geom = []
            seen = set()
            lim = math.radians(min_angle) if min_angle else None
            for f in new:
                for e in f.edges:
                    if e not in seen:
                        seen.add(e)
                        if lim is not None and len(e.link_faces) == 2:
                            a, b = e.link_faces
                            try:
                                if a.normal.angle(b.normal) < lim:
                                    continue
                            except ValueError:
                                continue
                        geom.append(e)
            if geom:
                bmesh.ops.bevel(self.bm, geom=geom, offset=bevel, offset_type='OFFSET',
                                segments=seg, profile=0.5, affect='EDGES',
                                clamp_overlap=True,
                                miter_outer='ARC' if self.v2 else 'SHARP')
                new = [f for f in self.bm.faces if f not in before]
        bmesh.ops.recalc_face_normals(self.bm, faces=new)
        mi = MAT_INDEX[mat]
        for f in new:
            f.material_index = mi
        return new

    # -- primitives ------------------------------------------------------
    def box(self, center, size, mat, bevel=BEVEL, seg=2, rot=None):
        before = set(self.bm.faces)
        M = Matrix.Translation(Vector(center))
        if rot is not None:
            M = M @ rot
        M = M @ Matrix.Diagonal(Vector(size).to_4d())
        bmesh.ops.create_cube(self.bm, size=1.0, matrix=M)
        self._stamp(before, mat, bevel, seg)
        return self

    def prism(self, profile, z0, z1, mat, bevel=BEVEL, seg=2, rot=None, at=None):
        """Extrude a 2D profile (list of (x, y) in the forward/up plane) across Z."""
        before = set(self.bm.faces)
        M = Matrix.Identity(4)
        if at is not None:
            M = Matrix.Translation(Vector(at))
        if rot is not None:
            M = M @ rot
        a = [self.bm.verts.new(M @ Vector((p[0], p[1], z0))) for p in profile]
        b = [self.bm.verts.new(M @ Vector((p[0], p[1], z1))) for p in profile]
        self.bm.faces.new(a)
        self.bm.faces.new(list(reversed(b)))
        n = len(profile)
        for i in range(n):
            j = (i + 1) % n
            self.bm.faces.new((a[i], a[j], b[j], b[i]))
        self._stamp(before, mat, bevel, seg)
        return self

    def cone(self, center, axis, r1, r2, length, mat, n=16, bevel=0.0, seg=1):
        before = set(self.bm.faces)
        M = Matrix.Translation(Vector(center)) @ _align_z(axis)
        bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=n,
                              radius1=r1, radius2=r2, depth=length, matrix=M)
        self._stamp(before, mat, bevel, seg)
        return self

    def cyl(self, center, axis, radius, length, mat, n=16, bevel=0.0025, seg=1):
        return self.cone(center, axis, radius, radius, length, mat, n, bevel, seg)

    def ball(self, center, radius, mat, seg=12, rings=6, squash=1.0):
        """A UV sphere.  Wave P (agent E): the tesla arc's electrode and the
        overcharge core's pressure vessel are the only round things in the kit and
        a bicone reads as a spinning top, not as a ball.  `squash` scales Y."""
        before = set(self.bm.faces)
        M = Matrix.Translation(Vector(center)) @ Matrix.Diagonal(
            Vector((1.0, squash, 1.0)).to_4d())
        bmesh.ops.create_uvsphere(self.bm, u_segments=seg, v_segments=rings,
                                  radius=radius, matrix=M)
        self._stamp(before, mat, 0.0, 0)
        return self

    def helix(self, a, b, radius, turns, mat, steps=18, size=(0.018, 0.012),
              phase=0.0, starts=1):
        """A raised helical rib running a -> b about that axis, `starts` of them.
        This is what makes a drill read as a drill from the side: a smooth cone
        spinning at 18 rad/s looks like a smooth cone standing still."""
        a, b = Vector(a), Vector(b)
        d = b - a
        L = d.length
        if L < 1e-6:
            return self
        u = d / L
        # two vectors across the axis
        ref = Y if abs(u.dot(Y)) < 0.9 else X
        e1 = u.cross(ref).normalized()
        e2 = u.cross(e1).normalized()
        for s in range(starts):
            base = phase + 2.0 * math.pi * s / starts
            for i in range(steps):
                t = (i + 0.5) / steps
                ang = base + 2.0 * math.pi * turns * t
                r = radius(t) if callable(radius) else radius
                if r <= 0.0005:
                    continue
                n = (e1 * math.cos(ang) + e2 * math.sin(ang))
                p = a + u * (L * t) + n * r
                # a short bar lying along the local tangent of the helix
                tangent = (u * (L / (2.0 * math.pi * max(turns, 0.001)))
                           + (e2 * math.cos(ang) - e1 * math.sin(ang)) * r)
                if tangent.length < 1e-6:
                    tangent = u
                self.cone(p, tangent, size[1] * 0.5, size[1] * 0.5, size[0],
                          mat, n=4, bevel=0.0)
        return self

    def ring(self, center, axis, r_out, r_in, length, mat, n=28, bevel=0.0):
        """A hollow tube: outer wall, inner wall and two annular end caps."""
        before = set(self.bm.faces)
        M = Matrix.Translation(Vector(center)) @ _align_z(axis)
        h = length * 0.5
        oa, ob, ia, ib = [], [], [], []
        for i in range(n):
            t = 2.0 * math.pi * i / n
            c, s = math.cos(t), math.sin(t)
            oa.append(self.bm.verts.new(M @ Vector((r_out * c, r_out * s, -h))))
            ob.append(self.bm.verts.new(M @ Vector((r_out * c, r_out * s, h))))
            ia.append(self.bm.verts.new(M @ Vector((r_in * c, r_in * s, -h))))
            ib.append(self.bm.verts.new(M @ Vector((r_in * c, r_in * s, h))))
        for i in range(n):
            j = (i + 1) % n
            self.bm.faces.new((oa[i], oa[j], ob[j], ob[i]))   # outer wall
            self.bm.faces.new((ia[i], ib[i], ib[j], ia[j]))   # inner wall
            self.bm.faces.new((oa[i], ia[i], ia[j], oa[j]))   # -cap
            self.bm.faces.new((ob[i], ob[j], ib[j], ib[i]))   # +cap
        self._stamp(before, mat, bevel, 1 if bevel else 0)
        return self

    def band(self, path, z0, z1, t, mat, bevel=0.0, close=True):
        """A closed belt: `path` is the OUTER outline as (x, y) points going
        anticlockwise; the band grows inward by `t` and spans z0..z1."""
        before = set(self.bm.faces)
        n = len(path)
        pts = [Vector((p[0], p[1], 0.0)) for p in path]
        inner = []
        for i in range(n):
            a = pts[(i - 1) % n]
            b = pts[i]
            c = pts[(i + 1) % n]
            d = (c - a)
            nrm = Vector((d.y, -d.x, 0.0))
            if nrm.length < 1e-9:
                nrm = Vector((0.0, 1.0, 0.0))
            nrm.normalize()
            # outward is away from the path centroid
            inner.append(b - nrm * t)
        cen = sum(pts, Vector()) / n
        for i in range(n):
            if (inner[i] - cen).length > (pts[i] - cen).length:
                inner[i] = pts[i] + (cen - pts[i]).normalized() * t
        oa = [self.bm.verts.new((p.x, p.y, z0)) for p in pts]
        ob = [self.bm.verts.new((p.x, p.y, z1)) for p in pts]
        ia = [self.bm.verts.new((p.x, p.y, z0)) for p in inner]
        ib = [self.bm.verts.new((p.x, p.y, z1)) for p in inner]
        for i in range(n):
            j = (i + 1) % n
            self.bm.faces.new((oa[i], oa[j], ob[j], ob[i]))
            self.bm.faces.new((ia[i], ib[i], ib[j], ia[j]))
            self.bm.faces.new((oa[i], ia[i], ia[j], oa[j]))
            self.bm.faces.new((ob[i], ob[j], ib[j], ib[i]))
        self._stamp(before, mat, bevel, 1 if bevel else 0)
        return self

    # -- mechanical detail ----------------------------------------------
    def bolt(self, pos, axis=(0, 1, 0), r=BOLT_R, h=BOLT_H, mat="dark_metal"):
        a = Vector(axis).normalized()
        return self.cone(Vector(pos) + a * (h * 0.5), a, r, r * 0.80, h, mat, n=6, bevel=0.0)

    def bolt_line(self, p0, p1, count, axis=(0, 1, 0), r=BOLT_R, mat="dark_metal"):
        p0, p1 = Vector(p0), Vector(p1)
        for i in range(count):
            t = 0.5 / count + i / count if count > 1 else 0.5
            self.bolt(p0.lerp(p1, t), axis, r=r, mat=mat)
        return self

    def bolt_rect(self, center, u, v, axis=(0, 1, 0), r=BOLT_R, mat="dark_metal"):
        """Four bolts at the corners of a rectangle spanned by +-u and +-v."""
        c, u, v = Vector(center), Vector(u), Vector(v)
        for su in (-1, 1):
            for sv in (-1, 1):
                self.bolt(c + u * su + v * sv, axis, r=r, mat=mat)
        return self

    # -- hardware that reads at game distance ----------------------------
    def hardware_bolt(self, pos, axis=(0, 1, 0), r=0.0105, mat="dark_metal",
                      washer="steel"):
        """A fastener you can actually identify: a washer under a hex head with
        a dark recessed socket down the middle.  88 tris.  Use this on the big
        visible plates; `bolt()` stays the cheap 20-tri one for dense rows."""
        # 68 tris: a dark washer disc under a bright hex ring head, so the
        # bore reads as a dark recessed socket without a third primitive.
        a = Vector(axis).normalized()
        p = Vector(pos)
        self.cone(p + a * 0.0011, a, r * 1.34, r * 1.28, 0.0022, mat, n=6)
        self.ring(p + a * 0.0048, a, r, r * 0.46, 0.0052, washer, n=6)
        return self

    def shaft(self, a, b, r, mat="steel", n=10, grooves=(0.22, 0.78), step=0.78):
        """A turned shaft: circlip grooves and a machined diameter step, which
        is what stops a cylinder reading as a cylinder."""
        a, b = Vector(a), Vector(b)
        d = b - a
        L = d.length
        if L < 1e-5:
            return self
        u = d / L
        if step and 0.0 < step < 1.0:
            self.cyl(a + u * (L * step * 0.5), u, r, L * step, mat, n=n, bevel=0.0012)
            self.cyl(a + u * (L * (step + (1.0 - step) * 0.5)), u, r * 0.72,
                     L * (1.0 - step), mat, n=n, bevel=0.0012)
        else:
            self.cyl(a + u * (L * 0.5), u, r, L, mat, n=n, bevel=0.0012)
        for g in grooves:
            self.ring(a + u * (L * g), u, r * 1.002, r * 0.84, 0.0026,
                      "dark_metal", n=n)
        return self

    def bearing_cap(self, center, axis, r, mat="steel", h=0.010, n=10):
        """The domed cap over a wheel or sprocket bearing."""
        c, a = Vector(center), Vector(axis).normalized()
        self.ring(c + a * (h * 0.35), a, r, r * 0.74, h * 0.7, mat, n=n)
        self.cone(c + a * (h * 0.80), a, r * 0.78, r * 0.46, h * 0.6, mat, n=n)
        return self

    def boss(self, pos, axis, r, h, mat="dark_metal"):
        """A chamfered mounting boss: hardware never bolts to bare sheet."""
        a = Vector(axis).normalized()
        self.cone(Vector(pos) + a * (h * 0.5), a, r, r * 0.86, h, mat, n=10)
        return self

    # -- the middle tier of surface detail -------------------------------
    def ribs(self, center, size, count, mat, normal=1, run=2, h=0.007, w=0.013):
        """Pressed stiffening ribs: bars proud of a face by `h`, running along
        axis `run` and spaced along the remaining axis."""
        c, s = Vector(center), Vector(size)
        spread = [i for i in range(3) if i not in (normal, run)][0]
        for i in range(count):
            t = (i + 0.5) / count - 0.5
            p = c.copy()
            p[spread] = c[spread] + t * s[spread]
            p[normal] = c[normal] + h * 0.5
            sz = Vector((0.0, 0.0, 0.0))
            sz[run] = s[run]
            sz[spread] = w
            sz[normal] = h
            self.box(p, sz, mat, bevel=0.0018, seg=1)
        return self

    def deck_tread(self, p0, p1, z0, z1, nu, nv, mat="steel", size=0.024, h=0.0032):
        """Coarse diamond tread laid on the surface running p0 -> p1 across Z.
        Unbevelled, 12 tris a diamond, because at game distance the pattern is
        the read and the bevel is not."""
        a, b = Vector((p0[0], p0[1], 0.0)), Vector((p1[0], p1[1], 0.0))
        d = b - a
        L = d.length
        if L < 1e-5:
            return self
        th = math.atan2(d.y, d.x)
        n = Vector((d.y, -d.x, 0.0)) / L
        if n.y < 0.0:
            n = -n
        R = rot_pitch(math.degrees(th)) @ Matrix.Rotation(math.radians(45.0), 4, 'Y')
        for i in range(nu):
            for j in range(nv):
                fu = (i + 0.5) / nu
                fv = (j + 0.5) / nv
                stagger = 0.5 / nu if j % 2 else 0.0
                fu = min(max(fu + stagger, 0.02), 0.98)
                p = a.lerp(b, fu) + n * (h * 0.5)
                self.box((p.x, p.y, z0 + (z1 - z0) * fv), (size, h, size * 0.55),
                         mat, bevel=0.0, rot=R)
        return self

    def cable_run(self, pts, r=0.0055, mat="dark_metal", channel=True,
                  channel_mat="dark_metal"):
        """A recessed channel with a loom lying in it."""
        for i in range(len(pts) - 1):
            a, b = Vector(pts[i]), Vector(pts[i + 1])
            if channel:
                d = b - a
                mid = a + d * 0.5
                self.box(mid, (max(abs(d.x), r * 3.4), r * 2.0,
                               max(abs(d.z), r * 3.4)), channel_mat,
                         bevel=0.0015, seg=1)
            self.seam(a, b, r=r, mat=mat, n=6)
        return self

    def drain_slots(self, p0, p1, count, w=0.020, h=0.010, depth=0.012,
                    mat="dark_metal"):
        """Slots along an edge, so a plate has somewhere for grit to leave."""
        a, b = Vector(p0), Vector(p1)
        for i in range(count):
            t = (i + 0.5) / count
            p = a.lerp(b, t)
            d = (b - a).normalized()
            sz = Vector((depth, h, depth))
            for k in range(3):
                if abs(d[k]) > 0.5:
                    sz[k] = w
            self.box(p, sz, mat, bevel=0.0012, seg=1)
        return self

    def seam(self, a, b, r=SEAM_R, mat="steel", n=6):
        """A weld bead run along the edge a..b."""
        a, b = Vector(a), Vector(b)
        d = b - a
        if d.length < 1e-6:
            return self
        return self.cyl(a + d * 0.5, d, r, d.length, mat, n=n, bevel=0.0)

    def plate(self, center, size, mat, axis=(0, 1, 0), bolts=True, inset=0.026,
              bevel=BEVEL, seg=2, rot=None, bolt_mat="dark_metal", hardware=False):
        """A bevelled plate with bolt heads proud of its outward face."""
        self.box(center, size, mat, bevel=bevel, seg=seg, rot=rot)
        if bolts:
            c = Vector(center)
            s = Vector(size)
            a = Vector(axis).normalized()
            R = rot if rot is not None else Matrix.Identity(4)
            # the two in-plane axes of the plate are the ones `axis` is not
            ax = max(range(3), key=lambda i: abs(a[i]))
            others = [i for i in range(3) if i != ax]
            u = Vector((0, 0, 0)); u[others[0]] = max(s[others[0]] * 0.5 - inset, 0.008)
            v = Vector((0, 0, 0)); v[others[1]] = max(s[others[1]] * 0.5 - inset, 0.008)
            face = c + (R @ (a * (s[ax] * 0.5)))
            if hardware:
                n = R @ a
                for su in (-1, 1):
                    for sv in (-1, 1):
                        self.hardware_bolt(face + (R @ u) * su + (R @ v) * sv, n)
            else:
                self.bolt_rect(face, R @ u, R @ v, axis=R @ a, mat=bolt_mat)
        return self

    def slab(self, p0, p1, z0, z1, t, mat, outward=(0, 1), bolts=0, bevel=BEVEL,
             seg=2, inset=0.03, bolt_mat="dark_metal"):
        """A plate whose OUTER surface runs p0 -> p1 in the forward/up plane and
        spans z0..z1 across.  Thickness `t` grows away from `outward`."""
        a, b = Vector((p0[0], p0[1], 0.0)), Vector((p1[0], p1[1], 0.0))
        d = b - a
        L = d.length
        if L < 1e-5:
            return self
        th = math.atan2(d.y, d.x)
        n = Vector((d.y, -d.x, 0.0)) / L
        if n.dot(Vector((outward[0], outward[1], 0.0))) < 0.0:
            n = -n
        c = (a + b) * 0.5 - n * (t * 0.5)
        R = rot_pitch(math.degrees(th))
        self.box((c.x, c.y, (z0 + z1) * 0.5), (L, t, z1 - z0), mat, bevel=bevel, seg=seg, rot=R)
        if bolts:
            u = d.normalized()
            for i in range(bolts):
                f = inset / L + (i / max(bolts - 1, 1)) * (1.0 - 2.0 * inset / L) if bolts > 1 else 0.5
                p = a.lerp(b, f) + n * 0.0
                for sz in (z0 + inset, z1 - inset):
                    self.bolt((p.x, p.y, sz), n, mat=bolt_mat)
        return self

    def louvres(self, center, size, count, mat="dark_metal", axis=(0, 1, 0)):
        """A vent: `count` thin slats sunk into a face."""
        c, s = Vector(center), Vector(size)
        for i in range(count):
            t = (i + 0.5) / count - 0.5
            p = c + Vector((0, 0, 0))
            p[2] = c[2] + t * s[2]
            self.box(p, (s[0], s[1], s[2] / count * 0.5), mat, bevel=0.0012, seg=1)
        return self

    # -- wave A (v2) primitives: curved, chamfered, lofted ----------------
    def loft(self, sections, mat, bevel=BEVEL_V2, seg=SEG_V2, cap=True,
             min_angle=None, closed=False):
        """Skin a run of cross-sections into one closed solid.  `sections` is a
        list of rings, each a list of 3D points (bot space) with the SAME count
        and the same winding.  This is the shell primitive: a tapered wedge, a
        cowl with chamfered cheeks, a hull whose section changes along its
        length.  Only real corners are bevelled (see `_stamp`), so the stations
        between two coplanar faces do not grow slivers.  `closed` joins the last
        section back to the first (a torus-like sweep) and skips the caps."""
        before = set(self.bm.faces)
        rings = [[self.bm.verts.new(Vector(p)) for p in s] for s in sections]
        n = len(rings[0])
        count = len(rings) if closed else len(rings) - 1
        for k in range(count):
            a, b = rings[k], rings[(k + 1) % len(rings)]
            for i in range(n):
                j = (i + 1) % n
                self.bm.faces.new((a[i], a[j], b[j], b[i]))
        if cap and not closed:
            self.bm.faces.new(list(reversed(rings[0])))
            self.bm.faces.new(rings[-1])
        self._stamp(before, mat, bevel, seg, min_angle=min_angle)
        return self

    def lathe(self, profile, center, axis, mat, n=24, phase=0.0, bevel=0.0,
              seg=0, min_angle=None, closed=False):
        """Revolve a profile of (radius, height) pairs about `axis` through
        `center`.  A point with radius 0 collapses to the axis, so a profile
        that starts and ends on the axis is a closed solid (a bottle, a dome,
        a hub); `closed=True` joins the last point to the first instead (a
        tyre carcass, an O-ring).  This is where round things stop being
        16-sided cylinders: fillets live in the profile, so they cost rings,
        not bevel geometry."""
        before = set(self.bm.faces)
        M = Matrix.Translation(Vector(center)) @ _align_z(axis)
        rings = []
        for (r, h) in profile:
            if r <= 1e-7:
                rings.append([self.bm.verts.new(M @ Vector((0.0, 0.0, h)))])
            else:
                ring = []
                for i in range(n):
                    t = phase + 2.0 * math.pi * i / n
                    ring.append(self.bm.verts.new(
                        M @ Vector((r * math.cos(t), r * math.sin(t), h))))
                rings.append(ring)
        m = len(rings)
        spans = m if closed else m - 1
        for k in range(spans):
            a, b = rings[k], rings[(k + 1) % m]
            for i in range(n):
                j = (i + 1) % n
                if len(a) == 1 and len(b) == 1:
                    continue
                if len(a) == 1:
                    self.bm.faces.new((a[0], b[j], b[i]))
                elif len(b) == 1:
                    self.bm.faces.new((a[i], a[j], b[0]))
                else:
                    self.bm.faces.new((a[i], a[j], b[j], b[i]))
        if not closed:
            if len(rings[0]) > 1:
                self.bm.faces.new(list(reversed(rings[0])))
            if len(rings[-1]) > 1:
                self.bm.faces.new(rings[-1])
        self._stamp(before, mat, bevel, seg, min_angle=min_angle)
        return self

    def outline(self, pts, origin, u, v, n, t, mat, bevel=BEVEL_V2, seg=SEG_V2,
                back=0.0, min_angle=None):
        """A flat plate whose OUTER face is the 2D outline `pts` (in the plane
        spanned by `u`, `v` through `origin`) and which is `t` thick back along
        -`n`.  `back` insets the rear face so the plate's edges are chamfered
        (a positive `back` shrinks the back outline towards its centroid).
        This is how a cheek plate, a cut-corner cover or a tapered lip is made
        without stacking boxes."""
        o, u, v, n = Vector(origin), Vector(u), Vector(v), Vector(n).normalized()
        cu = sum(p[0] for p in pts) / len(pts)
        cv = sum(p[1] for p in pts) / len(pts)
        front = [o + u * p[0] + v * p[1] for p in pts]
        rear = []
        for p in pts:
            du, dv = p[0] - cu, p[1] - cv
            L = math.hypot(du, dv)
            k = max(L - back, L * 0.2) / L if L > 1e-9 else 1.0
            rear.append(o + u * (cu + du * k) + v * (cv + dv * k) - n * t)
        return self.loft([rear, front], mat, bevel=bevel, seg=seg, min_angle=min_angle)

    def hose(self, pts, r, mat="rubber", n=8, per_span=6, fittings="steel",
             fit_r=None, fit_len=0.012):
        """A flexible line through `pts` (Catmull-Rom, so it sags and bends
        rather than kinking), swept with a round section, capped, with a hex
        crimp ferrule at each end.  Cables, hydraulic and pneumatic lines,
        braided gas feed: the detail that tells a player a machine is plumbed."""
        P = [Vector(p) for p in pts]
        if len(P) < 2:
            return self
        ext = [P[0] + (P[0] - P[1])] + P + [P[-1] + (P[-1] - P[-2])]
        path = []
        for k in range(1, len(ext) - 2):
            p0, p1, p2, p3 = ext[k - 1], ext[k], ext[k + 1], ext[k + 2]
            steps = per_span if k < len(ext) - 3 else per_span + 1
            for s in range(steps):
                t = s / per_span
                t2, t3 = t * t, t * t * t
                path.append(0.5 * ((2 * p1) + (-p0 + p2) * t
                                   + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                                   + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
        # parallel-transport frames so the section never twists
        tans = []
        for i in range(len(path)):
            a = path[max(i - 1, 0)]
            b = path[min(i + 1, len(path) - 1)]
            d = b - a
            tans.append(d.normalized() if d.length > 1e-9 else Vector((1, 0, 0)))
        ref = Y if abs(tans[0].dot(Y)) < 0.9 else X
        nrm = tans[0].cross(ref).normalized()
        sections = []
        for i, p in enumerate(path):
            if i:
                axis = tans[i - 1].cross(tans[i])
                if axis.length > 1e-9:
                    ang = tans[i - 1].angle(tans[i])
                    nrm = (Matrix.Rotation(ang, 3, axis.normalized()) @ nrm).normalized()
            bi = tans[i].cross(nrm).normalized()
            sections.append([p + (nrm * math.cos(2 * math.pi * j / n)
                                  + bi * math.sin(2 * math.pi * j / n)) * r
                             for j in range(n)])
        self.loft(sections, mat, bevel=0.0, seg=0)
        if fittings:
            fr = fit_r or r * 1.55
            for p, d in ((path[0], tans[0]), (path[-1], -tans[-1])):
                self.cone(p + d * (fit_len * 0.5 - 0.001), d, fr, fr * 0.92, fit_len,
                          fittings, n=6)
        return self

    def button_bolt(self, pos, axis=(0, 1, 0), r=0.0065, mat="steel",
                    washer="dark_metal", n=8):
        """A button-head cap screw on a washer: the fastener robot builders
        actually use on armour.  The dome is a three-ring lathe, so it holds a
        round specular dot at menu distance instead of a flat hex facet, and
        the hex socket is a dark recess on its crown.  About 100 tris."""
        a = Vector(axis).normalized()
        p = Vector(pos)
        if washer:
            self.lathe([(0.0, 0.0), (r * 1.45, 0.0), (r * 1.45, 0.0012),
                        (0.0, 0.0012)], p, a, washer, n=n)
        base = p + a * (0.0012 if washer else 0.0)
        h = r * 0.62
        self.lathe([(0.0, 0.0), (r, 0.0), (r, h * 0.30), (r * 0.80, h * 0.82),
                    (0.0, h)], base, a, mat, n=n)
        self.cone(base + a * (h - 0.0002), a, r * 0.36, r * 0.36, 0.0006,
                  "dark_metal", n=6)
        return self

    def countersunk(self, pos, axis=(0, 1, 0), r=0.0062, mat="steel", n=8):
        """A flush countersunk head in a chamfered seat.  Seat ring in dark
        metal so the head reads as sunk, flush head, dark hex recess."""
        a = Vector(axis).normalized()
        p = Vector(pos)
        self.lathe([(r * 1.35, 0.0), (r * 1.35, 0.0005), (r * 1.02, 0.0007),
                    (r * 1.02, 0.0), ], p, a, "dark_metal", n=n, closed=True)
        self.lathe([(0.0, 0.0), (r, 0.0), (r * 0.97, 0.0009), (0.0, 0.0009)],
                   p, a, mat, n=n)
        self.cone(p + a * 0.0010, a, r * 0.38, r * 0.38, 0.0005, "dark_metal", n=6)
        return self

    def hex_nut(self, pos, axis, r, h, mat="steel"):
        """A chamfered hex nut: hex prism with a 30-degree chamfer ring top."""
        a = Vector(axis).normalized()
        p = Vector(pos)
        self.lathe([(0.0, 0.0), (r, 0.0), (r, h * 0.75), (r * 0.84, h), (0.0, h)],
                   p, a, mat, n=6, phase=math.pi / 6.0)
        return self

    # -- sockets ---------------------------------------------------------
    def socket(self, name, pos):
        self.sockets.append((name, Vector(pos)))
        return self


# ---------------------------------------------------------------- scene

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_materials():
    out = []
    for name, col, metal, rough, emit in MATERIALS:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = col
        bsdf.inputs["Metallic"].default_value = metal
        bsdf.inputs["Roughness"].default_value = rough
        if emit > 0.0:
            bsdf.inputs["Emission Color"].default_value = col
            bsdf.inputs["Emission Strength"].default_value = emit
        m.diffuse_color = col
        out.append(m)
    return out


def finish_and_export(part, out_root, sharp_angle=40.0, uv=True):
    """Realise the Part as Blender objects, UV it and write the .glb."""
    reset_scene()
    mats = make_materials()
    scene_objs = []
    if part.v2:
        sharp_angle = V2_SHARP_ANGLE
    angle = math.radians(sharp_angle)

    for name in part.order:
        bm = part.objs[name]
        if len(bm.faces) == 0:
            # a stream that was opened and never drawn in (the default `body` of a
            # part authored entirely in named streams, fitment pass 2)
            continue
        bmesh.ops.triangulate(bm, faces=bm.faces[:],
                              quad_method='BEAUTY', ngon_method='BEAUTY')
        bmesh.ops.transform(bm, matrix=BOT2BL, verts=bm.verts[:])
        bm.normal_update()
        for f in bm.faces:
            f.smooth = True
        for e in bm.edges:
            if len(e.link_faces) == 2:
                a, b = e.link_faces
                try:
                    e.smooth = a.normal.angle(b.normal) <= angle
                except ValueError:
                    e.smooth = False
            else:
                e.smooth = False
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        for m in mats:
            me.materials.append(m)
        ob = bpy.data.objects.new(name, me)
        # A stream opened with an `origin` keeps that origin as the NODE's
        # translation (its vertices were authored relative to it), so the node
        # can be rotated about its own axis in Godot.  transform_apply below is
        # told location=False precisely so this survives.
        if name in part.origins:
            ob.location = BOT2BL @ part.origins[name]
        bpy.context.scene.collection.objects.link(ob)
        scene_objs.append(ob)

    part.objs = {}

    if uv:
        for ob in scene_objs:
            bpy.ops.object.select_all(action='DESELECT')
            ob.select_set(True)
            bpy.context.view_layer.objects.active = ob
            bpy.ops.object.mode_set(mode='EDIT')
            bpy.ops.mesh.select_all(action='SELECT')
            try:
                bpy.ops.uv.smart_project(angle_limit=math.radians(66.0),
                                         island_margin=0.01, correct_aspect=True,
                                         scale_to_bounds=False)
            except Exception:
                bpy.ops.uv.cube_project(cube_size=1.0)
            bpy.ops.object.mode_set(mode='OBJECT')
            if part.v2:
                # UV2: the unscaled, non-overlapping unwrap, for the baked masks.
                # Copied BEFORE uv_scale touches UV0, and kept second so glTF
                # writes it as TEXCOORD_1 and Godot reads it as UV2.
                ob.data.uv_layers.new(name="bake", do_init=True)
                ob.data.uv_layers.active_index = 0
            if part.uv_scale != 1.0:
                layer = ob.data.uv_layers.active
                if layer is not None:
                    for datum in layer.data:
                        datum.uv = (datum.uv[0] * part.uv_scale,
                                    datum.uv[1] * part.uv_scale)

    for name, pos in part.sockets:
        e = bpy.data.objects.new(name, None)
        e.empty_display_type = 'PLAIN_AXES'
        e.empty_display_size = 0.03
        e.location = BOT2BL @ Vector(pos)
        bpy.context.scene.collection.objects.link(e)
        scene_objs.append(e)

    bpy.ops.object.select_all(action='DESELECT')
    for ob in scene_objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = scene_objs[0]
    # transforms are already baked into the mesh data; this is belt and braces
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    if part.v2:
        # Weighted normals: face-area weighting keeps every large flat face
        # shading perfectly flat, so the whole normal turn happens across the
        # bevel strip.  That strip is what catches the strip lights.  The
        # exporter applies modifiers (export_apply=True), so the custom split
        # normals land in the glTF NORMAL accessor.
        for ob in scene_objs:
            if ob.type != 'MESH':
                continue
            wn = ob.modifiers.new("weighted_normals", 'WEIGHTED_NORMAL')
            wn.mode = 'FACE_AREA'
            wn.weight = 50
            wn.keep_sharp = True
            wn.thresh = 0.01

    out_dir = os.path.join(out_root, part.category)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, part.ident + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format='GLB',
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_materials='EXPORT',
        export_image_format='NONE',
        export_texcoords=True,
        export_normals=True,
        export_tangents=bool(part.v2),
        export_cameras=False,
        export_lights=False,
        export_extras=False,
        export_animations=False,
        export_skins=False,
        export_morph=False,
        export_draco_mesh_compression_enable=False,
    )
    tris = sum(len(o.data.polygons) for o in scene_objs if o.type == 'MESH')
    if part.v2 and part.bake_px > 0:
        for ob in scene_objs:
            if ob.type != 'MESH':
                continue
            suffix = "" if ob.name == "body" else "_" + ob.name
            bake_masks(ob, os.path.join(out_dir, part.ident + suffix + "_mask.png"),
                       part.bake_px)
    return path, tris


# ---------------------------------------------------------------- mask bake

#: The mask convention, agreed with the materials lead in docs/wave-a-contracts.md.
#: One RGB PNG per mesh node, on UV2 (TEXCOORD_1), linear data, not colour:
#:   R  EDGE      convex edge wear.  0 on flat faces, 1 on the crest of a
#:                bevel.  Bevel-node curvature at a 4 mm radius, masked by the
#:                small-radius AO so creases do NOT count as edges.
#:   G  AO        ambient occlusion within the part, 16 mm and 80 mm radii mixed
#:                (1 open, 0 fully occluded).  Grime, dust in tread grooves.
#:   B  CAVITY    concave creases and panel gaps: 1 in a seam, 0 in the open.
MASK_EDGE_RADIUS = 0.010   # pass 2: was 0.004 against the SHADING normal, which on a
                           # v2 part (real 6 mm bevels, weighted normals) is already
                           # round, so R came out near zero on every big shell edge
MASK_AO_NEAR = 0.016
MASK_AO_FAR = 0.08


def bake_masks(ob, out_path, px):
    """Cycles-bake the R edge / G AO / B cavity mask for one mesh object onto
    its `bake` UV layer (UV2) and save it as a PNG next to the .glb.  Runs
    AFTER the glTF export, because it swaps the object's materials for a single
    bake shader."""
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 48
    scene.cycles.use_denoising = False
    try:
        scene.cycles.device = 'GPU'
        prefs = bpy.context.preferences.addons['cycles'].preferences
        prefs.compute_device_type = 'METAL'
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
    except Exception:
        scene.cycles.device = 'CPU'

    img = bpy.data.images.new(os.path.basename(out_path), px, px, alpha=False,
                              float_buffer=False)
    img.colorspace_settings.name = 'Non-Color'

    m = bpy.data.materials.new("mask_bake")
    m.use_nodes = True
    nt = m.node_tree
    for nd in list(nt.nodes):
        nt.nodes.remove(nd)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    bev = nt.nodes.new("ShaderNodeBevel")
    bev.samples = 16
    bev.inputs["Radius"].default_value = MASK_EDGE_RADIUS
    ao_n = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao_n.samples = 16
    ao_n.inputs["Distance"].default_value = MASK_AO_NEAR
    ao_n.only_local = True
    ao_f = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao_f.samples = 16
    ao_f.inputs["Distance"].default_value = MASK_AO_FAR
    ao_f.only_local = True

    def math_node(op, a=None, b=None, clamp=True):
        nd = nt.nodes.new("ShaderNodeMath")
        nd.operation = op
        nd.use_clamp = clamp
        if a is not None and not hasattr(a, "is_output"):
            nd.inputs[0].default_value = a
        if b is not None and not hasattr(b, "is_output"):
            nd.inputs[1].default_value = b
        return nd

    # edge = (1 - dot(bevelN, N)) * gain, masked by near-AO so creases drop out
    dot = nt.nodes.new("ShaderNodeVectorMath")
    dot.operation = 'DOT_PRODUCT'
    nt.links.new(bev.outputs["Normal"], dot.inputs[0])
    # against the TRUE (flat) face normal: a real bevel strip is then "edge"
    # too, which is where paint wears first
    nt.links.new(geo.outputs["True Normal"], dot.inputs[1])
    one_minus = math_node('SUBTRACT', 1.0)
    nt.links.new(dot.outputs["Value"], one_minus.inputs[1])
    gain = math_node('MULTIPLY', None, 9.0)
    nt.links.new(one_minus.outputs[0], gain.inputs[0])
    near_pow = math_node('POWER', None, 3.0)
    nt.links.new(ao_n.outputs["AO"], near_pow.inputs[0])
    edge = math_node('MULTIPLY')
    nt.links.new(gain.outputs[0], edge.inputs[0])
    nt.links.new(near_pow.outputs[0], edge.inputs[1])
    # ao = near^0.5 * far
    near_sqrt = math_node('POWER', None, 0.5)
    nt.links.new(ao_n.outputs["AO"], near_sqrt.inputs[0])
    ao = math_node('MULTIPLY')
    nt.links.new(near_sqrt.outputs[0], ao.inputs[0])
    nt.links.new(ao_f.outputs["AO"], ao.inputs[1])
    # cavity = (1 - near AO) * 1.6
    cav0 = math_node('SUBTRACT', 1.0)
    nt.links.new(ao_n.outputs["AO"], cav0.inputs[1])
    cav = math_node('MULTIPLY', None, 1.6)
    nt.links.new(cav0.outputs[0], cav.inputs[0])

    comb = nt.nodes.new("ShaderNodeCombineColor")
    nt.links.new(edge.outputs[0], comb.inputs[0])
    nt.links.new(ao.outputs[0], comb.inputs[1])
    nt.links.new(cav.outputs[0], comb.inputs[2])
    nt.links.new(comb.outputs[0], emit.inputs["Color"])
    nt.links.new(emit.outputs[0], out.inputs["Surface"])
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    uvn = nt.nodes.new("ShaderNodeUVMap")
    uvn.uv_map = "bake"
    nt.links.new(uvn.outputs["UV"], tex.inputs["Vector"])
    nt.nodes.active = tex
    tex.select = True

    # the modifiers (weighted normals) are irrelevant to the bake; strip them
    for mod in list(ob.modifiers):
        ob.modifiers.remove(mod)
    ob.data.materials.clear()
    ob.data.materials.append(m)
    for poly in ob.data.polygons:
        poly.material_index = 0
    ob.data.uv_layers.active = ob.data.uv_layers["bake"]

    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.bake(type='EMIT', margin=max(4, px // 128), margin_type='EXTEND',
                        use_clear=True)
    img.filepath_raw = out_path
    img.file_format = 'PNG'
    img.save()
    return out_path
