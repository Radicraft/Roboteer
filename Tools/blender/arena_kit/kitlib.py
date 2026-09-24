"""Arena kit helper library (owned by the structures script, kit_structures.py).

AUTHORING SPACE IS GODOT SPACE:  +X right, +Y up, +Z = the FRONT (the arena side).

Every primitive below takes Godot-space numbers.  At export the geometry is
mapped once to Blender (x, y, z) -> (x, -z, y) (det +1, nothing mirrored), so in
Blender the piece stands Z-up with its front facing -Y, exactly as the kit
convention asks, and the glTF exporter's export_yup=True maps it straight back
to the numbers authored here.  The kit verifier reads the POSITION accessor
bounds out of each .glb to prove it.

Material slots are named by role; Godot swaps them for triplanar PBR sets by
name.  Faces written with explicit UVs (`sign`, `grating` infill, `hazard_paint`
strips) are flagged and skipped by the Smart UV Project that covers the rest.
"""

import math
import os
import struct
import json

import bpy
import bmesh
from mathutils import Matrix, Vector

# ------------------------------------------------------------------ materials

#: name -> (base colour, metallic, roughness, emission strength)
MATERIALS = {
    "galv_steel":      ((0.62, 0.64, 0.66, 1.0), 1.00, 0.42, 0.0),
    "dark_metal":      ((0.075, 0.078, 0.085, 1.0), 0.85, 0.55, 0.0),
    "container_paint": ((0.42, 0.42, 0.42, 1.0), 0.15, 0.62, 0.0),
    "rust":            ((0.30, 0.13, 0.06, 1.0), 0.35, 0.80, 0.0),
    "concrete":        ((0.46, 0.45, 0.43, 1.0), 0.00, 0.90, 0.0),
    "rubber":          ((0.05, 0.05, 0.055, 1.0), 0.00, 0.88, 0.0),
    "wood":            ((0.38, 0.27, 0.17, 1.0), 0.00, 0.78, 0.0),
    "hazard_paint":    ((0.95, 0.70, 0.05, 1.0), 0.05, 0.55, 0.0),
    "lamp_warm":       ((1.00, 0.62, 0.25, 1.0), 0.00, 0.20, 6.0),
    "lamp_white":      ((0.95, 0.97, 1.00, 1.0), 0.00, 0.20, 6.0),
    "lamp_strip":      ((0.55, 0.85, 1.00, 1.0), 0.00, 0.25, 5.0),
    "sign":            ((0.20, 0.20, 0.22, 1.0), 0.10, 0.45, 0.0),
    "grating":         ((0.40, 0.42, 0.44, 1.0), 0.90, 0.50, 0.0),
}

# Godot -> Blender, det = +1
G2B = Matrix(((1, 0, 0, 0),
              (0, 0, -1, 0),
              (0, 1, 0, 0),
              (0, 0, 0, 1)))

X = Vector((1, 0, 0))
Y = Vector((0, 1, 0))
Z = Vector((0, 0, 1))

HAZARD_M_PER_U = 0.5


def rot_x(deg):
    return Matrix.Rotation(math.radians(deg), 4, 'X')


def rot_y(deg):
    return Matrix.Rotation(math.radians(deg), 4, 'Y')


def rot_z(deg):
    return Matrix.Rotation(math.radians(deg), 4, 'Z')


def _align_z(axis):
    """4x4 rotation taking +Z to `axis`."""
    axis = Vector(axis).normalized()
    return Z.rotation_difference(axis).to_matrix().to_4x4()


class Kit:
    """Accumulates one bmesh (Godot space) plus a few named empties."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.fix = self.bm.faces.layers.int.new("fixuv")
        self.slots = []            # material names in slot order
        self.empties = []          # (name, godot pos)
        self.xform = None          # optional group transform (Matrix) applied to new geometry

    # ---------------------------------------------------------- internals
    def _mi(self, mat):
        if mat not in MATERIALS:
            raise KeyError(mat)
        if mat not in self.slots:
            self.slots.append(mat)
        return self.slots.index(mat)

    def _new_faces(self, before):
        return [f for f in self.bm.faces if f not in before]

    def _finish(self, before, mat, bevel=0.0, seg=1, recalc=True):
        new = self._new_faces(before)
        if bevel and bevel > 0.0:
            edges = {e for f in new for e in f.edges}
            bmesh.ops.bevel(self.bm, geom=list(edges), offset=bevel, offset_type='OFFSET',
                            segments=seg, profile=0.5, affect='EDGES',
                            clamp_overlap=True, miter_outer='SHARP')
            new = self._new_faces(before)
        if self.xform is not None:
            verts = list({v for f in new for v in f.verts})
            bmesh.ops.transform(self.bm, matrix=self.xform, verts=verts)
        if recalc:
            bmesh.ops.recalc_face_normals(self.bm, faces=new)
        mi = self._mi(mat)
        for f in new:
            f.material_index = mi
        return new

    # ---------------------------------------------------------- primitives
    def box(self, center, size, mat, bevel=0.015, seg=1, rot=None):
        before = set(self.bm.faces)
        M = Matrix.Translation(Vector(center))
        if rot is not None:
            M = M @ rot
        M = M @ Matrix.Diagonal(Vector(size).to_4d())
        bmesh.ops.create_cube(self.bm, size=1.0, matrix=M)
        return self._finish(before, mat, bevel, seg)

    def box_between(self, a, b, w, h, mat, bevel=0.01, seg=1, up=None):
        """A beam of cross-section w (side) x h (up) running from a to b."""
        a, b = Vector(a), Vector(b)
        d = b - a
        L = d.length
        fwd = d.normalized()
        up = Vector(up) if up is not None else (Y if abs(fwd.dot(Y)) < 0.95 else X)
        side = fwd.cross(up).normalized()
        up2 = side.cross(fwd).normalized()
        R = Matrix((side, up2, fwd)).transposed().to_4x4()
        return self.box((a + b) * 0.5, (w, h, L), mat, bevel, seg, rot=R)

    def tube(self, a, b, r, mat, sides=8, caps=True):
        a, b = Vector(a), Vector(b)
        d = b - a
        L = d.length
        if L < 1e-5:
            return []
        before = set(self.bm.faces)
        M = Matrix.Translation((a + b) * 0.5) @ _align_z(d) @ rot_z(180.0 / sides)
        bmesh.ops.create_cone(self.bm, cap_ends=caps, cap_tris=False, segments=sides,
                              radius1=r, radius2=r, depth=L, matrix=M)
        return self._finish(before, mat, 0.0, recalc=caps)

    def polyline_tube(self, pts, r, mat, sides=6):
        for p, q in zip(pts[:-1], pts[1:]):
            self.tube(p, q, r, mat, sides=sides, caps=True)

    def disc(self, center, axis, r, depth, mat, sides=10, bevel=0.0):
        c = Vector(center)
        ax = Vector(axis).normalized()
        before = set(self.bm.faces)
        M = Matrix.Translation(c) @ _align_z(ax)
        bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=sides,
                              radius1=r, radius2=r, depth=depth, matrix=M)
        return self._finish(before, mat, bevel, 1)

    def bolt(self, center, axis, mat="dark_metal", r=0.018, h=0.012):
        """Hex bolt head sitting on a surface, pointing along `axis`."""
        ax = Vector(axis).normalized()
        return self.disc(Vector(center) + ax * (h * 0.5), ax, r, h, mat, sides=6)

    def prism(self, base_pts, extrude, mat, bevel=0.0):
        """Closed prism: polygon `base_pts` (3D, planar, CCW seen from the
        side opposite to `extrude`... orientation is fixed by recalc) swept by
        vector `extrude`."""
        before = set(self.bm.faces)
        ev = Vector(extrude)
        vs0 = [self.bm.verts.new(Vector(p)) for p in base_pts]
        vs1 = [self.bm.verts.new(Vector(p) + ev) for p in base_pts]
        n = len(base_pts)
        self.bm.faces.new(vs0)
        self.bm.faces.new(list(reversed(vs1)))
        for i in range(n):
            j = (i + 1) % n
            self.bm.faces.new((vs0[i], vs0[j], vs1[j], vs1[i]))
        return self._finish(before, mat, bevel, 1)

    def quad(self, p0, p1, p2, p3, mat, uvs=None, double=False):
        """Single quad; winding p0->p1->p2->p3 CCW seen from the visible side.
        `uvs` pins explicit UVs (flagged so Smart UV leaves them alone)."""
        out = []
        for flip in ((False, True) if double else (False,)):
            pts = [p0, p1, p2, p3]
            uv = list(uvs) if uvs else None
            if flip:
                pts = list(reversed(pts))
                uv = list(reversed(uv)) if uv else None
            vs = [self.bm.verts.new(Vector(p)) for p in pts]
            if self.xform is not None:
                for v in vs:
                    v.co = self.xform @ v.co
            f = self.bm.faces.new(vs)
            f.material_index = self._mi(mat)
            if uv:
                for loop, t in zip(f.loops, uv):
                    loop[self.uv].uv = t
                f[self.fix] = 1
            out.append(f)
        return out

    def sheet(self, rows, mat, closed_u=False):
        """Grid surface from rows of points (list of lists).  Faces wind
        rows[i][j] -> rows[i][j+1] -> rows[i+1][j+1] -> rows[i+1][j]; the
        caller orders them so that is CCW seen from outside."""
        before = set(self.bm.faces)
        vrows = [[self.bm.verts.new(Vector(p)) for p in r] for r in rows]
        for i in range(len(vrows) - 1):
            a, b = vrows[i], vrows[i + 1]
            n = len(a)
            rng = range(n) if closed_u else range(n - 1)
            for j in rng:
                k = (j + 1) % n
                self.bm.faces.new((a[j], a[k], b[k], b[j]))
        return self._finish(before, mat, 0.0, recalc=False)

    def corrugated(self, origin, u_dir, v_dir, length, height, mat, pitch=0.278,
                   depth=0.036, crest=0.35, flank=0.15, out=None):
        """Trapezoidal corrugated sheet.  The profile runs along u_dir for
        `length`, the ribs run along v_dir for `height`.  The sheet bulges
        toward `out` (default u x v); faces are visible from that side.
        Profile per pitch: crest (outer), flank, trough (inner), flank."""
        o = Vector(origin)
        u = Vector(u_dir).normalized()
        v = Vector(v_dir).normalized()
        n = Vector(out).normalized() if out is not None else u.cross(v).normalized()
        n_waves = max(1, round(length / pitch))
        p = length / n_waves
        trough = 1.0 - crest - 2 * flank
        prof = []   # (t along u, offset along n)
        for k in range(n_waves):
            s = k * p
            prof.append((s, 0.0))
            prof.append((s + p * trough * 0.5, 0.0))
            prof.append((s + p * (trough * 0.5 + flank), depth))
            prof.append((s + p * (trough * 0.5 + flank + crest), depth))
            prof.append((s + p * (trough * 0.5 + 2 * flank + crest), 0.0))
        prof.append((length, 0.0))
        # merge duplicates
        clean = []
        for t, d in prof:
            if clean and abs(clean[-1][0] - t) < 1e-6:
                continue
            clean.append((t, d))
        bottom = [o + u * t + n * d for t, d in clean]
        top = [pt + v * height for pt in bottom]
        # winding: CCW seen from +n  ==  (u, v) right-handed about n
        if u.cross(v).dot(n) > 0:
            rows = [bottom, top]
        else:
            rows = [top, bottom]
        return self.sheet(rows, mat)

    def hazard_box(self, center, size, axis, mat="hazard_paint", bevel=0.01, rot=None):
        """Box whose UVs are laid by position: U along `axis` (1 unit / 0.5 m),
        V along the box's other long direction, so the chevron texture runs
        along the strip."""
        faces = self.box(center, size, mat, bevel=bevel, seg=1, rot=rot)
        ax = Vector(axis).normalized()
        R = rot.to_3x3() if rot is not None else Matrix.Identity(3)
        world_ax = (R @ ax).normalized()
        for f in faces:
            f.normal_update()
            fn = f.normal
            # V axis: the direction in the face plane perpendicular to U
            vdir = fn.cross(world_ax)
            if vdir.length < 1e-4:
                vdir = fn.cross(Y if abs(fn.dot(Y)) < 0.9 else X)
            vdir.normalize()
            for loop in f.loops:
                co = loop.vert.co
                loop[self.uv].uv = (co.dot(world_ax) / HAZARD_M_PER_U,
                                    co.dot(vdir) / HAZARD_M_PER_U)
            f[self.fix] = 1
        return faces

    def empty(self, name, pos):
        self.empties.append((name, Vector(pos)))

    def tris(self):
        n = 0
        for f in self.bm.faces:
            n += len(f.verts) - 2
        return n


# ------------------------------------------------------------------ scene

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def get_material(name):
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
    m.diffuse_color = col
    return m


def export_kit(kit, out_dir, sharp_angle=35.0):
    """Realise the Kit as one Blender object, UV it, weighted-normal it and
    write <out_dir>/<name>.glb.  Returns (path, tris)."""
    reset_scene()
    bm = kit.bm
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method='BEAUTY', ngon_method='BEAUTY')
    bmesh.ops.transform(bm, matrix=G2B, verts=bm.verts[:])
    bm.normal_update()
    ang = math.radians(sharp_angle)
    for f in bm.faces:
        f.smooth = True
        f.select = not bool(f[kit.fix])
    for e in bm.edges:
        if len(e.link_faces) == 2:
            a, b = e.link_faces
            try:
                e.smooth = a.normal.angle(b.normal) <= ang and a.material_index == b.material_index
            except ValueError:
                e.smooth = False
        else:
            e.smooth = False
    me = bpy.data.meshes.new(kit.name)
    bm.to_mesh(me)
    bm.free()
    kit.bm = None
    for s in kit.slots:
        me.materials.append(get_material(s))
    ob = bpy.data.objects.new(kit.name, me)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)

    # Smart UV on everything that has no pinned UVs
    if any(p.select for p in me.polygons):
        bpy.ops.object.mode_set(mode='EDIT')
        try:
            bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.004,
                                     correct_aspect=True, scale_to_bounds=False)
        except Exception:
            bpy.ops.uv.cube_project(cube_size=1.0)
        bpy.ops.object.mode_set(mode='OBJECT')
    if "fixuv" in me.attributes:
        me.attributes.remove(me.attributes["fixuv"])

    wn = ob.modifiers.new("wn", 'WEIGHTED_NORMAL')
    wn.keep_sharp = True
    wn.weight = 50
    wn.mode = 'FACE_AREA'

    objs = [ob]
    for name, pos in kit.empties:
        e = bpy.data.objects.new(name, None)
        e.empty_display_type = 'PLAIN_AXES'
        e.location = G2B @ pos
        bpy.context.scene.collection.objects.link(e)
        e.select_set(True)
        objs.append(e)

    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, kit.name + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', use_selection=True, export_yup=True,
        export_apply=True, export_materials='EXPORT', export_image_format='NONE',
        export_texcoords=True, export_normals=True, export_tangents=False,
        export_cameras=False, export_lights=False, export_extras=False,
        export_animations=False, export_skins=False, export_morph=False,
        export_draco_mesh_compression_enable=False,
    )
    tris = len(me.polygons)
    return path, tris


# ------------------------------------------------------------------ verification

def glb_info(path):
    """Read a .glb without Blender: POSITION bounds over all meshes (node
    translations applied, which is all this kit uses), triangle count,
    material names, node names."""
    with open(path, "rb") as fh:
        data = fh.read()
    magic, ver, length = struct.unpack_from("<4sII", data, 0)
    assert magic == b"glTF"
    clen, ctype = struct.unpack_from("<I4s", data, 12)
    js = json.loads(data[20:20 + clen])
    lo = [1e9] * 3
    hi = [-1e9] * 3
    tris = 0
    mats = [m["name"] for m in js.get("materials", [])]
    nodes = {}
    for node in js.get("nodes", []):
        t = node.get("translation", [0, 0, 0])
        nodes[node.get("name")] = t
        if "mesh" in node:
            mesh = js["meshes"][node["mesh"]]
            for prim in mesh["primitives"]:
                acc = js["accessors"][prim["attributes"]["POSITION"]]
                for k in range(3):
                    lo[k] = min(lo[k], acc["min"][k] + t[k])
                    hi[k] = max(hi[k], acc["max"][k] + t[k])
                if "indices" in prim:
                    tris += js["accessors"][prim["indices"]]["count"] // 3
    return {"min": lo, "max": hi, "tris": tris, "materials": mats, "nodes": nodes}
