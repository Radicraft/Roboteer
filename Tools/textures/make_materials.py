#!/usr/bin/env python3
"""make_materials.py - write the StandardMaterial3D .tres resources.

One resource per tiling texture set, in Arena/assets/materials/. Kept as a
generator rather than eight hand-written files so that a change to the shared
shape of the resource (a channel, a flag, a filter) is made once.

The .tres files it writes are plain text and are the real deliverable; this
script only has to be re-run when the material parameters change.

Notes on the flags that are easy to get wrong in Godot 4:
  - normal_enabled and ao_enabled must be set explicitly. A normal_texture on a
    material with normal_enabled unset is silently ignored.
  - roughness / metallic are scalars that MULTIPLY their texture, so they are
    set to 1.0 wherever a texture drives the channel, not to the base value.
  - *_texture_channel = 0 means red. The maps here are single-channel greyscale
    PNGs, so red is correct for all of them.
"""

from __future__ import annotations

import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TEX = os.path.join(ROOT, "Arena", "assets", "textures")
MAT = os.path.join(ROOT, "Arena", "assets", "materials")

# Anti-sparkle, required by G1 and asserted by Arena/tests/render_test.gd.
#
# texture_filter 5 = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC. Every one of
# these materials is on a surface the camera sees at a grazing angle - the arena floor
# most of all - which is exactly the case trilinear filtering blurs and anisotropic
# filtering does not. project.godot sets the level (4x); this opts the material in.
#
# normal_scale 0.5 on the METALLIC materials only. A strong normal on a metallic 1.0
# surface sparkles with white speckles at phone screen footprints (G1 measured it), and
# halving the normal is the material-side half of that fix. It is deliberately NOT
# applied to the plastics and rubber, which are not metallic, do not sparkle, and would
# just lose their moulding relief.
ANISOTROPIC = 5
ANTI_SPARKLE_NORMAL_SCALE = 0.5

# name -> (uv1_scale, extra resource lines)
MATERIALS = {
    # Bare steel: fully metallic, the roughness map carries the brush grain.
    "brushed_steel": ((2, 2, 1), []),
    # Titanium: also fully metallic, darker and busier so the two never merge.
    "scratched_titanium": ((2, 2, 1), []),
    # HDPE: albedo_color stays pure white so Bot._panel_material can assign the
    # livery straight into albedo_color and have it multiply this neutral grey
    # texture. Any tint baked here would poison every livery in the game.
    "hdpe_moulded": ((2, 2, 1), []),
    # Polycarbonate: translucent smoked panel, alpha 0.6 as specified.
    "polycarbonate": (
        (1, 1, 1),
        [
            "transparency = 1",
            "albedo_color = Color(1, 1, 1, 0.6)",
            "cull_mode = 2",
        ],
    ),
    # Tyre rubber: the darkest value in the scene.
    "tyre_rubber": ((2, 2, 1), []),
    # Arena floor: explicit 4x tile, triplanar deliberately OFF - the floor is a
    # single flat plane with proper UVs, and triplanar would cost a three-tap
    # sample per map for nothing.
    "arena_plate": (
        (4, 4, 1),
        ["uv1_triplanar = false"],
    ),
    # Hazard chevron: a 2048x512 strip. uv1_scale stays 1 so the mesh that uses
    # it decides how many times the stripe repeats along the wall.
    "chevron": ((1, 1, 1), []),
    "concrete_dark": ((4, 4, 1), []),
}

# name -> (metallic, has_ao, has_metallic_map)
ROLES = {
    "brushed_steel": (1.0, True, True),
    "scratched_titanium": (1.0, True, True),
    "hdpe_moulded": (0.0, True, True),
    "polycarbonate": (0.0, True, True),
    "tyre_rubber": (0.0, True, True),
    "arena_plate": (1.0, True, True),
    "chevron": (0.0, True, True),
    "concrete_dark": (0.0, True, True),
}


def write_material(name: str) -> str:
    uv, extra = MATERIALS[name]
    metallic, has_ao, has_metal_map = ROLES[name]

    maps = [("albedo", "albedo_texture"), ("normal", "normal_texture"),
            ("roughness", "roughness_texture")]
    if has_metal_map:
        maps.append(("metallic", "metallic_texture"))
    if has_ao:
        maps.append(("ao", "ao_texture"))

    present = []
    for suffix, prop in maps:
        rel = f"assets/textures/{name}/{name}_{suffix}.png"
        if not os.path.exists(os.path.join(ROOT, "Arena", rel)):
            raise SystemExit(f"missing texture: {rel}")
        present.append((suffix, prop, f"res://{rel}"))

    lines = [f'[gd_resource type="StandardMaterial3D" load_steps={len(present) + 1} format=3]', ""]
    for i, (suffix, _prop, path) in enumerate(present, start=1):
        lines.append(f'[ext_resource type="Texture2D" path="{path}" id="{i}_{suffix}"]')
    lines += ["", "[resource]", f'resource_name = "{name}"']

    for i, (suffix, prop, _path) in enumerate(present, start=1):
        if suffix == "normal":
            lines.append("normal_enabled = true")
        if suffix == "ao":
            lines += ["ao_enabled = true", "ao_texture_channel = 0"]
        if suffix == "roughness":
            lines += ["roughness = 1.0", "roughness_texture_channel = 0"]
        if suffix == "metallic":
            lines += [f"metallic = {metallic}", "metallic_texture_channel = 0"]
        lines.append(f'{prop} = ExtResource("{i}_{suffix}")')

    if not has_metal_map:
        lines.append(f"metallic = {metallic}")
    lines.append(f"uv1_scale = Vector3({uv[0]}, {uv[1]}, {uv[2]})")
    lines.append(f"texture_filter = {ANISOTROPIC}")
    if metallic > 0.0:
        lines.append(f"normal_scale = {ANTI_SPARKLE_NORMAL_SCALE}")
    lines += extra
    lines.append("")

    out = os.path.join(MAT, f"{name}.tres")
    with open(out, "w") as fh:
        fh.write("\n".join(lines))
    return out


def main() -> int:
    os.makedirs(MAT, exist_ok=True)
    for name in MATERIALS:
        print("wrote", os.path.relpath(write_material(name), ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
