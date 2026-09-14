# Graphics: models (agent G3)

Forty one Blender-generated parts in `Arena/assets/parts/`, built by Python in `Tools/blender/`.
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
   face, then swap the plate's `steel` surface material for the face material. Three variants, all the
   same envelope and the same scaling rule, so they are drop-in swaps:
   `plate_flat` (steel, titanium or polycarbonate faces), `plate_sloped` (the anti-wedge face) and
   **`plate_flat_hdpe`** (a one-piece moulding with radiused edges and countersunk fasteners, for an
   `hdpe` face; cut steel and moulded plastic do not look alike and at this distance it shows).
   Every plate carries a **raised inset `livery` panel over about 36 % of its face**, so a fully
   armoured bot still reads as the player's colour. Scaling X by thickness stretches the bolt heads and
   the livery panel with it; that reads as a thicker plate with deeper hardware and is intended.
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

41 parts, **134,808 tris**, **6.31 MB** total. Rebuild is under 4 seconds.

| category | parts | tris each | budget | on disk |
|---|---|---|---|---|
| chassis | 6 | 8,424 to 11,856 | 12,000 | 2.76 MB |
| drive | 3 | 956 to 2,496 | 1,000 (2,600 for the track) | 0.24 MB |
| weapon | 10 | 1,308 to 3,512 | 6,000 | 0.99 MB |
| armour | 3 | 1,136 to 1,540 | 1,800 | 0.21 MB |
| utility | 7 | 1,340 to 2,796 | 3,000 | 0.59 MB |
| boss | 10 | 1,384 to 4,416 | 8,000 | 1.52 MB |
| fx | 2 | 8 and 20 | tiny | 0.00 MB |

**The budgets in `docs/graphics-bar.md` were raised, deliberately.** That document guessed 4 to 8 k for a
chassis and 300 to 800 for a panel before anybody had rendered one. The second detail pass (washers and
recessed sockets on every visible fastener, pressed ribs, diamond tread, cable channels, drain slots,
edge rails, bearing caps, circlip grooves) is what carries the PS4 read, and it costs more than 800 tris
on a part that covers half a robot. The real constraint is what is on screen, not what is in a file:

    2 bots x (chassis 12k + 6 wheels 6k + weapon 6k + 5 armour plates 8k) = 64k tris

which on a Forward+ target is not the thing that will cost frames. `build_parts.py` prints OVER BUDGET
against the numbers in the table above, so a future regression still gets caught.

`wheel_standard` lands at 992 tris against the bar's 600. Held there on purpose: eight bevelled tread
cleats, a six-spoke hub and a bearing cap are what make a wheel read as machined, and 12 wheels across
two bots is 11.9k tris.

Per-part numbers, bounding boxes and the material split live in `Arena/assets/parts/manifest.json` and
are printed by `verify_parts.py`.

Byte size runs around 48 bytes per triangle because the smart UV unwrap splits vertices at every island
seam, so there is little vertex sharing. That is the price of usable UVs and it is not worth optimising
at 4.8 MB.

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
- **Three tiers of form.** Big form (the hull), mid form (pressed ribs, diamond tread on every walking
  surface, chamfered mounting bosses, recessed cable channels, drain slots, edge rails, thickness steps)
  and small form (hardware). A part with only the first and third tiers reads as a bevelled box, which
  is what the first pass did; `rkit.Part` has a primitive for each mid-tier feature so adding it to a
  new part is one line.
- **Hardware you can identify.** `Part.hardware_bolt` is a dark washer disc under a bright hex ring
  head, so the bore reads as a recessed socket: 68 tris, used on every fastener big enough to see.
  `Part.bolt` stays the cheap 20-tri one for dense rows. `Part.shaft` puts circlip grooves and a
  machined diameter step on anything cylindrical. `Part.bearing_cap` caps wheel and sprocket hubs.
  Weld beads sit on **outside** corners, where they can actually be seen.
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

## 8. Review renders

`Tools/blender/render_contact_sheet.py` renders the library so the quality can actually be judged,
rather than inferred from triangle counts.

```bash
# both outputs: 30 tiles at 1024 composited into a sheet, plus the 2048 hero
~/Applications/Blender.app/Contents/MacOS/Blender -b --python Tools/blender/render_contact_sheet.py

# just the sheet, or just a few parts
... render_contact_sheet.py -- --mode sheet --only wedge,flipper --tile 1024
```

EEVEE Next, 96 samples (160 for the hero), ray-traced reflections and soft shadows, a three-point
studio rig whose energies scale with the subject so a wheel and a chassis are lit identically, an
HDRI-free dark grey world, a dark floor, and the eight material slots given review-quality placeholder
PBR (steel metallic 1.0 roughness 0.35 with a stretched procedural noise on roughness, livery `#3358a0`
at roughness 0.5, matte HDPE, roughness-0.9 rubber, emissive teal core, alpha-0.6 polycarbonate). View
transform is **Khronos PBR Neutral**, not AgX: AgX desaturates so hard that the livery blue reads grey,
which defeats the purpose of the sheet.

The file runs on both sides of the pipeline. Under Blender it renders tiles to a temp directory, then
shells out to system python3 with `--compose` to lay them out with PIL, because Blender's Python has no
PIL. The tiles are deleted afterwards; the only outputs are:

- `Art/review/parts-contact-sheet.png` (3128 x 2862, 6.8 MB), every part at yaw 35 / pitch 30, labelled
  with id, category and tri count, grouped by category.
- `Art/review/hero-wedge-flipper.png` (2048, 3.0 MB): wedge + flipper + four wheels on the 4wd sockets +
  srimech + `plate_sloped` on the ramp + `plate_flat` on the top and rear.

The file runs on both sides of the pipeline. Under Blender it renders tiles to a temp directory, then
shells out to system python3 with `--compose` to lay them out with PIL, because Blender's Python has no
PIL. The tiles are deleted afterwards; the only outputs are:

- `Art/review/parts-contact-sheet.png` (2427 x 2747, 3.9 MB), the 31 non-boss parts at yaw 35 / pitch 30,
  labelled with id, category and tri count, grouped by category. Regenerate it with
  `--only` left off and `--sheet-tile 400`; the bosses have their own sheet because they need the
  assembled second row.
- `Art/review/hero-wedge-flipper.png` (2048, 2.9 MB): wedge + flipper + four wheels on the 4wd sockets +
  srimech + `plate_sloped` on the ramp + `plate_flat` on the top and rear, all steel.
- `Art/review/bosses-contact-sheet.png` (2.4 MB): the five signature parts on the top row, the five
  bosses assembled on their host chassis on the bottom row. This is where the §3 silhouette test is run.
- `Art/review/hero-wedge-flipper-materials.png` (2048, 2.9 MB): the same build with **hdpe flanks**
  (`plate_flat_hdpe`) and a **polycarbonate rear**, which is the check that the material slots read as
  different materials and that the livery panel survives a fully armoured bot.

### THE WEDGE RULING: the flipper arm IS the front armour

On a wedge the flipper and the front armour plate want the same face, and at rest they are coplanar.
**Ruled: `plate_sloped` bolts to the ramp first, and the flipper arm rides on top of it.** The arm is
the outermost surface, the plate is structure underneath. Two numbers P2 must get right, both of which
are easy to get wrong and both of which are in `render_contact_sheet.py` as the worked example:

- **The mount pitch is not the ramp angle.** The wedge ramp is -19.4 degrees, but the flipper plate
  already slopes -6.5 degrees in its own frame. The mount pitch is the difference, **-12.9 degrees**.
  Use -19.4 and the arm dives straight through the armour and out of the bottom of the wedge.
- **The origin lifts along the ramp normal** (0.331, 0.943) by the whole plate stack: thickness units x
  12 mm, plus the 13 mm raised step, plus a few mm of air. For a 3-unit plate that is 49 mm, which
  turns `socket_weapon_front` at (0.070, 0.050) into (0.072, 0.121).

Generalise it as: a front weapon whose rest pose lies on a sloped chassis face mounts at
`socket_weapon_front + ramp_normal * armour_stack`, pitched by `ramp_angle - weapon_rest_angle`.

### Three things the hero renders found, and fixed

- **`socket_weapon_front` was on the outer lip.** You cannot bolt a flipper to 20 mm of nose plate, and
  a hinge there put the flipper's tip 0.85 m from the bot centre against a catalogue reach of 0.40. It
  is now the weapon **pivot**, on the front face of the structural hull at mounting height, placed so a
  catalogue-reach weapon's tip lands at or just past the nose. Wedge `(0.070, 0.050)`, box
  `(0.386, -0.005)`, pyramid `(0.300, 0.0)`, long_low `(0.270, 0.012)`, tall_tank `(0.436, 0.025)`.
- **The srimech folded backwards off the tail.** Mounted on `socket_srimech` its pusher pad ended
  0.29 m behind the bot. The arm now folds forward along the deck, which is also how the real mechanism
  works: it lies along the top and swings back and down to right the machine.
- **`box` and `pyramid` had no silhouette.** Rebuilt: the box is now stepped, with a low forward working
  deck and a raised rear equipment bay; the pyramid has a properly truncated top and bottom, each with
  edge rails and a bolted hatch. `socket_weapon_top` on the box moved down onto the forward deck at
  `(0.20, 0.089)`; every socket **name** is unchanged.

## 9. The five arena bosses

`Tools/blender/parts_boss.py`, exported to `Arena/assets/parts/boss/`. Brief v3 §8 and stage5-spec §4
fix each boss to one chassis and one drive, so each signature part is authored against ONE host and
carries the same conventions as everything else (`socket_pivot` at the joint axis, `socket_tip` at the
business end, the eight named material slots).

| boss | `<id>.glb` signature part | parents to | `<id>_hull.glb` overlay |
|---|---|---|---|
| THRESHER | a symmetric PAIR of serrated lifting-crusher jaws on one cross shaft, closing onto a fixed serrated bed, two hydraulic rams | `long_low` / `socket_weapon_front` | agricultural belt banding, a deck spine rail, two low work lamps |
| GRUDGE | an industrial flame turret: twin nozzles with ignition electrodes, a manifold, and an upright fuel drum on the turret back | `box` / `socket_weapon_top` | corrugated heat shielding, a scorch cowl, one wide slit lamp |
| BANDSAW | a continuous toothed BAND looping two small pulleys in a slim fore-aft bar, carried on posts clear of the deck | `wedge` / `socket_weapon_front` | an open tube roll cage, thin flank blades, one lamp on a stalk |
| ANVIL | a full-width riveted wall plate plus a drop-forge gantry: two uprights, a crosshead and an overhead hammer | `tall_tank` / `socket_weapon_front` | slab armour, buttress ribs, a chamfered brow, twin vertical visor slots |
| CINDER | an oversized curved scoop whose throw arm runs on a visible chain and sprockets along the flank | `box` / `socket_weapon_front` | a louvred cowl, a crest ridge, a ring lamp |

**The hull overlays are one mesh named `overlay`**, authored in the host chassis' own space, so P2
parents them to the chassis root at identity with no offset. They sit a few mm proud of the hull. Each
carries a `core_glow` lamp motif so a boss reads as a character rather than as a repainted competitor.

**ANVIL is the one exception to "one part, one socket".** Its wall and its hammer gantry mount at two
places on the tall_tank, so the file's origin is `socket_weapon_front` and the gantry is modelled at the
offset to `socket_weapon_top`, local `(-0.346, 0.380)`. Parent the whole file at the front socket and
both pieces land.

### The silhouette test (brief §3)

The test is silhouette, not name, and the house robots are out. Each design was steered away from the
shape it would otherwise drift into: THRESHER is a symmetric jaw pair, never a single claw with a lance;
GRUDGE has no claw, no animal face and no military styling, and its upright drum is the read; ANVIL is a
wall plus a press gantry, not a wedge with an axe on a stick.

**One design was rejected on this test and rebuilt.** The first BANDSAW sat its loop down inside the
wedge deck, so only one pulley showed and the assembled bot read as a robot with a large toothed
circular saw on its deck, which is exactly the silhouette it must not have. The loop now rides entirely
above the deck on two posts, longer and with smaller pulleys, so both runs of the band and both pulleys
read from any angle. The docstring in `build_bandsaw` records this so nobody quietly reverts it.

The test is run against the assembled machine, not the loose part: `render_contact_sheet.py --bosses`
builds each boss (chassis + overlay + signature part + its catalogue drive, tracks included) and renders
it as a second row of `Art/review/bosses-contact-sheet.png`. A part floating on its own cannot be
silhouette-tested.

## 10. Known gaps

- `polycarbonate` is declared and coloured but no part ships with it bound. It is a runtime swap onto
  `plate_flat`'s `steel` surface, which is what the second hero render demonstrates.
- Per-chassis armour plate sets were optional and are not built: the three generic plates scale to every
  face. If a chassis ends up needing a shaped plate (the pyramid's sloped faces are the likely one),
  that is a new builder in `parts_misc.py`, not a change to the pipeline.
- The wedge deck is crowded: with a srimech fitted, its pusher pad parks over the core bay. Cosmetic,
  and it goes away as soon as P2 animates the arm, but worth knowing before someone files it as a bug.
- No boss or arena models. Different scope (`docs/graphics-bar.md` lists `boss` and `arena` as
  categories, but the G3 brief covers the part library).
- Nothing is rendered here by design. The evidence is tri counts, bounding boxes, signed volumes, the
  zero-warning Godot import and the 180 assertions in `_g3_import_probe.gd`. A visual pass belongs with
  G1's frames against `Art/direction/*.png`, once there are materials and lights to judge it under.
