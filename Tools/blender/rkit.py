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

    def __init__(self, ident, category):
        self.ident = ident
        self.category = category
        self.objs = {}
        self.order = []
        self.sockets = []
        self.bm = None
        # The primary mesh object is always called `body`, so the Godot glTF
        # importer can name the scene root after the part id without a clash.
        self.use("body")

    # -- object streams (a part may hold more than one mesh, e.g. shell/ring)
    def use(self, name):
        if name not in self.objs:
            self.objs[name] = bmesh.new()
            self.order.append(name)
        self.bm = self.objs[name]
        return self

    # -- internals
    def _stamp(self, before, mat, bevel, seg):
        new = [f for f in self.bm.faces if f not in before]
        if bevel and bevel > 0.0 and seg > 0:
            geom = []
            seen = set()
            for f in new:
                for e in f.edges:
                    if e not in seen:
                        seen.add(e)
                        geom.append(e)
            if geom:
                bmesh.ops.bevel(self.bm, geom=geom, offset=bevel, offset_type='OFFSET',
                                segments=seg, profile=0.5, affect='EDGES',
                                clamp_overlap=True, miter_outer='SHARP')
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

    def seam(self, a, b, r=SEAM_R, mat="steel", n=6):
        """A weld bead run along the edge a..b."""
        a, b = Vector(a), Vector(b)
        d = b - a
        if d.length < 1e-6:
            return self
        return self.cyl(a + d * 0.5, d, r, d.length, mat, n=n, bevel=0.0)

    def plate(self, center, size, mat, axis=(0, 1, 0), bolts=True, inset=0.026,
              bevel=BEVEL, seg=2, rot=None, bolt_mat="dark_metal"):
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
    angle = math.radians(sharp_angle)

    for name in part.order:
        bm = part.objs[name]
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
        export_tangents=False,
        export_cameras=False,
        export_lights=False,
        export_extras=False,
        export_animations=False,
        export_skins=False,
        export_morph=False,
        export_draco_mesh_compression_enable=False,
    )
    tris = sum(len(o.data.polygons) for o in scene_objs if o.type == 'MESH')
    return path, tris
