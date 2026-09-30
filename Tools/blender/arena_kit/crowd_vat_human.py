"""Roboteer arena kit: 3D CROWD PEOPLE with a vertex animation texture (VAT).

Wave C crowd (docs/wave-c-crowd-notes.md). The card atlas (crowd_cards_human.py) draws
every person as a flat picture that turns to face the lens, with four poses that swap
in one frame. This script builds the same MakeHuman / MPFB2 people as real low-poly
meshes and bakes short animation clips into a texture, so the crowd can be drawn as
MultiMesh instances that face the ARENA, are lit by the venue's own lights, and move
smoothly (idle sway, clap, raise, cheer, flinch) with a per-person phase.

Run:

    Blender -b --python Tools/blender/arena_kit/crowd_vat_human.py -- \
        [--variants 0,3,7] [--tris 1400]

What it does per person
-----------------------
1. build_human() from crowd_cards_human.py (same bodies, clothes, licences).
2. Rest pose; every piece's modifiers applied except the armature (helpers masked,
   covered skin hidden, clothes subdivision), eyes/brows/lashes dropped.
3. Cycles bakes each piece's DIFFUSE COLOUR into a colour attribute (so one material
   draws the whole person), and a "zone" attribute marks skin / top / bottom / hat /
   hair / shoes / scarf so the game can re-tint clothes per instance.
4. Everything joined into one mesh and decimated (collapse) to about --tris triangles;
   bone weights survive the collapse, so the armature still drives it.
5. Clips: pose snapshots (pose_person) are interpolated bone by bone (quaternion
   slerp, eased) and every frame's evaluated vertex positions and normals are stored.

Outputs
-------
Arena/arena/kit/crowd/crowd_people_vat.png   RGB8, 2048 wide. People are packed on shelves:
    person i owns columns col..col+verts and rows row..row+2F; row + f is every vertex's
    position in frame f (x, y, z in Godot axes, 0..255 across POS_MIN..POS_MAX), row + F + f
    its normal (0..255 = -1..1). Import lossless, no mipmaps, no VRAM compression.
Tools/blender/arena_kit/crowd_out/crowd_people.json   per person: verts, col, row, triangle
    indices (full and far LOD), per-vertex colour (sRGB) and zone; the clip table.
Then bake the game's resource from the JSON:
    Godot --headless --path Arena --script qa/_crowd_people_bake.gd
    -> Arena/arena/kit/crowd/crowd_people.res (CrowdPeopleData)
"""

import json
import math
import os
import sys
import time

import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import crowd_cards as cc  # noqa: E402
import crowd_cards_human as ch  # noqa: E402

OUT_DIR = cc.OUT_DIR
FPS = 12.0
TEX_W = 2048
# Godot axes (x right, y up, z toward the viewer = the person's front).
POS_MIN = np.array([-0.95, -0.6, -0.95], dtype=np.float64)
POS_MAX = np.array([0.95, 2.45, 0.95], dtype=np.float64)

ZONES = {"skin": 0, "top": 1, "bottom": 2, "hat": 3, "hair": 4, "shoes": 5,
         "scarf": 6}
MAT_ZONE = {"HM_top": 1, "HM_hivis": 1, "HM_bottom": 2, "HM_hat": 3,
            "HM_hair": 4, "HM_shoes": 5, "HM_scarf": 6}
DROP = ("brow", "lash")


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"variants": None, "tris": 1000, "lod_tris": 260}
    i = 0
    while i < len(argv):
        if argv[i] == "--variants":
            opts["variants"] = [int(x) for x in argv[i + 1].split(",")]
            i += 1
        elif argv[i] == "--tris":
            opts["tris"] = int(argv[i + 1])
            i += 1
        i += 1
    return opts


# --------------------------------------------------------- more people
# Eight more bodies for the 3D crowd only (the card atlas stays at 16): older, heavier,
# younger, taller, tattooed, a teen. Same asset licensing as crowd_cards_human.asset().
V = dict
EXTRA_VARIANTS = [
    V(name="polo_dad", g=1.0, age=48, w=0.75, m=0.5, h=1.79, race=ch.race(0, 0, 1),
      skin="middleage_caucasian_male", hair=("short02", "salt"), brows="eyebrow010",
      top=("namuhekam_male_polo_shirt", "navy", 0.9),
      bottom=("elvs_jeans_bootcut", "denim", 1.0), shoes="shoes02", hat=None,
      scarf=None, phone=True, yaw=0, poses=["hips", "clap", "fist_pump", "hands_head"]),
    V(name="cardigan_woman", g=0.0, age=52, w=0.7, m=0.4, h=1.64,
      race=ch.race(0.2, 0, 0.8), skin="middleage_caucasian_female",
      hair=("bob01", "auburn"), brows="eyebrow002",
      top=("punkduck_v_neck_top", "camel", 0.9),
      bottom=("mindfront_female_trousers_1", "black", 0.8), shoes="shoes04", hat=None,
      scarf=None, phone=True, yaw=0, poses=["crossed", "clap_high", "straight_up", "cover_mouth"]),
    V(name="tank_lad", g=1.0, age=20, w=0.4, m=0.75, h=1.83, race=ch.race(1, 0, 0),
      skin="young_african_male", hair=("short01", "black"), brows="eyebrow003",
      top=("elvs_male_tankshirt1", "offwhite", 0.9),
      bottom=("cortu_cargo_pants", "olive", 0.9), shoes="shoes06",
      hat=("elvs_slouchy_beanie1", "black", 0.7), scarf=None, phone=False, yaw=0,
      poses=["relaxed", "fists", "fist_pump", "recoil"]),
    V(name="newsboy_old", g=1.0, age=71, w=0.55, m=0.35, h=1.70, race=ch.race(0, 0, 1),
      skin="old_caucasian_male", hair=("short04", "white"), brows="eyebrow012",
      top=("mindfront_lusekofta", "navy", 0.8),
      bottom=("mindfront_male_trousers_2", "charcoal", 0.9), shoes="shoes01",
      hat=("elvs_male_trilby_hat", "brown", 0.8), scarf=None, phone=False, yaw=0,
      poses=["pockets", "clap", "v_up", "hands_head"]),
    V(name="braid_teen", g=0.0, age=16, w=0.4, m=0.45, h=1.60, race=ch.race(0.6, 0, 0.4),
      skin="young_african_female", hair=("braid01", "black"), brows="eyebrow006",
      top=("punkduck_retro_top", "teal", 0.9),
      bottom=("punkduck_female_tight_jeans", "darkdenim", 1.0), shoes="shoes05",
      hat=None, scarf=None, phone=True, yaw=0,
      poses=["relaxed", "clap_high", "straight_up", "cheeks"]),
    V(name="heavy_woman", g=0.0, age=38, w=1.0, m=0.45, h=1.67, race=ch.race(0, 0.3, 0.7),
      skin="young_caucasian_female", hair=("long01", "brown"), brows="eyebrow004",
      top=("mindfront_knitted_sweater_02", "forest", 0.8),
      bottom=("elvs_jeans_straight_leg", "denim", 1.0), shoes="shoes03", hat=None,
      scarf=None, phone=True, yaw=0, poses=["hips", "clap", "v_up", "cover_mouth"]),
    V(name="fisher_hat", g=1.0, age=27, w=0.45, m=0.5, h=1.74, race=ch.race(0, 1, 0),
      skin="young_asian_male", hair=("short03", "black"), brows="eyebrow009",
      top=("toigo_fisherman_sweater", "mustard", 0.8),
      bottom=("elvs_male_trouser", "black", 0.9), shoes="shoes02",
      hat=("mindfront_fishing_hat_01", "khaki", 0.8), scarf=None, phone=False, yaw=0,
      poses=["pockets", "clap", "fist_pump", "recoil"]),
    V(name="big_tattoo", g=1.0, age=40, w=0.9, m=0.8, h=1.92, race=ch.race(0, 0, 1),
      skin="rehmanpolanski_skin_viking_tattoos", hair=("long01", "blonde"),
      brows="eyebrow005", top=("elvs_male_tankshirt1", "black", 0.9),
      bottom=("elvs_jeans_straight_leg", "darkdenim", 1.0), shoes="shoes06", hat=None,
      scarf="scarf_red", phone=False, yaw=0, poses=["crossed", "fists", "v_up", "hands_head"]),
]
ALL_VARIANTS = list(ch.VARIANTS) + EXTRA_VARIANTS

# Clips in the texture, in order: (name, sample spacing in seconds). Slow clips are
# sampled sparsely (the shader interpolates), fast ones at 12 fps.
CLIP_RATE = {"idle": 0.25, "clap_in": 1 / 12.0, "clap": 1 / 12.0, "raise": 1 / 12.0,
             "cheer": 1 / 12.0, "flinch_in": 1 / 12.0, "boo_in": 1 / 12.0, "boo": 1 / 10.0,
             "sit": 0.25, "sit_raise": 1 / 12.0, "sit_cheer": 1 / 12.0}


# ------------------------------------------------------------- poses

def derived_poses():
    """Extra poses the clips need that the card atlas never drew."""
    P = cc.POSES
    import copy

    def mod(src, name, **kw):
        p = copy.deepcopy(P[src])
        for k, v in kw.items():
            if k in ("R", "L"):
                for kk, vv in v.items():
                    p[k][kk] = vv
            else:
                p[k] = v
        P[name] = p
        return name

    for base in ("relaxed", "pockets", "crossed", "hips"):
        b = P[base]
        hp, hr, hy = b["head"]
        mod(base, base + "_sway_a", shift=b["shift"] + 0.022,
            head=(hp + 4, hr + 3, hy + 16), lean=b["lean"] + 1.5)
        mod(base, base + "_sway_b", shift=b["shift"] - 0.02,
            head=(hp + 2, hr - 3, hy - 14), lean=b["lean"] - 1.0)
    for base in ("clap", "clap_high"):
        b = P[base]
        R = dict(b["R"])
        L = dict(b["L"])
        R["w"] = (b["R"]["w"][0] + 0.085, b["R"]["w"][1] - 0.01, b["R"]["w"][2] + 0.01)
        L["w"] = (b["L"]["w"][0] + 0.085, b["L"]["w"][1] - 0.01, b["L"]["w"][2] + 0.01)
        mod(base, base + "_open", R=R, L=L, crouch=b["crouch"] * 0.4)
    for base in ("v_up", "straight_up", "fist_pump"):
        b = P[base]
        R = dict(b["R"])
        L = dict(b["L"])
        R["w"] = (R["w"][0] * 0.9, R["w"][1], R["w"][2] - 0.07)
        L["w"] = (L["w"][0] * 0.9, L["w"][1], L["w"][2] - 0.07 if L["w"][2] > 0.4 else L["w"][2])
        mod(base, base + "_low", R=R, L=L, crouch=b["crouch"] + 0.03, lean=b["lean"] + 3,
            head=(b["head"][0] - 4, b["head"][1], b["head"][2]))
    # A boo: both arms thrust out toward the arena, fists turned down (thumbs down), leaning
    # in, head shaking; the loop pumps the arms down and back.
    arm = cc.arm
    P["boo_a"] = dict(lean=8, crouch=0.02, shift=0.012, head=(-4, 0, 18),
                      R=arm((0.15, -0.34, 0.47), (0.7, 0.4, -1.0), hand=(0.05, -0.35, -0.95),
                            shape="fist"),
                      L=arm((0.15, -0.33, 0.46), (0.7, 0.4, -1.0), hand=(0.05, -0.35, -0.95),
                            shape="fist"))
    P["boo_b"] = dict(lean=12, crouch=0.04, shift=-0.012, head=(-8, 0, -18),
                      R=arm((0.14, -0.3, 0.32), (0.7, 0.4, -1.0), hand=(0.05, -0.2, -1.0),
                            shape="fist"),
                      L=arm((0.14, -0.29, 0.31), (0.7, 0.4, -1.0), hand=(0.05, -0.2, -1.0),
                            shape="fist"))


def pose_plan(v):
    idle = v["poses"][0]
    if idle not in ("relaxed", "pockets", "crossed", "hips"):
        idle = "relaxed"
    clap = v["poses"][1] if v["poses"][1] in ("clap", "clap_high") else "clap"
    cheer = v["poses"][2] if v["poses"][2] in ("v_up", "straight_up", "fist_pump") else "v_up"
    flinch = v["poses"][3]
    return idle, clap, cheer, flinch


# ------------------------------------------------------------- mesh

def upd():
    bpy.context.view_layer.update()


def people_objects(rig):
    out = []
    for ob in bpy.data.objects:
        if ob.type != 'MESH':
            continue
        p = ob
        while p is not None and p != rig:
            p = p.parent
        if p == rig:
            out.append(ob)
    return out


def zone_of(ob):
    for m in ob.data.materials:
        if m is not None and m.name.split(".")[0] in MAT_ZONE:
            return MAT_ZONE[m.name.split(".")[0]]
    return 0


def flatten_piece(ob, rig, dg):
    """Modifiers (except the armature) baked into the mesh at rest pose; bone weights
    kept. Returns False when the piece is dropped."""
    low = ob.name.lower()
    if any(k in low for k in DROP):
        bpy.data.objects.remove(ob, do_unlink=True)
        return False
    arm_mods = [m for m in ob.modifiers if m.type == 'ARMATURE']
    for m in arm_mods:
        m.show_viewport = False
    upd()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), preserve_all_data_layers=True,
                                         depsgraph=dg)
    mw = ob.matrix_world.copy()
    names = [g.name for g in ob.vertex_groups]
    zone = zone_of(ob)
    bone_parent = ob.parent_bone if ob.parent_type == 'BONE' else ""
    ob.modifiers.clear()
    ob.data = me
    # vertex groups follow the mesh data by index; names stay on the object
    for m in list(me.materials):
        pass
    ob.parent = None
    ob.matrix_world = mw
    if bone_parent:
        vg = ob.vertex_groups.new(name=bone_parent)
        vg.add(list(range(len(me.vertices))), 1.0, 'REPLACE')
    za = me.attributes.new("zone", 'FLOAT', 'POINT')
    za.data.foreach_set("value", [float(zone)] * len(me.vertices))
    return True


def bake_colours(pieces):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 4
    sc.cycles.use_denoising = False
    for ob in pieces:
        me = ob.data
        if "bake_col" not in me.color_attributes:
            me.color_attributes.new("bake_col", 'FLOAT_COLOR', 'CORNER')
        me.color_attributes.active_color = me.color_attributes["bake_col"]
        bpy.ops.object.select_all(action='DESELECT')
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        try:
            bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'}, target='VERTEX_COLORS')
        except Exception as e:  # a piece with no material: flat grey
            print("[vat] bake failed on", ob.name, e)


SEGMENTS = (("thigh", "thigh"), ("calf", "calf"), ("foot", "foot"), ("ball", "foot"),
            ("toe", "foot"), ("upperarm", "uarm"), ("lowerarm", "larm"), ("hand", "hand"),
            ("thumb", "hand"), ("index", "hand"), ("middle", "hand"), ("ring", "hand"),
            ("pinky", "hand"), ("neck", "head"), ("head", "head"))


def segment_of(bone):
    """The rigid limb segment a bone belongs to (fingers ride the hand, the spine, pelvis
    and clavicles are one torso): joints are only where segments meet."""
    for key, seg in SEGMENTS:
        if key in bone:
            side = "_l" if bone.endswith("_l") else ("_r" if bone.endswith("_r") else "")
            return seg + side
    return "torso"


def dominant_bones(ob):
    """Per vertex: the limb segment of its heaviest bone weight."""
    me = ob.data
    names = [g.name for g in ob.vertex_groups]
    out = []
    for v in me.vertices:
        best, w = "", 0.0
        for g in v.groups:
            gname = names[g.group]
            if gname.startswith("HM_") or gname in ("dec_w", "body") or gname.startswith("Delete"):
                continue
            if g.weight > w:
                best, w = gname, g.weight
        out.append(segment_of(best) if best else "torso")
    return out


def joint_weights(ob):
    """Vertex group "dec_w" for the collapse: 0 on vertices where the dominant bone changes
    (knees, elbows, hips, shoulders, the neck), 1 elsewhere. The collapse keeps the joints,
    so no triangle spans a joint and nothing tears into a spike when a limb bends."""
    me = ob.data
    dom = dominant_bones(ob)
    edge_v = np.empty(len(me.edges) * 2, dtype=np.int64)
    me.edges.foreach_get("vertices", edge_v)
    edge_v = edge_v.reshape(-1, 2)
    joint = np.zeros(len(me.vertices), dtype=bool)
    d = np.array(dom)
    diff = d[edge_v[:, 0]] != d[edge_v[:, 1]]
    joint[edge_v[diff, 0]] = True
    joint[edge_v[diff, 1]] = True
    vg = ob.vertex_groups.get("dec_w") or ob.vertex_groups.new(name="dec_w")
    vg.add([int(i) for i in np.nonzero(~joint)[0]], 1.0, 'REPLACE')
    vg.add([int(i) for i in np.nonzero(joint)[0]], 0.15, 'REPLACE')


def join_and_decimate(pieces, rig, tris, height):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in pieces:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = pieces[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = "HM_person"
    # world transform into the mesh, then parent to the rig with an armature modifier
    ob.data.transform(ob.matrix_world)
    ob.matrix_world = Matrix.Identity(4)
    me = ob.data
    me.color_attributes.active_color = me.color_attributes["bake_col"]
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.geometry.color_attribute_convert(domain='POINT', data_type='FLOAT_COLOR')
    # merge coincident seams inside each piece (MakeHuman UV seams), then collapse
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.remove_doubles(threshold=0.0005)
    bpy.ops.mesh.quads_convert_to_tris()
    bpy.ops.object.mode_set(mode='OBJECT')
    now = len(me.polygons)
    if now > tris:
        joint_weights(ob)
        for _ in range(2):
            # Some garments (open fronts, tank tops) stop the collapse early: a second pass.
            if len(me.polygons) <= tris * 1.15:
                break
            d = ob.modifiers.new("dec", 'DECIMATE')
            d.decimate_type = 'COLLAPSE'
            d.ratio = tris / float(len(me.polygons))
            d.use_collapse_triangulate = True
            if not os.environ.get("CROWD_NOJOINT"):
                d.vertex_group = "dec_w"
                d.vertex_group_factor = 4.0
            bpy.ops.object.modifier_apply(modifier="dec")
    clean_skin(ob, height)
    add_phone_piece(ob, rig)
    for p in me.polygons:
        p.use_smooth = True
    a = ob.modifiers.new("arm", 'ARMATURE')
    a.object = rig
    return ob


def clean_skin(ob, height):
    """After the collapse the body pokes through the clothes: drop every skin face that
    sits behind (or within a centimetre of) a garment, and paint the head's skin one flat
    colour so no face is ever readable (and the lips do not become one red triangle)."""
    import bmesh
    from mathutils.bvhtree import BVHTree
    me = ob.data
    zone = np.empty(len(me.vertices))
    me.attributes["zone"].data.foreach_get("value", zone)
    zone = np.round(zone).astype(int)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    cloth_polys = []
    cloth_co = [v.co.copy() for v in bm.verts]
    for f in bm.faces:
        if all(zone[v.index] in (1, 2, 5, 6) for v in f.verts):
            cloth_polys.append([v.index for v in f.verts])
    tree = BVHTree.FromPolygons(cloth_co, cloth_polys) if cloth_polys else None
    doomed = []
    neck = 0.84 * height
    for f in bm.faces:
        if not all(zone[v.index] == 0 for v in f.verts):
            continue
        c = f.calc_center_median()
        if c.z > neck or tree is None:
            continue
        hit = tree.find_nearest(c, 0.05)
        if hit[0] is None:
            continue
        loc, nrm, _, dist = hit
        if dist < 0.012 or (c - loc).dot(nrm) < 0.0:
            doomed.append(f)
    bmesh.ops.delete(bm, geom=doomed, context='FACES')
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bm.to_mesh(me)
    bm.free()
    # flat head skin
    n = len(me.vertices)
    zone = np.empty(n)
    me.attributes["zone"].data.foreach_get("value", zone)
    co = np.empty(n * 3)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    ca = me.color_attributes["bake_col"]
    col = np.empty(n * 4)
    ca.data.foreach_get("color", col)
    col = col.reshape(-1, 4)
    head = (np.round(zone) == 0) & (co[:, 2] > neck)
    if head.any():
        skin = np.median(col[(np.round(zone) == 0)], axis=0)
        col[head] = skin
        # a touch darker under the brow line and at the back: reads as a head, not a mask
        col[head, :3] *= np.where(co[head, 2] > 0.93 * height, 0.92, 1.0)[:, None]
    # MakeHuman people are bare under an open jacket or a low neckline: a dark undershirt
    # on the torso's remaining skin (never the arms).
    torso = ((np.round(zone) == 0) & (co[:, 2] > 0.5 * height) & (co[:, 2] < neck - 0.03)
             & (np.abs(co[:, 0]) < 0.17))
    col[torso, :3] = np.array([0.018, 0.018, 0.02])
    zone[torso] = 2
    me.attributes["zone"].data.foreach_set("value", zone)
    ca.data.foreach_set("color", col.reshape(-1))
    print("[vat] skin faces dropped %d, head verts flattened %d" % (len(doomed), int(head.sum())))


def cluster_lod(pos0, idx, cell, zone=None):
    """A far LOD that needs no texture of its own: vertices are clustered on a grid (rest
    pose) and each cluster is represented by one of its OWN vertices, so the LOD's
    indices point into the same VAT columns. Degenerate and duplicate triangles go."""
    key = np.floor(pos0 / cell).astype(np.int64)
    if zone is not None:
        key = np.concatenate([key, np.asarray(zone, dtype=np.int64)[:, None]], axis=1)
    rep = {}
    remap = np.empty(len(pos0), dtype=np.int64)
    for i, k in enumerate(map(tuple, key)):
        if k not in rep:
            rep[k] = i
        remap[i] = rep[k]
    tri = remap[np.asarray(idx, dtype=np.int64).reshape(-1, 3)]
    ok = (tri[:, 0] != tri[:, 1]) & (tri[:, 1] != tri[:, 2]) & (tri[:, 0] != tri[:, 2])
    tri = tri[ok]
    seen = set()
    out = []
    for t in tri:
        k = tuple(sorted(t))
        if k in seen:
            continue
        seen.add(k)
        out.extend(int(x) for x in t)
    return out


def snapped_lod(ob, tris):
    """The far LOD without a texture of its own: a collapse-decimated copy of the person
    whose every vertex is snapped to the nearest vertex of the full mesh, so its triangles
    index the same VAT columns (well-shaped triangles, unlike grid clustering)."""
    from mathutils.kdtree import KDTree
    import bmesh
    me = ob.data
    zone = np.empty(len(me.vertices))
    me.attributes["zone"].data.foreach_get("value", zone)
    kd = KDTree(len(me.vertices))
    for v in me.vertices:
        if zone[v.index] < 6.5:    # never snap onto the phone
            kd.insert(v.co, v.index)
    kd.balance()
    cp = ob.copy()
    cp.data = me.copy()
    cp.modifiers.clear()
    bpy.context.scene.collection.objects.link(cp)
    # The far people carry no phone: drop it before the collapse, or it welds to the hand
    # and the hidden phone drags the hand's triangles away with it.
    bm = bmesh.new()
    bm.from_mesh(cp.data)
    zl = bm.verts.layers.float.get("zone")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v[zl] > 6.5], context='VERTS')
    bm.to_mesh(cp.data)
    bm.free()
    d = cp.modifiers.new("dec", 'DECIMATE')
    d.decimate_type = 'COLLAPSE'
    d.ratio = min(1.0, tris / float(max(1, len(me.polygons))))
    d.use_collapse_triangulate = True
    bpy.ops.object.select_all(action='DESELECT')
    cp.select_set(True)
    bpy.context.view_layer.objects.active = cp
    joint_weights(cp)
    d.vertex_group = "dec_w"
    d.vertex_group_factor = 2.0
    bpy.ops.object.modifier_apply(modifier="dec")
    bone = dominant_bones(ob)
    cp_bone = dominant_bones(cp)
    # Snap to the nearest full-mesh vertex that follows the SAME bone, or an arm vertex
    # snapped onto the hip stretches across the body as soon as the arm goes up.
    snap = []
    for v in cp.data.vertices:
        b = cp_bone[v.index]
        pick = None
        for (_, i, _) in kd.find_n(v.co, 24):
            if bone[i] == b:
                pick = i
                break
        snap.append(pick if pick is not None else kd.find(v.co)[1])
    out = []
    seen = set()
    for p in cp.data.polygons:
        vv = [snap[i] for i in p.vertices]
        for k in range(1, len(vv) - 1):
            t = (vv[0], vv[k], vv[k + 1])
            if len(set(t)) < 3 or tuple(sorted(t)) in seen:
                continue
            seen.add(tuple(sorted(t)))
            out.extend(int(x) for x in t)
    bpy.data.objects.remove(cp, do_unlink=True)
    return out


def add_phone_piece(ob, rig):
    """A phone in the right hand (zone 7): the game shows it only for the people filming,
    and only while their arms are up. Weighted to the hand, so it rides every clip."""
    import bmesh
    me = ob.data
    b = rig.data.bones["hand_r"]
    mw = rig.matrix_world @ b.matrix_local
    head = mw.translation
    yax = (mw.to_3x3() @ Vector((0, 1, 0))).normalized()
    zax = (mw.to_3x3() @ Vector((0, 0, 1))).normalized()
    xax = yax.cross(zax).normalized()
    centre = head + yax * 0.085 + zax * 0.02
    size = (0.075, 0.15, 0.012)
    bm = bmesh.new()
    bm.from_mesh(me)
    zl = bm.verts.layers.float.get("zone")
    cl = bm.verts.layers.float_color.get("bake_col")
    dl = bm.verts.layers.deform.verify()
    g = ob.vertex_groups.get("hand_r")
    if g is None:
        g = ob.vertex_groups.new(name="hand_r")
    corners = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                p = centre + xax * (sx * size[0] / 2) + yax * (sy * size[1] / 2) + zax * (sz * size[2] / 2)
                v = bm.verts.new(p)
                if zl is not None:
                    v[zl] = 7.0
                if cl is not None:
                    v[cl] = (0.02, 0.02, 0.025, 1.0)
                v[dl][g.index] = 1.0
                corners.append(v)
    c = corners
    for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
        face = bm.faces.new([c[i] for i in f])
        bmesh.ops.triangulate(bm, faces=[face])
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()


def sit_person(rig, arm_pose, seed, lean=4.0):
    """Seated on the tread's front edge: the person's origin is the seat; thighs forward,
    shins hanging over the step below."""
    ch.pose_person(rig, arm_pose, seed)
    pbs = rig.pose.bones
    bones = rig.data.bones
    hipc = (bones["thigh_l"].head_local + bones["thigh_r"].head_local) / 2
    drop = hipc.z - 0.13 / max(rig.matrix_world.to_scale().z, 1e-6)
    pl = pbs["pelvis"]
    pl.matrix = Matrix.Translation(Vector((0.0, 0.03, -drop))) @ pl.matrix
    ch.upd()
    for s in "lr":
        ch.aim(pbs["thigh_" + s], Vector((0.05 if s == "l" else -0.05, -1.0, 0.08)))
        ch.aim(pbs["calf_" + s], Vector((0.0, -0.2, -1.0)))
        ch.aim(pbs["foot_" + s], Vector((0.0, -1.0, -0.15)))
    for nm in ch.SPINE:
        pb = pbs[nm]
        ch.rot_about(pb, Matrix.Rotation(math.radians(lean) / 3.0, 3, 'X'),
                     pb.matrix.translation.copy())
        ch.upd()


# ------------------------------------------------------------- clips

def snapshot(rig):
    return {pb.name: pb.matrix_basis.copy() for pb in rig.pose.bones}


def apply_mix(rig, A, B, t):
    t = t * t * (3.0 - 2.0 * t)
    for pb in rig.pose.bones:
        la, ra, sa = A[pb.name].decompose()
        lb, rb, sb = B[pb.name].decompose()
        pb.matrix_basis = Matrix.LocRotScale(la.lerp(lb, t), ra.slerp(rb, t), sa.lerp(sb, t))


def clip_frames(keys, frames_per_seg, loop):
    """keys: pose snapshots. Returns a list of (A, B, t) samples."""
    out = []
    segs = len(keys) if loop else len(keys) - 1
    for s in range(segs):
        A = keys[s]
        B = keys[(s + 1) % len(keys)]
        n = frames_per_seg[s] if isinstance(frames_per_seg, list) else frames_per_seg
        for i in range(n):
            out.append((A, B, i / float(n)))
    if not loop:
        out.append((keys[-1], keys[-1], 0.0))
    return out


def evaluate(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    n = len(me.vertices)
    co = np.empty(n * 3, dtype=np.float64)
    me.vertices.foreach_get("co", co)
    nr = np.empty(n * 3, dtype=np.float64)
    me.vertices.foreach_get("normal", nr)
    ev.to_mesh_clear()
    co = co.reshape(-1, 3)
    nr = nr.reshape(-1, 3)
    # Blender (x, y, z), person facing -Y  ->  Godot (x, z, -y), facing +Z
    g = np.stack([co[:, 0], co[:, 2], -co[:, 1]], axis=1)
    gn = np.stack([nr[:, 0], nr[:, 2], -nr[:, 1]], axis=1)
    return g, gn


def main():
    opts = parse_args()
    t0 = time.time()
    cc.setup_card_scene(4)
    root = bpy.data.objects["Root"]
    derived_poses()
    vs = opts["variants"] if opts["variants"] is not None else list(range(len(ALL_VARIANTS)))
    people = []
    blocks = []
    clip_table = None
    for c in vs:
        v = ALL_VARIANTS[c]
        ch.clear_people()
        root.scale = (1, 1, 1)
        root.location = (0, 0, 0)
        root.rotation_euler = (0, 0, 0)
        rig, basemesh = ch.build_human(v, root)
        rig.data.pose_position = 'REST'
        upd()
        dg = bpy.context.evaluated_depsgraph_get()
        pieces = [ob for ob in people_objects(rig) if flatten_piece(ob, rig, dg)]
        print("[vat] %s pieces: %s" % (v["name"], [p.name for p in pieces]))
        bake_colours(pieces)
        # the rig's own scale (root) is in the pieces' world matrices now; the rig must
        # drive the flattened mesh in that same space
        person = join_and_decimate(pieces, rig, opts["tris"], v["h"])
        me = person.data
        lod1 = snapped_lod(person, opts["lod_tris"])
        rig.data.pose_position = 'POSE'
        # The mesh is in world space but the rig sits under the scaled Root: bind it by
        # parenting with the current transform kept.
        person.parent = rig
        person.matrix_parent_inverse = rig.matrix_world.inverted()
        upd()
        idle, clap, cheer, flinch = pose_plan(v)
        snaps = {}
        for name in (idle, idle + "_sway_a", idle + "_sway_b", clap, clap + "_open", cheer,
                     cheer + "_low", flinch, "boo_a", "boo_b"):
            ch.pose_person(rig, name, c)
            snaps[name] = snapshot(rig)
        for name, arms, lean in (("sit", "relaxed", 4.0), ("sit_b", "relaxed_sway_a", 7.0),
                                 ("sit_up", cheer, 0.0), ("sit_up_low", cheer + "_low", 5.0)):
            sit_person(rig, arms, c, lean)
            snaps[name] = snapshot(rig)
        S = snaps
        clips = [
            ("idle", clip_frames([S[idle], S[idle + "_sway_a"], S[idle], S[idle + "_sway_b"]],
                                 [4, 4, 4, 4], True), True),
            ("clap_in", clip_frames([S[idle], S[clap + "_open"]], 5, False), False),
            ("clap", clip_frames([S[clap], S[clap + "_open"]], [3, 3], True), True),
            ("raise", clip_frames([S[idle], S[cheer]], 6, False), False),
            ("cheer", clip_frames([S[cheer], S[cheer + "_low"]], [4, 4], True), True),
            ("flinch_in", clip_frames([S[idle], S[flinch]], 5, False), False),
            ("boo_in", clip_frames([S[idle], S["boo_a"]], 5, False), False),
            ("boo", clip_frames([S["boo_a"], S["boo_b"]], [4, 4], True), True),
            ("sit", clip_frames([S["sit"], S["sit_b"]], [6, 6], True), True),
            ("sit_raise", clip_frames([S["sit"], S["sit_up"]], 5, False), False),
            ("sit_cheer", clip_frames([S["sit_up"], S["sit_up_low"]], [3, 3], True), True),
        ]
        table = {}
        frames_pos = []
        frames_nrm = []
        row = 0
        for name, samples, loop in clips:
            table[name] = {"start": row, "count": len(samples), "loop": loop,
                           "step_s": CLIP_RATE[name]}
            for (A, B, t) in samples:
                apply_mix(rig, A, B, t)
                upd()
                p, n = evaluate(person)
                frames_pos.append(p)
                frames_nrm.append(n)
                row += 1
        if clip_table is None:
            clip_table = table
        # vertex data
        nv = len(me.vertices)
        col = np.ones((nv, 4), dtype=np.float64)
        if "bake_col" in me.color_attributes:
            ca = me.color_attributes["bake_col"]
            buf = np.empty(nv * 4, dtype=np.float64)
            ca.data.foreach_get("color", buf)
            col = buf.reshape(-1, 4)
        zone = np.zeros(nv)
        if "zone" in me.attributes:
            zb = np.empty(nv, dtype=np.float64)
            me.attributes["zone"].data.foreach_get("value", zb)
            zone = np.round(zb)
        # linear -> sRGB 8 bit
        srgb = np.where(col[:, :3] <= 0.0031308, col[:, :3] * 12.92,
                        1.055 * np.power(np.clip(col[:, :3], 0, None), 1 / 2.4) - 0.055)
        idx = []
        for p in me.polygons:
            vv = list(p.vertices)
            for k in range(1, len(vv) - 1):
                # Godot front faces are clockwise; the z flip mirrors handedness, keep order
                idx += [vv[0], vv[k], vv[k + 1]]
        pos = np.stack(frames_pos)          # F x V x 3

        nrm = np.stack(frames_nrm)
        blocks.append((pos, nrm))
        lo = pos.min(axis=(0, 1))
        hi = pos.max(axis=(0, 1))
        people.append({
            "name": v["name"], "height_m": v["h"], "verts": nv, "tris": len(idx) // 3,
            "indices": idx,
            "lod1": lod1, "lod1_tris": len(lod1) // 3,
            "colour": [int(x) for x in np.clip(np.round(srgb * 255), 0, 255).reshape(-1)],
            "zone": [int(z) for z in zone],
            "bounds": [lo.tolist(), hi.tolist()],
        })
        print("[vat] lod1 %d tris" % (len(lod1) // 3))
        print("[vat] %s verts %d tris %d frames %d bounds %s..%s %.1fs" % (
            v["name"], nv, len(idx) // 3, pos.shape[0], lo.round(2), hi.round(2), time.time() - t0))
    # texture: people packed side by side on shelves of 2F rows (positions, then normals),
    # so the texture holds only the columns people use.
    F = blocks[0][0].shape[0]
    W = TEX_W
    x = 0
    shelf = 0
    place = []
    for pos, nrm in blocks:
        n = pos.shape[1]
        if x + n > W:
            shelf += 1
            x = 0
        place.append((x, shelf * 2 * F))
        x += n
    img = np.zeros(((shelf + 1) * 2 * F, W, 3), dtype=np.uint8)
    for i, (pos, nrm) in enumerate(blocks):
        cx, base = place[i]
        n = pos.shape[1]
        people[i]["row"] = base
        people[i]["col"] = cx
        q = np.clip((pos - POS_MIN) / (POS_MAX - POS_MIN), 0, 1)
        qn = np.clip(nrm * 0.5 + 0.5, 0, 1)
        # All positions, then all normals: consecutive frames sit on consecutive rows,
        # which PNG's row filter compresses far better than interleaved rows.
        for f in range(F):
            img[base + f, cx:cx + n] = np.round(q[f] * 255)
            img[base + F + f, cx:cx + n] = np.round(qn[f] * 255)
    os.makedirs(OUT_DIR, exist_ok=True)
    png = os.path.join(OUT_DIR, "crowd_people_vat.png")
    cc.write_png(png, img.astype(np.float32) / 255.0)
    meta = {
        "fps": FPS, "frames": F, "width": W, "rows_per_person": F * 2, "layout": "shelves: per person col/row, F position rows then F normal rows",
        "pos_min": POS_MIN.tolist(), "pos_max": POS_MAX.tolist(),
        "clips": clip_table, "zones": ZONES,
        "people": people,
        "source": "Tools/blender/arena_kit/crowd_vat_human.py (MakeHuman/MPFB2, CC0 + CC-BY, "
                  "see docs/third-party-models.md)",
    }
    os.makedirs(os.path.join(HERE, "crowd_out"), exist_ok=True)
    with open(os.path.join(HERE, "crowd_out", "crowd_people.json"), "w") as fh:
        json.dump(meta, fh, separators=(",", ":"))
    for k, (kind, lic, au, src) in sorted(ch.USED.items()):
        print("[vat] asset %-10s %-50s %-6s %s" % (kind, k, lic, au))
    print("[vat] wrote %s (%dx%d) and crowd_people.json in %.1fs" % (
        png, W, img.shape[0], time.time() - t0))


if __name__ == "__main__":
    main()
