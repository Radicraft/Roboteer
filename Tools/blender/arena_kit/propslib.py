"""Helpers for the arena kit's broadcast and dressing props (kit_props.py).

AUTHORING SPACE IS GODOT SPACE:  +X right, +Y up, +Z = the FRONT of the piece
(the side that faces the arena / the audience), metres.

The kit convention is stated in Blender terms (Z-up, front = Blender -Y,
exported with export_yup=True).  The glTF exporter maps Blender (x, y, z) to
glTF (x, z, -y), so we author directly in Godot numbers and apply G2B
(Godot -> Blender: (x, y, z) -> (x, -z, y)) once when the mesh is realised.
Composing the two is the identity, so a vertex written here at (1, 2, 3) is
exactly (1, 2, 3) in Godot, and a front face written at +Z sits at Blender -Y
before export, as the convention demands.  det(G2B) = +1, nothing mirrors.

Material slots are by NAME only (Godot swaps them for triplanar PBR).  Each
piece carries only the slots it uses.  Faces authored with explicit UVs
(`quad(..., uv=...)`, used for the `screen` and `sign` faces) keep them;
every other face gets a Smart UV Project.

Kept deliberately independent of Tools/blender/rkit.py (whose material list
and bot-space convention are the parts library's, and which is being changed
by the models lead) but it follows the same house style: real chamfers on
hard edges only, 40 degree sharp-edge split, weighted normals, triangulated.
"""

import math
import os
import random

import bpy
import bmesh
from mathutils import Matrix, Vector

G2B = Matrix(((1, 0, 0, 0),
              (0, 0, -1, 0),
              (0, 1, 0, 0),
              (0, 0, 0, 1)))

X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))

#: slot -> (base colour linear RGBA, metallic, roughness, emission strength)
MATERIALS = {
    "galv_steel":   ((0.56, 0.57, 0.58, 1.0), 1.0, 0.46, 0.0),
    "dark_metal":   ((0.075, 0.078, 0.085, 1.0), 1.0, 0.55, 0.0),
    "aluminium":    ((0.78, 0.79, 0.81, 1.0), 1.0, 0.30, 0.0),
    "rust":         ((0.16, 0.062, 0.028, 1.0), 0.45, 0.82, 0.0),
    "concrete":     ((0.42, 0.41, 0.39, 1.0), 0.0, 0.92, 0.0),
    "rubber":       ((0.028, 0.028, 0.031, 1.0), 0.0, 0.86, 0.0),
    "wood":         ((0.40, 0.25, 0.12, 1.0), 0.0, 0.78, 0.0),
    "hazard_paint": ((0.92, 0.62, 0.02, 1.0), 0.0, 0.55, 0.0),
    "lamp_warm":    ((1.0, 0.72, 0.42, 1.0), 0.0, 0.30, 4.0),
    "lamp_white":   ((0.92, 0.95, 1.0, 1.0), 0.0, 0.12, 6.0),
    "lamp_amber":   ((1.0, 0.30, 0.0, 0.85), 0.0, 0.08, 1.5),
    "lamp_strip":   ((0.35, 0.80, 1.0, 1.0), 0.0, 0.30, 3.0),
    "lamp_red":     ((1.0, 0.04, 0.02, 1.0), 0.0, 0.25, 6.0),
    "screen":       ((0.015, 0.016, 0.02, 1.0), 0.0, 0.18, 0.0),
    "sign":         ((0.82, 0.82, 0.78, 1.0), 0.0, 0.50, 0.0),
    "flight_case":  ((0.030, 0.030, 0.034, 1.0), 0.0, 0.62, 0.0),
    "cable":        ((0.018, 0.018, 0.020, 1.0), 0.0, 0.50, 0.0),
}

CHAMFER = 0.006


def align_z(axis):
    """Rotation (4x4) taking local +Z onto `axis`."""
    a = Vector(axis).normalized()
    d = a.dot(Z)
    if d > 0.999999:
        return Matrix.Identity(4)
    if d < -0.999999:
        return Matrix.Rotation(math.pi, 4, 'X')
    return Z.rotation_difference(a).to_matrix().to_4x4()


def rx(deg):
    return Matrix.Rotation(math.radians(deg), 4, 'X')


def ry(deg):
    return Matrix.Rotation(math.radians(deg), 4, 'Y')


def rz(deg):
    return Matrix.Rotation(math.radians(deg), 4, 'Z')


def V(*a):
    if len(a) == 1:
        return Vector(a[0])
    return Vector(a)


class Mesh:
    """One exported mesh object, accumulated as bmesh in Godot space."""

    def __init__(self, name, origin=(0.0, 0.0, 0.0), parent=None):
        self.name = name
        self.origin = Vector(origin)   # node translation in Godot space
        self.parent = parent           # name of parent Mesh in the same glb
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.fixed = self.bm.faces.layers.int.new("fixed_uv")
        self.slots = []
        self.xf = [Matrix.Identity(4)]  # transform stack for grouped parts

    # -- grouping ------------------------------------------------------------
    def push(self, M):
        self.xf.append(self.xf[-1] @ M)
        return self

    def pop(self):
        self.xf.pop()
        return self

    @property
    def T(self):
        return self.xf[-1]

    # -- internals -----------------------------------------------------------
    def _mi(self, mat):
        if mat not in MATERIALS:
            raise KeyError("unknown slot " + mat)
        if mat not in self.slots:
            self.slots.append(mat)
        return self.slots.index(mat)

    def _stamp(self, before, mat, bevel=0.0, seg=1, angle=30.0):
        new = [f for f in self.bm.faces if f not in before]
        bmesh.ops.recalc_face_normals(self.bm, faces=new)
        if bevel and bevel > 0.0 and seg > 0:
            lim = math.radians(angle)
            geom, seen = [], set()
            for f in new:
                for e in f.edges:
                    if e in seen:
                        continue
                    seen.add(e)
                    if len(e.link_faces) == 2:
                        a, b = e.link_faces
                        try:
                            if a.normal.angle(b.normal) > lim:
                                geom.append(e)
                        except ValueError:
                            pass
            if geom:
                bmesh.ops.bevel(self.bm, geom=geom, offset=bevel, offset_type='OFFSET',
                                segments=seg, profile=0.5, affect='EDGES',
                                clamp_overlap=True, miter_outer='SHARP')
                new = [f for f in self.bm.faces if f not in before]
                bmesh.ops.recalc_face_normals(self.bm, faces=new)
        mi = self._mi(mat)
        for f in new:
            f.material_index = mi
        return new

    # -- primitives ----------------------------------------------------------
    def box(self, center, size, mat, bevel=CHAMFER, seg=1, rot=None):
        before = set(self.bm.faces)
        M = self.T @ Matrix.Translation(V(center))
        if rot is not None:
            M = M @ rot
        M = M @ Matrix.Diagonal(V(size).to_4d())
        bmesh.ops.create_cube(self.bm, size=1.0, matrix=M)
        return self._stamp(before, mat, bevel, seg)

    def box_ab(self, a, b, mat, bevel=CHAMFER, seg=1):
        """Axis-aligned box from min corner a to max corner b."""
        a, b = V(a), V(b)
        return self.box((a + b) * 0.5, b - a, mat, bevel, seg)

    def beam(self, a, b, w, h, mat, up=(0, 1, 0), bevel=0.0, seg=1, ext=0.0):
        """Rectangular bar from a to b (section w across, h along `up`)."""
        a, b = V(a), V(b)
        d = b - a
        L = d.length
        if L < 1e-6:
            return []
        f = d / L
        u = V(up)
        if abs(u.normalized().dot(f)) > 0.98:
            u = V(1, 0, 0) if abs(f.x) < 0.9 else V(0, 0, 1)
        s = f.cross(u).normalized()
        u = s.cross(f).normalized()
        R = Matrix((s, u, f)).transposed().to_4x4()
        return self.box((a + b) * 0.5, (w, h, L + 2 * ext), mat, bevel, seg, rot=R)

    def lathe(self, profile, center, axis, mat, n=16, cap=True, bevel=0.0,
              seg=1, phase=0.0, closed=False):
        """Revolve [(r, h), ...] about local Z (mapped onto `axis`)."""
        before = set(self.bm.faces)
        M = self.T @ Matrix.Translation(V(center)) @ align_z(axis)
        rings = []
        for (r, h) in profile:
            if r <= 1e-6:
                rings.append([self.bm.verts.new(M @ V(0, 0, h))])
            else:
                ring = []
                for i in range(n):
                    t = phase + 2 * math.pi * i / n
                    ring.append(self.bm.verts.new(M @ V(r * math.cos(t), r * math.sin(t), h)))
                rings.append(ring)
        pairs = [(rings[k], rings[k + 1]) for k in range(len(rings) - 1)]
        if closed:
            pairs.append((rings[-1], rings[0]))
            cap = False
        for A, B in pairs:
            if len(A) == 1 and len(B) == 1:
                continue
            for i in range(n):
                j = (i + 1) % n
                if len(A) == 1:
                    self.bm.faces.new((A[0], B[j], B[i]))
                elif len(B) == 1:
                    self.bm.faces.new((A[i], A[j], B[0]))
                else:
                    self.bm.faces.new((A[i], A[j], B[j], B[i]))
        if cap:
            if len(rings[0]) > 1:
                self.bm.faces.new(list(reversed(rings[0])))
            if len(rings[-1]) > 1:
                self.bm.faces.new(rings[-1])
        return self._stamp(before, mat, bevel, seg)

    def cyl(self, center, axis, r, length, mat, n=12, bevel=0.0, seg=1, cap=True, r2=None):
        r2 = r if r2 is None else r2
        return self.lathe([(r, -length / 2), (r2, length / 2)], center, axis, mat,
                          n=n, cap=cap, bevel=bevel, seg=seg)

    def rod(self, a, b, r, mat, n=8, cap=True, bevel=0.0):
        a, b = V(a), V(b)
        d = b - a
        return self.cyl((a + b) * 0.5, d, r, d.length, mat, n=n, cap=cap, bevel=bevel)

    def tube_ring(self, center, axis, r_out, r_in, length, mat, n=16, bevel=0.0):
        """A hollow short pipe / collar (open bore)."""
        h = length / 2
        prof = [(r_in, -h), (r_out, -h), (r_out, h), (r_in, h)]
        return self.lathe(prof, center, axis, mat, n=n, cap=False, closed=True, bevel=bevel)

    def torus(self, center, axis, R, r, mat, nu=16, nv=6, arc=360.0, phase=0.0):
        before = set(self.bm.faces)
        M = self.T @ Matrix.Translation(V(center)) @ align_z(axis)
        full = arc >= 359.9
        nu_v = nu if full else nu + 1
        grid = []
        for i in range(nu_v):
            t = math.radians(phase) + math.radians(arc) * i / nu
            c, s = math.cos(t), math.sin(t)
            ring = []
            for j in range(nv):
                p = 2 * math.pi * j / nv
                rr = R + r * math.cos(p)
                ring.append(self.bm.verts.new(M @ V(rr * c, rr * s, r * math.sin(p))))
            grid.append(ring)
        for i in range(nu if full else nu):
            A = grid[i]
            B = grid[(i + 1) % nu_v]
            for j in range(nv):
                k = (j + 1) % nv
                self.bm.faces.new((A[j], B[j], B[k], A[k]))
        if not full:
            self.bm.faces.new(grid[0])
            self.bm.faces.new(list(reversed(grid[-1])))
        return self._stamp(before, mat)

    def sphere(self, center, r, mat, seg=10, rings=5, scale=(1, 1, 1)):
        before = set(self.bm.faces)
        M = self.T @ Matrix.Translation(V(center)) @ Matrix.Diagonal(V(scale).to_4d())
        bmesh.ops.create_uvsphere(self.bm, u_segments=seg, v_segments=rings, radius=r, matrix=M)
        return self._stamp(before, mat)

    def prism(self, profile, z0, z1, mat, M=None, bevel=CHAMFER, seg=1):
        """Extrude a 2D profile [(x, y), ...] (CCW seen from +Z) from z0 to z1."""
        before = set(self.bm.faces)
        M = self.T @ (M if M is not None else Matrix.Identity(4))
        a = [self.bm.verts.new(M @ V(p[0], p[1], z0)) for p in profile]
        b = [self.bm.verts.new(M @ V(p[0], p[1], z1)) for p in profile]
        self.bm.faces.new(list(reversed(a)))
        self.bm.faces.new(b)
        n = len(profile)
        for i in range(n):
            j = (i + 1) % n
            self.bm.faces.new((a[i], a[j], b[j], b[i]))
        return self._stamp(before, mat, bevel, seg)

    def sweep(self, pts, r, mat, n=6, cap=True, twist=0.0):
        """A tube along a polyline (cables, rebar, hoses)."""
        before = set(self.bm.faces)
        P = [self.T @ V(p) for p in pts]
        tang = []
        for i in range(len(P)):
            if i == 0:
                t = P[1] - P[0]
            elif i == len(P) - 1:
                t = P[-1] - P[-2]
            else:
                t = (P[i + 1] - P[i]).normalized() + (P[i] - P[i - 1]).normalized()
            tang.append(t.normalized())
        ref = V(0, 1, 0) if abs(tang[0].y) < 0.9 else V(1, 0, 0)
        nrm = tang[0].cross(ref).normalized()
        rings = []
        for i, p in enumerate(P):
            if i > 0:
                # parallel transport
                q = tang[i - 1].rotation_difference(tang[i])
                nrm = (q @ nrm).normalized()
            bi = tang[i].cross(nrm).normalized()
            ring = []
            for k in range(n):
                t = 2 * math.pi * k / n + twist
                ring.append(self.bm.verts.new(p + (nrm * math.cos(t) + bi * math.sin(t)) * r))
            rings.append(ring)
        for i in range(len(rings) - 1):
            A, B = rings[i], rings[i + 1]
            for k in range(n):
                j = (k + 1) % n
                self.bm.faces.new((A[k], A[j], B[j], B[k]))
        if cap:
            self.bm.faces.new(list(reversed(rings[0])))
            self.bm.faces.new(rings[-1])
        return self._stamp(before, mat)

    def quad(self, corners, mat, uv=((0, 0), (1, 0), (1, 1), (0, 1))):
        """A single quad with EXACT UVs.  `uv` is given in glTF / Godot
        convention (V = 0 at the TOP); it is flipped to Blender's V-up here so
        the exporter's own flip lands it back exactly."""
        vs = [self.bm.verts.new(self.T @ V(c)) for c in corners]
        f = self.bm.faces.new(vs)
        f.material_index = self._mi(mat)
        for loop, (u, v) in zip(f.loops, uv):
            loop[self.uv].uv = (u, 1.0 - v)
        f[self.fixed] = 1
        return [f]

    def crumple(self, faces, amp, seed=0, freq=3.0, cuts=2):
        """Subdivide freshly stamped faces and push their vertices about with
        smooth noise: crushed sheet metal instead of perfect boxes."""
        from mathutils import noise
        # Blender randomises the noise permutation table per process; seed it
        # or the heaps come out different on every run.
        noise.seed_set(1000 + int(seed))
        faces = [f for f in faces if f.is_valid]
        edges = list({e for f in faces for e in f.edges})
        res = bmesh.ops.subdivide_edges(self.bm, edges=edges, cuts=cuts, use_grid_fill=True)
        verts = set(v for f in faces if f.is_valid for v in f.verts)
        verts |= {v for v in res["geom"] if isinstance(v, bmesh.types.BMVert)}
        off = V(seed * 1.37, seed * 2.11, seed * 0.73)
        for v in verts:
            n = noise.noise_vector(v.co * freq + off)
            v.co += V(n) * amp
        mi = faces[0].material_index if faces else 0
        return mi

    def bolt(self, pos, axis, r=0.012, h=0.008, mat="galv_steel", n=6):
        a = V(axis).normalized()
        return self.cyl(V(pos) + a * (h / 2), a, r, h, mat, n=n)

    def bolts_rect(self, center, u, v, axis, r=0.012, mat="galv_steel", n=6):
        c, u, v = V(center), V(u), V(v)
        for su in (-1, 1):
            for sv in (-1, 1):
                self.bolt(c + u * su + v * sv, axis, r=r, mat=mat, n=n)


# ---------------------------------------------------------------- realise

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def _material(name):
    m = bpy.data.materials.get(name)
    if m is not None:
        return m
    col, metal, rough, emit = MATERIALS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough
    if emit > 0.0:
        bsdf.inputs["Emission Color"].default_value = col
        bsdf.inputs["Emission Strength"].default_value = emit
    if col[3] < 1.0:
        bsdf.inputs["Alpha"].default_value = col[3]
        try:
            m.surface_render_method = 'BLENDED'
        except Exception:
            pass
    return m


def realise(meshes, sharp_angle=40.0):
    """Turn Mesh builders into Blender objects.  Returns {name: object}."""
    objs = {}
    lim = math.radians(sharp_angle)
    for m in meshes:
        bm = m.bm
        if m.origin.length > 0.0:
            bmesh.ops.translate(bm, vec=-m.origin, verts=bm.verts[:])
        bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method='BEAUTY',
                              ngon_method='BEAUTY')
        bmesh.ops.transform(bm, matrix=G2B, verts=bm.verts[:])
        bm.normal_update()
        for f in bm.faces:
            f.smooth = True
            f.select = f[m.fixed] == 0
        for e in bm.edges:
            if len(e.link_faces) == 2:
                a, b = e.link_faces
                try:
                    e.smooth = a.normal.angle(b.normal) <= lim
                except ValueError:
                    e.smooth = False
            else:
                e.smooth = False
        me = bpy.data.meshes.new(m.name)
        bm.to_mesh(me)
        bm.free()
        for s in m.slots:
            me.materials.append(_material(s))
        ob = bpy.data.objects.new(m.name, me)
        ob.location = G2B @ m.origin
        bpy.context.scene.collection.objects.link(ob)
        objs[m.name] = ob
    for m in meshes:
        if m.parent:
            ob, par = objs[m.name], objs[m.parent]
            ob.parent = par
            ob.location = G2B @ (m.origin - next(x.origin for x in meshes if x.name == m.parent))
    # Smart UV on everything that was not authored with exact UVs.
    for ob in objs.values():
        bpy.ops.object.select_all(action='DESELECT')
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.mode_set(mode='EDIT')
        # face selection came through from bmesh (fixed faces deselected)
        try:
            bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.01,
                                     correct_aspect=True, scale_to_bounds=False)
        except Exception:
            bpy.ops.uv.cube_project(cube_size=1.0)
        bpy.ops.object.mode_set(mode='OBJECT')
        wn = ob.modifiers.new("wn", 'WEIGHTED_NORMAL')
        wn.keep_sharp = True
        wn.weight = 50
    return objs


def export_glb(objs, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objs.values():
        ob.select_set(True)
    bpy.context.view_layer.objects.active = next(iter(objs.values()))
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', use_selection=True, export_yup=True,
        export_apply=True, export_materials='EXPORT', export_image_format='NONE',
        export_texcoords=True, export_normals=True, export_tangents=False,
        export_cameras=False, export_lights=False, export_extras=False,
        export_animations=False, export_skins=False)


def build(meshes, path):
    reset_scene()
    objs = realise(meshes)
    export_glb(objs, path)
    return objs


def rng(seed):
    return random.Random(seed)
