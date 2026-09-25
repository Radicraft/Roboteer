# Wave A contracts

Shared agreements between the wave A leads. Each lead owns its own section; to change
someone else's section, say so in your own section and let them fold it in.

## 1. Materials and surface masks (owner: MATERIALS lead)

Status: v2, 2026-09-24 (masks: UV2 bake primary, vertex colour fallback). Built to by
`Arena/assets/materials/shaders/rb_painted.gdshader` and `Arena/bot/part_visuals.gd`. Parts that do not follow it still render (every rule
below degrades to "clean, no wear"), so nothing has to land at once.

### 1.1 Slot names (glTF material names)

A part names its materials by slot, exactly as today (`PartVisuals` matches by
`resource_name`, never by surface index). Unchanged slots:

| slot | what it is | master |
|---|---|---|
| `livery` | painted panel, takes the player's colour and the paint job | painted master (clearcoat, edge wear) |
| `hdpe` | moulded plastic, takes the livery tint | StandardMaterial3D |
| `dark_metal` | black powder coat on frames, brackets, motor cans | painted master, powder coat preset (wears to steel) |
| `steel` | bare brushed steel | StandardMaterial3D, anisotropic |
| `titanium` | bare titanium | StandardMaterial3D, light anisotropy |
| `polycarbonate` | clear or smoked shell | StandardMaterial3D, alpha depth pre-pass |
| `rubber` | tyres, bump stops | StandardMaterial3D |
| `copper` | bus bars, windings | derived from steel |
| `core_glow` | the power core, the only thing that blooms | emissive |

New slot, optional:

| slot | what it is |
|---|---|
| `status_light` | small indicator lenses (arming light, LED strip). Emissive, below the glow threshold at rest; `PartAnim` or gameplay may pulse it. Use sparingly; `core_glow` stays the one hero emitter. |

### 1.2 Surface masks

**v2, 2026-09-24 evening: the models lead's baked UV2 mask is the convention**, and the
painted master reads it. It is better than the vertex-colour plan in v1 (a baked texture
does not bleed across long triangles, holds at fight distance and works on the GL tier),
so v1's vertex colours are now only the fallback for parts not yet rebuilt.

**Primary: one baked mask texture per mesh node, on UV2.**

| what | value |
|---|---|
| file | `<part id>[_<node>]_mask.png` next to the part's `.glb` (`_<node>` omitted for the node named `body`) |
| UV | glTF `TEXCOORD_1` (Godot `UV2`), the unscaled non-overlapping unwrap |
| encoding | RGB, linear data (Non-Color), baked by `Tools/blender/rkit.py` `bake_masks` |
| R | **edge**: 0 on flat faces, 1 on a bevel crest (Cycles bevel node, 4 mm radius, creases removed by near AO) |
| G | **AO**: 1 open, 0 fully occluded (16 mm and 80 mm radii mixed) |
| B | **cavity**: 1 in a seam or panel gap, 0 in the open |

How it is used: `PartVisuals.with_mask()` finds the file from the `Model_<id>` root and
the mesh node's name and binds it to that mesh's painted-master material
(`mask_enabled`, `mask_tex`). `livery` and `dark_metal` chip where
`R x wear` exceeds the chip noise (primer ring, then bare steel); grime darkens and
roughens where `max(1 - G, B)` is high. StandardMaterial3D slots (steel, titanium, hdpe,
rubber, polycarbonate) do not read it today.

Import settings for the mask PNGs: `compress/mode=2` (VRAM compressed) and
`mipmaps/generate=true`. As first committed they are Lossless, raw RGBA8 in VRAM
(4 MB per 1024 mask; docs/wave-a-materials-notes.md 4.4). 512 px is plenty for a plate.

**Fallback: vertex colour COLOR_0**, for a part with no mask file. White means clean.

| channel | meaning | 1.0 | 0.0 |
|---|---|---|---|
| R | edge cover, `1 - convexity` | flat or protected | sharpest exposed edge |
| G | occlusion | open | occluded |
| B, A | reserved, export 1.0 | | |

With no mask file the shader also measures curvature from screen derivatives (1.3), so a
bevelled part with no bake still gets light wear on its bevels at close range, and none
at fight distance or on the GL tier.

Blender notes for the fallback: a Float Color attribute (Byte Color is sRGB and gets
linearised by the exporter), `export_vertex_color='ACTIVE'`, bevels of at least 2
segments. `Tools/textures/make_test_board.py` is a worked example.

**Open item for the models lead (CLOSED 2026-09-24, models lead, see 5.3):** the fitted HDPE plates (`plate_<chassis>_<face>_hdpe`)
are bound with the HDPE armour material on their `steel` slot (`bot.gd`
`_add_panel_visual`), so `paint_test` counts a painted `steel` surface and fails
("steel is left bare, not painted"). Naming that glTF slot `hdpe` in the model (and
binding `{"hdpe": ...}`) fixes the count and says what the surface is.

### 1.3 Geometry the shader depends on

1. **Bevels 4 to 8 mm** on major plate edges with **smooth (weighted) normals across the
   bevel**, not a hard edge either side of it. The painted master measures curvature per
   pixel from the normal's screen derivative (`|dN| / |dP|`), which finds a 6 mm bevel as a
   band about 250 rad/m and a flat plate as zero, independent of triangle size. A hard
   edge split gives it nothing to measure.
2. **Tangents exported** (`export_tangents=True`). Brushed steel and titanium are
   anisotropic, and the brush runs along **UV U** (the tangent). Lay the U axis of a steel
   island along the machining direction: lengthwise on a blade or plate, around the axis
   on a turned part (hub, shaft, disc face uses a polar unwrap so U runs round the rim).
3. **UV1 only**, one unwrap per part, texel density as uniform across the kit as you can
   get it. `PartVisuals.density_matched()` rescales every surface to 1600 texels/m, so the
   absolute value does not matter; consistency within one part does.
4. UV2 carries the baked mask (1.2) and nothing else. Keep it non-overlapping.

### 1.4 What the materials lead provides back

1. The masters in `Arena/assets/materials/` and their shaders in
   `Arena/assets/materials/shaders/`, bound by slot through `PartVisuals` (no call site
   changes).
2. `Arena/qa/material_board.tscn`: a test board of bevelled panels, a sphere and a
   cylinder built to this contract under a fixed showroom rig; `--board-hero` puts the
   fixture machine under the same rig, with any paint job and livery.
3. Decals (warning stripes, invented stencils, bolt grime, scorch) as Decal textures in
   `Arena/assets/textures/decals/`, placed by code, never baked into a part's UVs.

## 2. Venue kit (owner: ARENA KIT / VENUE lead)

Status: v1, 2026-09-24. Built to by `Arena/arena/kit/venue_kit.gd`.

### 2.1 One node per arena scene

Each `Arena/arena/<id>.tscn` gets exactly ONE extra child, added by the kit lead and by
nobody else:

    [ext_resource type="PackedScene" path="res://arena/kit/venue_kit.tscn" id="kit"]
    [node name="VenueKit" parent="." instance=ExtResource("kit")]
    venue = "<id>"

The hazards engineer owns everything else in those files and in the arena scripts
(hazards, telegraphs, lamp bezels, arena lights, floor markings). The kit lead does not
edit `arena_base.gd` or the six subclasses. If the two of us both touch a .tscn, rebase
on the other's commit; the VenueKit node is one self-contained block, so the merge is
trivial.

### 2.2 Rules the kit keeps (and the tests assert)

1. NOTHING under `VenueKit` is a `CollisionObject3D` (no bodies, no areas, no shapes).
   `Arena/tests/venue_kit_test.gd` walks the subtree and fails on any.
2. Nothing under `VenueKit` reads or writes the shared fight RNG, `_physics_process`, or
   any physics state. It runs in `_process` and on the GPU. Its randomness is a private
   `RandomNumberGenerator` seeded from a constant.
3. It READS the parent arena (`arena_size()`, `escalated()`, the `hazard_fx` signal,
   `spike_patch_centre()`); it never calls anything that changes it.
4. Every kit piece degrades by tier (`GraphicsQuality`): high, medium, low. Nothing in the
   kit carries hazard information, so the kit may drop pieces freely on low tiers.
5. Visual layer: kit geometry renders on VisualInstance3D layer 1 like the arena, plus
   layer 11 (`VenueKit.RENDER_LAYER_VENUE`) so a camera (the screen feed, a later intro
   camera) can include or exclude the venue.

### 2.3 Presentation events the kit listens to

| event | source | effect |
|---|---|---|
| crowd reaction (`big_hit`, `flipped`, `ko`, `endgame`) | the kit WATCHES `AudioMix._swell_at` (read only), which the mixer stamps each time a swell really plays, after its own gap check; so picture and sound fire on the same frame with no edit to `Arena/fx/audio_mix.gd`. OWED to the audio lead: a `crowd_reacted(key, intensity)` signal on AudioMix; when it lands the kit connects to it and drops the watch. `get_tree().call_group("venue_kit", "on_crowd_reaction", key, intensity)` also works for anyone else | crowd cheers or flinches, phone flashes burst, the screen stings |
| hazard | parent arena's existing `hazard_fx(kind, active, position)` | small crowd lean-in |
| endgame | polls `arena.escalated()` in `_process` | pyro burst, crowd to full excitement, floods warm |

### 2.4 Hooks the later intro/camera wave calls

    venue_kit.play_entrance(side: int)   # 0 player gate, 1 opponent gate: light sweep + gate strip chaser + pyro, 3.5 s
    venue_kit.skip_entrance()            # snaps everything to the idle state
    venue_kit.fire_pyro(kind: String)    # "gate", "columns", "sparks", "all"
    venue_kit.set_excitement(v: float)   # 0..1, decays by itself
    venue_kit.intro_camera_marks() -> Array[Transform3D]   # suggested flyover poses per venue

None of them are called by the fight today; `--roboteer-venue-entrance` on the QA capture
scene calls `play_entrance` so the pieces can be judged in isolation.

## 3. Combat feel: shake, hit-stop, camera, finish beat (owner: COMBAT engineer)

Status: v1, 2026-09-25. Built to by `Arena/fx/impact_shake.gd`, `Arena/fx/feel_tiers.gd`,
`Arena/fight/hit_stop.gd`, `Arena/ui/camera_rig.gd`, `Arena/fight/fight.gd`. Write-up:
`docs/wave-a-combat-notes.md`; feel spec: `docs/aaa/combat-feel.md`.

### 3.1 One shake budget

Every camera shake in the fight goes through ONE call on the FX tree's ImpactShake (group
`roboteer_impact_shake`); nobody moves the camera for effect any other way.

    shake.add_trauma(amount: float, source: String = "hit")   # amount 0..1
    shake.kick_direction(screen_dir: Vector2, degrees: float, roll := 0.5)   # capped 2.5 deg
    shake.punch_zoom(amount: float)                            # 0..1 = up to 10 % of the distance

| source | ceiling on the shared trauma | who |
|---|---|---|
| `hit` | 1.0 | FightFx impacts (feel tiers), a flipper throw |
| `hazard` | 0.7 | FightFx `_hazard_shake` (hazards engineer) |
| `landing` | 0.5 | reserved for a machine landing from a throw (no caller yet) |
| `continuous` | 0.3 | saw / grinder / flame streams |

A source adds below its ceiling and is clipped at it; it never pulls the trauma down. An unknown
source is treated as `hit`. `kick(strength)` is the old call and means `add_trauma(strength, "hit")`.

### 3.2 Where the shake is applied (and what it never touches)

The rig applies translation, rotation (noise + directional kick) and the zoom punch on its
`Camera3D` CHILD only. The rig node itself never moves for effect, so `CameraRig.steering_basis()`
(what the player's stick is turned by) and every framing measurement stay still under a kick.
The rig and its camera are never physics interpolated (they move in `_process`).

### 3.3 Hit-stop and slow motion (the tick-clock hold)

- Feel tiers (`FeelTiers.TIERS`, scuff / hit / heavy / smash) decide the stop: 0 / 45 / 80 / 110 ms,
  and 0.6 s of quarter speed when a part comes OFF (smash). FightFx emits `impact_felt(feel)`;
  the fight turns it into `HitStop.request_stop(ms)` / `request_slowmo(s)`.
- Caps (`HitStop.DIALS`): 120 ms per stop, 250 ms between stops, slow motion = one tick in 4.
- A hold only DELAYS ticks, never adds or drops one: the physics tick rate never changes, held
  iterations pause the tree for the sim while the FX tree and the rig play through. Replay 0.25x /
  0.5x and the seek use the same clock. Proof: `Arena/tests/hitstop_test.gd` (hit-stop on,
  0.25x, 0.5x and a seek all end on the same tick with the same damage hash, 0 m drift).
- Consequence for everyone: no simulation rule may read `Engine.get_physics_frames()` (it counts
  held frames). Use `Bot.sim_ticks()` or the fight's `_tick`.

### 3.4 Camera framing (for the kit and stage leads)

- `CameraRig.FIGHT_CLOSER = 0.87`: the fight's resting distance is 13 % closer than wave G
  (owner decision 2026-09-24), pitch unchanged at 50. It scales the pair fit and the player floor,
  never `fit_arena`, the endgame reveal or a pinch. Venue dressing that was framed for the old
  distance shows ~13 % less of the arena edge in a fight.
- Airborne pull-out: up to 22 % further out while a chassis is between 0.45 m and 1.4 m up.
- `PLAYER_LEASH_LIMIT` 0.19 (was 0.21) keeps the player in the centre 60 % with the shake included.
- Measured (camera_track_test, 1206 x 556): the player is 22 to 29 % of the frame height through
  an exchange; the opponent is wholly in frame on every bearing out to 2.4 m (was 2.6 m); past
  that the off-screen arrow (projection based) takes over.

### 3.5 Damage events and the result

- Every `damage_event` carries `source` ("impact", "cut", "burn", "heat", ...). Burns scorch,
  blows scratch; decals ride on the struck body (`Bot.body_for_part`).
- Continuous damage is coalesced per attacker/victim pair: a bite every 0.035 condition.
- At the result the machines stop driving and scoring (`Bot.stop_for_result()`) but their
  BODIES KEEP MOVING through the arena's 3.5 s finish beat (`FINISH_BEAT_S`), then freeze. The
  result is built before this, so nothing after it can change it. Determinism tests hash the
  result row without transforms (see `hazard_determinism_test.gd`).
- Swift: `FinishBeatGate` (Roboteer/FightView.swift) holds the result sheet and the career Match
  Report for `FinishBeat.seconds` = 3.5 s after the result arrives; a tap skips it.
- `rules.endgame_at_s`: see section 6.

## 4. Hazards and the shared warning layer (owner: ARENA HAZARDS engineer)

Status: v1, 2026-09-24. Built to by `Arena/arena/arena_base.gd` (`hazard_schedule()`),
`Arena/arena/hazard_telegraph.gd`, `Arena/arena/hazard_meshes.gd`. Write-up:
`docs/wave-a-hazards-notes.md`. (Numbered 4 so the combat engineer's shake budget can be §3.)

### 4.1 Who edits what in the arena files

- The hazards engineer owns `arena_base.gd`, the six arena subclasses, the hazard kit,
  arena lights and environment tweaks, floor markings, hazard FX and hazard audio.
- The venue kit lead adds exactly one `VenueKit` child to each `<id>.tscn` (§2.1) and
  nothing else. The hazards engineer does not touch that node. The arenas are built in
  code, so the hazards side never needs to edit a `.tscn` at all.

### 4.2 `hazard_schedule()` (read-only, on every arena)

Returns one Dictionary per hazard: `id`, `kind` (spikes | flame | ram | pit | grinder |
turntable), `group`, `position` (floor centre), `size`, `shape` (rect | disc | ring), `yaw`,
`in_s` (seconds to its next activation, 0 while active, 999 never), `active`, `warn_s`,
`always_on`, `contact`, `sound_at`, `lamps`. It is derived from the hazard tick clock and
never mutates anything; `hazard_warning_test.gd` reads it ten times a tick for 90 s and
proves the timeline is unchanged. Anyone may read it (the venue kit's crowd lean-in, a
screen showing "SPIKES IN 3", the intro camera), never write through it.

### 4.3 `hazard_fx` signal change

The Drop Zone's warning now emits `hazard_fx("pit_warning", on, ZERO)` instead of
`("pit", true)`, and `("pit", true)` fires once, as the leaves START to slide (it used to
fire at the warning and again at full open). Listeners keyed on `"pit"` see one event per
opening, at the right moment. Every other kind is unchanged.

### 4.4 FightFx entry points the telegraph calls (in `Arena/fx/fx.gd`, now combat-owned)

- `on_hazard_warning(kind, position)`: plays the hazard's wind-up (`warn_spikes`,
  `warn_flame`, `warn_ram`, `warn_pit`), once per group, exactly `ArenaBase.WARN_LEAD_S`
  (1.25 s) before it acts.
- `on_hazard_strike(kind, position, near_player)`: camera trauma by kind and a haptic when
  the player's machine is within 1.5 m of the footprint.
- ALL hazard camera motion goes through one function, `FightFx._hazard_shake(strength)`,
  which calls `ImpactShake.add_trauma(strength, "hazard")` when the combat engineer's
  budget API is present and the old `kick()` otherwise. Retune the hazard ceiling in
  `ImpactShake.SOURCE_CEILING["hazard"]`, the per-kind strengths in `FightFx.HAZARD_SHAKE`.

### 4.5 Rules the warning layer keeps

1. `_process` only; no physics body, no collision shape, no shared RNG (the test walks the
   subtree for collision objects). `HazardTelegraph.enabled = false` removes it entirely;
   the Coliseum hashes identically either way.
2. No warning starts later than the AI can perceive the hazard (owner, 2026-09-24).
   `hazard_warning_test.gd` re-derives the AI's longest look from `opponent_ai.gd`
   (`SKILLS[*].danger_s + HAZARD_LEAD_S`, `SPIKE_AVOID_LEAD_S`) and fails if any arena's
   warning window is shorter. Anyone lengthening the AI's lookahead must lengthen
   `ArenaBase.SPIKE_WARN_S` with it.
3. Hazard information never degrades by quality tier: the decal, lamps, light and
   wind-up are identical on every tier.

## 5. Part models (owner: MODELS lead)

Status: v1, 2026-09-24. Built to by `Tools/blender/rkit.py` (v2 parts), `Tools/blender/parts_hero.py`,
`Arena/bot/bot.gd _fitted_plate_id`, `Arena/bot/weapons/flipper.gd _add_visual`. Write-up:
`docs/wave-a-models-notes.md`.

### 5.1 What never changes when a part is rebuilt

Part ids, `.glb` paths, the node named `body`, every `socket_*` name and position, the
origin, the axis rule (+X nose, +Y up, +Z right, glTF coordinates = bot coordinates) and
the overall envelope. Collision is NEVER read from a model: every shape is the physics
code's own box or hull. The wave A rebuild of `wedge`, `flipper`, `wheel_standard` and
`srimech` was checked socket for socket against the previous manifest (identical).

### 5.2 Masks

Section 1.2 is the convention; `rkit.bake_masks` writes it for every part built with
`Part(v2=True, bake_px=N)`. The mask PNG `.import` files are committed with
`compress/mode=2` and `mipmaps/generate=true`, as 1.2 asks. Sizes: 1024 for the chassis
and the flipper arm, 512 for everything else.

### 5.3 Fitted armour plates

`plate_<chassis>_<face>` and `plate_<chassis>_<face>_hdpe` (today: `wedge` x front, top,
sides, rear). `bot.gd` prefers them over the generic scaled plates. Frame: +X outward,
the OUTER face on the model origin, placed at `Vector3(size.x * 0.5, 0, 0)` in the panel's
frame at scale 1, so the outer face coincides with the collision box's outer face at any
thickness. Visible depth is `ChassisBase.PLATE_PROUD` (22 mm).

Slots: a metal plate's body is `steel` (bound to the face material, exactly as the
generic plates); an `_hdpe` plate's body is `hdpe` and it has NO `steel` surface (its
fasteners are `titanium`), which closes the materials lead's open item in 1.2. `livery`
is the raised cowl or panel on every fitted plate. Reactive armour keeps
`plate_flat_reactive`.

### 5.4 Flipper gas system

`flipper.glb` has a second mesh node, `mount` (bottle, cradle, regulator and gauge,
lines, valve block), authored in the BOT's orientation relative to the pivot.
`flipper.gd` moves it onto the chassis body as `FlipperMount` at the pivot, so it does
not swing with the arm. It carries its own mask, `flipper_mount_mask.png`, bound while it
is still under `Model_flipper`. No body, no shape, no mass.

### 5.5 Ground contact per drive (for the stage lead's rest height)

No drive model carries a ground-contact socket. Every wheel's origin is the axle centre
and it spins about local +Z. `DriveBase` scales a wheel model by `radius / 0.11`, so
multiply these by that scale.

| drive model | contact radius / lowest point, model space | notes |
|---|---|---|
| `wheel_standard` (v2) | **0.110 m** at the lug crown (= `FightTypes.WHEEL_RADIUS`) | carcass between lugs 0.1015; the two lug rows are staggered so there is always a lug under the axle, lowest point stays 0.110 within 0.1 mm. The manifest AABB reads 0.1094 only because no vertex sits exactly on an axis |
| `wheel_omni` (v1) | 0.110 m | unchanged |
| `track_unit` (v1) | belt bottom y = -0.120 | unchanged |
| `adaptive_tracks` (v1) | belt bottom y = -0.1195 | unchanged |
| `legs` (v1) | foot bottom y = -0.0953 before `legs.gd` scales Y | unchanged |
| `hover` (v1) | skirt bottom y = -0.115 | unchanged |

The chassis origin is on the axle plane, 0.110 m above the floor (`FLOOR_Y = -0.11` in
every chassis model), so a machine on 0.11 wheels rests with its origin 0.11 above the
surface it stands on.

## 6. Fight clock and the house bot (owner: PROGRESSION engineer, shell side; COMBAT engineer, arena side)

Wave B, 2026-09-25 (owner decisions 8 and 9). `CareerFightConfig.json` (Roboteer/CareerFightView.swift)
now sends, for every fight that has a `NextMatch` card (career match, replay, title defence, daily):

| key | value | notes |
|---|---|---|
| `rules.duration_s` | `next.durationS` | 120 for the opener (Series 1 match 1, not a replay), 90 for the daily's Sprint, 180 otherwise. A fight with no card (ladder ghost) still sends 180. |
| `rules.endgame_at_s` | `next.endgameAtS` | 80 for the opener, 60 for Sprint, 120 otherwise. NOT sent without a card: the arena defaults to 120. |
| `rules.enforcer`, `enforcer_mode`, `enforcer_speed` | only when `next.hasHouseBot` | the daily's "Open corner" has no house bot, so the three keys are ABSENT. A title defence's speed rises 0.05 per cycle of eight challengers, capped at 1.25; the daily's "Hungry house bot" sends x1.25. |

Arena side (combat engineer), DONE 2026-09-25: `Arena/fight/fight.gd` reads `rules.endgame_at_s`
in `start_fight` (`Fight.endgame_ticks_for(rules)`, `fight.endgame_at_ticks()`): the round turns
(arena escalates, camera reveal, ENDGAME sting, `phase_changed`) and the house bot is released on
tick `round(endgame_at_s x 60)`. Missing, non-numeric or <= 0 means 120 s (tick 7200). A value at or
past `duration_s` simply never turns. Tested in `Arena/tests/enforcer_test.gd` (the opener: still in
its corner at 79.5 s, out hunting at 80 s). The numbers live in `Shared/parts.json` `progression.round` and
`progression.opener`.

## 7. Stage: menu and garage presentation (owner: STAGE lead)

Status: v1, 2026-09-25. Built to by `Arena/workshop/stage.gd` and `Arena/workshop/stage_director.gd`.
Write-up: `docs/wave-a-stage-notes.md`; evidence: `docs/look/proving-slice.html`. (Numbered 7 because
§3 is held for the combat engineer's shake budget, see §4.)

### 7.1 What the stage reads from a machine (keep these and the stage keeps working)

| what | how the stage finds it | who must keep it |
|---|---|---|
| the parts | `Bot.attached_parts()`, each part's `part_kind` (`wheel`, `weapon`, `armour`, `chassis`) | combat (Bot), models |
| ground contact | every drawing `MeshInstance3D` under a part with `part_kind == "wheel"`, plus the hull children named `TrackSkin*`, `Leg*`, `HoverSkirt` (under `Bot.chassis`); a machine with none stands on its lowest mesh of any kind | models (node names), combat (drive builders) |
| framing bounds | the world AABB of every visible render mesh under the machine, taken in turntable space so turning never changes it | nobody: any mesh is fine |
| the nose | the turntable's own +X: the machine is placed with `place_at(table origin, table +X)` and then seated | combat (`place_at(at, facing)` keeps its meaning) |
| the test-fire spark | `Bot.weapon_socket_world()` if present, else a point on the front | combat |

G2 pull-out categories map to `part_kind`: `weapon` -> `weapon`, `drive`/`wheels` -> `wheel`,
`armour` -> `armour`, `chassis` -> `chassis`. `utility` and `paint` frame the machine but pull nothing.

### 7.2 Rules the stage keeps (and the tests assert)

- Every machine on the stage (hero on the raised or retracted turntable, face-off opponent on the
  floor) has its lowest ground contact within **2 mm** of the surface under it, for every drive in
  `parts.json`, measured by box and by vertex (`tests/stage_seat_test.gd`). The stage seats by
  geometry after `place_at`; it never trusts `place_at`'s height.
- Nothing else on the machine is below the surface (3 mm allowance for a tread).
- A rebuild on a turned table keeps the machine's heading on the table (a builder edit mid turn
  does not snap it).
- Stage machines are frozen: every body under them is static, no physics runs on the stage.
- The director's camera is never physics interpolated (it moves in `_process`); a fight never looks
  through it (`tests/stage_director_test.gd`).
- Exactly one shadow caster on the stage; ambient 0.05 or lower; floor albedo 0.04 or lower
  (`tests/workshop_test.gd`).

### 7.3 Bridge

`workshop_config.shot` / `.opponent` / `.focus` / `.frame`: see `docs/bridge-spec.md`. Absent `shot`
is the old behaviour. Showroom and garage open with the table at `StageDirector.OPENING_TURN_DEG`
(three quarters to the lens) when the stage first comes up.

### 7.4 Asks of other sections (not changed by the stage lead)

- COMBAT: `Bot.place_at` still stands the root at `max(origin.y, drive radius)`, which buries the
  wheels on any raised origin. The stage works round it; anything else that places a machine above
  y 0 would not.
- COMBAT (done in e681e1f and c56a1ab): the rig camera and the World SubViewport are off physics
  interpolation; before that the rig unprojected a stale pose (the ui_test frame bias failures).
- COMBAT: in fights the wheels rest 2 to 11 mm into the floor, and a vertical spinner machine 34 to
  37 mm once fighting (physics contact depth, Jolt; render follows physics within 0.6 mm). See
  `docs/wave-a-stage-notes.md`.
- MODELS: `TrackSkin*` belts draw about 10 mm below the wheel collision shapes they wrap, so tracked
  and adaptive tracked machines show the belt 10 mm further into the floor than the physics contact.
