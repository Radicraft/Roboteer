# Wave A, models: the hero build to the target look

Written 2026-09-24 by the hard-surface modelling lead. The job: bring ONE machine (the
first build in a new garage, Tinribs: wedge, four wheels, flipper, srimech, steel front,
HDPE sides, polycarbonate rear, titanium top) to the look in `docs/look/img2/` in the real
engine, without changing a single socket, id, collision shape or gameplay number. The
targets and the "why ours reads as a toy" list are in `docs/look/menu-hero-options-v2.html`;
the spec is `docs/look/reference-study.md` section 3.

Evidence is in `docs/aaa/img/wave-a/models/` (section 6).

---

## 1. What changed in rkit (`Tools/blender/rkit.py`)

Everything is opt-in per part: `Part(ident, category, v2=True, bake_px=N)`. A v1 part
rebuilt today comes out byte for byte as before, so the other 49 parts are untouched until
someone moves them over.

| feature | what it does | why |
|---|---|---|
| `BEVEL_V2` 6 mm, `BEVEL_V2_MID` 4 mm, `BEVEL_V2_SMALL` 2.2 mm, `SEG_V2` 3 | the bevel sizes of reference-study 3.3 (4 to 8 mm on major edges) | at the menu distance 1 px is about 1 mm; v1's 2 to 4 mm bevels were 2 to 4 px and could not hold a highlight |
| angle-filtered bevels (`_stamp`, `V2_BEVEL_MIN_ANGLE` 20 degrees) | only edges whose faces meet at more than 20 degrees are bevelled | lofts and lathes have seams between coplanar faces; bevelling those grows slivers and wastes triangles |
| `miter_outer='ARC'` | rounded outer corners where three bevels meet | a sharp miter pinches the highlight at every corner |
| weighted normals (`WEIGHTED_NORMAL`, face area, keep sharp) + `V2_SHARP_ANGLE` 50 | big flat faces shade dead flat; the whole normal turn happens inside the bevel strip | this is the thin bright line on every edge that reads as "expensive" |
| tangents exported | `export_tangents=True` | the materials lead's brushed steel and titanium are anisotropic |
| UV2 (`bake` layer, glTF `TEXCOORD_1`) | a copy of the unscaled, non-overlapping unwrap, made before `uv_scale` touches UV0 | the mask needs a unique unwrap; UV0 is tiled by `PartVisuals.density_matched` |
| `bake_masks` | Cycles bake (Metal GPU, 48 samples) of R edge / G AO / B cavity onto UV2, saved as `<id>[_<node>]_mask.png` next to the `.glb` | wear on edges and grime in corners, never scattered noise. Convention: `docs/wave-a-contracts.md` 1.2 and 5.2 |
| `loft(sections)` | skins a run of cross-sections into a closed solid | the shell primitive: tapered wedges, cheek-chamfered hulls, cowls, knife-edged lips |
| `lathe(profile)` | revolves a (radius, height) profile; radius 0 closes on the axis, `closed=True` makes a ring | tyres, rims, bottles, domes, bosses with fillets in the profile rather than 16-sided cylinders |
| `outline(pts, frame, t, back)` | a 2D outline in any plane, extruded, with the back face inset so the edges are chamfered | cheek plates, cut-corner panels, spokes, cradles |
| `hose(points, r)` | Catmull-Rom sweep with parallel-transport frames, capped, hex ferrules at the ends | cable and gas lines that sag and bend instead of kinking |
| `button_bolt`, `countersunk`, `hex_nut` | a button-head cap screw on a washer (about 100 tris), a flush head in a dark seat, a chamfered hex nut | round heads hold a specular dot at menu distance; flat hex facets did not |

Collision shapes are separate from render meshes and stay that way: every collision shape
is built by the physics code (`BotMeshes.wedge_points()`, the plate boxes in
`bot.gd _add_panel`, the flipper box in `flipper.gd`). Nothing reads a model to make a
body. Confirmed by reading every `CollisionShape3D` construction under `Arena/bot/`.

Other tooling:

- `Tools/blender/parts_hero.py`: the v2 builders. They REPLACE the v1 builders of the same
  id in `build_parts.py`'s registry (registered last); the v1 functions stay in their files
  as the record of what changed.
- `Tools/blender/verify_parts.py --compare OLD/manifest.json`: fails if a rebuilt part lost,
  gained or moved any socket, and prints the triangle delta. Run it on every rebuild.
- `Tools/blender/render_hero_v2.py`: EEVEE review render of a build assembled EXACTLY as
  the engine assembles it (the transforms come from the engine, not from sockets), under
  the reference-study 3.1 showroom rig. Review materials use the baked masks (livery chips
  to steel on R, grime on G and B), so it doubles as a check that the masks are sane.
- `Arena/qa/hero_assembly_dump.gd`: headless Godot, writes every model's bot-space
  transform for the Tinribs build (plates on the physics hull anchors, the pinned flipper
  pivot) to JSON for the render above.
- `Arena/qa/hero_capture.tscn`: windowed Godot, the workshop stage with the turntable
  parked and a fixed camera (`--hero-cam=menu|three_quarter|flipper|rear|wheel`), so a
  before and an after frame are comparable. `menu` is reference-study 3.2 item 1 (27
  degrees vertical, 2.8 m, 0.55 m up).

```bash
B=~/Applications/Blender.app/Contents/MacOS/Blender
G=~/Applications/Godot.app/Contents/MacOS/Godot
$B -b --python Tools/blender/build_parts.py -- --only wedge,flipper,wheel_standard,srimech,\
plate_wedge_front,plate_wedge_front_hdpe,plate_wedge_top,plate_wedge_top_hdpe,\
plate_wedge_sides,plate_wedge_sides_hdpe,plate_wedge_rear,plate_wedge_rear_hdpe
python3 Tools/blender/verify_parts.py --compare /path/to/old/manifest.json
$G --headless --path Arena --import
$G --headless --path Arena --script res://qa/hero_assembly_dump.gd -- /tmp/hero.json
$B -b --python Tools/blender/render_hero_v2.py -- --assembly /tmp/hero.json \
    --parts Arena/assets/parts --out /tmp/after --views hero,high,rear,flipper,wheel
# the engine frame (Godot does not quit by itself after the shots; kill it)
perl -e 'alarm(shift); exec(@ARGV)' 25 $G --path Arena --resolution 1434x660 \
    res://qa/hero_capture.tscn -- --roboteer-shots=/tmp/hc,3,2 --hero-cam=three_quarter
```

The first Cycles bake of a session spends about 70 s compiling Metal kernels; after that a
part bakes in 2 to 7 s.

## 2. The hero parts, and the one decision in each

Every socket of `wedge`, `flipper`, `wheel_standard` and `srimech` is identical to the
previous manifest (`--compare`, zero moves). Envelopes stay inside the old ones.

- **`wedge`**: a lofted, cheek-chamfered powder-coat hull built on the PHYSICS hull's own
  numbers (`BODY_TOP` 0.07, the slope from x 0.10 to the lip at 0.45), so the armour
  anchors, which come from those numbers, land on its surfaces. v1's deck sat at 0.09 and
  its louvred lid stood 4 cm proud of the top plate; both gone. Livery sponsons between the
  wheels carry the side plates, filleted axle bosses with nut rings, the flipper's hinge
  brackets and knuckles on the deck strip in front of the lid, a titanium nose bar, skid
  rails, motor looms behind the tyres. The control core stays in the deck under the lid
  (brief section 6). In this build the top, sides, rear and flipper cover most of the hull,
  so the effort went where it shows.
- **`flipper`**: authored level in the ARM's frame and turned by the same -6.5 degrees
  `flipper.gd` already compensates, so nothing in `flipper.gd`'s signed-off numbers moves.
  Now 0.50 m wide inside the 0.52 m collision arm (v1 was 0.29 m, narrower than the thing
  that hits). A lofted sheet with chamfered edges, a 4 degree press-brake fold so the two
  halves catch the strip lights differently, a bolted doubler and a hardened lip, three
  knuckles on a pin with nuts, ribs and the ram underneath. **The gas system is a second
  node, `mount`**, which `flipper.gd` moves onto the chassis at the pivot (contract 5.4):
  v1's bottle rode on the arm and swung through the deck on every flip.
- **`wheel_standard`**: a lathed carcass with rounded shoulders and a sidewall bulge, 32
  chevron lugs in two staggered rows raked 30 degrees and running off the shoulder,
  machined steel flanges proud of the bead on both faces, five tapered spokes, a hub with a
  bearing cap and five nuts each side. Symmetric in Z because the same model goes on both
  sides. Contact radius 0.110 m exactly (contract 5.5).
- **`srimech`**: same pivot, tip and envelope; a chamfered base bracket, cheeks, the
  shoulder pin, two lofted titanium links on knuckles, a radiused HDPE pad, a lathed
  cylinder and its line.
- **Fitted plates, new ids `plate_wedge_{front,top,sides,rear}[_hdpe]`**: section 4.

## 3. Budgets (triangles)

| part | v1 | v2 | notes |
|---|---:|---:|---|
| `wedge` | 8,936 | 8,812 | detail moved from the hidden deck to what shows |
| `flipper` | 2,464 | 6,184 | 3,256 arm + 2,044 hull-mounted gas system |
| `wheel_standard` | 992 | 4,120 | 2,176 of it is the tyre; the biggest per-machine cost (x4) |
| `srimech` | 1,592 | 2,376 | |
| front plate | 1,464 (`plate_sloped`) | 844 | mostly under the flipper |
| side plate | 1,136 (`plate_flat_hdpe`) | 1,448 (hdpe), 1,160 (metal) | x2 |
| top plate | 1,540 (`plate_flat`) | 2,532 (metal), 3,012 (hdpe) | the biggest livery surface |
| rear plate | 1,540 (`plate_flat`) | 1,996 (metal), 2,316 (hdpe) | |
| **Tinribs on screen** | **23,776** | **42,120** | two machines about 84k |

LODs: Godot generates them on import (`meshes/generate_lods=true` in every part's
`.import`), measured with a probe: LOD1 is about half, LOD2 about a quarter (the tyre
2,176 to 1,088 to 96). The fight camera sits on LOD1 to LOD2, so the close-up price is
paid only in the menu, garage and intro shots. On an A17/A18 Forward+ target 84k
triangles is not the frame cost (shadows, SSR and fog are; reference-study 3.4), but it is
still the first thing to trim if the phone disagrees: the tyre lugs (2 x 16 to 2 x 12 saves
about 350 per wheel) and the button-bolt washers (about 30 tris each, 40-odd on the build)
are the cheap cuts. `build_parts.BUDGET_NOTE` records the new per-part ceilings so a
regression still prints OVER BUDGET.

## 4. Fitted armour plates (the change outside Tools/blender)

The generic plates are ONE 0.50 x 0.30 m model scaled non-uniformly onto every face. On a
wedge flank that is 0.33 x 0.6 in plane and 2.5 through the thickness: round bolt heads
become ovals, a 6 mm bevel becomes 2 mm along one axis and 15 mm along another, and the
highlight the bevel exists for is gone. No amount of modelling survives that, so:

- `plate_<chassis>_<face>` and `plate_<chassis>_<face>_hdpe` are authored at the face's real
  size (`wedge.gd` `FRONT_SIZE`, `SIDE_SIZE`, `REAR_SIZE`, `TOP_SIZE`), at scale 1, with the
  OUTER face on the origin.
- `bot.gd _add_panel_visual` (15 lines plus `_fitted_plate_id`, marked "Wave A (models)")
  uses one when it exists and places it at `size.x * 0.5` in the panel frame, which is the
  collision box's outer face at every thickness. Thicker armour grows INWARD into the hull
  (`ChassisBase.PLATE_PROUD`), so the visible plate is the same at 1 to 4 units and one
  model per face is honest. Visual only: the collision box, the mass, the joints and the
  detach behaviour are untouched.
- Metal plates bind the face material on their `steel` slot, as before; HDPE plates carry
  an `hdpe` body and no `steel` surface at all (contract 5.3). Reactive keeps its cassette
  plate.
- The top plate is the machine's biggest livery surface, so it carries a ridged two-piece
  cowl with sloped sides and a V seam, a titanium frame with button bolts, and two lifting
  eyes. The sides and rear carry raised chamfered livery panels; the front is a knife-edged
  steel plate with a titanium strip and countersunk fasteners.

`assembly_test` accepted only the generic `Model_plate_flat_hdpe` on every chassis; it now
also accepts the fitted one (declared edit, 5 lines). `assembly_bugs_test`'s material
signature did not see the painted master's colour (a ShaderMaterial parameter, not an
`albedo_color`), which surfaced once the v2 wedge stopped carrying an `hdpe` skirt; the
signature now reads the `albedo` shader parameter too (declared edit, 6 lines).

## 5. Rebuilding the other 49 parts with it

Per part, in order:

1. `Part(..., v2=True, bake_px=512)` (1024 for a chassis or anything bigger than 0.4 m).
2. Raise major edges to `BEVEL_V2`, secondary to `BEVEL_V2_MID`. v1 builders pass
   `bevel=BEVEL` or small numbers explicitly; those need editing, the default does not.
3. Replace box stacks that define the silhouette with `loft` (hulls, wedges, cowls) and
   `outline` (plates, cheeks, brackets); every cylinder that is seen with a `lathe` that has
   its fillets in the profile; `bolt`/`hardware_bolt` with `button_bolt` (armour, covers) or
   `countersunk` (working faces, anything that slides); cables and gas lines with `hose`.
4. Put detail where it shows in the assembled machine, not in the part on its own (render
   it assembled with `render_hero_v2.py`; the dump script takes any config with a small
   edit).
5. `verify_parts.py --compare` (zero socket moves), then `--import`, the part tests
   (`assembly_test`, `parts_p_test`, `texel_density_test`, `paint_test`), a Godot frame.
6. For a chassis: add its fitted plates by calling the shared plate builders in
   `parts_hero.py` with that chassis' face sizes (from its `plate_size()`), and make sure the
   hull's visual top, flanks and front sit on the PHYSICS hull numbers so the plates land
   on it.

Estimate, one Opus agent, including its own renders and checks (the kit exists now, so
these are lower than the art-pass table's steps 9 to 12):

| group | parts | per part | total |
|---|---|---|---|
| other chassis + their fitted plates | box, pyramid, long_low, tall_tank, shell, apex | 0.5 day | 3 days |
| rival weapons (what the face-off shows) | vertical and horizontal spinner, saw, axe, ram, crusher, lifter | 0.3 to 0.5 day | 3 days |
| other weapons | full body, vortex, twin saw, drill, shock prod, tesla, napalm, flamethrower | 0.3 day | 2.5 days |
| drives | wheel_omni, track_unit, adaptive_tracks, legs, hover | 0.25 to 0.5 day | 1.5 days |
| utility | rear_wedge, skirts, magnets, scoop, spare_battery, counterweight, overcharge_core | 0.2 day | 1.5 days |
| generic plates | plate_flat, plate_sloped, plate_flat_hdpe, plate_flat_reactive (still used by chassis without fitted plates) | 0.1 day | 0.5 day |
| bosses | five signature parts + five hull overlays, with the silhouette test | 0.5 day | 5 days (the overlays must be redone against the new hulls) |
| **total** | | | **about 17 agent-days** |

The FX scraps (`debris_bolt`, `spark_chip`) should stay v1: they are instanced by the
hundred and a bevel buys nothing at 5 px.

## 6. Evidence

All in `docs/aaa/img/wave-a/models/`:

| file | what |
|---|---|
| `blender-compare-hero.jpg` | before, after, target (Recraft showroom) side by side, EEVEE, showroom rig, blue livery |
| `blender-before-*.jpg`, `blender-after-*.jpg` | the individual EEVEE renders (hero, high, rear; after also flipper and wheel close-ups) |
| `blender-after-orange-*.jpg` | the same build in Pit orange, the target's colour, for the side-by-side with `docs/look/img2/menu-a-showroom.webp` |
| `engine-compare-three-quarter.jpg` | the engine, windowed Forward+ on the Mac, `hero_capture` fixed camera: before and after |
| `engine-before-*.jpg`, `engine-after-*.jpg` | engine frames: menu, three_quarter, flipper, rear (hero_capture), and the stage lead's own menu camera (stage_preview) |

The engine "before" frames were taken from a copy of today's Arena with the v1 parts
dropped back in, so the stage, the lights and the materials are identical and only the
models differ.

## 7. Owed

1. **Brush direction.** Contract 1.3 item 2 asks for the U axis of steel islands along the
   machining direction (polar on turned faces). `smart_project` does not do that. Needs a
   per-primitive UV pass (lathe and loft know their own U); not done.
2. **The flipper ram does not extend.** It is on the arm; the barrel should stay on the
   chassis and the rod slide. Same `mount` trick, one more node.
3. **Tyre cost.** 4,120 per wheel is the biggest line. Revisit after the device fps pass.
4. **Other chassis' fitted plates** (section 5 item 6) and the generic plates' v2 pass.
5. **The stage's own menu camera** still frames the machine at about a fifth of the frame
   height; reference-study 3.2 wants 36 to 42 %. That is the stage lead's rig, not a model
   question; `hero_capture --hero-cam=menu` shows the spec framing.

## 8. WHERE THIS STOPPED (2026-09-24, coordinator STOP at the session limit)

- Committed as a WIP commit. Done: rkit v2, the hero parts, fitted wedge plates, bot.gd and
  flipper.gd hooks, contract section 5, the evidence images listed in section 6 (the
  orange `after-orange-high` render was cut off; the rest exist).
- NOT yet run at the stop: the final `scripts/test-arena.sh` over the whole suite and
  `scripts/build-sim.sh`. Last run of `assembly_test`, `parts_p_test`,
  `texel_density_test`, `workshop_test` passed; `assembly_bugs_test` failed ONE check
  (livery signature), fixed in the test after that run and not re-run. `paint_test` not run
  since the HDPE plates lost their `steel` slot (which was the materials lead's reported
  cause of its failure).
- Next: run the full suite and the sim build, re-run `paint_test` and `assembly_bugs_test`,
  then the section 7 items. The `arena.pck` was NOT re-exported (the lead does that).
- Section 3 says the fight camera sits on LOD1 to LOD2. That is an estimate. It has not
  been measured.
