"""The Marshal: Roboteer's own neutral arena official (wave D, docs/wave-d-marshal-notes.md).

    ~/Applications/Blender.app/Contents/MacOS/Blender -b -P Tools/blender/marshal/build_marshal.py

A compact four-duct hover drone with a horizontal light bar across its nose, a small
nozzle under the chin (the extinguisher and the tow line both leave from there) and a
card slot on its right flank. Deliberately NOT a person: no head, no arms, no chest
panel, no stripes. Its silhouette is a flat lozenge with four rings, which from the
fight camera reads as "a drone" and nothing else.

Writes Arena/assets/marshal/marshal.glb. Authoring is in Blender space (X right, Y
forward, Z up); the exporter's +Y up conversion makes Blender +Y the model's -Z in
Godot, which is Godot's forward, so the nose points where a Node3D looks.

Materials are named by the part they dress (shell, frame, duct, rotor, glass, steel,
rubber, bar_housing, lamp). Arena/fight/marshal.gd binds them to its own materials,
built from the kit's PBR sets in OBJECT space (a world-space triplanar swims on a
moving thing).

Nodes Godot drives by name:
    Rotor0..3        spin about their own Y (origins at the duct centres)
    BarSeg0..9       the light bar's ten segments, left to right, lit one by one
    Beacon           the small lamp on the mast
    Nozzle           an empty at the nozzle tip (spray and tow line start here)
    CardSlot         an empty at the card slot on the right flank
"""

import math
import os

import bpy
import bmesh
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(REPO, "Arena", "assets", "marshal", "marshal.glb")

BODY_W = 0.30        # X
BODY_L = 0.36        # Y
BODY_H = 0.12        # Z
DUCT_X = 0.265
DUCT_Y = 0.205
DUCT_R = 0.118       # outer radius
DUCT_T = 0.016       # wall
DUCT_H = 0.055
BAR_SEGS = 10

MATS = {
    # name: (base colour, metallic, roughness, emission)
    "shell": ((0.80, 0.80, 0.77, 1.0), 0.0, 0.45, 0.0),
    "frame": ((0.12, 0.125, 0.135, 1.0), 0.9, 0.5, 0.0),
    "duct": ((0.06, 0.062, 0.068, 1.0), 0.2, 0.55, 0.0),
    "rotor": ((0.04, 0.04, 0.045, 1.0), 0.0, 0.5, 0.0),
    "glass": ((0.03, 0.04, 0.05, 1.0), 0.0, 0.08, 0.0),
    "steel": ((0.62, 0.63, 0.66, 1.0), 1.0, 0.3, 0.0),
    "rubber": ((0.05, 0.05, 0.055, 1.0), 0.0, 0.85, 0.0),
    "bar_housing": ((0.02, 0.02, 0.022, 1.0), 0.0, 0.35, 0.0),
    "lamp": ((1.0, 0.7, 0.2, 1.0), 0.0, 0.3, 3.0),
}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name):
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    col, metal, rough, emit = MATS[name]
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


def finish(ob, mat, bevel=0.0, segs=2, smooth_deg=35.0):
    ob.data.materials.clear()
    ob.data.materials.append(material(mat))
    if bevel > 0.0:
        mod = ob.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segs
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(30.0)
        mod.harden_normals = True
    # Smooth by angle so bevels catch light and flats stay flat.
    for p in ob.data.polygons:
        p.use_smooth = True
    try:
        ob.data.set_sharp_from_angle(angle=math.radians(smooth_deg))
    except AttributeError:
        pass
    return ob


def apply_all(ob):
    bpy.context.view_layer.objects.active = ob
    for mod in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)


def link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


def mesh_from_bm(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return link(bpy.data.objects.new(name, me))


def prism(name, sides, rx, ry, z0, z1, taper=1.0, rot=0.0):
    """A closed prism: `sides`-gon of radii rx, ry at z0, scaled by `taper` at z1."""
    bm = bmesh.new()
    lo, hi = [], []
    for i in range(sides):
        a = rot + 2.0 * math.pi * i / sides
        lo.append(bm.verts.new((rx * math.cos(a), ry * math.sin(a), z0)))
        hi.append(bm.verts.new((rx * taper * math.cos(a), ry * taper * math.sin(a), z1)))
    bm.faces.new(list(reversed(lo)))
    bm.faces.new(hi)
    for i in range(sides):
        j = (i + 1) % sides
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    bm.normal_update()
    return mesh_from_bm(name, bm)


def box(name, size, at, rot=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    if rot is not None:
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=rot, verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(at), verts=bm.verts)
    return mesh_from_bm(name, bm)


def ring(name, r_out, r_in, h, sides=20, at=(0, 0, 0)):
    """A duct: a tube with a flared lip on top."""
    bm = bmesh.new()
    rings = []
    # (radius, z) profile, outside going up then inside coming down.
    prof = [(r_out, -h * 0.5), (r_out, h * 0.3), (r_out + 0.008, h * 0.5),
            (r_in + 0.004, h * 0.5), (r_in, h * 0.3), (r_in, -h * 0.5)]
    for (r, z) in prof:
        row = []
        for i in range(sides):
            a = 2.0 * math.pi * i / sides
            row.append(bm.verts.new((at[0] + r * math.cos(a), at[1] + r * math.sin(a), at[2] + z)))
        rings.append(row)
    n = len(rings)
    for k in range(n):
        a_row = rings[k]
        b_row = rings[(k + 1) % n]
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((a_row[i], a_row[j], b_row[j], b_row[i]))
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return mesh_from_bm(name, bm)


def cylinder(name, r, depth, sides, at, axis="Z"):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=sides,
                          radius1=r, radius2=r, depth=depth)
    if axis == "X":
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "Y"), verts=bm.verts)
    elif axis == "Y":
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "X"), verts=bm.verts)
    bmesh.ops.translate(bm, vec=Vector(at), verts=bm.verts)
    return mesh_from_bm(name, bm)


def sphere(name, r, at, segs=12, rings=6, half=False):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)
    if half:
        # keep the lower hemisphere (a sensor dome hanging under the body)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z > 0.0001], context="VERTS")
        edge = [e for e in bm.edges if e.is_boundary]
        if edge:
            bmesh.ops.holes_fill(bm, edges=edge, sides=0)
    bmesh.ops.translate(bm, vec=Vector(at), verts=bm.verts)
    return mesh_from_bm(name, bm)


def empty(name, at):
    e = bpy.data.objects.new(name, None)
    e.empty_display_type = "PLAIN_AXES"
    e.empty_display_size = 0.03
    e.location = Vector(at)
    return link(e)


def build():
    reset()
    parts = []

    # ---- body: an octagonal lozenge, slightly domed, light shell over a dark keel
    top = prism("ShellTop", 8, BODY_W * 0.5 / math.cos(math.pi / 8), BODY_L * 0.5 / math.cos(math.pi / 8),
                0.0, BODY_H * 0.55, taper=0.78, rot=math.pi / 8)
    parts.append(finish(top, "shell", bevel=0.012, segs=3))
    # the keel narrows downward from the shell's rim: 0.98 of it at the top, 0.84 below
    keel = prism("Keel", 8, BODY_W * 0.5 / math.cos(math.pi / 8) * 0.84,
                 BODY_L * 0.5 / math.cos(math.pi / 8) * 0.84, -BODY_H * 0.45, 0.0,
                 taper=0.98 / 0.84, rot=math.pi / 8)
    parts.append(finish(keel, "frame", bevel=0.008, segs=2))

    # a raised spine plate on top, a darker hatch, and the mast with its beacon
    parts.append(finish(box("Hatch", (0.12, 0.08, 0.012), (0, -0.075, BODY_H * 0.55 + 0.004)), "frame", bevel=0.004))
    parts.append(finish(cylinder("Mast", 0.008, 0.07, 8, (0, -0.125, BODY_H * 0.55 + 0.04)), "steel"))
    beacon = sphere("Beacon", 0.016, (0, -0.125, BODY_H * 0.55 + 0.085), segs=10, rings=6)
    parts.append(finish(beacon, "lamp"))

    # ---- arms and ducts
    rotors = []
    for idx, (sx, sy) in enumerate([(-1, 1), (1, 1), (-1, -1), (1, -1)]):
        cx, cy = sx * DUCT_X, sy * DUCT_Y
        # arm: a tapered strut from the body corner to the duct
        ax0 = Vector((sx * BODY_W * 0.32, sy * BODY_L * 0.30, 0.0))
        ax1 = Vector((cx - sx * DUCT_R * 0.72, cy - sy * DUCT_R * 0.72, 0.0))
        mid = (ax0 + ax1) * 0.5
        d = ax1 - ax0
        ang = math.atan2(d.y, d.x)
        arm = box("Arm%d" % idx, (d.length + 0.02, 0.045, 0.03), mid, Matrix.Rotation(ang, 3, "Z"))
        parts.append(finish(arm, "frame", bevel=0.006))
        duct = ring("Duct%d" % idx, DUCT_R, DUCT_R - DUCT_T, DUCT_H, sides=22, at=(cx, cy, 0.0))
        parts.append(finish(duct, "duct", smooth_deg=50.0))
        # motor hub on a cross strut inside the duct
        strut = box("Strut%d" % idx, (DUCT_R * 2.0 - DUCT_T, 0.012, 0.008), (cx, cy, -0.012),
                    Matrix.Rotation(math.radians(45 if sx * sy > 0 else -45), 3, "Z"))
        parts.append(finish(strut, "frame"))
        hub = cylinder("Hub%d" % idx, 0.022, 0.03, 10, (cx, cy, 0.0))
        parts.append(finish(hub, "steel", bevel=0.003))
        # the rotor: its own object with its origin on the duct axis, so Godot spins it
        bm = bmesh.new()
        for k in range(2):
            geom = bmesh.ops.create_cube(bm, size=1.0)
            vs = geom["verts"]
            bmesh.ops.scale(bm, vec=Vector((DUCT_R * 0.9, 0.022, 0.004)), verts=vs)
            bmesh.ops.translate(bm, vec=Vector((DUCT_R * 0.45, 0, 0)), verts=vs)
            # a little pitch on the blade
            bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(12), 3, "X"), verts=vs)
            bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi * k, 3, "Z"), verts=vs)
        rotor = mesh_from_bm("Rotor%d" % idx, bm)
        rotor.location = (cx, cy, 0.012)
        rotors.append(finish(rotor, "rotor"))
        parts.append(rotor)

    # ---- the light bar: a dark housing across the top of the nose, its face tipped 25
    # degrees forward from straight up, so the fight camera (steeply above) and the finish
    # beat's orbit (35 degrees, in front) both see all ten segments; they stand proud of it
    tilt = Matrix.Rotation(math.radians(25.0), 3, "X")    # top face tipped toward the nose
    bar_w = BODY_W * 0.86
    bar_y = BODY_L * 0.22
    bar_z = BODY_H * 0.55 + 0.004
    housing = box("BarHousing", (bar_w + 0.02, 0.07, 0.026), (0, 0, 0), tilt)
    for v in housing.data.vertices:
        v.co += Vector((0, bar_y, bar_z))
    parts.append(finish(housing, "bar_housing", bevel=0.005))
    seg_w = bar_w / BAR_SEGS
    normal = tilt @ Vector((0, 0, 1))
    for s in range(BAR_SEGS):
        x = -bar_w * 0.5 + seg_w * (s + 0.5)
        seg = box("BarSeg%d" % s, (seg_w * 0.8, 0.052, 0.008), (0, 0, 0), tilt)
        centre = Vector((x, bar_y, bar_z)) + normal * 0.014
        for v in seg.data.vertices:
            v.co += centre
        parts.append(finish(seg, "lamp"))

    # ---- under the chin: the nozzle (extinguisher and tow line), angled down and forward
    nz = cylinder("NozzleBody", 0.016, 0.07, 10, (0, 0, 0), axis="Y")
    rot = Matrix.Rotation(math.radians(35.0), 3, "X")
    for v in nz.data.vertices:
        v.co = rot @ v.co + Vector((0.0, BODY_L * 0.36, -BODY_H * 0.46))
    parts.append(finish(nz, "steel", bevel=0.002))
    tip_dir = rot @ Vector((0, 1, 0))
    nozzle_tip = Vector((0.0, BODY_L * 0.36, -BODY_H * 0.46)) + tip_dir * 0.04
    cone = cylinder("NozzleTip", 0.011, 0.02, 10, (0, 0, 0), axis="Y")
    for v in cone.data.vertices:
        v.co = rot @ v.co + nozzle_tip
    parts.append(finish(cone, "frame"))

    # sensor dome under the body, and the winch ring behind it
    parts.append(finish(sphere("Dome", 0.045, (0, 0.03, -BODY_H * 0.45), segs=14, rings=8, half=True), "glass"))
    parts.append(finish(ring("Winch", 0.02, 0.012, 0.012, sides=12, at=(0, -0.07, -BODY_H * 0.5)), "steel"))

    # skids: two short rails on struts (it perches when it lands for the result)
    for sx in (-1, 1):
        rail = box("Skid%d" % (0 if sx < 0 else 1), (0.014, BODY_L * 0.72, 0.014),
                   (sx * BODY_W * 0.30, 0, -BODY_H * 0.45 - 0.07))
        parts.append(finish(rail, "rubber", bevel=0.004))
        for sy in (-1, 1):
            leg = box("Leg%d%d" % (sx + 1, sy + 1), (0.012, 0.012, 0.075),
                      (sx * BODY_W * 0.27, sy * BODY_L * 0.2, -BODY_H * 0.45 - 0.035),
                      Matrix.Rotation(math.radians(-18.0 * sx), 3, "Y"))
            parts.append(finish(leg, "frame"))

    # the card slot on the right flank: a dark letterbox
    parts.append(finish(box("CardSlotFrame", (0.012, 0.11, 0.022), (BODY_W * 0.5 - 0.004, 0.0, 0.0)), "bar_housing", bevel=0.003))

    for ob in parts:
        if ob.modifiers:
            apply_all(ob)

    empty("Nozzle", nozzle_tip + tip_dir * 0.012)
    empty("CardSlot", (BODY_W * 0.5 + 0.004, 0.0, 0.0))
    empty("Tether", (0, -0.07, -BODY_H * 0.5 - 0.01))

    # join the static parts into as few meshes as the material count allows; keep the
    # ones Godot drives (rotors, bar segments, beacon) separate.
    keep = {"Beacon"} | {"Rotor%d" % i for i in range(4)} | {"BarSeg%d" % i for i in range(BAR_SEGS)}
    static = [o for o in bpy.context.scene.objects if o.type == "MESH" and o.name not in keep]
    bpy.ops.object.select_all(action="DESELECT")
    for o in static:
        o.select_set(True)
    bpy.context.view_layer.objects.active = static[0]
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = "Body"

    # UVs for the object-space textures (box projection is enough for a small drone)
    for o in bpy.context.scene.objects:
        if o.type != "MESH":
            continue
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.cube_project(cube_size=0.4)
        bpy.ops.object.mode_set(mode="OBJECT")

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=OUT, export_format="GLB", use_selection=True, export_yup=True,
        export_apply=True, export_materials="EXPORT", export_image_format="NONE",
        export_texcoords=True, export_normals=True, export_tangents=False,
        export_cameras=False, export_lights=False, export_extras=False,
        export_animations=False, export_skins=False, export_morph=False)
    tris = 0
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            o.data.calc_loop_triangles()
            tris += len(o.data.loop_triangles)
    print("MARSHAL wrote %s, %d triangles, %d objects" % (OUT, tris,
          len([o for o in bpy.context.scene.objects])))


build()
