#!/usr/bin/env bash
# Rebuild every Roboteer texture set from the generated source images.
#
#   SRC=/path/to/sources Tools/textures/build_all.sh
#
# SRC defaults to Tools/textures/sources, which holds the eleven picked Recraft
# generations as LOSSLESS WebP (verified byte-identical to the PNGs they came
# from; WebP purely to keep the repo under its size budget). One image per
# material, plus arena_plate_2k (the crisp-upscaled 2048 arena floor) and
# chevron_grunge (a generated hazard stripe, used only for its wear).
# Keeping them means the whole set rebuilds without spending another credit.
# The exact Recraft prompt behind each is recorded in
# docs/graphics-textures-notes.md so any of them can be regenerated instead.
#
# Outputs land in Arena/assets/textures/<material>/.
#
# Every number below was arrived at by looking at the 2x2 preview, not by
# guessing. The three that matter most:
#   --flatten   how wide a lighting gradient to divide out. Small values kill
#               the generator's baked-in studio lighting, which is what makes a
#               tile show a repeating grid of light and dark patches. It must
#               stay well *below* the size of the real features: the tyre tread
#               blocks are ~60 px, so tyre_rubber flattens at 80, while the
#               featureless metals go as low as 11.
#   --equalise  evens out wear *density*. Flattening cannot see that one half of
#               a generated image is a thicket of scratches and the other half
#               is nearly clean, because the local mean is identical - only the
#               local contrast differs. Without it, both metals and the arena
#               floor showed a repeating band of busyness at every tile join.
#   --contrast  applied after flattening, to put back the local detail that
#               aggressive flattening takes out with the lighting.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/../.." && pwd)"
SRC="${SRC:-${HERE}/sources}"
OUT="${ROOT}/Arena/assets/textures"
PREVIEWS="${HERE}/previews"
# Previews live OUTSIDE the Godot project on purpose: anything under Arena/ is
# imported as a game texture and packed into arena.pck, and 11 review sheets was
# 10 MB of the shipped pack.
PBR="python3 ${HERE}/make_pbr.py --preview-dir ${PREVIEWS}"

if [ ! -d "${SRC}" ]; then
  echo "error: no source directory ${SRC} (set SRC=...)" >&2
  exit 1
fi
mkdir -p "${OUT}"

# Sources are .webp; accept .png too so a freshly generated image can be dropped
# in and built without converting it first.
src() {
  for ext in webp png; do
    if [ -f "${SRC}/$1.${ext}" ]; then echo "${SRC}/$1.${ext}"; return; fi
  done
  echo "error: no source image ${SRC}/$1.{webp,png}" >&2
  exit 1
}

# ---- bot materials -------------------------------------------------------

# Bare steel and titanium: wave A (materials lead) replaced the Recraft-derived sets,
# whose strong fine normals read as crumpled foil, with procedural FFT sets from
# make_masters.py (below, after the Recraft sets). Their sources stay in sources/ for
# history; they are no longer built.

# Moulded HDPE. Deliberately colourless and mid-light: the livery colour is a
# multiply on top of this, so any tint here would poison every livery, and any
# extra brightness would clip the pale liveries. See the notes for the code path.
${PBR} "$(src hdpe_moulded)" "${OUT}/hdpe_moulded" --name hdpe_moulded \
  --flatten 20 --seam-band 0.08 --contrast 1.9 --desaturate 1.0 --target-mean 0.72 \
  --normal-strength 1.7 --height-highpass 20 --normal-scale 0.5 \
  --rough-base 0.58 --rough-gain 0.14 --ao-strength 0.35 --metallic 0.0

# Polycarbonate. Light, low roughness, only the hairline scratches to see. The
# material resource makes it translucent; the texture stays nearly clear.
${PBR} "$(src polycarbonate)" "${OUT}/polycarbonate" --name polycarbonate \
  --flatten 26 --seam-band 0.08 --contrast 1.6 --desaturate 0.7 --target-mean 0.80 \
  --normal-strength 1.3 --height-highpass 22 --normal-scale 0.5 \
  --rough-base 0.08 --rough-gain 0.12 --ao-strength 0.25 --metallic 0.0

# Tyre rubber at 512: the darkest value in the scene, per the art direction.
# Negative rough-gain because tyre wear is dull, not shiny - the polished tread
# crowns are the smooth part and the torn grooves are the rough part.
${PBR} "$(src tyre_rubber)" "${OUT}/tyre_rubber" --name tyre_rubber \
  --size 512 --flatten 80 --seam-band 0.05 --contrast 1.25 --desaturate 0.85 --target-mean 0.10 \
  --normal-strength 4.5 --height-highpass 48 \
  --rough-base 0.86 --rough-gain -0.16 --ao-sigma 14 --ao-strength 0.7 --metallic 0.0

# ---- arena materials -----------------------------------------------------

# The arena floor, 2048 because it is the largest continuous surface on screen
# and the camera looks straight at it. Sigmas are doubled against the 1024 sets
# because they are in pixels.
${PBR} "$(src arena_plate_2k)" "${OUT}/arena_plate" --name arena_plate \
  --flatten 24 --equalise 0.80 --equalise-sigma 120 --seam-band 0.05 --contrast 1.5 \
  --desaturate 0.40 --target-mean 0.50 --tint 1.0,1.01,1.03 \
  --normal-strength 2.2 --height-highpass 34 \
  --normal-scale 0.5 --rough-base 0.38 --rough-gain 0.20 --rough-dirt 0.18 \
  --ao-sigma 20 --ao-strength 0.5 --metallic 1.0

# Hazard chevron: geometry drawn, wear generated. 2048x512 strip, exact 256 px
# period, so --no-seamless is correct - it already wraps and blending it would
# only soften the painted edges.
CHEV_ALBEDO="$(mktemp -t chevron_albedo).png"
python3 "${HERE}/make_chevron.py" "$(src chevron_grunge)" "${CHEV_ALBEDO}" \
  --width 2048 --height 512 --period 256
${PBR} "${CHEV_ALBEDO}" "${OUT}/chevron" --name chevron \
  --no-seamless --flatten 0 \
  --normal-strength 1.8 --height-highpass 12 --normal-scale 0.5 \
  --rough-base 0.62 --rough-gain 0.16 --rough-dirt 0.10 \
  --ao-sigma 8 --ao-strength 0.3 --metallic 0.0
rm -f "${CHEV_ALBEDO}"

# Dark concrete for the yard floor and the stage surround.
${PBR} "$(src concrete_dark)" "${OUT}/concrete_dark" --name concrete_dark \
  --flatten 34 --equalise 0.60 --equalise-sigma 100 --seam-band 0.09 --contrast 1.45 --desaturate 0.55 --target-mean 0.17 \
  --normal-strength 2.0 --height-highpass 22 --normal-scale 0.5 \
  --rough-base 0.82 --rough-gain 0.12 --rough-dirt 0.06 --ao-strength 0.6 --metallic 0.0

# ---- damage decals -------------------------------------------------------
# Recraft cannot return transparency, so these are generated as dark marks on
# white paper and the paper is keyed out here. They are Decal node textures:
# they must NOT tile, and their borders are faded to zero alpha so the decal
# box never shows as a rectangle.

# Scorch: soot. Forced to a near-black colour so it darkens a panel without
# changing its hue, which is exactly what the art direction asks damage to do.
${PBR} "$(src scorch)" "${OUT}/scorch" --name scorch --decal \
  --size 512 --decal-white 0.97 --decal-black 0.30 --decal-gamma 1.15 \
  --decal-colour 20,18,17 --decal-fade 0.05 \
  --normal-strength 0.6 --height-highpass 24 --rough-base 0.95 --rough-gain 0.04

# Three long gouges. Keeps its own grey so the torn metal reads, and a low
# roughness because a fresh gouge exposes bright bare metal.
${PBR} "$(src scratch_decal)" "${OUT}/scratch_decal" --name scratch_decal --decal \
  --decal-white 0.99 --decal-black 0.55 --decal-gamma 0.8 --decal-fade 0.04 \
  --normal-strength 3.5 --height-highpass 14 --normal-scale 0.5 --rough-base 0.30 --rough-gain 0.22

# Rust blooms, an alpha overlay. Keeps the orange brown.
${PBR} "$(src rust_spots)" "${OUT}/rust_spots" --name rust_spots --decal \
  --decal-white 0.96 --decal-black 0.45 --decal-gamma 1.3 --decal-fade 0.05 \
  --normal-strength 2.0 --height-highpass 18 --normal-scale 0.5 --rough-base 0.92 --rough-gain 0.06

# ---- Godot side ----------------------------------------------------------

# ---- wave A masters and decals (procedural, no sources) -------------------
python3 "${HERE}/make_masters.py" --preview-dir "${PREVIEWS}"
python3 "${HERE}/make_decals.py"

python3 "${HERE}/make_materials.py"

# Import once so the .import files exist, force mipmaps on (Godot defaults them
# off and only turns them on when the *editor* sees the texture used in 3D, so
# a headless build would otherwise ship an aliasing arena floor), then import
# again so the new flags take effect.
GODOT="${GODOT:-${HOME}/Applications/Godot.app/Contents/MacOS/Godot}"
if [ -x "${GODOT}" ]; then
  "${GODOT}" --headless --path "${ROOT}/Arena" --import >/dev/null 2>&1 || true
  python3 "${HERE}/set_import_flags.py"
  "${GODOT}" --headless --path "${ROOT}/Arena" --import >/dev/null 2>&1 || true
  echo ""
  "${GODOT}" --headless --path "${ROOT}/Arena" --script tests/_g2_material_probe.gd | tail -12
else
  echo "note: Godot not found at ${GODOT}; skipped import, flags and the probe" >&2
fi

echo ""
echo "done. sets in ${OUT}:"
du -sh "${OUT}"/* | sort -k2
