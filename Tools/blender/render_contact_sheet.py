"""Review renders for the Roboteer part library (agent G3).

One file, two jobs, because the compositing needs PIL and Blender's Python
does not have it:

  * run under Blender, it imports every .glb from Arena/assets/parts, gives the
    eight material slots proper placeholder PBR, lights a small studio and
    renders each part at `--tile` px from a 3/4 front-high view, plus one
    assembled hero bot at `--hero` px.  Then it shells out to system python3
    to do the compositing.
  * run under system python3 with `--compose`, it lays the tiles out into
    Art/review/parts-contact-sheet.png with a label under each.

    ~/Applications/Blender.app/Contents/MacOS/Blender -b --python \\
        Tools/blender/render_contact_sheet.py -- [--mode both|sheet|hero]
                                                 [--tile 1024] [--hero 2048]
                                                 [--only wedge,flipper]

The tiles are written to a temp directory and deleted once the sheet is built,
so the only things left behind are the two PNGs in Art/review/.
"""

import argparse
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile

try:
    import bpy
    from mathutils import Euler, Matrix, Vector
    IN_BLENDER = True
except ImportError:
    IN_BLENDER = False

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
PARTS = os.path.join(REPO, "Arena", "assets", "parts")
REVIEW = os.path.join(REPO, "Art", "review")

YAW = 35.0          # degrees round from the nose, toward the bot's right
PITCH = 30.0        # degrees above the axle plane

# Bot space (+X fwd, +Y up, +Z right) to Blender space, which is what a glTF
# import lands in: bot (x, y, z) -> blender (x, -z, y).
def b2b(v):
    return Vector((v[0], -v[2], v[1]))


def srgb(c):
    """sRGB 0..1 to linear, so hex colours come out looking like the hex."""
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexcol(h):
    h = h.lstrip("#")
    return tuple(srgb(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4)) + (1.0,)


# ---------------------------------------------------------------- materials

def _principled(mat):
    return mat.node_tree.nodes["Principled BSDF"]


def _brushed(mat, lo, hi, scale=(1.0, 9.0, 1.6), noise_scale=3.0):
    """A stretched procedural noise on roughness: the anisotropic smear of a
    brushed or linished metal, so highlights break up instead of reading as a
    single flat specular blob."""
    nt = mat.node_tree
    bsdf = _principled(mat)
    coord = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = scale
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = noise_scale
    noise.inputs["Detail"].default_value = 2.0
    noise.inputs["Roughness"].default_value = 0.55
    rng = nt.nodes.new("ShaderNodeMapRange")
    rng.inputs["From Min"].default_value = 0.25
    rng.inputs["From Max"].default_value = 0.75
    rng.inputs["To Min"].default_value = lo
    rng.inputs["To Max"].default_value = hi
    nt.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    nt.links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], rng.inputs["Value"])
    nt.links.new(rng.outputs["Result"], bsdf.inputs["Roughness"])


def studio_materials():
    """The nine slots from docs/graphics-bar.md as review-quality placeholders.
    G2's real PBR sets replace these; the point here is to judge the geometry
    under something that behaves like metal, plastic and rubber."""
    out = {}

    def mk(name):
        m = bpy.data.materials.new("review_" + name)
        m.use_nodes = True
        out[name] = m
        return m, _principled(m)

    m, b = mk("steel")
    b.inputs["Base Color"].default_value = hexcol("#9aa0a6")
    b.inputs["Metallic"].default_value = 1.0
    b.inputs["Roughness"].default_value = 0.35
    _brushed(m, 0.29, 0.41)

    m, b = mk("titanium")
    b.inputs["Base Color"].default_value = hexcol("#8b8d95")
    b.inputs["Metallic"].default_value = 1.0
    b.inputs["Roughness"].default_value = 0.28
    _brushed(m, 0.23, 0.33, scale=(1.0, 6.0, 6.0), noise_scale=4.0)

    m, b = mk("livery")
    b.inputs["Base Color"].default_value = hexcol("#3358a0")
    b.inputs["Metallic"].default_value = 0.0
    b.inputs["Roughness"].default_value = 0.50
    b.inputs["Specular IOR Level"].default_value = 0.5

    m, b = mk("hdpe")
    b.inputs["Base Color"].default_value = hexcol("#d6d2c8")
    b.inputs["Metallic"].default_value = 0.0
    b.inputs["Roughness"].default_value = 0.78
    b.inputs["Specular IOR Level"].default_value = 0.35

    m, b = mk("rubber")
    b.inputs["Base Color"].default_value = hexcol("#1b1c1e")
    b.inputs["Metallic"].default_value = 0.0
    b.inputs["Roughness"].default_value = 0.90
    b.inputs["Specular IOR Level"].default_value = 0.3

    m, b = mk("dark_metal")
    b.inputs["Base Color"].default_value = hexcol("#3a3d42")
    b.inputs["Metallic"].default_value = 1.0
    b.inputs["Roughness"].default_value = 0.52
    _brushed(m, 0.46, 0.58, scale=(1.0, 5.0, 5.0), noise_scale=5.0)

    m, b = mk("core_glow")
    b.inputs["Base Color"].default_value = hexcol("#0a2b28")
    b.inputs["Emission Color"].default_value = hexcol("#2af0d2")
    b.inputs["Emission Strength"].default_value = 7.0
    b.inputs["Roughness"].default_value = 0.3

    # Wave P (agent E): the ninth slot.  Without it a copper surface falls back
    # to the raw rkit material and the review render is not showing what Godot
    # shows.
    m, b = mk("copper")
    b.inputs["Base Color"].default_value = hexcol("#b0561f")
    b.inputs["Metallic"].default_value = 1.0
    b.inputs["Roughness"].default_value = 0.34
    _brushed(m, 0.30, 0.40, scale=(1.0, 5.0, 5.0), noise_scale=5.0)

    m, b = mk("polycarbonate")
    b.inputs["Base Color"].default_value = hexcol("#b9cfe0")
    b.inputs["Metallic"].default_value = 0.0
    b.inputs["Roughness"].default_value = 0.08
    b.inputs["Alpha"].default_value = 0.6
    b.inputs["IOR"].default_value = 1.585
    m.surface_render_method = 'BLENDED'
    m.use_backface_culling = False

    return out


def retarget(objs, shared):
    """Point every material slot at the shared review material with the same
    base name.  The glTF importer suffixes duplicates, hence the split."""
    for ob in objs:
        if ob.type != 'MESH':
            continue
        for slot in ob.material_slots:
            if slot.material is None:
                continue
            base = slot.material.name.split(".")[0]
            if base in shared:
                slot.material = shared[base]


# ------------------------------------------------------------------- studio

def new_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_EEVEE_NEXT'
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGB'
    sc.render.image_settings.compression = 90
    sc.render.film_transparent = False
    sc.eevee.taa_render_samples = 96
    sc.eevee.use_shadows = True
    sc.eevee.shadow_ray_count = 4
    sc.eevee.shadow_step_count = 8
    sc.eevee.use_raytracing = True
    sc.eevee.ray_tracing_options.use_denoise = True
    sc.eevee.ray_tracing_options.resolution_scale = '1'
    # Khronos PBR Neutral over AgX: AgX desaturates hard, and the whole point
    # of this sheet is judging how the materials read.  Godot ships ACES; this
    # is the closest thing Blender has that does not eat the livery blue.
    for vt in ('Khronos PBR Neutral', 'AgX', 'Standard'):
        try:
            sc.view_settings.view_transform = vt
            break
        except TypeError:
            continue
    sc.view_settings.exposure = 0.40
    sc.view_settings.gamma = 1.0
    # HDRI-free: a flat dark grey world, so all the shaping comes from the rig
    world = bpy.data.worlds.new("studio")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = hexcol("#20242b")
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.32
    sc.world = world
    return sc


def add_floor(z, radius):
    me = bpy.data.meshes.new("floor")
    bm_size = max(radius * 14.0, 3.0)
    verts = [(-bm_size, -bm_size, z), (bm_size, -bm_size, z),
             (bm_size, bm_size, z), (-bm_size, bm_size, z)]
    me.from_pydata(verts, [], [(0, 1, 2, 3)])
    me.update()
    mat = bpy.data.materials.new("floor")
    mat.use_nodes = True
    b = _principled(mat)
    b.inputs["Base Color"].default_value = hexcol("#0a0b0d")
    b.inputs["Roughness"].default_value = 0.62
    b.inputs["Specular IOR Level"].default_value = 0.22
    b.inputs["Metallic"].default_value = 0.0
    me.materials.append(mat)
    ob = bpy.data.objects.new("floor", me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def _area(name, loc, target, size, energy, colour):
    d = bpy.data.lights.new(name, 'AREA')
    d.shape = 'SQUARE'
    d.size = size
    d.energy = energy
    d.color = colour
    ob = bpy.data.objects.new(name, d)
    ob.location = loc
    direction = (Vector(target) - Vector(loc)).normalized()
    ob.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    bpy.context.scene.collection.objects.link(ob)
    return ob


def three_point(target, radius, cam_dir):
    """Key up-front off the camera's shoulder, cool fill opposite, cold rim
    behind.  Energy scales with the subject so a wheel and a chassis are lit
    the same way."""
    t = Vector(target)
    up = Vector((0.0, 0.0, 1.0))
    right = cam_dir.cross(up).normalized()
    d = max(radius, 0.12) * 3.2
    w = max(radius, 0.12) ** 2

    _area("key", t + (cam_dir * 0.45 + right * 0.95 + up * 1.00).normalized() * d,
          t, radius * 2.2, 820.0 * w, hexcol("#fff1dd")[:3])
    _area("fill", t + (cam_dir * 0.9 - right * 1.2 + up * 0.10).normalized() * d,
          t, radius * 5.0, 85.0 * w, hexcol("#c6d8f5")[:3])
    _area("rim", t + (-cam_dir * 1.0 + right * 0.15 + up * 0.75).normalized() * d,
          t, radius * 1.6, 260.0 * w, hexcol("#b6cdf2")[:3])


def frame_camera(corners, yaw=YAW, pitch=PITCH, lens=72.0, margin=1.10):
    """Put the camera on the yaw/pitch ray and solve the exact distance that
    fits every bounding-box corner.  In camera space the sideways offsets do
    not depend on distance, so the fit is one max() rather than a search."""
    sc = bpy.context.scene
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = lens
    cam_data.sensor_width = 36.0
    cam = bpy.data.objects.new("cam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam

    y, p = math.radians(yaw), math.radians(pitch)
    away = Vector((math.cos(p) * math.cos(y), -math.cos(p) * math.sin(y), math.sin(p)))
    view = -away
    right = view.cross(Vector((0.0, 0.0, 1.0)))
    right = right.normalized() if right.length > 1e-6 else Vector((1.0, 0.0, 0.0))
    up = right.cross(view).normalized()

    lo = Vector((min(c[i] for c in corners) for i in range(3)))
    hi = Vector((max(c[i] for c in corners) for i in range(3)))
    target = (lo + hi) * 0.5
    radius = (hi - lo).length * 0.5

    half = math.atan(cam_data.sensor_width * 0.5 / lens)
    tan = math.tan(half) / margin
    d = 0.0
    for c in corners:
        rel = Vector(c) - target
        depth0 = rel.dot(view)
        for off in (abs(rel.dot(right)), abs(rel.dot(up))):
            d = max(d, off / tan - depth0)
    d = max(d, radius * 1.2)

    cam.location = target + away * d
    basis = Matrix((right, up, away)).transposed().to_4x4()
    cam.rotation_euler = basis.to_euler()
    return cam, target, radius, view


# -------------------------------------------------------------------- parts

def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    roots = [o for o in new if o.parent is None]
    return new, roots


def part_corners(objs):
    out = []
    for ob in objs:
        if ob.type != 'MESH':
            continue
        mw = ob.matrix_world
        for c in ob.bound_box:
            out.append(mw @ Vector(c))
    return out


def sockets_of(objs):
    d = {}
    for ob in objs:
        if ob.name.startswith("socket_"):
            d[ob.name] = ob.matrix_world.translation.copy()
    return d


def hide_empties(objs):
    for ob in objs:
        if ob.type == 'EMPTY':
            ob.hide_render = True


def render_to(path, size_x, size_y=None):
    sc = bpy.context.scene
    sc.render.resolution_x = size_x
    sc.render.resolution_y = size_y or size_x
    sc.render.resolution_percentage = 100
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


# ------------------------------------------------------------------- tiles

def render_tiles(manifest, tile_dir, size, only):
    shared = None
    index = []
    for ident in sorted(manifest["parts"]):
        if only and ident not in only:
            continue
        entry = manifest["parts"][ident]
        glb = os.path.join(PARTS, entry["file"])
        new_scene()
        shared = studio_materials()
        objs, _roots = import_glb(glb)
        retarget(objs, shared)
        hide_empties(objs)
        corners = part_corners(objs)
        cam, target, radius, view = frame_camera(corners)
        floor_z = min(c.z for c in corners) - 0.004
        add_floor(floor_z, radius)
        three_point(target, radius, view)
        out = os.path.join(tile_dir, ident + ".png")
        render_to(out, size)
        index.append({"id": ident, "file": out, "category": entry["category"],
                      "tris": entry["tris"]})
        print("  tile %-22s %s" % (ident, os.path.basename(out)))
        sys.stdout.flush()
    return index


# -------------------------------------------------------------------- hero

#: (glb path, socket name or explicit bot-space position, bot pitch degrees,
#:  bot yaw degrees, bot-space scale, material overrides).
#: Placement is in BOT space and converted on the way in, so the numbers here
#: read the same way as the ones in parts_chassis.py.
#:
#: THE WEDGE RULING (see docs/graphics-models-notes.md): the flipper arm IS the
#: front armour on a wedge. `plate_sloped` bolts on to the ramp first, and the
#: arm rides on top of it. Two numbers matter and both are easy to get wrong:
#:   * the ramp is -19.4 degrees, but the flipper plate already slopes -6.5
#:     degrees in its own frame, so the mount pitch is -12.9, not -19.4. Use the
#:     ramp angle directly and the arm dives straight through the armour.
#:   * the origin is lifted along the ramp normal (0.331, 0.943) by the plate
#:     stack (3 units of 12 mm plus the 13 mm step) plus a few mm of air.
RAMP_PITCH = -12.9
FLIPPER_ON_ARMOUR = (0.072, 0.121, 0.0)

WHEELS_AND_TOP = [
    ("drive/wheel_standard.glb", "socket_wheel_4wd_fr", 0.0, 0.0, (1, 1, 1), None),
    ("drive/wheel_standard.glb", "socket_wheel_4wd_fl", 0.0, 0.0, (1, 1, 1), None),
    ("drive/wheel_standard.glb", "socket_wheel_4wd_rr", 0.0, 0.0, (1, 1, 1), None),
    ("drive/wheel_standard.glb", "socket_wheel_4wd_rl", 0.0, 0.0, (1, 1, 1), None),
    ("utility/srimech.glb", "socket_srimech", 0.0, 0.0, (1, 1, 1), None),
]

#: armour plate origins sit on their INNER face and grow along local +X, so the
#: position given is the surface the plate bolts to.
HERO = [
    ("armour/plate_sloped.glb", (0.245, 0.004, 0.0), 70.65, 0.0, (3.0, 1.42, 1.12), None),
    ("weapon/flipper.glb", FLIPPER_ON_ARMOUR, RAMP_PITCH, 0.0, (1.0, 1.0, 1.0), None),
    ("armour/plate_flat.glb", (-0.300, 0.131, 0.0), 90.0, 0.0, (2.0, 0.95, 1.12), None),
    ("armour/plate_flat.glb", (-0.452, 0.020, 0.0), 0.0, 180.0, (3.0, 0.47, 1.12), None),
] + WHEELS_AND_TOP

#: the same build with hdpe flanks and a polycarbonate rear, so the material
#: variety and the livery panel surviving full armour both show.
HERO_MIXED = [
    ("armour/plate_sloped.glb", (0.245, 0.004, 0.0), 70.65, 0.0, (3.0, 1.42, 1.12), None),
    ("weapon/flipper.glb", FLIPPER_ON_ARMOUR, RAMP_PITCH, 0.0, (1.0, 1.0, 1.0), None),
    ("armour/plate_flat.glb", (-0.300, 0.131, 0.0), 90.0, 0.0, (2.0, 0.95, 1.12), None),
    ("armour/plate_flat.glb", (-0.452, 0.020, 0.0), 0.0, 180.0, (3.0, 0.47, 1.12),
     {"steel": "polycarbonate"}),
    ("armour/plate_flat_hdpe.glb", (0.0, -0.004, 0.252), 0.0, -90.0, (2.0, 0.52, 1.62), None),
    ("armour/plate_flat_hdpe.glb", (0.0, -0.004, -0.252), 0.0, 90.0, (2.0, 0.52, 1.62), None),
] + WHEELS_AND_TOP


def place(roots, pos_bot, pitch_deg, yaw_deg, scale):
    """Position a freshly imported part in Blender space from bot-space numbers.
    Bot pitch is rotation about bot +Z, which is Blender -Y; bot yaw is about
    bot +Y, which is Blender +Z."""
    for r in roots:
        r.location = pos_bot if isinstance(pos_bot, Vector) else b2b(pos_bot)
        r.rotation_mode = 'YXZ'
        r.rotation_euler = Euler((0.0, -math.radians(pitch_deg),
                                  math.radians(yaw_deg)), 'YXZ')
        r.scale = (scale[0], scale[2], scale[1])   # bot (x, y, z) -> blender (x, z, y)


def render_hero(out_path, size, recipe):
    new_scene()
    shared = studio_materials()
    chassis_objs, _ = import_glb(os.path.join(PARTS, "chassis", "wedge.glb"))
    sockets = sockets_of(chassis_objs)
    retarget(chassis_objs, shared)
    all_objs = list(chassis_objs)

    for rel, where, pitch, yaw, scale, mats in recipe:
        objs, roots = import_glb(os.path.join(PARTS, *rel.split("/")))
        if isinstance(where, str):
            if where not in sockets:
                raise SystemExit("hero: the wedge has no %s" % where)
            pos = sockets[where]
        else:
            pos = b2b(where)
        place(roots, pos, pitch, yaw, scale)
        local = dict(shared)
        if mats:
            for src, dst in mats.items():
                local[src] = shared[dst]
        retarget(objs, local)
        all_objs += objs

    hide_empties(all_objs)
    bpy.context.view_layer.update()
    corners = part_corners(all_objs)
    cam, target, radius, view = frame_camera(corners, yaw=38.0, pitch=26.0,
                                             lens=85.0, margin=1.06)
    add_floor(-0.11, radius)
    three_point(target, radius, view)
    bpy.context.scene.eevee.taa_render_samples = 160
    render_to(out_path, size)
    print("  hero -> %s" % out_path)


# ------------------------------------------------------------- boss builds
#: The five boss machines exactly as stage5-spec §4 fixes them, so the
#: silhouette test in brief §3 is run against what a player actually meets,
#: not against a part floating on its own.
#: (boss id, host chassis, socket for the signature part, drive, wheel sockets)
BOSS_BUILDS = [
    ("thresher", "long_low", "socket_weapon_front", "6wd",
     ["socket_wheel_fr", "socket_wheel_fl", "socket_wheel_mr",
      "socket_wheel_ml", "socket_wheel_rr", "socket_wheel_rl"]),
    ("grudge", "box", "socket_weapon_top", "tracks", []),
    ("bandsaw", "wedge", "socket_weapon_front", "2wd",
     ["socket_wheel_2wd_rr", "socket_wheel_2wd_rl"]),
    ("anvil", "tall_tank", "socket_weapon_front", "4wd",
     ["socket_wheel_4wd_fr", "socket_wheel_4wd_fl",
      "socket_wheel_4wd_rr", "socket_wheel_4wd_rl"]),
    ("cinder", "box", "socket_weapon_front", "6wd",
     ["socket_wheel_fr", "socket_wheel_fl", "socket_wheel_mr",
      "socket_wheel_ml", "socket_wheel_rr", "socket_wheel_rl"]),
]

#: tracked bosses: (bot-space position, yaw, x scale) per side
TRACKS = [((0.0, 0.0, 0.268), 0.0, 1.16), ((0.0, 0.0, -0.268), 180.0, 1.16)]


def render_boss_tiles(tile_dir, size, builds=None):
    """Chassis + hull overlay + signature part + drive, one tile per boss."""
    index = []
    for bid, host, socket_name, drive, wheels in (builds or BOSS_BUILDS):
        new_scene()
        shared = studio_materials()
        objs, _ = import_glb(os.path.join(PARTS, "chassis", host + ".glb"))
        sockets = sockets_of(objs)
        all_objs = list(objs)

        for rel, where in (("boss/%s_hull.glb" % bid, (0.0, 0.0, 0.0)),
                           ("boss/%s.glb" % bid, socket_name)):
            o, roots = import_glb(os.path.join(PARTS, *rel.split("/")))
            pos = sockets[where] if isinstance(where, str) else b2b(where)
            place(roots, pos, 0.0, 0.0, (1, 1, 1))
            all_objs += o

        for w in wheels:
            o, roots = import_glb(os.path.join(PARTS, "drive", "wheel_standard.glb"))
            place(roots, sockets[w], 0.0, 0.0, (1, 1, 1))
            all_objs += o
        if drive == "tracks":
            for pos, yaw, sx in TRACKS:
                o, roots = import_glb(os.path.join(PARTS, "drive", "track_unit.glb"))
                place(roots, b2b(pos), 0.0, yaw, (sx, 1.0, 1.0))
                all_objs += o

        retarget(all_objs, shared)
        hide_empties(all_objs)
        bpy.context.view_layer.update()
        corners = part_corners(all_objs)
        cam, target, radius, view = frame_camera(corners, yaw=38.0, pitch=24.0,
                                                 lens=80.0, margin=1.05)
        add_floor(-0.11, radius)
        three_point(target, radius, view)
        out = os.path.join(tile_dir, bid + "_built.png")
        render_to(out, size)
        index.append({"id": bid.upper(), "file": out, "category": "boss",
                      "tris": 0, "sort": 1,
                      "note": "%s + %s_hull + %s" % (host, bid, drive)})
        print("  boss %-12s %s" % (bid, os.path.basename(out)))
        sys.stdout.flush()
    return index


# --------------------------------------------------------------- compositing

def compose(index_path, out_path, tile_px=512, cols=6):
    from PIL import Image, ImageDraw, ImageFont

    with open(index_path) as fh:
        index = json.load(fh)
    if not index:
        raise SystemExit("nothing to compose")

    order = {"chassis": 0, "drive": 1, "weapon": 2, "armour": 3, "utility": 4, "boss": 5, "fx": 6}
    # bosses read best as two rows: the five signature parts, then the five
    # hull overlays, so each column is one boss.
    index.sort(key=lambda e: (e.get("sort", 0), order.get(e["category"], 9),
                              1 if e["id"].endswith("_hull") else 0, e["id"]))

    rows = (len(index) + cols - 1) // cols
    label_h = 46
    pad = 10
    cell_w = tile_px + pad
    cell_h = tile_px + label_h + pad
    head = 88
    sheet = Image.new("RGB", (cols * cell_w + pad, rows * cell_h + pad + head),
                      (16, 17, 20))
    draw = ImageDraw.Draw(sheet)

    def font(sz):
        for p in ("/System/Library/Fonts/Supplemental/Arial Bold.ttf",
                  "/System/Library/Fonts/Supplemental/Arial.ttf",
                  "/System/Library/Fonts/Helvetica.ttc"):
            if os.path.exists(p):
                try:
                    return ImageFont.truetype(p, sz)
                except Exception:
                    pass
        return ImageFont.load_default()

    f_title, f_id, f_sub = font(40), font(23), font(18)
    total = sum(e["tris"] for e in index)
    draw.text((pad + 8, 22),
              "Roboteer part library  %d parts  %s tris  yaw %d / pitch %d  EEVEE Next"
              % (len(index), "{:,}".format(total), int(YAW), int(PITCH)),
              font=f_title, fill=(226, 228, 232))

    for i, entry in enumerate(index):
        cx = pad + (i % cols) * cell_w
        cy = pad + head + (i // cols) * cell_h
        tile = Image.open(entry["file"]).convert("RGB")
        if tile.size != (tile_px, tile_px):
            tile = tile.resize((tile_px, tile_px), Image.LANCZOS)
        sheet.paste(tile, (cx, cy))
        draw.rectangle([cx, cy, cx + tile_px - 1, cy + tile_px - 1], outline=(44, 47, 52))
        draw.text((cx + 6, cy + tile_px + 5), entry["id"], font=f_id, fill=(232, 234, 238))
        sub = entry.get("note") or "%s   %s tris" % (entry["category"],
                                                     "{:,}".format(entry["tris"]))
        draw.text((cx + 6, cy + tile_px + 27), sub, font=f_sub, fill=(140, 146, 156))

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    sheet.save(out_path, optimize=True)
    print("contact sheet -> %s  (%d x %d, %.2f MB)"
          % (out_path, sheet.width, sheet.height,
             os.path.getsize(out_path) / 1048576.0))


# --------------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", default="both", choices=["both", "sheet", "hero"])
    ap.add_argument("--tile", type=int, default=1024)
    ap.add_argument("--sheet-tile", type=int, default=400,
                    help="px per tile in the composited sheet")
    ap.add_argument("--hero", type=int, default=2048)
    ap.add_argument("--only", default="")
    ap.add_argument("--compose", default="", help="index.json, python3 side only")
    ap.add_argument("--out", default="")
    ap.add_argument("--sheet-out", default="")
    ap.add_argument("--cols", type=int, default=6)
    ap.add_argument("--bosses", action="store_true",
                    help="also render each boss assembled on its host chassis")
    if IN_BLENDER:
        argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
        args = ap.parse_args(argv)
    else:
        args = ap.parse_args()

    if args.compose:
        compose(args.compose, args.out or os.path.join(REVIEW, "parts-contact-sheet.png"),
                args.sheet_tile, args.cols)
        return

    if not IN_BLENDER:
        raise SystemExit("run me under Blender, or with --compose <index.json>")

    os.makedirs(REVIEW, exist_ok=True)
    with open(os.path.join(PARTS, "manifest.json")) as fh:
        manifest = json.load(fh)
    only = set(w.strip() for w in args.only.split(",") if w.strip())

    tmp = tempfile.mkdtemp(prefix="roboteer-tiles-")
    try:
        if args.mode in ("both", "sheet"):
            index = render_tiles(manifest, tmp, args.tile, only)
            if args.bosses:
                index += render_boss_tiles(tmp, args.tile)
            index_path = os.path.join(tmp, "index.json")
            with open(index_path, "w") as fh:
                json.dump(index, fh)
            py = shutil.which("python3") or "/usr/bin/python3"
            subprocess.run([py, os.path.abspath(__file__), "--compose", index_path,
                            "--sheet-tile", str(args.sheet_tile),
                            "--cols", str(args.cols),
                            "--out", args.sheet_out
                            or os.path.join(REVIEW, "parts-contact-sheet.png")],
                           check=True)
        if args.mode in ("both", "hero"):
            render_hero(os.path.join(REVIEW, "hero-wedge-flipper.png"), args.hero, HERO)
            render_hero(os.path.join(REVIEW, "hero-wedge-flipper-materials.png"),
                        args.hero, HERO_MIXED)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
