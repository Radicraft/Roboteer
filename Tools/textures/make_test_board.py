"""make_test_board.py - the material test board shapes, built to the wave A mask contract.

Run:  ~/Applications/Blender.app/Contents/MacOS/Blender -b -P Tools/textures/make_test_board.py

Writes Arena/qa/material_board.glb: four known-good shapes that follow
docs/wave-a-contracts.md section 1 exactly, so the masters can be judged on geometry that
is right, and a new part's masks can be compared against one that is:

  board_panel   0.40 x 0.28 x 0.025 m armour plate, 6 mm 3-segment bevel, a recessed
                inset panel (concave edges, cavity) and four bolt heads
  board_block   0.30 x 0.16 x 0.20 m chassis block, 8 mm bevel, a chamfered nose
  board_hub     0.09 m radius drum, 4 mm bevel, polar UV so U runs round the rim
  board_sphere  0.10 m radius UV sphere (the 18 % grey check from reference-study 3.1)

Every mesh has smooth (weighted) normals across its bevels, exported tangents and a
float COLOR_0: R = 1 - convexity, G = occlusion (from concave edge angles), B = A = 1.
One material each, named "board" (the Godot scene overrides it per instance).
"""

import math
import os

import bmesh
import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "Arena", "qa", "material_board.glb")


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def finish(obj, bevel_width, segments, uv="cube"):
    """Bevel, weight normals, unwrap, bake masks."""
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    if bevel_width > 0:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = bevel_width
        mod.segments = segments
        mod.limit_method = "ANGLE"
        mod.angle_limit = math.radians(35)
        mod.harden_normals = False
        bpy.ops.object.modifier_apply(modifier="bevel")
    bpy.ops.object.shade_smooth()
    wn = obj.modifiers.new("wn", "WEIGHTED_NORMAL")
    wn.keep_sharp = False
    wn.weight = 100
    bpy.ops.object.modifier_apply(modifier="wn")
    # Tangents need tris or quads; ngons from the inset and the cylinder caps block them.
    tri = obj.modifiers.new("tri", "TRIANGULATE")
    tri.keep_custom_normals = True
    tri.min_vertices = 5
    bpy.ops.object.modifier_apply(modifier="tri")

    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    if uv == "cube":
        bpy.ops.uv.cube_project(cube_size=1.0)
    elif uv == "sphere":
        bpy.ops.uv.sphere_project()
    elif uv == "cylinder":
        bpy.ops.uv.cylinder_project(direction="ALIGN_TO_OBJECT")
    bpy.ops.object.mode_set(mode="OBJECT")
    bake_masks(obj)

    mat = bpy.data.materials.get("board") or bpy.data.materials.new("board")
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    obj.select_set(False)


def bake_masks(obj):
    """Contract section 1.2: R = 1 - convexity, G = occlusion, float colour, point domain."""
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.edges.ensure_lookup_table()
    convex = [0.0] * len(bm.verts)
    concave = [0.0] * len(bm.verts)
    for e in bm.edges:
        if len(e.link_faces) != 2:
            continue
        a = e.calc_face_angle_signed(0.0)  # + convex, - concave
        for v in e.verts:
            if a > 0:
                convex[v.index] = max(convex[v.index], a)
            else:
                concave[v.index] = max(concave[v.index], -a)
    bm.free()
    attr = me.color_attributes.new("mask", "FLOAT_COLOR", "POINT")
    for i, _v in enumerate(me.vertices):
        r = 1.0 - min(convex[i] / math.radians(40.0), 1.0)
        g = 1.0 - 0.8 * min(concave[i] / math.radians(60.0), 1.0)
        attr.data[i].color = (r, g, 1.0, 1.0)
    me.color_attributes.active_color = attr
    me.color_attributes.render_color_index = me.color_attributes.find("mask")


def panel():
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    obj = bpy.context.active_object
    obj.name = "board_panel"
    obj.scale = (0.40, 0.025, 0.28)
    bpy.ops.object.transform_apply(scale=True)
    # Recessed inset on the front face (-Y): inset then push in 6 mm.
    bpy.ops.object.mode_set(mode="EDIT")
    bm = bmesh.from_edit_mesh(obj.data)
    front = min(bm.faces, key=lambda f: f.calc_center_median().y)
    res = bmesh.ops.inset_region(bm, faces=[front], thickness=0.05, depth=0.0)
    bmesh.ops.translate(bm, verts=list(front.verts), vec=(0.0, 0.006, 0.0))
    bmesh.update_edit_mesh(obj.data)
    bpy.ops.object.mode_set(mode="OBJECT")
    finish(obj, 0.006, 3)
    # Bolt heads: separate objects joined in, so they carry their own bevel.
    bolts = []
    for x in (-0.17, 0.17):
        for z in (-0.11, 0.11):
            bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=0.009, depth=0.008,
                                                location=(x, -0.0165, z),
                                                rotation=(math.radians(90), 0, 0))
            b = bpy.context.active_object
            finish(b, 0.0015, 2)
            bolts.append(b)
    for b in bolts:
        b.select_set(True)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.join()
    return obj


def block():
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    obj = bpy.context.active_object
    obj.name = "board_block"
    obj.scale = (0.30, 0.16, 0.20)
    bpy.ops.object.transform_apply(scale=True)
    # Chamfered nose: pull the top front edge back and down into a wedge.
    bpy.ops.object.mode_set(mode="EDIT")
    bm = bmesh.from_edit_mesh(obj.data)
    for v in bm.verts:
        if v.co.x > 0.1 and v.co.z > 0.05:
            v.co.x -= 0.09
    bmesh.update_edit_mesh(obj.data)
    bpy.ops.object.mode_set(mode="OBJECT")
    finish(obj, 0.008, 3)
    return obj


def hub():
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=0.09, depth=0.07,
                                        rotation=(math.radians(90), 0, 0))
    obj = bpy.context.active_object
    obj.name = "board_hub"
    bpy.ops.object.transform_apply(rotation=True)
    finish(obj, 0.004, 3, uv="cylinder")
    return obj


def sphere():
    bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=32, radius=0.10)
    obj = bpy.context.active_object
    obj.name = "board_sphere"
    finish(obj, 0.0, 0, uv="sphere")
    return obj


def main():
    reset()
    objs = [panel(), block(), hub(), sphere()]
    # Lay them out in a row along X so the glb opens readable; Godot re-places them.
    for i, o in enumerate(objs):
        o.location = (i * 0.5, 0.0, 0.0)
    for o in objs:
        o.select_set(True)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=OUT, export_format="GLB", use_selection=True,
        export_normals=True, export_tangents=True,
        export_vertex_color="ACTIVE", export_all_vertex_colors=False,
        export_materials="EXPORT", export_apply=True, export_yup=True,
    )
    print("wrote", OUT)


main()
