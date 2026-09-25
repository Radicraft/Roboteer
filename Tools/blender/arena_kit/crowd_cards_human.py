"""Roboteer arena kit: the HUMAN CROWD CARD ATLAS (MakeHuman / MPFB2 people).

A second crowd atlas, same layout and camera contract as crowd_cards.py,
but every person is a real MakeHuman body (MPFB2) wearing MakeHuman
community clothes, so the crowd reads as people rather than toys.

Run (regenerates every output):

    Blender -b --python Tools/blender/arena_kit/crowd_cards_human.py

Optional arguments after ``--``:

    --variants 0,3,7   only re-render these person variants (others are
                       re-used from the previous run's cell cache)
    --frames 0,2       only re-render these frames
    --samples 64       Cycles samples per cell (default 64)
    --sheet            also write a 2x debug sheet of the rendered cells
                       to the cell cache folder

Requirements
------------
* Blender 4.5 with the MPFB2 extension installed (Get Extensions, "MPFB").
* The MakeHuman asset packs unpacked into MPFB's user data folder
  (``~/Library/Application Support/Blender/4.5/extensions/.user/
  user_default/mpfb/data``), which is where MPFB's own "load pack"
  button puts them:
    - makehuman_system_assets_cc0.zip (skins, hair, eyes, eyebrows,
      eyelashes, shoes), from
      http://files.makehumancommunity.org/asset_packs/makehuman_system_assets/
    - the community packs hats03, pants01, pants02, shirts01, shirts02
      and skins02 from the same site (asset_packs/<name>/<name>_cc0.zip
      or _cc-by.zip).
  Every asset this script loads is checked against the pack's licence
  record (packs/*.json) AND the licence line in the asset's own file:
  only CC0 and CC-BY assets are accepted, anything else stops the run.
  The CC-BY authors are credited in docs/third-party-models.md.

What it builds
--------------
16 people.  Each is an MPFB human (macro sliders: sex, age, weight,
muscle, height, ethnic mix), the "game_engine" skeleton, a MakeHuman
skin texture, eyes, eyebrows, eyelashes, hair, clothes and shoes fitted
by MPFB (so they deform with the skeleton).  Clothes are re-tinted to
muted club-night colours: the garment's own texture is kept as a
luminance detail map (folds, knit, seams, denim wear) and multiplied by
the tint.  A hi-vis vest is a material zone on a sweater (torso fluoro
yellow with two reflective bands, sleeves dark); scarves and phones are
small modelled pieces.

Posing: bones are aimed directly in armature space (no constraints).
Arms and legs are solved with a two-bone analytic IK from wrist targets
given in the torso frame in units of body height (the same pose
vocabulary as crowd_cards.py: pockets, crossed, hips, clap, fists,
v_up, straight_up, fist_pump, phone, hands_head, cover_mouth, recoil,
cheeks).  Rows 0/1 are idle standing variations, row 2 CHEER (arms up,
five of the sixteen hold up a phone with a lit screen), row 3 FLINCH.

Each cell is rendered in Cycles with an ORTHOGRAPHIC camera 40 degrees
above horizontal, the same neutral soft three-light rig and transparent
film as crowd_cards.py (imported from it), 2x supersampled.

Outputs
-------
Arena/arena/kit/crowd/crowd_atlas_human.png       2048x1024 RGBA,
                                                  straight alpha, colour
                                                  dilated 8 px (then the
                                                  cell mean) into the
                                                  transparent area
Arena/arena/kit/crowd/crowd_atlas_human_emit.png  same layout, white =
                                                  phone screen glow
                                                  (CHEER row only)
Arena/arena/kit/crowd/crowd_atlas_human.json      layout description,
                                                  same keys as
                                                  crowd_atlas.json
docs/aaa/img/wave-a/kit/crowd-atlas-human-preview.png   sheet at 2x on a
                                                        dark background

Layout: 16 columns (variant c) x 4 rows (frame r: idle, bob, cheer,
flinch) of 128x256 cells.  120 px per metre everywhere, so the cell is
1.0667 m wide and 2.1333 m tall in the camera plane.  The feet contact
point sits at pixel (64, 234) of each cell (x from the left, y from the
top), i.e. 22 px = 0.1833 m above the bottom edge of the card.
"""

import glob
import importlib
import json
import math
import os
import sys
import tempfile
import time

import bpy
import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import crowd_cards as cc  # noqa: E402  (shared camera, lights, image I/O)

MPFB = importlib.import_module("bl_ext.user_default.mpfb")
from bl_ext.user_default.mpfb.services.humanservice import HumanService  # noqa: E402,E501
from bl_ext.user_default.mpfb.services.locationservice import LocationService  # noqa: E402,E501
from bl_ext.user_default.mpfb.services.targetservice import TargetService  # noqa: E402,E501

# ----------------------------------------------------------------- paths

REPO = cc.REPO
OUT_DIR = cc.OUT_DIR
PREV_DIR = cc.PREV_DIR
CACHE_DIR = os.path.join(tempfile.gettempdir(), "roboteer_crowd_cells_human")
DATA = LocationService.get_user_data()

COLS, ROWS = cc.COLS, cc.ROWS
CELL_W, CELL_H, SS = cc.CELL_W, cc.CELL_H, cc.SS
FRAMES = cc.FRAMES
CAM_ELEV = cc.CAM_ELEV
RIG = "game_engine"


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"variants": None, "frames": None, "samples": 64, "sheet": False}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--variants":
            opts["variants"] = [int(x) for x in argv[i + 1].split(",")]
            i += 1
        elif a == "--frames":
            opts["frames"] = [int(x) for x in argv[i + 1].split(",")]
            i += 1
        elif a == "--samples":
            opts["samples"] = int(argv[i + 1])
            i += 1
        elif a == "--sheet":
            opts["sheet"] = True
        i += 1
    return opts


# ------------------------------------------------------ asset licensing

OK_LICENCES = {"CC0", "CC-BY"}
_PACKS = {}
USED = {}          # asset name -> (kind, licence, author, source)


def _packs():
    if not _PACKS:
        for f in glob.glob(os.path.join(DATA, "packs", "*.json")):
            with open(f, encoding="utf-8") as fh:
                for k, v in json.load(fh).items():
                    _PACKS[k] = v
    return _PACKS


def _norm_licence(s):
    s = s.upper().replace("_", "-").replace(" ", "")
    if s.startswith("CC0"):
        return "CC0"
    if s.startswith("CC-BY") or s.startswith("CCBY"):
        return "CC-BY"
    return s


def _header_licence(path):
    """Licence named in the asset file's own comment header, or None."""
    lic = None
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            s = line.strip()
            low = s.lower()
            if "released as cc0" in low:
                return "CC0"
            if low.startswith("license") or low.startswith("# license"):
                lic = s.split(None, 2)[-1] if low.startswith("# ") \
                    else s.split(None, 1)[-1]
                lic = lic.lstrip(":").strip()
                return _norm_licence(lic)
    return lic


def asset(kind, name, ext=".mhclo"):
    """Absolute path of an installed MakeHuman asset, licence-checked."""
    folder = os.path.join(DATA, kind, name)
    files = sorted(glob.glob(os.path.join(folder, "*" + ext)))
    if not files:
        raise SystemExit("missing MakeHuman asset %s/%s: install the asset "
                         "packs listed in this script's header" % (kind, name))
    path = files[0]
    rec = _packs().get(name)
    if rec is None:
        raise SystemExit("asset %s has no pack licence record" % name)
    lic = _norm_licence(rec.get("license", ""))
    head = _header_licence(path)
    if lic not in OK_LICENCES or (head is not None and head != lic):
        raise SystemExit("asset %s licence not usable (pack %s, file %s)"
                         % (name, lic, head))
    USED[name] = (kind, lic, rec.get("author", ""), rec.get("source", ""))
    return path


def mhmat_texture(mhmat):
    with open(mhmat, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if line.startswith("diffuseTexture"):
                return os.path.join(os.path.dirname(mhmat),
                                    line.split(None, 1)[1].strip())
    return None


# ---------------------------------------------------------------- colours

def lin(c):
    return cc.lin(c)


C = {
    "charcoal": (0.19, 0.19, 0.21), "black": (0.075, 0.075, 0.085),
    "navy": (0.14, 0.17, 0.27), "marl": (0.50, 0.50, 0.51),
    "olive": (0.31, 0.32, 0.21), "burgundy": (0.38, 0.14, 0.16),
    "forest": (0.17, 0.27, 0.20), "rust": (0.52, 0.28, 0.16),
    "khaki": (0.52, 0.47, 0.35), "brown": (0.30, 0.22, 0.16),
    "stone": (0.62, 0.60, 0.55), "slate": (0.30, 0.34, 0.38),
    "plum": (0.33, 0.22, 0.30), "mustard": (0.62, 0.48, 0.18),
    "teal": (0.16, 0.30, 0.31), "denim": (0.25, 0.32, 0.44),
    "darkdenim": (0.15, 0.18, 0.26), "offwhite": (0.78, 0.76, 0.72),
    "camel": (0.56, 0.43, 0.29), "hivis": (0.80, 0.90, 0.16),
    "scarf_red": (0.50, 0.14, 0.12), "scarf_blue": (0.18, 0.24, 0.40),
    "scarf_green": (0.20, 0.36, 0.22),
}

HAIR = {
    "black": (0.05, 0.045, 0.04), "darkbrown": (0.13, 0.085, 0.06),
    "brown": (0.25, 0.16, 0.10), "auburn": (0.33, 0.15, 0.08),
    "blonde": (0.58, 0.46, 0.30), "grey": (0.52, 0.51, 0.50),
    "white": (0.72, 0.71, 0.69), "salt": (0.36, 0.34, 0.32),
}


def age_macro(years):
    """MakeHuman age slider: 0.1875 = 11 y, 0.5 = 25 y, 1.0 = 90 y."""
    if years <= 25:
        return 0.1875 + (years - 11) / 14.0 * 0.3125
    return 0.5 + (years - 25) / 65.0 * 0.5


def race(af, as_, ca):
    t = af + as_ + ca
    return {"african": af / t, "asian": as_ / t, "caucasian": ca / t}


# ------------------------------------------------------------- variants
# g = gender (0 female .. 1 male), age in years, w = weight, m = muscle,
# h = standing height in metres (the card is scaled to it), race mix,
# skin = MakeHuman skin, hair = (asset or None, colour), brows = eyebrow
# asset, top/bottom/hat = (asset, colour, detail) with detail = how much
# of the garment texture's light/dark survives (1 = all of it), keep =
# use the garment's own texture colours, scarf = colour name or None.

V = dict
VARIANTS = [
    V(name="hoodie_grey", g=1.0, age=24, w=0.5, m=0.55, h=1.80,
      race=race(0, 0, 1), skin="young_caucasian_male",
      hair=("short02", "brown"), brows="eyebrow001",
      top=("elvs_hooded_sweat_jacket1", "marl", 0.8),
      bottom=("punkduck_male_classic_jeans", "darkdenim", 1.0),
      shoes="shoes05", hat=None, scarf=None, phone=False, yaw=6,
      poses=["pockets", "clap", "v_up", "hands_head"]),
    V(name="cap_tee", g=1.0, age=31, w=0.55, m=0.5, h=1.76,
      race=race(0, 1, 0), skin="young_asian_male",
      hair=("short04", "black"), brows="eyebrow009",
      top=("elvs_male_logo_tshirt1", None, 1.0, "keep"),
      bottom=("elvs_jeans_straight_leg", "denim", 1.0),
      shoes="shoes06", hat=("mindfront_patrol_cap", "black", 0.6),
      scarf=None, phone=True, yaw=-8,
      poses=["relaxed", "clap", "phone", "cover_mouth"]),
    V(name="jacket_woman", g=0.0, age=27, w=0.45, m=0.45, h=1.66,
      race=race(1, 0, 0), skin="young_african_female",
      hair=("ponytail01", "black"), brows="eyebrow006",
      top=("elvs_male_shirt_untucked_bd1", "charcoal", 0.9),
      bottom=("punkduck_female_tight_jeans", "darkdenim", 1.0),
      shoes="shoes03", hat=None, scarf=None, phone=True, yaw=10,
      poses=["crossed", "clap_high", "phone", "cover_mouth"]),
    V(name="heavy_beard", g=1.0, age=44, w=1.0, m=0.6, h=1.82,
      race=race(0, 0, 1),
      skin="jartur69_middleage_slavic_male_with_genitals_and_beard",
      hair=("short04", "darkbrown"), brows="eyebrow010",
      top=("toigo_fisherman_sweater", "olive", 0.8),
      bottom=("cortu_cargo_pants", "charcoal", 0.9),
      shoes="shoes03", hat=None, scarf="scarf_red", phone=False, yaw=-4,
      poses=["crossed", "fists", "fist_pump", "hands_head"]),
    V(name="hivis", g=1.0, age=36, w=0.6, m=0.65, h=1.78,
      race=race(1, 0, 0.15), skin="middleage_african_male",
      hair=("short01", "black"), brows="eyebrow003",
      top=("mindfront_knitted_sweater_02", "navy", 0.6, "hivis"),
      bottom=("mindfront_male_trousers_1", "charcoal", 0.9),
      shoes="shoes03", hat=None, scarf=None, phone=False, yaw=-10,
      poses=["hips", "clap", "v_up", "recoil"]),
    V(name="beanie_woman", g=0.0, age=23, w=0.45, m=0.4, h=1.63,
      race=race(0, 0, 1), skin="toigo_light_skin_female_freckles",
      hair=("long01", "auburn"), brows="eyebrow002",
      top=("mindfront_knitted_sweater_01", "slate", 0.8),
      bottom=("punkduck_female_tight_jeans", "denim", 1.0),
      shoes="shoes05", hat=("mindfront_knitted_hat_01", "burgundy", 0.8),
      scarf=None, phone=False, yaw=8,
      poses=["pockets", "clap", "straight_up", "cheeks"]),
    V(name="teen_hood", g=0.9, age=17, w=0.4, m=0.45, h=1.70,
      race=race(0, 1, 0.2), skin="young_asian_male",
      hair=("short03", "black"), brows="eyebrow009",
      top=("elvs_hooded_sweat_jacket1", "black", 0.8),
      bottom=("elvs_jeans_straight_leg", "darkdenim", 1.0),
      shoes="shoes05", hat=None, scarf=None, phone=True, yaw=8,
      poses=["relaxed", "fists", "phone", "recoil"]),
    V(name="older_man", g=1.0, age=66, w=0.6, m=0.4, h=1.74,
      race=race(0, 0, 1), skin="old_caucasian_male",
      hair=("short04", "grey"), brows="eyebrow012",
      top=("mindfront_knitted_sweater_01", "navy", 0.8),
      bottom=("elvs_male_trouser", "brown", 0.9),
      shoes="shoes01", hat=("elvs_male_flat_cap1", "stone", 0.9),
      scarf=None, phone=False, yaw=-3,
      poses=["crossed", "clap", "fist_pump", "cover_mouth"]),
    V(name="pony_woman", g=0.0, age=33, w=0.5, m=0.5, h=1.70,
      race=race(0.1, 0.6, 0.3), skin="young_asian_female",
      hair=("ponytail01", "darkbrown"), brows="eyebrow004",
      top=("joepal_crude_t-shirt_female", "forest", 0.9),
      bottom=("punkduck_female_tight_jeans", "darkdenim", 1.0),
      shoes="shoes02", hat=None, scarf=None, phone=False, yaw=5,
      poses=["hips", "clap_high", "v_up", "hands_head"]),
    V(name="hood_olive", g=1.0, age=26, w=0.45, m=0.6, h=1.84,
      race=race(1, 0, 0), skin="young_african_male",
      hair=("short01", "black"), brows="eyebrow003",
      top=("elvs_hooded_sweat_jacket1", "olive", 0.8),
      bottom=("cortu_cargo_pants", "black", 0.9),
      shoes="shoes06", hat=None, scarf=None, phone=True, yaw=-5,
      poses=["pockets", "clap", "phone", "recoil"]),
    V(name="tall_rust", g=1.0, age=29, w=0.45, m=0.5, h=1.90,
      race=race(0, 0, 1), skin="toigo_light_skin_male_ginger",
      hair=("short02", "auburn"), brows="eyebrow005",
      top=("toigo_fisherman_sweater", "rust", 0.8),
      bottom=("punkduck_male_classic_jeans", "denim", 1.0),
      shoes="shoes02", hat=None, scarf=None, phone=False, yaw=7,
      poses=["relaxed", "clap", "straight_up", "hands_head"]),
    V(name="shorts_cap", g=1.0, age=22, w=0.55, m=0.6, h=1.77,
      race=race(0.3, 0, 0.7), skin="young_caucasian_male2",
      hair=("short01", "darkbrown"), brows="eyebrow007",
      top=("elvs_crude_t-shirt_male", "marl", 0.9),
      bottom=("cortu_jeans_shorts", "denim", 1.0),
      shoes="shoes05", hat=("mindfront_patrol_cap", "navy", 0.6),
      scarf=None, phone=False, yaw=-9,
      poses=["relaxed", "fists", "v_up", "cheeks"]),
    V(name="burgundy_jacket", g=0.0, age=41, w=0.55, m=0.45, h=1.68,
      race=race(0, 0, 1), skin="middleage_caucasian_female",
      hair=("bob01", "brown"), brows="eyebrow002",
      top=("elvs_male_shirt_untucked_bd1", "burgundy", 0.9),
      bottom=("mindfront_female_trousers_1", "black", 0.8),
      shoes="shoes03", hat=None, scarf=None, phone=True, yaw=6,
      poses=["crossed", "clap", "phone", "cover_mouth"]),
    V(name="heavy_hoodie", g=1.0, age=30, w=0.95, m=0.5, h=1.75,
      race=race(1, 0, 0), skin="mindfront_skin_male_african_middleage",
      hair=("afro01", "black"), brows="eyebrow003",
      top=("elvs_hooded_sweat_jacket1", "navy", 0.8),
      bottom=("cortu_cargo_pants", "khaki", 0.9),
      shoes="shoes06", hat=None, scarf=None, phone=False, yaw=-7,
      poses=["pockets", "fists", "fist_pump", "hands_head"]),
    V(name="scarf_tee", g=1.0, age=35, w=0.5, m=0.55, h=1.72,
      race=race(0.2, 0.5, 0.3), skin="middleage_asian_male",
      hair=("short04", "black"), brows="eyebrow011",
      top=("drednicolson_short-tail_camo_tee", "charcoal", 0.7),
      bottom=("elvs_jeans_straight_leg", "darkdenim", 1.0),
      shoes="shoes04", hat=None, scarf="scarf_blue", phone=False, yaw=9,
      poses=["relaxed", "clap", "v_up", "recoil"]),
    V(name="older_woman", g=0.0, age=62, w=0.6, m=0.4, h=1.58,
      race=race(0, 0, 1), skin="old_caucasian_female",
      hair=("bob02", "white"), brows="eyebrow002",
      top=("mindfront_knitted_sweater_02", "plum", 0.8),
      bottom=("mindfront_female_trousers_1", "charcoal", 0.8),
      shoes="shoes04", hat=None, scarf="scarf_green", phone=True, yaw=-7,
      poses=["crossed", "clap_high", "phone", "cheeks"]),
]

# ------------------------------------------------------------ materials


def _new_mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    return m, nt


_IMG_PX = {}


def _img(path):
    """(image, HxWx4 float pixel array) for a texture, cached."""
    img = bpy.data.images.load(path, check_existing=True)
    if path not in _IMG_PX:
        w, h = img.size
        px = np.empty(w * h * img.channels, dtype=np.float32)
        img.pixels.foreach_get(px)
        _IMG_PX[path] = px.reshape(h, w, img.channels)
    return img, _IMG_PX[path]


def uv_median_lum(ob, tex_path):
    """Median luminance of the texture where the garment's UVs actually
    sample it (so the flat UV-sheet background never counts)."""
    _, px = _img(tex_path)
    h, w = px.shape[:2]
    uvl = ob.data.uv_layers.active
    if uvl is None:
        return 0.5
    uv = np.empty(len(uvl.data) * 2, dtype=np.float32)
    uvl.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2) % 1.0
    x = np.clip((uv[:, 0] * w).astype(int), 0, w - 1)
    y = np.clip((uv[:, 1] * h).astype(int), 0, h - 1)
    lum = px[y, x, :3].astype(np.float64) @ np.array([0.2126, 0.7152, 0.0722])
    return float(np.median(lum))


def mhmat_normal(mhmat):
    with open(mhmat, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if line.startswith("normalmapTexture"):
                return os.path.join(os.path.dirname(mhmat),
                                    line.split(None, 1)[1].strip())
    return None


def tinted_mat(name, tex_path, tint, detail=0.8, rough=0.75, sheen=0.08,
               median=0.5, normal_path=None, use_alpha=False, nt_out=None):
    """Principled material: tint x (texture luminance / its median) ^
    detail, keeping the garment texture's folds, knit and wear but not its
    colour.  tint None = the texture's own colours.  Very dark source
    textures carry little real detail, so their detail is damped."""
    m, nt = _new_mat(name)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bs.inputs["Roughness"].default_value = rough
    bs.inputs["Sheen Weight"].default_value = sheen
    bs.inputs["Sheen Roughness"].default_value = 0.6
    nt.links.new(bs.outputs[0], out.inputs["Surface"])
    if normal_path and os.path.exists(normal_path):
        ntx = nt.nodes.new("ShaderNodeTexImage")
        ntx.image = bpy.data.images.load(normal_path, check_existing=True)
        ntx.image.colorspace_settings.name = 'Non-Color'
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = 0.7
        nt.links.new(ntx.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs[0], bs.inputs["Normal"])
    colour = None
    if tex_path and os.path.exists(tex_path):
        img, _ = _img(tex_path)
        tx = nt.nodes.new("ShaderNodeTexImage")
        tx.image = img
        tx.interpolation = 'Cubic'
        if use_alpha:
            nt.links.new(tx.outputs["Alpha"], bs.inputs["Alpha"])
        if tint is None:
            colour = tx.outputs["Color"]
        else:
            if median < 0.06:
                detail *= 0.35
            bw = nt.nodes.new("ShaderNodeRGBToBW")
            nt.links.new(tx.outputs["Color"], bw.inputs[0])
            dv = nt.nodes.new("ShaderNodeMath")
            dv.operation = 'DIVIDE'
            dv.inputs[1].default_value = max(median, 0.004)
            nt.links.new(bw.outputs[0], dv.inputs[0])
            pw = nt.nodes.new("ShaderNodeMath")
            pw.operation = 'POWER'
            pw.inputs[1].default_value = detail
            nt.links.new(dv.outputs[0], pw.inputs[0])
            cl = nt.nodes.new("ShaderNodeClamp")
            cl.inputs["Min"].default_value = 0.35
            cl.inputs["Max"].default_value = 1.5
            nt.links.new(pw.outputs[0], cl.inputs[0])
            mx = nt.nodes.new("ShaderNodeMix")
            mx.data_type = 'RGBA'
            mx.blend_type = 'MULTIPLY'
            mx.inputs["Factor"].default_value = 1.0
            mx.inputs[6].default_value = lin(tint)
            nt.links.new(cl.outputs[0], mx.inputs[7])
            colour = mx.outputs[2]
    if colour is None:
        bs.inputs["Base Color"].default_value = lin(tint or (0.5, 0.5, 0.5))
    elif nt_out is not None:
        nt_out(nt, colour, bs)
    else:
        nt.links.new(colour, bs.inputs["Base Color"])
    return m


def flat_mat(name, rgb, rough=0.6, emit=0.0):
    m, nt = _new_mat(name)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bs.inputs["Base Color"].default_value = lin(rgb)
    bs.inputs["Roughness"].default_value = rough
    if emit:
        bs.inputs["Emission Color"].default_value = lin(rgb)
        bs.inputs["Emission Strength"].default_value = emit
    nt.links.new(bs.outputs[0], out.inputs["Surface"])
    return m


def set_material(ob, mat):
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    for p in ob.data.polygons:
        p.material_index = 0


def skin_mat(basemesh, mhmat):
    """Soft, slightly subsurface skin from the MakeHuman skin texture."""
    tex = mhmat_texture(mhmat)
    m, nt = _new_mat("HM_skin_" + basemesh.name)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bs.inputs["Roughness"].default_value = 0.55
    bs.inputs["Subsurface Weight"].default_value = 0.12
    bs.inputs["Subsurface Radius"].default_value = (0.9, 0.35, 0.2)
    bs.inputs["Subsurface Scale"].default_value = 0.01
    tx = nt.nodes.new("ShaderNodeTexImage")
    tx.image = bpy.data.images.load(tex, check_existing=True)
    nt.links.new(tx.outputs["Color"], bs.inputs["Base Color"])
    nt.links.new(bs.outputs[0], out.inputs["Surface"])
    basemesh.data.materials.clear()
    basemesh.data.materials.append(m)
    for p in basemesh.data.polygons:
        p.material_index = 0
    return m


# ---------------------------------------------------------- human build


def rest_coords(ob):
    """Vertex positions with shape keys applied but no modifiers."""
    saved = [(md, md.show_viewport) for md in ob.modifiers]
    for md, _ in saved:
        md.show_viewport = False
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    co = np.empty(len(me.vertices) * 3, dtype=np.float32)
    me.vertices.foreach_get("co", co)
    ev.to_mesh_clear()
    for md, s in saved:
        md.show_viewport = s
    return co.reshape(-1, 3)


def add_clothes(basemesh, kind, name, subdiv=1):
    path = asset(kind, name)
    ob = HumanService.add_mhclo_asset(
        path, basemesh, asset_type=kind if kind != "clothes" else "Clothes",
        subdiv_levels=subdiv, material_type="MAKESKIN")
    mhmats = glob.glob(os.path.join(os.path.dirname(path), "*.mhmat"))
    tex = mhmat_texture(mhmats[0]) if mhmats else None
    nrm = mhmat_normal(mhmats[0]) if mhmats else None
    return ob, tex, nrm


def dress(ob, tex, nrm, tint, detail, rough=0.75, sheen=0.08, alpha=False,
          name="HM_cloth"):
    med = uv_median_lum(ob, tex) if tex else 0.5
    set_material(ob, tinted_mat(name, tex, tint, detail=detail, rough=rough,
                                sheen=sheen, median=med, normal_path=nrm,
                                use_alpha=alpha))


def hivis_dress(ob, tex, nrm, sleeve_tint, detail, rig, H):
    """A hi-vis vest over a dark sweater, as a material zone: torso fluoro
    yellow with two grey reflective bands, sleeves the sweater colour.
    The zone mask is a per-vertex attribute from the REST shape (arm-hole
    by distance from the spine line, bands by height), so its edges are
    interpolated smoothly across faces instead of stair-stepping."""
    co = rest_coords(ob)
    bones = rig.data.bones
    sh_x = abs(bones["upperarm_l"].head_local.x)
    z = co[:, 2] / H
    ax = np.abs(co[:, 0])
    # arm-hole: outside ~80% of the shoulder joint's x, or anything below
    # the armpit that is further out than the ribcage
    vest = ((ax < sh_x * 0.80) & (z > 0.47)).astype(np.float32)
    band = (((z > 0.585) & (z < 0.615)) | ((z > 0.665) & (z < 0.695))
            ).astype(np.float32)
    me = ob.data
    attr = me.color_attributes.new("hv", 'FLOAT_COLOR', 'POINT')
    cols = np.zeros((len(me.vertices), 4), dtype=np.float32)
    cols[:, 0] = vest
    cols[:, 1] = band
    cols[:, 3] = 1.0
    attr.data.foreach_set("color", cols.ravel())
    med = uv_median_lum(ob, tex)

    def zone(nt, colour, bs):
        at = nt.nodes.new("ShaderNodeAttribute")
        at.attribute_name = "hv"
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(at.outputs["Color"], sep.inputs[0])
        mr = nt.nodes.new("ShaderNodeMapRange")
        mr.inputs["From Min"].default_value = 0.42
        mr.inputs["From Max"].default_value = 0.58
        nt.links.new(sep.outputs[0], mr.inputs["Value"])
        mb = nt.nodes.new("ShaderNodeMapRange")
        mb.inputs["From Min"].default_value = 0.42
        mb.inputs["From Max"].default_value = 0.58
        nt.links.new(sep.outputs[1], mb.inputs["Value"])
        vestc = nt.nodes.new("ShaderNodeMix")
        vestc.data_type = 'RGBA'
        vestc.blend_type = 'MULTIPLY'
        vestc.inputs["Factor"].default_value = 1.0
        vestc.inputs[6].default_value = lin(C["hivis"])
        vestc.inputs[7].default_value = (1, 1, 1, 1)
        m1 = nt.nodes.new("ShaderNodeMix")
        m1.data_type = 'RGBA'
        nt.links.new(mr.outputs[0], m1.inputs["Factor"])
        nt.links.new(colour, m1.inputs[6])
        nt.links.new(vestc.outputs[2], m1.inputs[7])
        bandf = nt.nodes.new("ShaderNodeMath")
        bandf.operation = 'MULTIPLY'
        nt.links.new(mr.outputs[0], bandf.inputs[0])
        nt.links.new(mb.outputs[0], bandf.inputs[1])
        m2 = nt.nodes.new("ShaderNodeMix")
        m2.data_type = 'RGBA'
        nt.links.new(bandf.outputs[0], m2.inputs["Factor"])
        nt.links.new(m1.outputs[2], m2.inputs[6])
        m2.inputs[7].default_value = lin((0.60, 0.61, 0.60))
        nt.links.new(m2.outputs[2], bs.inputs["Base Color"])

    set_material(ob, tinted_mat("HM_hivis", tex, C[sleeve_tint],
                                detail=detail, median=med, normal_path=nrm,
                                nt_out=zone))


def hide_covered(basemesh, body_co, garments):
    """Mask the body under the clothes so skin never pokes through when
    the joints bend: every body vertex within 3 cm of a garment's rest
    surface and behind it (or within 6 mm of it) is hidden."""
    from mathutils.bvhtree import BVHTree
    for md in list(basemesh.modifiers):
        if md.type == 'MASK' and md.vertex_group.startswith("Delete."):
            basemesh.modifiers.remove(md)
    H = float(body_co[:, 2].max())
    hide = np.zeros(len(body_co), dtype=bool)
    # never mask the neck and upper chest: open collars and zips show it,
    # and a masked edge there reads as a jagged hole
    keep = ((body_co[:, 2] > 0.76 * H) & (np.abs(body_co[:, 0]) < 0.085)
            & (body_co[:, 1] < 0.02))
    for ob in garments:
        co = rest_coords(ob)
        polys = [tuple(p.vertices) for p in ob.data.polygons]
        tree = BVHTree.FromPolygons([Vector(c) for c in co], polys)
        for i, c in enumerate(body_co):
            if hide[i] or keep[i]:
                continue
            hit = tree.find_nearest(Vector(c), 0.03)
            if hit[0] is None:
                continue
            loc, nrm, _, dist = hit
            if dist < 0.006 or (Vector(c) - loc).dot(nrm) < 0:
                hide[i] = True
    vg = basemesh.vertex_groups.new(name="HM_covered")
    vg.add([int(i) for i in np.nonzero(hide)[0]], 1.0, 'REPLACE')
    md = basemesh.modifiers.new("HM hide covered", 'MASK')
    md.vertex_group = "HM_covered"
    md.invert_vertex_group = True
    return int(hide.sum())


def build_human(v, root):
    macro = TargetService.get_default_macro_info_dict()
    macro.update({"gender": v["g"], "age": age_macro(v["age"]),
                  "weight": v["w"], "muscle": v["m"],
                  "height": 0.5, "proportions": 0.6,
                  "cupsize": 0.5, "firmness": 0.5})
    macro["race"] = dict(v["race"])
    basemesh = HumanService.create_human(macro_detail_dict=macro,
                                         feet_on_ground=True, scale=0.1)
    basemesh.name = "HM_" + v["name"]
    rig = HumanService.add_builtin_rig(basemesh, RIG, import_weights=True)
    rig.name = "HM_rig_" + v["name"]
    # rest measures (armature space == world, rig unscaled at the origin)
    body_co = rest_coords(basemesh)
    body = basemesh.vertex_groups.get("body")
    in_body = np.zeros(len(body_co), dtype=bool)
    for vx in basemesh.data.vertices:
        for g in vx.groups:
            if g.group == body.index:
                in_body[vx.index] = True
    H = float(body_co[in_body, 2].max())
    # skin, eyes, brows, lashes, hair
    skin_mat(basemesh, asset("skins", v["skin"], ".mhmat"))
    HumanService.add_mhclo_asset(
        asset("eyes", "low-poly"), basemesh, asset_type="Eyes",
        subdiv_levels=0, material_type="PROCEDURAL_EYES")
    for kind, nm in (("eyebrows", v["brows"]),
                     ("eyelashes", "eyelashes02")):
        HumanService.add_mhclo_asset(
            asset(kind, nm), basemesh, asset_type=kind.capitalize(),
            subdiv_levels=0, material_type="MAKESKIN")
    if v["hair"][0]:
        ob, tex, nrm = add_clothes(basemesh, "hair", v["hair"][0], subdiv=0)
        dress(ob, tex, None, HAIR[v["hair"][1]], 0.9, rough=0.55, sheen=0.0,
              alpha=True, name="HM_hair")
    # clothes
    garments = []
    for slot in ("bottom", "top", "hat"):
        spec = v.get(slot)
        if not spec:
            continue
        ob, tex, nrm = add_clothes(basemesh, "clothes", spec[0])
        mode = spec[3] if len(spec) > 3 else None
        if mode == "hivis":
            hivis_dress(ob, tex, nrm, spec[1], spec[2], rig, H)
        elif mode == "keep":
            dress(ob, tex, nrm, None, 1.0, name="HM_" + slot)
        else:
            dress(ob, tex, nrm, C[spec[1]], spec[2], name="HM_" + slot)
        if slot != "hat":
            garments.append(ob)
    ob, tex, nrm = add_clothes(basemesh, "clothes", v["shoes"])
    dress(ob, tex, nrm, None, 1.0, rough=0.5, name="HM_shoes")
    garments.append(ob)
    # MPFB grounds the bare feet; the shoe soles sit below that, so lift
    # the person until the soles rest on the contact plane
    lift = max(0.0, -float(rest_coords(ob)[:, 2].min()))
    hide_covered(basemesh, body_co, garments)
    if v.get("scarf"):
        make_scarf(rig, H, C[v["scarf"]])
    rig.parent = root
    s = v["h"] / H
    root.scale = (s, s, s)
    root.location = (0.0, 0.0, lift * s)
    rig["H"] = H
    return rig, basemesh


def make_scarf(rig, H, rgb):
    """A knitted loop round the neck, bone-parented to neck_01."""
    import bmesh
    me = bpy.data.meshes.new("HM_scarf")
    ob = bpy.data.objects.new("HM_scarf", me)
    bpy.context.scene.collection.objects.link(ob)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=24, radius1=0.095,
                          radius2=0.078, depth=0.08)
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.026)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    me.materials.append(tinted_mat("HM_scarf", None, rgb, rough=0.9))
    nb = rig.data.bones["neck_01"]
    head = nb.head_local
    mw = Matrix.Translation(head + Vector((0, 0.006, 0.005)))
    ob.parent = rig
    ob.parent_type = 'BONE'
    ob.parent_bone = "neck_01"
    ob.matrix_world = rig.matrix_world @ mw
    return ob


def clear_people():
    for ob in list(bpy.data.objects):
        if ob.type in ('CAMERA', 'LIGHT') or ob.name == "Root":
            continue
        bpy.data.objects.remove(ob, do_unlink=True)
    bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True,
                           do_recursive=True)


# --------------------------------------------------------------- posing

SPINE = ["spine_01", "spine_02", "spine_03"]
FINGERS = ["index", "middle", "ring", "pinky"]


def upd():
    bpy.context.view_layer.update()


def rot_about(pb, R, pivot):
    pb.matrix = (Matrix.Translation(pivot) @ R.to_4x4()
                 @ Matrix.Translation(-pivot) @ pb.matrix)


def aim(pb, target_dir):
    cur = pb.matrix.to_3x3().col[1].normalized()
    q = cur.rotation_difference(Vector(target_dir).normalized())
    rot_about(pb, q.to_matrix(), pb.matrix.translation.copy())
    upd()


def solve2(a, t, l1, l2, pole):
    d = t - a
    dist = d.length
    dist = min(max(dist, abs(l1 - l2) + 1e-3), (l1 + l2) * 0.998)
    u = d.normalized()
    x = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(l1 * l1 - x * x, 0.0))
    p = Vector(pole) - u * Vector(pole).dot(u)
    if p.length < 1e-6:
        p = Vector((0, 1, 0)) - u * u.y
    return a + u * x + p.normalized() * h, a + u * dist


def reset_pose(rig):
    for pb in rig.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
        pb.scale = (1, 1, 1)
    upd()


def pose_person(rig, pose_name, seed):
    P = cc.POSES[pose_name]
    H = rig["H"]
    pbs = rig.pose.bones
    reset_pose(rig)
    bones = rig.data.bones
    hipc = (bones["thigh_l"].head_local + bones["thigh_r"].head_local) / 2
    ankle = {}
    for s in "lr":
        a = bones["foot_" + s].head_local.copy()
        # MakeHuman's rest stance is wide: bring the feet in to a natural
        # standing width (about 0.13 H between the ankles)
        a.x = math.copysign(max(abs(a.x) * 0.55, 0.065 * H), a.x)
        ankle[s] = a
    foot_dir = {s: (bones["foot_" + s].tail_local
                    - bones["foot_" + s].head_local) for s in "lr"}
    # pelvis: crouch + weight shift
    pl = pbs["pelvis"]
    shift = Vector((P["shift"] * H, 0.0, -P["crouch"] * H))
    pl.matrix = Matrix.Translation(shift) @ pl.matrix
    upd()
    # legs: two-bone IK to keep each ankle planted
    for s in "lr":
        th, ca = pbs["thigh_" + s], pbs["calf_" + s]
        l1 = bones["thigh_" + s].length
        l2 = bones["calf_" + s].length
        a = th.matrix.translation.copy()
        knee, _ = solve2(a, ankle[s], l1, l2, (0, -1, 0))
        aim(th, knee - a)
        aim(ca, ankle[s] - ca.matrix.translation)
        aim(pbs["foot_" + s], foot_dir[s])
    # spine lean (+ = forward, toward -Y) spread over three bones
    lean = math.radians(P["lean"])
    for nm in SPINE:
        pb = pbs[nm]
        rot_about(pb, Matrix.Rotation(lean / 3.0, 3, 'X'),
                  pb.matrix.translation.copy())
        upd()
    # head: (pitch up +, roll, yaw)
    hp, hr, hy = P["head"]
    if hp < 0:
        hp *= 0.3      # keep faces toward the camera: only a slight nod
    hp += 7.0          # and lift the chin: they watch the pit below the
    #                    camera, so faces tip up toward it
    for nm, f in (("neck_01", 0.4), ("head", 0.6)):
        pb = pbs[nm]
        R = (Matrix.Rotation(math.radians(hy * f), 3, 'Z')
             @ Matrix.Rotation(math.radians(-hp * f), 3, 'X')
             @ Matrix.Rotation(math.radians(hr * f), 3, 'Y'))
        rot_about(pb, R, pb.matrix.translation.copy())
        upd()
    # arms: wrist targets in the torso frame (units of H, from hipc)
    Rl = Matrix.Rotation(lean, 3, 'X')
    for side, s, sx in (("R", "r", -1.0), ("L", "l", 1.0)):
        spec = P[side]
        w = spec["w"]
        tgt = hipc + shift + Rl @ (Vector((sx * w[0], w[1], w[2])) * H)
        pole = Rl @ Vector((sx * spec["pole"][0], spec["pole"][1],
                            spec["pole"][2]))
        cl = pbs["clavicle_" + s]
        ua, la, hd = pbs["upperarm_" + s], pbs["lowerarm_" + s], \
            pbs["hand_" + s]
        # shrug the clavicle when the hand goes above the shoulder
        sh = ua.matrix.translation
        rise = (tgt.z - sh.z) / H
        if rise > 0.05:
            ang = min(rise * 90.0, 22.0)
            rot_about(cl, Matrix.Rotation(math.radians(ang) * sx, 3, 'Y'),
                      cl.matrix.translation.copy())
            upd()
        a = ua.matrix.translation.copy()
        l1 = bones["upperarm_" + s].length
        l2 = bones["lowerarm_" + s].length
        elbow, wrist = solve2(a, tgt, l1, l2, pole)
        aim(ua, elbow - a)
        aim(la, wrist - la.matrix.translation)
        hdir = spec["hand"]
        if hdir is not None:
            aim(hd, Rl @ Vector((sx * hdir[0], hdir[1], hdir[2])))
        else:
            aim(hd, wrist - elbow)
        # fingers
        shape = spec["shape"]
        curl = {"fist": 80, "phone": 55, "pocket": 60,
                "open": 12}.get(shape, 12)
        for fn in FINGERS:
            for k in (1, 2, 3):
                pb = pbs["%s_%02d_%s" % (fn, k, s)]
                pb.rotation_quaternion = Matrix.Rotation(
                    math.radians(curl), 3, 'X').to_quaternion()
        th = pbs["thumb_02_" + s]
        th.rotation_quaternion = Matrix.Rotation(
            math.radians(curl * 0.4), 3, 'X').to_quaternion()
    upd()


def hand_frame(rig, s):
    pb = rig.pose.bones["hand_" + s]
    mw = rig.matrix_world @ pb.matrix
    wrist = mw.translation.copy()
    hd = (mw.to_3x3().col[1]).normalized()
    return wrist, hd


def add_phone(rig, s, h_m):
    import bmesh
    wrist, hd = hand_frame(rig, s)
    to_cam = Vector((0, -math.cos(CAM_ELEV), math.sin(CAM_ELEV)))
    up = (hd - to_cam * hd.dot(to_cam)).normalized()
    xax = up.cross(to_cam).normalized()
    m = Matrix((xax, up, to_cam)).transposed()
    centre = wrist + hd * 0.085 + to_cam * 0.03
    screens, objs = [], []
    for kind, size, off in (("body", (0.075, 0.155, 0.009), 0.0),
                            ("screen", (0.067, 0.145, 0.001), 0.0052)):
        me = bpy.data.meshes.new("HMphone_" + kind)
        ob = bpy.data.objects.new("HMphone_" + kind, me)
        bpy.context.scene.collection.objects.link(ob)
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bm.to_mesh(me)
        bm.free()
        ob.matrix_world = (Matrix.Translation(centre + to_cam * off)
                           @ m.to_4x4() @ Matrix.Diagonal(size + (1,)))
        if kind == "body":
            me.materials.append(flat_mat("HM_phone", (0.05, 0.05, 0.06),
                                         rough=0.3))
        else:
            me.materials.append(cc.screen_mat(6.0))
            screens.append(ob)
        objs.append(ob)
    return objs, screens


# --------------------------------------------------------------- render


def cell_path(c, r, kind="col"):
    return os.path.join(CACHE_DIR, "%s_%02d_%d.png" % (kind, c, r))


def render_emit(sc, screens, emit_file):
    blk = cc.black_mat()
    saved = []
    for ob in sc.objects:
        if ob.type != 'MESH' or ob in screens:
            continue
        saved.append((ob.data, list(ob.data.materials)))
        for i in range(len(ob.data.materials)):
            ob.data.materials[i] = blk
    wstr = sc.world.node_tree.nodes["Background"].inputs["Strength"]
    old = wstr.default_value
    wstr.default_value = 0.0
    hidden = [ob for ob in sc.objects if ob.type == 'LIGHT']
    for ob in hidden:
        ob.hide_render = True
    sc.render.filepath = emit_file
    bpy.ops.render.render(write_still=True)
    for ob in hidden:
        ob.hide_render = False
    wstr.default_value = old
    for data, mlist in saved:
        for i, m in enumerate(mlist):
            data.materials[i] = m


def render_cells(opts):
    root = cc.setup_card_scene(opts["samples"])
    sc = bpy.context.scene
    sc.cycles.max_bounces = 6
    sc.cycles.transparent_max_bounces = 16
    vs = opts["variants"] if opts["variants"] is not None else range(COLS)
    fs = opts["frames"] if opts["frames"] is not None else range(ROWS)
    os.makedirs(CACHE_DIR, exist_ok=True)
    t0 = time.time()
    for c in vs:
        v = VARIANTS[c]
        clear_people()
        root.scale = (1, 1, 1)
        root.location = (0, 0, 0)
        root.rotation_euler = (0, 0, 0)
        rig, basemesh = build_human(v, root)
        root.rotation_euler = (0, 0, math.radians(v.get("yaw", 0)))
        print("[human] built %s %.1fs" % (v["name"], time.time() - t0))
        for r in fs:
            for ob in list(bpy.data.objects):
                if ob.name.startswith("HMphone"):
                    bpy.data.objects.remove(ob, do_unlink=True)
            pose = v["poses"][r]
            pose_person(rig, pose, c * 7 + r)
            screens = []
            if pose == "phone":
                _, screens = add_phone(rig, "r", v["h"])
            sc.render.filepath = cell_path(c, r)
            bpy.ops.render.render(write_still=True)
            emit_file = cell_path(c, r, "emit")
            if screens:
                render_emit(sc, screens, emit_file)
            elif os.path.exists(emit_file):
                os.remove(emit_file)
            print("[human] cell %d/%d (%s %s) %.1fs" % (
                c, r, v["name"], FRAMES[r], time.time() - t0))
    return time.time() - t0


def assemble():
    atlas = np.zeros((ROWS * CELL_H, COLS * CELL_W, 4), dtype=np.float32)
    emit = np.zeros((ROWS * CELL_H, COLS * CELL_W), dtype=np.float32)
    report = []
    for c in range(COLS):
        for r in range(ROWS):
            p = cell_path(c, r)
            if not os.path.exists(p):
                raise SystemExit("missing cell %s: run without --variants"
                                 % p)
            cell = cc.downsample(cc.load_png(p), SS)
            ys, xs = np.nonzero(cell[:, :, 3] > 0.02)
            report.append((c, r, xs.min(), xs.max(), ys.min(), ys.max()))
            cell = cc.dilate_cell(cell, cc.DILATE_PX)
            atlas[r * CELL_H:(r + 1) * CELL_H,
                  c * CELL_W:(c + 1) * CELL_W] = cell
            ep = cell_path(c, r, "emit")
            if os.path.exists(ep):
                e = cc.load_png(ep)
                lum = e[:, :, :3].max(axis=2) * e[:, :, 3]
                lum = lum.reshape(CELL_H, SS, CELL_W, SS).mean(axis=(1, 3))
                emit[r * CELL_H:(r + 1) * CELL_H,
                     c * CELL_W:(c + 1) * CELL_W] = np.clip(lum * 1.2, 0, 1)
    os.makedirs(OUT_DIR, exist_ok=True)
    cc.write_png(os.path.join(OUT_DIR, "crowd_atlas_human.png"), atlas)
    cc.write_png(os.path.join(OUT_DIR, "crowd_atlas_human_emit.png"), emit)
    meta = {
        "cols": COLS, "rows": ROWS, "cell": [CELL_W, CELL_H],
        "world_height_m": round(cc.WORLD_H, 4),
        "world_width_m": round(cc.WORLD_W, 4),
        "px_per_m": cc.PX_PER_M,
        "anchor_px": list(cc.ANCHOR_PX),
        "anchor_note": "feet contact point in each cell, pixels from the "
                       "cell's top-left; 22 px (0.1833 m) above the card's "
                       "bottom edge",
        "camera": "orthographic, 40 deg above horizontal, facing the person",
        "alpha": "straight (not premultiplied); colour dilated into the "
                 "transparent area",
        "frames": FRAMES,
        "emit": "crowd_atlas_human_emit.png: white = phone screen "
                "(cheer row)",
        "variants": [{"name": v["name"], "height_m": v["h"],
                      "phone": v["phone"], "poses": v["poses"]}
                     for v in VARIANTS],
    }
    with open(os.path.join(OUT_DIR, "crowd_atlas_human.json"), "w") as f:
        json.dump(meta, f, indent=2)
        f.write("\n")
    for c, r, x0, x1, y0, y1 in report:
        flag = ""
        if x0 < 1 or x1 > CELL_W - 2 or y0 < 1 or y1 > CELL_H - 4:
            flag = "  <-- touches the edge"
        print("[human] bbox %2d/%d x %3d..%3d y %3d..%3d%s" % (
            c, r, x0, x1, y0, y1, flag))
    return atlas, emit


def write_preview(atlas, emit):
    """The whole sheet at 2x on the dark venue grey."""
    dark = np.array([0.075, 0.07, 0.07], dtype=np.float32)
    base = cc.over(np.broadcast_to(dark, atlas.shape[:2] + (3,)), atlas)
    base = np.clip(base + emit[:, :, None] * 0.35, 0, 1)
    big = cc.upscale_nn(base, 2)
    pad = 32
    canvas = np.empty((big.shape[0] + 2 * pad, big.shape[1] + 2 * pad, 3),
                      dtype=np.float32)
    canvas[:] = dark
    canvas[pad:pad + big.shape[0], pad:pad + big.shape[1]] = big
    cc.write_png(os.path.join(PREV_DIR, "crowd-atlas-human-preview.png"),
                 canvas)


def main():
    opts = parse_args()
    t = render_cells(opts)
    print("[human] cells rendered in %.1fs" % t)
    atlas, emit = assemble() if opts["variants"] is None or all(
        os.path.exists(cell_path(c, r)) for c in range(COLS)
        for r in range(ROWS)) else (None, None)
    if atlas is not None:
        write_preview(atlas, emit)
        if opts["sheet"]:
            cc.write_png(os.path.join(CACHE_DIR, "sheet.png"),
                         cc.over(np.array([0.24, 0.245, 0.26],
                                          dtype=np.float32), atlas))
    print("[human] assets used:")
    for k, (kind, lic, au, src) in sorted(USED.items()):
        print("[human]   %-10s %-50s %-6s %s %s" % (kind, k, lic, au, src))
    print("[human] done in %.1fs" % t)


if __name__ == "__main__":
    main()
