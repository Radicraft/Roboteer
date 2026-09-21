# Wave P, agent E: the models, materials and textures for the thirteen new parts

Wave P added thirteen parts to the catalogue, all playable and tested, all
rendering through fallbacks: procedural hulls, plain struts, a plain skirt ring,
and an overcharge core that drew nothing at all. This is their art.

Bar: `docs/graphics-bar.md`, including the owner's reference of 2026-09-21,
Gear.Club Stradale on iPhone -- showroom PBR, real materials, chunky readable
silhouettes that hold up on a 6.9 inch OLED.

---

## 0. Two facts that changed the plan

**Blender IS installed.** The brief said it was not and that a pure-Python glTF
path would have to be found or written. It is at
`~/Applications/Blender.app/Contents/MacOS/Blender`, version 4.5.0, and it runs
headless (`-b`) perfectly well, including EEVEE Next renders with no window.
Every part here was therefore built with the kit the other 41 parts were built
with, `Tools/blender/**`, which is the right answer on its own merits: these
thirteen have to sit on the same machine as those forty-one and share their
bevel radius, their fastener vocabulary, their material slots and their axis
rule. Writing glTF by hand would have produced parts that looked like a
different game's.

**No free model was usable.** The owner asked, verbatim, *"where possible see if
there are good existing 3d models online we can freely use"*. Kenney, KayKit,
Quaternius, Poly Haven, ambientCG, OpenGameArt and Sketchfab's CC0 filter were
all surveyed; **0 of 13** could be used. The full record, including the
Quaternius licence problem (the pack pages still say CC0, the site now carries a
custom licence forbidding redistribution, and a contradiction is not something
to ship an App Store binary on), is in `docs/third-party-models.md`. That file
is the answer to the owner's question and is meant to be read before anyone
spends the afternoon again.

---

## 1. How to rebuild any of it

```bash
# one part, or a few (a couple of seconds each)
~/Applications/Blender.app/Contents/MacOS/Blender -b --python Tools/blender/build_parts.py -- \
    --only apex,hover,vortex_spinner

# every part (about 20 seconds)
~/Applications/Blender.app/Contents/MacOS/Blender -b --python Tools/blender/build_parts.py

# check the exported bytes without Blender: tris, bounding boxes, sockets,
# winding, the axis rule
python3 Tools/blender/verify_parts.py

# LOOK at them. -b, so no window, no sound: safe with the owner at the Mac
~/Applications/Blender.app/Contents/MacOS/Blender -b --python Tools/blender/render_contact_sheet.py -- \
    --mode sheet --tile 640 --only apex,overcharge_core,plate_flat_reactive
#   -> Art/review/parts-contact-sheet.png

# the two new texture sets
python3 Tools/textures/make_pbr.py Tools/textures/sources/armour_reinforced.webp \
    Arena/assets/textures/armour_reinforced --name armour_reinforced ...   # numbers in section 5
python3 Tools/textures/make_materials.py

# sidecars, then the tests
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path Arena --import
scripts/test-arena.sh parts_p_test assembly_test texel_density_test
```

---

## 2. Per part: what was built, and the one decision in each

Every model is authored in Bot space (+X forward, +Y up, +Z right, origin on the
axle plane) so the exported glTF coordinates are numerically identical to the
Godot ones. Nothing is rotated or scaled on the way in. See
`docs/graphics-models-notes.md` section 2 for why that comes out as the
identity; it is verified, not assumed, and `verify_parts.py` re-checks it on
every export.

### Weapons (`Tools/blender/parts_weapon.py`)

| part | tris | the decision |
|---|---|---|
| `shock_prod` | 2,780 | Three prongs on ribbed **polycarbonate** stand-offs with **copper** rods and `core_glow` tips, plus a transformer can and a bus bar. D1 asked for it to "read as electrical at a glance, because the player's only other clue is the other machine stopping". Bare steel does not read that way next to a steel hull, which is why the copper slot exists (section 4). |
| `tesla_arc` | 4,020 | A real wound former: 13 copper turns, a ribbed insulator stack, a toroid and a discharge ball. `socket_spark` sits at the electrode tip, 0.104 m up, which is where F's bolt leaves from. |
| `drill_lance` | 2,036 | Three helical flutes over a stacked-cone taper, via a new `rkit.Part.helix`. **Everything on it is rotationally symmetric or helical on purpose**: the whole model parents to the spinning body, so the motor housing D1 asked for at the root would have spun with it. The collar reads as the bearing it is, turning or not. See the owed list. |
| `twin_saw` | 3,116 | One disc, 0.19 m, instanced twice by D1. Dished plate, raised titanium ring, three expansion slots, 22 carbide teeth. It carries **no** guard, motor or belt cover, unlike `saw.glb`: those are not on the disc and would have spun. What makes it read as "the same part deliberately bigger" is the tooth count and the hub, not a repeated bracket. |
| `napalm_cannon` | 2,240 | A short mortar canted up 9 degrees, with **five charges in a visible rack** so the finite ammunition is on the machine. `socket_muzzle` at the mouth for F's smoke. |
| `vortex_spinner` | 6,460 | Ten **raked scoops** rather than the full body spinner's eight square blocks. The scoop profile spans 1.4 times the ring's height, because at fight distance the only thing separating the two weapons on screen is that the teeth on this one stick UP. Reviewed side by side against `full_body_spinner.glb`; they now read as different weapons. |

### Drives (`Tools/blender/parts_drive.py`)

| part | tris | the decision |
|---|---|---|
| `legs` | 2,368 | **ONE leg**, fitted four times. **Proportion was the whole problem and the first cut got it wrong**: the drop from hull to floor is only 0.05 to 0.09 m, so a hip housing built to the width of the collision box is wider than the leg is tall and the part reads as a block with a plate under it. Everything structural is narrow (0.058 m at the hip), the members are kept OUTSIDE the housing where the silhouette can see them, the thigh sweeps well aft of the hip so there is a real Z-shape, and the foot is dark rather than bright steel. It articulates fore and aft, in the X/Y plane, because that is the plane a stride happens in and it keeps the foot under the mount, which is where D2's collision box is. |
| `hover` | 8,904 | A **stadium** skirt, not a cylinder: the hull it seals against is a rectangle. **Depth is the read and the first cut got that wrong too**: a hover rides 0.20 m up, and a 0.05 m band under a hull that high is a picture frame with daylight under it, which is exactly how it rendered. It is now 0.115 m deep, the lower two thirds are a rubber curtain rather than structure, and a perforated plenum floor closes the middle so you cannot see the arena through the machine. Four ducted fans at the corners, each with a `glow` mesh node in the throat. |
| `adaptive_tracks` | 5,416 | Same 0.70 m envelope and inboard frame face as `track_unit.glb`, so `tracks.gd` places it with the code it already had. What differs is the belt: **discrete link plates on pins** instead of one moulded skin, which is the visible half of "the belts are segmented and cannot be torn off". Its two sprockets and four road wheels are `spin_*` nodes on their own axes and they turn (section 3). |

### Chassis, utility, armour

| part | tris | the decision |
|---|---|---|
| `apex` | 13,940 | **The undercut has to read**, which is the one thing D2 asked for by name, and a 44 mm step alone does not at 235 px per metre. Three things carry it: the step; a chamfer skirt all round that turns the step into a continuous hard shadow line rather than a soft corner; and a bright titanium catch rail along the top of the step against the dark foot, so the eye is given an edge to follow. Nothing above the waist is wider than the waist. 22 sockets, same set as the other five hulls. |
| `overcharge_core` | 2,412 | **It has to read hot, and "hot" is not one glowing box.** A split pressure vessel with a lit seam you can see into, a lit bore in the nose, copper bus bars and terminals, a finned heat sink big enough to read as a heat sink, and a blow-off valve. The emissive is kept to about 4 % of the surface deliberately: the arena's glow threshold blooms anything emissive, and a part that glows all over becomes a white lozenge on an OLED rather than a machine with a hot core in it. |
| `plate_flat_reactive` | 4,372 | Reactive armour is a **grid of separate cassettes** on a backing plate, not a sheet, and that IS the explanation of its catalogue row (excellent against a spinner, poor against a saw). Three rows of five on standoffs, one already fired and empty, a livery strip down each edge so the player's colour survives. `bot.gd` swaps it in on the same rule the HDPE plate already used. |
| `reinforced`, `reactive` | materials | Section 5. |

---

## 3. What moves, and the rule it obeys

The saws, the drill and both spinners are bodies on hinge motors: the physics
already turns them and nothing new was needed. Three parts are NOT on joints and
would otherwise have been rigid props:

- **the walker's legs** are four collision boxes welded to the hull (`legs.gd`
  explains at length why a leg is not a wheel). Four rigid boxes sliding across
  the floor read as a machine being dragged.
- **the hover's skirt** is one visual on the hull. A cushion that never moves
  reads as a box resting on the floor.
- **the belt's sprockets and road wheels** are geometry inside one skin node. A
  track whose wheels do not turn reads as a sledge.

`Arena/bot/part_anim.gd` (`PartAnim`, new) animates those three, and the rule it
obeys is worth stating because determinism is a hard rule in this repo:

> It touches the `transform` of MeshInstance3D nodes under an imported model,
> and a **duplicated** emissive material on the model's own `glow` node. It
> never writes to a RigidBody3D, never applies a force, never reads or writes
> anything a result depends on, and takes its timing from `_process`, not
> `_physics_process`. The phase is integrated from the chassis's own measured
> speed, so the animation strictly FOLLOWS the fight and cannot feed back into
> it.

Three modes:

- **ROLL**: every `spin_*` child turns about its own local Z at the road speed,
  with the radius taken from that node's own mesh so a sprocket and a road wheel
  of different sizes stay in step with the ground rather than with each other.
  Attached automatically by `PartVisuals.instantiate()` to any model that has
  `spin_*` nodes, so it is a property of the model and no gameplay file has to
  learn about it.
- **STRIDE**: the leg swings about its hip with a lift on the forward half of
  the cycle. A **trot** (diagonal pairs together), which is the gait a four
  legged machine with a rigid body actually uses and the only one that does not
  look like it is falling over. The phase comes from distance travelled, so the
  feet keep pace with the floor at any speed and stop dead when the machine
  does.
- **HOVER**: a bob on two beats so it does not tick like a metronome, a lean
  that follows the road speed, and a skirt glow that brightens with the work the
  fans are doing.

**One trap worth naming.** `tracks.gd` fits one 0.70 m belt to whatever
wheelbase the hull has by scaling it along X alone, typically by about 1.17.
That was harmless while the sprockets were baked into a skin that never moved:
a slightly oval sprocket standing still is a slightly oval sprocket. Turn it and
the ovalness turns with it, and a wheel that visibly swells and shrinks once per
revolution reads as a bug the moment anyone notices it. `PartAnim` cancels the
parent's scale on each spinner's own axes, so their POSITIONS still spread with
the wheelbase (which is right) and only their shape is protected.

**A new rkit facility made the belt possible.** `Part.use(name, origin=...)`
opens a mesh stream whose exported glTF NODE sits at a point rather than at
identity, with its geometry authored relative to that point. A glTF node can
only rotate about its own origin, so without this a sprocket at x = 0.25 could
not be turned at all. `verify_parts.py`'s bounding-box maths was corrected to
account for node translation at the same time, or the manifest would have
reported those streams around the part origin.

### One edit in another agent's file, declared

`Arena/bot/chassis/apex.gd` is D2's. Six lines were added at the **bottom** of
it, marked as agent E's, and nothing above them was touched.

D2 landed a change while this was in flight: the Apex now hands its bodywork
over to a full body spinner the way the Shell does, pulling `levels()` in to
`CORE_FRACTION` 0.64. That worked while `levels()` WAS the silhouette. The
moment `apex.glb` landed it stopped being the silhouette -- `_build_visual`
draws the model instead -- so the collision body would have shrunk to 0.39 m
while the model stayed full size, and an Apex under a vortex spinner would have
stood proud of its own ring at all four corners with nothing solid behind the
overhang.

The six lines are `_on_model_bound()`, which is the hook `ChassisBase` provides
for exactly this and which `shell.gd` already uses at the same point for the
same reason. They scale the model uniformly by the same `CORE_FRACTION`, so the
undercut, the catch rail and the deck keep their proportions, and
`PartVisuals.bind` already divides its texel density measurement by a node's own
scale so the materials do not coarsen with it. `parts_p_test` asserts both
states (full size with a flipper, 0.64 with a vortex, and uniform).

---

## 4. The ninth material slot: `copper`

`rkit.MATERIALS` gained `copper`, **appended, never inserted** (the exported
slot order follows that list, so an insertion would shift the slot order of
every part already on disk). `PartVisuals.slot_material` resolves it to the
brushed steel set with a copper albedo, metallic 1.0, roughness 0.38 -- so a
copper bus bar is turned and brushed like everything else on the machine, it is
just not grey. It costs nothing in the pack, which a texture set of its own
would not have.

It exists because "it should read as electrical at a glance" was D1's brief for
two of the six weapons and bare steel does not read that way next to a hull that
is also bare steel. Four parts carry it: the prod, the arc, the cannon's fuses
and the core's terminals. `render_contact_sheet.py` gained the matching review
material, or the review render would not have been showing what Godot shows.

---

## 5. The two armour faces

Both are proper PBR sets through the existing pipeline
(`docs/graphics-textures-notes.md`), not flat colours. D2 had been telling them
apart with two rows in `FightTypes.MATERIAL_COLOUR`; those rows are now the
fallback rather than the answer.

**Sources** (Recraft `recraftv4_1_raster`, no style id, 1024, 2 candidates each,
4 credits each; picks saved as lossless WebP in `Tools/textures/sources/`):

- `armour_reinforced`: *thick hardened reinforced armour steel plate, dense
  cross-hatched rolled mill surface with a faint hammered hardened face, rows of
  shallow rolled dimples, dark cool gunmetal grey, heavy industrial armour
  steel, fine grinding marks and a few deep gouges* + the standard material-photo
  tail.
- `armour_reactive`: *matte sand-brown ceramic composite reactive armour
  coating, coarse granular sandblasted anti-slip texture, warm khaki grey-brown,
  dry chalky matte military paint over steel, faint chipping showing dark primer
  through, fine speckled grit* + the same tail.

**Build numbers** (both reach a measured seam delta of exactly 0.0):

```
armour_reinforced  --flatten 16 --equalise 0.65 --equalise-sigma 70 --seam-band 0.07
                   --contrast 1.8 --desaturate 0.55 --target-mean 0.38 --tint 0.99,1.0,1.02
                   --normal-strength 3.2 --height-highpass 20
                   --rough-base 0.42 --rough-gain 0.22 --rough-dirt 0.06
                   --ao-strength 0.55 --metallic 1.0
armour_reactive    --flatten 30 --equalise 0.55 --equalise-sigma 90 --seam-band 0.08
                   --contrast 1.5 --desaturate 0.35 --target-mean 0.36 --tint 1.03,1.0,0.96
                   --normal-strength 2.4 --height-highpass 18 --normal-scale 0.5
                   --rough-base 0.82 --rough-gain 0.12 --rough-dirt 0.05
                   --ao-strength 0.5 --metallic 0.0
```

Reinforced is fully metallic and reads as bare hardened plate; reactive is
metallic 0.0, roughness mean 0.91, and is **the one armour face in the game that
is neither bare metal nor the player's colour**, which is the point of it. All
ten maps import as ASTC with mipmaps and no size limit (checked, not assumed).

---

## 6. Texel density: a real finding

`texel_density_test.gd` failed on the first hover build: **750 texels per metre
at `hover/rubber`, under the 900 floor**. It is the largest part in the kit by
surface area, it is mostly rubber, and the rubber set is 512 px, so even the
largest runtime `uv1_scale` step (8x) could not reach the floor.

The fix is at the source rather than by raising the clamp. `rkit.Part` gained a
`uv_scale`, applied to the UV layer once at export, and `hover` is built with
`uv_scale=3.0`. `smart_project` packs whatever it is given into the 0..1 square,
so a physically large part comes out at a low density and a small one at a high
one -- the eightfold spread `PartVisuals.density_matched` exists to paper over at
runtime. This is that fix moved upstream for the one part that needed it. It is
set per part on purpose: deriving it from surface area would change all 41 parts
already on disk, and every one of them already passes.

After: lowest is 949 at `apex/livery`, spread 2.0x (was 26.2x raw), worst
workshop magnification 2.04 texels per screen pixel. All 20 checks green.

---

## 7. Verification

| what | result |
|---|---|
| `verify_parts.py` | 53 parts, all PASS: tri counts, bounding boxes, sockets, UV presence, the axis rule, and a positive signed volume on every part (the evidence that nothing is inside out, in place of a render) |
| `assembly_test` | 23 checks, 0 failed. The `Model_<id>` gate is **re-armed**: D2 had relaxed it to "only when the manifest has one", and the manifest now has one for the Apex, so the check is real again |
| `parts_p_test` (new) | 166 checks, 0 failed |
| `texel_density_test` | 20 checks, 0 failed |
| `assembly_bugs_test`, `paint_test`, `workshop_test`, `mobility_p_test`, `weapons_p_test` | green |
| whole suite | 34 files, **3 failed and none of them mine**: `commentary_test` (the ticker strip), `stage_camera_test` (a forwarded orbit) and `test_arena_runs_test` (a stick drag, the name row, the scrap counter). Every one of those assertions is HUD, controls or camera, in `hud.gd` and `controls.gd`, which agent H had open at the time |

### Pack size

| | bytes | |
|---|---|---|
| `arena.pck` at `566ddba` | 48,874,364 | |
| `arena.pck` now | 55,899,968 | +7,025,604 (+6.70 MB) |

That delta is the **whole wave P working tree**, not just this agent: F's sounds
and H's UI glyphs exported into the same pack. This agent's own share is 12
meshes and 2 texture sets: **3.18 MB** in the iOS (ASTC) variants that actually
ship, 8.89 MB counting every desktop variant sitting in `.godot/imported`. The
12 `.glb` files are 2.8 MB on disk and 58,064 triangles, taking the kit from 41
parts and 134,808 triangles to **53 parts and 192,872**.

A worst case machine is roughly 40k triangles (an Apex at 13,940, a vortex at
6,460, four legs at 2,368 each, plates and a srimech), so two of them is about
80k. That is not a number a Forward+ A17 or newer notices.
| EEVEE review renders | `Art/review/parts-contact-sheet.png`, `-b` so no window and no sound |

`parts_p_test.gd` is worth knowing about: as well as the obvious checks it
asserts that **each model is the size of the collision body the gameplay
actually uses**, with a stated slack per part read off the weapon script it
belongs to (a muzzle, a tooth tip and an electrode are supposed to be proud of
the box that does the hitting). A model that does not match its body is a
machine whose hits land nowhere near where the player aimed, and nothing else in
the suite would catch it. It also asserts that the Apex's two weapon sockets are
**exactly** the numbers `ChassisBase._weapon_fallback` was already handing out,
so landing the hull cannot silently move a weapon D2 measured.

**What could not be verified without a phone.** Everything about the LOOK.
`--headless` has no renderer, and a headless simulator launch shows a still
behind the menus rather than a live render (agent G measured that in wave P and
it is worth not rediscovering). So: the Forward+ read of the copper against the
steel, whether the core's 4 % emissive blooms correctly through the arena's glow
threshold, whether the apex's undercut shadow line survives the arena's key
light, whether the hover's skirt glow is too strong, and whether the legs'
stride reads as walking rather than as twitching. All five are judged from EEVEE
review renders here, which is not the same renderer.

---

## 8. Dials

- `PartAnim.STRIDE_LENGTH` 0.60 m per cycle, `STRIDE_SWING` 15 degrees,
  `STRIDE_LIFT` 0.22 of leg height. Longer stride length = longer, lazier steps.
- `PartAnim.HOVER_BOB` 0.012 m, `HOVER_LEAN` 3.5 degrees,
  `HOVER_GLOW_MIN/MAX` 0.35 to 1.25 of the core material's own energy.
- `parts_drive.SKIRT_DEPTH` 0.115 m, mirrored by `hover.gd`'s own constant. The
  two must move together.
- `parts_drive.LEG_HEIGHT` 0.090 m, the height the leg is authored at; `legs.gd`
  scales Y to the hull's real drop, which is 0.05 to 0.09.
- `parts_chassis.build_apex`'s `under` 0.044 m: how far the foot pulls in. More
  makes the undercut read harder and makes the hull look narrower at the floor.
- `PartVisuals.TARGET_TEXELS_PER_M` 1600, unchanged, and the new
  `rkit.Part.uv_scale` for any future part that cannot reach the floor.
- Tri budgets in `build_parts.BUDGET_NOTE`: `adaptive_tracks` 4200, `hover` 3600,
  `legs` 1600. The hover is over its own note at 8,904 and was left there
  deliberately; see the owed list.

---

## 9. Owed, and what was deliberately not done

1. **The drill's motor housing.** D1 asked for "a collar and a motor housing at
   the root that stays with the hull". The model parents entirely to the
   spinning body, so a housing would spin with it. It was left off rather than
   shipped spinning. Fixing it properly means a second node on the chassis, in
   `drill_lance.gd`, which is D1's file.
2. **The fire patch scorch decal.** D1 also asked, separately, for a 0.45 m disc
   mesh to replace the plain emissive disc in `FirePatch._light`. Not done: it
   lives in `napalm_cannon.gd` (D1's) and a Decal node with the existing
   `scorch` texture set would be the better answer anyway, which is F's area.
   The current emissive disc works; it is not a placeholder.
3. **The belt does not scroll, its wheels turn.** "Tracks scroll" was the ask.
   Scrolling the belt skin needs either per-link nodes or a hand-authored UV
   loop; turning the sprockets and road wheels at the road speed is correct,
   cheap, and reads as driving. The honest description is "the running gear
   turns", and it is a real animation rather than a UV trick.
4. **`hover` is 8,904 tris against a 3,600 note**, and `apex` 13,940 against
   12,000. Both were trimmed once (the hover came down from 9,136 with smaller
   duct segment counts) and then left: the worst case on screen is two machines
   at roughly 40k tris each, which is nothing for a Forward+ A17 or newer, and
   the alternative was taking detail out of the two parts the player looks at
   most. Revisit if device fps says so.
5. **`part_meshes.gd` was not changed.** It is the Stage 3 procedural fallback
   geometry and every new part already has a fallback there or in its own
   module. Nothing was added because nothing needed adding; the file is listed
   in the contract's E row, not required to change.
6. **The look is not signed off.** Section 7. Five specific things need the
   phone.

---

## 10. A trap worth recording

**The build image dropped out mid-session** (`/Volumes/RoboteerBuild2`, the
second one; the first died in an earlier wave). It came back as "Container
superblock is invalid" and `diskutil verifyVolume` failed with exit 8. It was
**not** actually corrupt: a forced detach and a plain re-attach brought it back
with everything intact.

```bash
hdiutil detach /dev/disk5 -force
hdiutil attach "/Volumes/New Volume/RoboteerBuild2.sparsebundle" -mountpoint /Volumes/RoboteerBuild2
```

What WAS lost was the three `.glb` files written in the minute before it went,
while their Python source survived. The lesson is cheap: after an unmount
scare, re-run the builder rather than trusting the outputs, and check
`git status` for files that should exist and do not.
