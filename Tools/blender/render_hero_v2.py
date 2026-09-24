"""Wave A review render: the hero build assembled EXACTLY as the engine
assembles it, lit with the showroom rig of docs/look/reference-study.md 3.1.

    # 1. where the engine puts every model (plates on the physics hull anchors,
    #    the flipper on the pinned pivot):
    Godot --headless --path Arena --script res://qa/hero_assembly_dump.gd -- /tmp/hero.json
    # 2. render it (EEVEE, -b so no window):
    Blender -b --python Tools/blender/render_hero_v2.py -- --assembly /tmp/hero.json \
        --parts Arena/assets/parts --out docs/aaa/img/wave-a/models/after \
        [--livery "#d1662b"] [--views hero,rear,wheel,flipper] [--size 2048]

`--parts` can point at a copy of an older parts tree, which is how the
before/after pairs are made from the same camera and light.

The materials here are review stand-ins, not the materials lead's: they exist
to judge the geometry and to show what the baked masks (`<id>_mask.png`, R edge,
G AO, B cavity on UV2, docs/wave-a-contracts.md) are for: the livery chips to
bare steel on R, and every slot darkens into its own crevices on G and B.
"""

import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

BOT2BL = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))

CATEGORY = {}


def srgb(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexcol(h):
    h = h.lstrip("#")
    return tuple(srgb(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4)) + (1.0,)


# ------------------------------------------------------------------ scene

def new_scene(size_x, size_y):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE_NEXT'
    sc.render.resolution_x = size_x
    sc.render.resolution_y = size_y
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGB'
    sc.eevee.taa_render_samples = 128
    sc.eevee.use_shadows = True
    sc.eevee.shadow_ray_count = 4
    sc.eevee.shadow_step_count = 8
    sc.eevee.use_raytracing = True
    sc.eevee.ray_tracing_options.use_denoise = True
    sc.eevee.ray_tracing_options.resolution_scale = '1'
    sc.eevee.fast_gi_method = 'GLOBAL_ILLUMINATION'
    for vt in ('Khronos PBR Neutral', 'AgX', 'Standard'):
        try:
            sc.view_settings.view_transform = vt
            break
        except TypeError:
            continue
    sc.view_settings.exposure = 0.0
    world = bpy.data.worlds.new("black")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = hexcol("#0b0d11")
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.35
    sc.world = world
    return sc


def emissive_box(name, center, size, strength, colour=(1, 1, 1, 1), rot=None):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = size
    if rot:
        ob.rotation_euler = rot
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for nd in list(nt.nodes):
        nt.nodes.remove(nd)
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs["Color"].default_value = colour
    e.inputs["Strength"].default_value = strength
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(e.outputs[0], o.inputs[0])
    ob.data.materials.append(m)
    ob.visible_camera = False
    ob.visible_shadow = False
    return ob


def spot(name, loc, target, energy, colour, angle_deg=28.0, size=0.15, shadow=True):
    d = bpy.data.lights.new(name, 'SPOT')
    d.energy = energy
    d.color = colour[:3]
    d.spot_size = math.radians(angle_deg * 2.0)
    d.spot_blend = 0.85
    d.shadow_soft_size = size
    d.use_shadow = shadow
    ob = bpy.data.objects.new(name, d)
    ob.location = loc
    ob.rotation_euler = (Vector(target) - Vector(loc)).normalized().to_track_quat(
        '-Z', 'Y').to_euler()
    bpy.context.scene.collection.objects.link(ob)
    return ob


def showroom(target):
    """reference-study 3.1, translated to Blender watts.  Key 4300 K front
    left 35 degrees up, fill 6500 K front right low at a quarter of the key,
    two cold rims behind at 1.2x key, a softbox above and two strip lights
    behind that exist to be reflected, a near-black glossy floor."""
    t = Vector(target)

    def around(yaw_deg, elev_deg, dist):
        y, e = math.radians(yaw_deg), math.radians(elev_deg)
        # yaw 0 = in front of the nose (+X bot = +X blender), positive toward
        # the camera side (bot right = blender -Y)
        return t + Vector((math.cos(e) * math.cos(y), -math.cos(e) * math.sin(y),
                           math.sin(e))) * dist

    key = 170.0
    spot("key", around(-20.0, 35.0, 2.6), t, key, hexcol("#ffd6b3"), 28.0, 0.15)
    spot("fill", around(75.0, 15.0, 2.6), t, key / 4.0, hexcol("#fbfafa"), 40.0,
         0.4, shadow=False)
    spot("rim_l", around(-150.0, 28.0, 2.4), t, key * 1.2, hexcol("#dbe5ff"), 25.0,
         0.2, shadow=False)
    spot("rim_r", around(160.0, 28.0, 2.4), t, key * 1.2, hexcol("#dbe5ff"), 25.0,
         0.2, shadow=False)
    # softbox above: reflected, not seen
    emissive_box("softbox", t + Vector((0, 0, 2.2)), (1.6, 0.6, 0.02), 3.0)
    ob = bpy.data.lights.new("softbox_fill", 'AREA')
    ob.shape = 'RECTANGLE'
    ob.size, ob.size_y = 1.6, 0.6
    ob.energy = 60.0
    ob.color = hexcol("#fff4e8")[:3]
    lo = bpy.data.objects.new("softbox_fill", ob)
    lo.location = t + Vector((0, 0, 2.15))
    bpy.context.scene.collection.objects.link(lo)
    # two strips behind the stage at 45 degrees either side
    for sgn in (-1.0, 1.0):
        p = around(180.0 + sgn * 45.0, 18.0, 2.2)
        yaw = math.atan2(p.y - t.y, p.x - t.x)
        emissive_box("strip", p, (0.08, 2.4, 0.08), 4.0, hexcol("#f4f7ff"),
                     rot=(0.0, 0.0, yaw))
    # floor: near black, glossy (roughness 0.22)
    me = bpy.data.meshes.new("floor")
    s = 12.0
    z = FLOOR_Z
    me.from_pydata([(-s, -s, z), (s, -s, z), (s, s, z), (-s, s, z)], [], [(0, 1, 2, 3)])
    fm = bpy.data.materials.new("floor")
    fm.use_nodes = True
    b = fm.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.022, 0.024, 0.028, 1.0)
    b.inputs["Roughness"].default_value = 0.22
    me.materials.append(fm)
    fl = bpy.data.objects.new("floor", me)
    bpy.context.scene.collection.objects.link(fl)


FLOOR_Z = -0.11


# ------------------------------------------------------------------ materials

def _principled(m):
    return m.node_tree.nodes["Principled BSDF"]


BASE = {
    # slot: (colour hex, metallic, roughness, extra)
    "steel": ("#a3a7ac", 1.0, 0.32, "brushed"),
    "titanium": ("#9a948a", 1.0, 0.28, "brushed"),
    "dark_metal": ("#2b2e33", 0.0, 0.55, "powder"),
    "hdpe": (None, 0.0, 0.60, "hdpe"),
    "polycarbonate": ("#c9d6e3", 0.0, 0.10, "clear"),
    "rubber": ("#141416", 0.0, 0.90, "rubber"),
    "livery": (None, 0.0, 0.40, "paint"),
    "core_glow": ("#0a2b28", 0.0, 0.3, "glow"),
    "copper": ("#b0561f", 1.0, 0.34, "brushed"),
}


def make_material(slot, livery_hex, mask_img):
    colour, metal, rough, kind = BASE.get(slot, ("#808080", 0.0, 0.5, ""))
    m = bpy.data.materials.new("rv2_%s" % slot)
    m.use_nodes = True
    nt = m.node_tree
    b = _principled(m)
    col = hexcol(colour) if colour else hexcol(livery_hex)
    if kind == "hdpe":
        col = tuple(c * 0.85 + 0.12 for c in hexcol(livery_hex)[:3]) + (1.0,)
    b.inputs["Base Color"].default_value = col
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    if kind == "paint":
        b.inputs["Coat Weight"].default_value = 1.0
        b.inputs["Coat Roughness"].default_value = 0.05
    if kind == "brushed":
        b.inputs["Anisotropic"].default_value = 0.5
    if kind == "clear":
        b.inputs["Alpha"].default_value = 0.55
        b.inputs["IOR"].default_value = 1.585
        m.surface_render_method = 'BLENDED'
    if kind == "glow":
        b.inputs["Emission Color"].default_value = hexcol("#2af0d2")
        b.inputs["Emission Strength"].default_value = 6.0
    if mask_img is None:
        return m
    # masks on UV2 ("bake" in Blender, the second UV layer on import)
    uv = nt.nodes.new("ShaderNodeUVMap")
    uv.uv_map = "UVMap.001"
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = mask_img
    tex.interpolation = 'Linear'
    nt.links.new(uv.outputs[0], tex.inputs[0])
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tex.outputs[0], sep.inputs[0])
    # grime: base colour x mix(0.55, 1, AO) and x (1 - 0.35 cavity)
    ao_mix = nt.nodes.new("ShaderNodeMapRange")
    ao_mix.inputs["To Min"].default_value = 0.55
    nt.links.new(sep.outputs[1], ao_mix.inputs[0])
    cav = nt.nodes.new("ShaderNodeMapRange")
    cav.inputs["To Min"].default_value = 1.0
    cav.inputs["To Max"].default_value = 0.65
    nt.links.new(sep.outputs[2], cav.inputs[0])
    grime = nt.nodes.new("ShaderNodeMath")
    grime.operation = 'MULTIPLY'
    nt.links.new(ao_mix.outputs[0], grime.inputs[0])
    nt.links.new(cav.outputs[0], grime.inputs[1])
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = 'RGBA'
    mul.blend_type = 'MULTIPLY'
    mul.inputs["Factor"].default_value = 1.0
    mul.inputs[6].default_value = col
    comb = nt.nodes.new("ShaderNodeCombineColor")
    for i in range(3):
        nt.links.new(grime.outputs[0], comb.inputs[i])
    nt.links.new(comb.outputs[0], mul.inputs[7])
    base_out = mul.outputs[2]
    if kind in ("paint", "hdpe", "powder"):
        # edge wear: the crest of every bevel chips through to bare steel,
        # broken up by noise so it is chips, not a painted outline
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 90.0
        noise.inputs["Detail"].default_value = 6.0
        wear = nt.nodes.new("ShaderNodeMath")
        wear.operation = 'MULTIPLY'
        nt.links.new(sep.outputs[0], wear.inputs[0])
        nt.links.new(noise.outputs[0], wear.inputs[1])
        ramp = nt.nodes.new("ShaderNodeMapRange")
        ramp.inputs["From Min"].default_value = 0.42
        ramp.inputs["From Max"].default_value = 0.50
        nt.links.new(wear.outputs[0], ramp.inputs[0])
        mixc = nt.nodes.new("ShaderNodeMix")
        mixc.data_type = 'RGBA'
        nt.links.new(ramp.outputs[0], mixc.inputs["Factor"])
        nt.links.new(base_out, mixc.inputs[6])
        mixc.inputs[7].default_value = hexcol("#8e9297")
        base_out = mixc.outputs[2]
        mm = nt.nodes.new("ShaderNodeMapRange")
        mm.inputs["To Min"].default_value = metal
        mm.inputs["To Max"].default_value = 1.0
        nt.links.new(ramp.outputs[0], mm.inputs[0])
        nt.links.new(mm.outputs[0], b.inputs["Metallic"])
        if kind == "paint":
            cw = nt.nodes.new("ShaderNodeMapRange")
            cw.inputs["To Min"].default_value = 1.0
            cw.inputs["To Max"].default_value = 0.0
            nt.links.new(ramp.outputs[0], cw.inputs[0])
            nt.links.new(cw.outputs[0], b.inputs["Coat Weight"])
    nt.links.new(base_out, b.inputs["Base Color"])
    return m


# ------------------------------------------------------------------ assembly

def find_glb(root, ident):
    for cat in ("chassis", "drive", "weapon", "armour", "utility", "boss", "fx"):
        p = os.path.join(root, cat, ident + ".glb")
        if os.path.exists(p):
            return p
    return None


def import_part(root, ident, bot_matrix, livery_hex, face_material, cache,
                only="", skip=()):
    path = find_glb(root, ident)
    if path is None:
        print("  missing model", ident)
        return []
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    holder = bpy.data.objects.new("hold_" + ident, None)
    bpy.context.scene.collection.objects.link(holder)
    holder.matrix_world = BOT2BL @ bot_matrix @ BOT2BL.inverted()
    for o in new:
        if o.parent is None:
            o.parent = holder
    for o in new:
        nm = o.name.split(".")[0]
        if o.type != 'MESH' or (only and nm != only) or nm in skip:
            o.hide_render = True
            continue
        base = os.path.splitext(path)[0]
        suffix = "" if o.name.split(".")[0] == "body" else "_" + o.name.split(".")[0]
        mpath = base + suffix + "_mask.png"
        img = None
        if os.path.exists(mpath) and len(o.data.uv_layers) > 1:
            img = bpy.data.images.load(mpath, check_existing=True)
            img.colorspace_settings.name = 'Non-Color'
            o.data.uv_layers[1].name = "UVMap.001"
        for slot in o.material_slots:
            if slot.material is None:
                continue
            name = slot.material.name.split(".")[0]
            if name == "steel" and face_material and ident.startswith("plate"):
                name = face_material
            key = (name, mpath if img else "")
            if key not in cache:
                cache[key] = make_material(name, livery_hex, img)
            slot.material = cache[key]
    return new


def mat_from_row(r):
    bx, by, bz = Vector(r["basis_x"]), Vector(r["basis_y"]), Vector(r["basis_z"])
    M = Matrix.Identity(4)
    for i in range(3):
        M[i][0], M[i][1], M[i][2] = bx[i], by[i], bz[i]
        M[i][3] = r["origin"][i]
    return M


# ------------------------------------------------------------------ cameras

VIEWS = {
    # name: (yaw from nose toward the bot's right, elevation, distance, lens,
    #        look-at offset in bot space)
    "hero": (38.0, 9.0, 2.35, 50.0, (0.02, 0.02, 0.0)),
    "high": (35.0, 30.0, 2.6, 50.0, (0.0, 0.0, 0.0)),
    "rear": (150.0, 22.0, 2.4, 50.0, (0.0, 0.02, 0.0)),
    "wheel": (62.0, 6.0, 0.95, 85.0, (0.25, 0.0, 0.30)),
    "flipper": (18.0, 26.0, 1.25, 70.0, (0.24, 0.03, 0.0)),
}


def camera(view, size_x, size_y):
    yaw, elev, dist, lens, look = VIEWS[view]
    t = BOT2BL @ Vector(look)
    y, e = math.radians(yaw), math.radians(elev)
    away = Vector((math.cos(e) * math.cos(y), -math.cos(e) * math.sin(y), math.sin(e)))
    cd = bpy.data.cameras.new("cam")
    cd.lens = lens
    cd.sensor_width = 36.0
    cd.sensor_fit = 'HORIZONTAL'
    cam = bpy.data.objects.new("cam", cd)
    bpy.context.scene.collection.objects.link(cam)
    cam.location = t + away * dist
    cam.rotation_euler = (-away).to_track_quat('-Z', 'Y').to_euler()
    bpy.context.scene.camera = cam
    return cam


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--assembly", required=True)
    ap.add_argument("--parts", required=True)
    ap.add_argument("--out", required=True, help="output prefix")
    ap.add_argument("--livery", default="#3358a0")
    ap.add_argument("--views", default="hero,high,rear,wheel,flipper")
    ap.add_argument("--size", type=int, default=2048)
    ap.add_argument("--samples", type=int, default=128)
    args = ap.parse_args(argv)

    with open(args.assembly) as fh:
        rows = json.load(fh)["parts"]
    for view in [v.strip() for v in args.views.split(",") if v.strip()]:
        sx, sy = args.size, int(args.size * 1320 / 2868)
        sc = new_scene(sx, sy)
        sc.eevee.taa_render_samples = args.samples
        cache = {}
        split = {r["id"] for r in rows if r.get("only")}
        for r in rows:
            import_part(args.parts, r["id"], mat_from_row(r), args.livery,
                        r.get("face_material", ""), cache, only=r.get("only", ""),
                        skip=("mount",) if r["id"] in split and not r.get("only") else ())
        showroom(BOT2BL @ Vector((0.0, 0.0, 0.0)))
        camera(view, sx, sy)
        sc.render.filepath = "%s-%s.png" % (args.out, view)
        bpy.ops.render.render(write_still=True)
        print("  wrote", sc.render.filepath)


if __name__ == "__main__":
    main()
