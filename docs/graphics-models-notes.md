# Graphics: models (agent G3)

Thirty Blender-generated parts in `Arena/assets/parts/`, built by Python in `Tools/blender/`.
Nothing here is hand-modelled, so every part is reproducible, diffable and tweakable by changing a
number. Scope per `docs/graphics-bar.md`: `Tools/blender/**`, `Arena/assets/parts/**`, this file, and
`Arena/tests/_g3_import_probe.gd`.

## 1. How to run it

```bash
# generate every part (about 4 seconds, writes Arena/assets/parts/**)
~/Applications/Blender.app/Contents/MacOS/Blender -b --python Tools/blender/build_parts.py

# one part, or a few
~/Applications/Blender.app/Contents/MacOS/Blender -b --python Tools/blender/build_parts.py -- \
    --only wedge,flipper,wheel_standard

# check the exported files without opening Blender (reads the .glb bytes back)
python3 Tools/blender/verify_parts.py

# make Godot import them, then check they load, in Godot, as a scene
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path Arena --import
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path Arena --script tests/_g3_import_probe.gd
```

`build_parts.py --only ...` rewrites only those parts and merges their entries into the existing
`manifest.json`, so a single-part iteration loop is a couple of seconds. Blender writes nothing outside
`Arena/assets/parts/`; there are no `.blend` files and no temp files to clean up.

Files:

| file | what it is |
|---|---|
| `Tools/blender/rkit.py` | the toolkit: Bot space, the axis matrix, the eight materials, the `Part` builder (box, prism, cone, cylinder, ring, band, slab, plate, bolt, weld seam, louvres, socket), triangulation, sharp-edge marking, UV unwrap, glTF export |
| `Tools/blender/parts_chassis.py` | the six chassis plus the shared hull helpers (core bay, deck plates, flank plates, corner brackets, wheel gear, sockets) |
| `Tools/blender/parts_drive.py` | `wheel_standard`, `wheel_omni`, `track_unit` |
| `Tools/blender/parts_weapon.py` | the ten weapons |
| `Tools/blender/parts_misc.py` | the two armour plates, the seven utility parts, the two FX scraps |
| `Tools/blender/build_parts.py` | CLI, the part registry, the poly budgets, the manifest writer |
| `Tools/blender/verify_parts.py` | pure-python GLB reader: tri counts, bounding boxes, sockets, materials, UV presence, the axis assertions and the winding check. Also `--rebuild-manifest` |
| `Arena/tests/_g3_import_probe.gd` | the Godot side of the check. Leading underscore, so `scripts/test-arena.sh` skips it |

## 2. THE AXIS RULE

**Author in Bot space and the exported glTF coordinates are numerically identical to the Bot
coordinates Godot sees. There is no conversion for P2 to undo.**

Bot space is `docs/graphics-bar.md`'s convention: **+X forward, +Y up, +Z right**, metres, origin at the
chassis centre on the **axle plane**, which is `WHEEL_RADIUS` = 0.11 m above the arena floor. So the
floor is at `y = -0.11`.

Why it comes out identity:

- Blender is Z-up, so `rkit.BOT2BL` maps Bot `(x, y, z)` to Blender `(x, -z, y)` once, when the bmesh is
  turned into an object. `det(BOT2BL) = +1`, so nothing is mirrored and no winding is flipped.
- The glTF exporter runs with `export_yup=True`, which maps Blender `(x, y, z)` to glTF `(x, z, -y)`.
- Compose the two and you get the identity: Bot `(x, y, z)` to glTF `(x, y, z)`.
- Godot's glTF importer does no further conversion: glTF and Godot share the same right-handed
  Y-up, -Z-forward basis. A vertex authored at Bot `(0.45, 0, 0.3)` lands in Godot at `(0.45, 0, 0.3)`.

Godot's default "forward" for a `Node3D` is -Z, which is **not** the bot's forward. The bot's nose is
+X, exactly as the physics code and `Shared/parts.json` already assume (wheel slots are `[x, z]` pairs
in this same space). P2 does not need to rotate anything: parent the glTF scene to the chassis body at
identity and the nose points where the physics thinks it does.

**This is verified, not assumed.** `verify_parts.py` reads the POSITION accessor `min`/`max` straight
out of each `.glb` and asserts, per chassis, that `socket_weapon_front.x > 0`, that `socket_wheel_fr.z >
0` and `socket_wheel_fl.z < 0`, that the front axle is forward of the rear one, and that the wheel
sockets sit on `y = 0`. `_g3_import_probe.gd` re-checks the same four facts on the instantiated scene
inside Godot, so both ends of the pipeline are covered. All 30 parts pass.

`verify_parts.py` also computes each mesh's **signed volume** from the exported triangles. Every part is
built from closed primitives, so a positive total proves the winding (and therefore the normals) point
outward. All 30 are positive; that is the evidence that nothing is inside out, in place of a render.

## 3. What P2 gets, per file

Every part is one `.glb` at `res://assets/parts/<category>/<id>.glb`. Instantiating it gives:

```
<id>                      Node3D          scene root, named after the part id
  body                    MeshInstance3D  the part
  ring                    MeshInstance3D  shell chassis only, the full-body spinner shell
  socket_*                Node3D          one per socket, identity rotation, position only
```

- The primary mesh node is **always** called `body`. Do not rely on the root's name beyond convenience.
- **Socket empties carry position only.** Their rotation is identity, i.e. they inherit the bot's axes.
  Facing comes from the name (`front` faces +X, `sides_r` faces +Z, `top` faces +Y, and so on), not from
  a rotation you have to interpret. This was deliberate: a socket basis is one more sign convention to
  get wrong, and there is nothing a rotated socket buys here that a named one does not.
- `Arena/assets/parts/manifest.json` lists every part with its tri count, byte size, mesh node names,
  axis-aligned bounding box, every socket and its position, the per-material triangle split, and a UV0
  flag. Load it if you want the numbers without instantiating; the assembler does not need it.

### Sockets on a chassis (22 on every one of the six)

| socket | where |
|---|---|
| `socket_wheel_fr` `fl` `mr` `ml` `rr` `rl` | the six **6wd** positions from `Shared/parts.json`, on the axle plane. `r` is +Z (the bot's right), `l` is -Z |
| `socket_wheel_4wd_fr` `fl` `rr` `rl` | the four **4wd** positions, which are not the same X as the 6wd ones |
| `socket_wheel_2wd_rr` `rl` | the two **2wd** positions |
| `socket_armour_front` `rear` `sides_l` `sides_r` `top` | the centre of each armoured face |
| `socket_weapon_front` | just inside the nose, at the height the weapon should hinge |
| `socket_weapon_top` | on the deck. Present on all five non-shell chassis even where the catalogue says `mount_weapon: front`, so you have the option |
| `socket_weapon_shell` | shell chassis only, at the origin, the spin axis of the ring |
| `socket_utility_0` | rear deck |
| `socket_utility_1` | front, low (scoop, skirts, magnets) |
| `socket_srimech` | rear deck, behind `socket_utility_0` |

The wheel sockets are read from `Shared/parts.json` at build time, so they cannot drift from the
catalogue. Three sets are emitted rather than one because 2wd, 4wd and 6wd use different X positions on
every chassis: use `socket_wheel_<n>wd_*` when it exists and `socket_wheel_*` (the 6wd row) otherwise.

Weapons and utility parts carry two extra empties, `socket_pivot` (the hinge or spin axis) and
`socket_tip` (the business end, for impact FX and reach checks). They are not in the graphics-bar list;
they are there because P2 needs the joint anchor and the FX layer needs the contact point, and guessing
either from a bounding box is how a flipper ends up hinged in the wrong place.

### What P2 must do

1. **Load and parent at identity.** No rotation, no scale, no axis flip. The origin of a chassis is its
   centre on the axle plane; the origin of a weapon is its mount socket, so it parents straight to
   `socket_weapon_*` with a zero offset.
2. **Wheels** spin about their own local **+Z**. Origin is the axle centre, so drop `wheel_standard.glb`
   on a `socket_wheel_*` with no offset and no rotation.
3. **Tracks**: `track_unit.glb` is 0.70 m long, centred on the origin, and its frame plate is on the -Z
   (inboard) side. Scale along X for the chassis footprint. For the other side **rotate 180 degrees
   about Y**, do not mirror with a negative scale, which would invert the normals.
4. **Armour plates** are authored 0.50 m wide (Z) by 0.30 m tall (Y) at **one thickness unit = 0.012 m**
   along X, outward face at +X. Scale `x` by the catalogue `thickness` (1 to 4) and `y`/`z` to fit the
   face, then swap the plate's `steel` surface material for the face material.
5. **Materials**: swap by surface name, never by index. See section 4.
6. **The shell chassis' `ring`** is a separate `MeshInstance3D` inside `shell.glb`. It is the plain outer
   shell; `full_body_spinner.glb` is the toothed version that replaces it when that weapon is fitted.
   Both share the same 0.325 m bore, so they are interchangeable on the bearing race modelled into the
   hub. The FBS teeth reach 0.45 m, which is the catalogue `reach`.
7. **FX**: `debris_bolt.glb` (the bolt shower) and `spark_chip.glb` are single small solids with one
   surface each, ready for `MultiMeshInstance3D`.
8. **Collision is unchanged.** These are visual meshes only, exactly as `docs/graphics-bar.md` says: the
   convex shapes in the physics code stay.

## 4. Material slots

Eight slots, the names from `docs/graphics-bar.md`, each a placeholder Principled BSDF with a plausible
base colour, metallic and roughness so the parts are readable before G2's textures land. No textures are
embedded, not even a placeholder: the files carry geometry and named materials only, which is why the
whole set is 3.4 MB.

| slot | placeholder | used for |
|---|---|---|
| `livery` | orange, dielectric, rough 0.40 | every plate meant to take the player's colour |
| `steel` | metal, rough 0.34 | working faces, ramps, brackets, shafts |
| `titanium` | metal, rough 0.26 | hardened edges, teeth, tips, strakes |
| `hdpe` | off-white, dielectric, rough 0.58 | skirts, pusher pads, battery cases |
| `polycarbonate` | pale blue, rough 0.10 | reserved; no part uses it yet, it arrives when armour plates are materialised at runtime |
| `rubber` | near-black, rough 0.86 | tyres, tread cleats, track belts |
| `dark_metal` | near-black metal, rough 0.52 | structure, frames, bolt heads, motor pods, hub bores |
| `core_glow` | teal, emission strength 3 | the control core in every chassis' core bay, and both FX scraps |

In Godot, read them by name:

```gdscript
var mesh := (part.get_node("body") as MeshInstance3D).mesh
for i in mesh.get_surface_count():
    match mesh.surface_get_material(i).resource_name:
        "livery":  mesh.surface_set_material(i, livery_material)
        "steel":   ...
```

The exporter drops slots a part does not use, so surface indices differ between parts. Always match on
`resource_name`.

Two notes for G1 and G2:

- `core_glow` is also what `debris_bolt` and `spark_chip` use. Brief §6 wants bolts **emissive gold**;
  the graphics-bar slot list has exactly one emissive slot, so the FX layer should bind a gold emissive
  material to `core_glow` on those two meshes and the teal one on the chassis. Different material
  resource, same slot name.
- Every chassis uses `livery` on its flank and deck plates and nothing else does, so recolouring a bot is
  one material swap on `body`.

## 5. Poly counts and sizes

30 parts, **73,108 tris**, **3.38 MB** total. Against the `docs/graphics-bar.md` budget:

| category | parts | tris each | budget | on disk |
|---|---|---|---|---|
| chassis | 6 | 4,888 to 7,864 | 4k to 8k | 1.74 MB |
| drive | 3 | 944 to 1,968 | 600 per wheel | 0.20 MB |
| weapon | 10 | 1,020 to 3,512 | 2k to 6k | 0.91 MB |
| armour | 2 | 400 to 464 | 300 to 800 | 0.05 MB |
| utility | 7 | 984 to 2,796 | not specified | 0.48 MB |
| fx | 2 | 8 and 20 | tiny | 0.00 MB |

Chassis, weapons and armour are inside the bar. **The wheels are not:** `wheel_standard` is 944 tris
against a stated 600, and `wheel_omni` is 956. That is deliberate and it is the one budget I chose to
miss. The cost is the eight bevelled tread cleats and the six-spoke hub, and those are what make a wheel
read as a machined object rather than a cylinder at the framing in `Art/direction/bot-in-workshop.png`.
Six wheels on two bots is 11.3k tris, which against a 73k library and a Forward+ target is not the thing
that will cost frames. `track_unit` at 1,968 is measured against its own 2,000 bar in `build_parts.py`,
since a 0.7 m track with a belt, cleats, sprockets and four road wheels is not a wheel.

Per-part numbers, bounding boxes and the material split live in `Arena/assets/parts/manifest.json` and
are printed by `verify_parts.py`.

Byte size runs around 48 bytes per triangle because the smart UV unwrap splits vertices at every island
seam, so there is little vertex sharing. That is the price of usable UVs and it is not worth optimising
at 3.4 MB.

## 6. Quality rules, and how each one is enforced

- **Bevels, 2 to 4 mm.** `rkit.BEVEL` is 3.5 mm, applied per primitive as it is added (`Part._stamp`
  bevels only the edges of the geometry just created, so primitives never bevel each other). Small
  detail uses 1.5 to 3 mm, bolts use none.
- **No n-gons in the export.** Every mesh is run through `bmesh.ops.triangulate` before it leaves
  bmesh, so the exported primitives are triangles by construction, not by the exporter's fallback.
- **Smooth shading with an autosmooth angle.** Faces are all smooth; edges are marked sharp where the
  two adjacent face normals differ by more than **40 degrees**. 40 rather than 30 because a two-segment
  bevel on a right angle turns 30 degrees per step, and a 30 degree threshold would break exactly the
  highlight the bevel exists to create. Sharp edges are set on the mesh's `sharp_edge` attribute, which
  Blender 4.1+ uses to compute corner normals directly, so no autosmooth modifier is needed and the
  exporter picks the split normals up.
- **UV unwrap.** `smart_project` at a 66 degree angle limit with a 0.01 island margin, on every mesh.
  There is a `cube_project` fallback if the operator ever fails headless (it does not on 4.5). One UV
  set, as specified. `_g3_import_probe.gd` asserts every surface has a non-empty `ARRAY_TEX_UV`.
- **Panel gaps, bolt heads, weld seams.** Real geometry, no textures. Plates are laid as separate boxes
  with a 6 mm gap (`rkit.GAP`) and the dark structural hull showing through. Bolt heads are tapered hex
  prisms (20 tris) sitting proud of the plate face at the corners. Weld seams are six-sided beads run
  along the structural corners. This is why a chassis is 5 to 8k tris rather than 1k.
- **Imports into Godot 4.6 with no warnings.** `Godot --headless --path Arena --import` produces zero
  error or warning lines across all 30 files.

## 7. The parts, and the design decisions worth knowing

Every silhouette is original. Brief v3 §3 rules out the named competitor machines and the house robots
by shape as well as by name, so nothing here is a rounded-off version of a real machine: the chassis
are the six abstract archetypes in §5.1 and the weapons are the ten mechanism types in §5.3, drawn as
generic engineering rather than as anybody's build.

**Chassis** are all built the same way: a dark structural hull, then `livery` plates bolted on with real
gaps, then the details. Every one has a **core bay**: a rectangular opening in the deck plates with a
`dark_metal` frame, a grille of three bars and a recessed `core_glow` block about 30 mm down. That is
brief §6's control core, visible before the armour comes off, and it is the reason the deck is laid as
four plates around a hole rather than as one slab.

- `wedge` (0.9 x 0.6): a full-width steel ramp from a 20 mm lip up to the deck, two titanium strakes up
  the ramp, a raised louvred electronics lid over the rear deck, HDPE side skirts and a rear
  anti-spinner slope with a bumper bar.
- `box` (0.8 x 0.6): the generalist. Flank, front and rear plates all panel-gapped, L brackets up all
  four vertical corners, an access hatch with a handle on the left flank and a vent on the right.
- `pyramid` (0.8 x 0.8): **symmetric about the axle plane**, so it reads identical inverted, with four
  sloped faces up to a flat steel top and four down to a flat titanium bottom. One note for P2: the
  catalogue height is 0.26, so the half-height is 0.13 against a 0.11 wheel radius. It sits 20 mm proud
  when inverted. Either accept the rock or give it a larger wheel; I kept the catalogue number rather
  than quietly changing the silhouette.
- `long_low` (1.2 x 0.5): ramps at **both** ends, a full-length steel chassis rail down each flank with
  six bolts a side, flanks split into three panels.
- `tall_tank` (0.9 x 0.7): two stacked boxes with a visible shoulder plate and weld seams where they
  meet, a sloped titanium brow on the upper box, and a bolted **turret ring** on top. `socket_weapon_top`
  is at the ring centre, 35 mm above the deck.
- `shell` (0.8 x 0.8): a hub drum, open underneath so the wheels live inside it, a bearing race with
  twelve bolts, and a **separate `ring` mesh** at 0.40 m outer radius.

**Drive.** `wheel_standard` is 0.11 m radius by 0.06 m wide per the bar, built as a rubber ring (so the
hub shows through from both sides) with eight bevelled tread cleats, a six-spoke titanium hub, lug bolts
on both faces and a valve stem. `wheel_omni` is the same envelope with eight tangential barrel rollers
on pins. `track_unit` is a rounded-rectangle belt built with `Part.band`, cleated, over two sprockets
and four road wheels, with a bolted inboard frame and tensioners.

**Weapons** use the catalogue `reach` as the real dimension. `horizontal_spinner` is a 1.10 m bar (0.55
each side, exactly the catalogue reach at the hardened tip), `full_body_spinner` teeth reach 0.45,
`saw` teeth reach 0.30, `flipper` tip 0.40, `crusher` jaw 0.30. Each is a real mechanism: the flipper
has a pneumatic ram, a gas bottle with strap rings and a regulator; the lifter has a threaded screw
actuator with eleven modelled thread rings and a travelling nut; the crusher's jaw is three bolted
segments curving down to two teeth over an anvil; the axe has a coil spring return; the saw has a
guard, a motor and a belt cover; the flamethrower has a bottle, a regulator, a feed pipe and two
ignition electrodes.

**Utility.** `srimech` is a two-link arm with an HDPE pusher pad and its own pneumatic cylinder.
`skirts` are hinged HDPE strips on four knuckles a side with a titanium scuff rail. `scoop` is a curve
built from five bolted segments with side cheeks and a hardened lip. `counterweight` is a cast block in
a steel cradle with a lifting eye. All of them are authored around the socket they mount to.

**FX.** `debris_bolt` is a capped hex prism at **20 tris**, not the 12 in the brief: 12 is only
reachable with an open shell, and an open shell disappears when you see its back face. 20 tris across a
120-bolt shower is 2,400 tris, which is nothing. `spark_chip` is an 8-tri tapered sliver.

## 8. Known gaps

- `polycarbonate` is declared and coloured but no part uses it yet. It arrives when P2 materialises
  armour faces from the catalogue.
- Per-chassis armour plate sets were optional and are not built: `plate_flat` and `plate_sloped` scale
  to every face. If a chassis ends up needing a shaped plate (the pyramid's sloped faces are the likely
  one), that is a new builder in `parts_misc.py`, not a change to the pipeline.
- No boss or arena models. Different scope (`docs/graphics-bar.md` lists `boss` and `arena` as
  categories, but the G3 brief covers the part library).
- Nothing is rendered here by design. The evidence is tri counts, bounding boxes, signed volumes, the
  zero-warning Godot import and the 180 assertions in `_g3_import_probe.gd`. A visual pass belongs with
  G1's frames against `Art/direction/*.png`, once there are materials and lights to judge it under.
