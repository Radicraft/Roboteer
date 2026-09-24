# AAA teardown: the six arenas

Environment art and level design lead, 2026-09-24. Pre-production only: no game code was
changed. Concept targets and the current frames sit side by side in
`docs/look/arenas/arenas-v1.html`.

Owner's verdict: "quite basic looking... same design, no crowd, no visual prompts, no
environmental effects." The teardown below agrees with every word of it, and adds one finding
the owner could not have seen from the phone alone: **there is nothing at all outside the
walls.** Every arena floats in a flat colour void (`COL_BG` / `arena_env.tres`
`background_mode = 1`). The wide frames in `docs/look/arenas/current/*-wide.jpg` show it.

Sources read: `Arena/arena/arena_base.gd` and the six subclasses, `corner_zone.gd`,
`events/event_arena_base.gd`, `Arena/render/*`, `Arena/fx/fx.gd` (hazard hook),
`Arena/fx/impact_shake.gd`, `Arena/render/damage_decals.gd`, `Arena/ui/camera_rig.gd`,
`docs/audio-notes.md`, `docs/stage5-arenas-notes.md`, `docs/brief-v3.md` §2, §3, §7, §13,
`docs/brief-v4-playtest.md` §2, §3, §5, §7, `docs/graphics-bar.md`,
`docs/graphics-render-notes.md`.

Current frames: captured 2026-09-24 on the Mac with windowed desktop Godot (Forward+, high
tier), fight fixture, player on the charge AI, through `Arena/qa/arena_capture.tscn` (a new QA
only scene; it picks the arena from `--roboteer-capture-arena=` and adds a wide establishing
camera after `--roboteer-capture-wide=` seconds; nothing shipped references it).

---

## 0. What the camera actually sees (read this first)

Everything in this document is ranked by what reaches the player's eye, so the camera
decides the priorities.

- `FightTypes.CAM_FOV` 28 (vertical, a long lens), pitch 50, yaw -135 (behind the player's
  spawn), tracking at about 6.75 to 7.25 m (`camera_rig.gd` `PLAYER_MIN_FRACTION` 0.16).
- At that pose the ground footprint is roughly 3.5 m deep. **Floor is 75 to 100 % of every
  fight frame.** The walls appear only when a fight goes near one (which the AI makes
  common, see the frames), and what is beyond the wall is in the top 10 to 25 % of the frame
  at most, seen steeply from above.
- The full arena and its surroundings are seen only at: the pre-fight moment, the endgame
  reveal (`endgame_reveal()`, 0.6 s out and 0.8 s back), the KO wreckage orbit, and the
  menu/scouting art.

Consequences that shape the whole plan:

1. **The floor is the primary identity carrier.** Material, colour, wear, decals, lit
   markings and hazard hardware in the floor are what a thumbnail of a live fight shows.
   Today five of six floors are the same scratched plate texture at a different tint.
2. **The wall top and the first two metres beyond it are the secondary carrier.** Stands must
   start right behind the wall and rise steeply (so they enter the top band of the frame),
   and the wall itself needs to become a designed object (padding, lamp strip, nozzles,
   barrier glass), not a grey box with a chevron cap.
3. **Distant venue detail is for the reveal, the intro and the KO orbit.** It can be cheap:
   impostors, cards, baked light, a painted backdrop.
4. **Light is cheaper than geometry at this angle.** Pools of coloured light, emissive strips
   and floor light cues read at 7 m through a 28 degree lens far better than modelled detail.

---

## 1. Shared state today (applies to all six)

| Area | Today | Evidence |
|---|---|---|
| Geometry | One `StaticBody3D` floor slab (or four around a hole), four `flat_box_mesh` walls with a 6 cm chevron `BoxMesh` cap. No bevels, no trims, no wall hardware, no corner posts. | `arena_base.gd` `_build_floor`, `_build_walls` |
| Beyond the walls | Nothing. Background is a flat colour tinted per arena. | `COL_BG`, `arena_env.tres` `background_mode = 1`; every `*-wide.jpg` |
| Lighting | One shadowed directional key from top left, one unshadowed cold fill, one `UPDATE_ONCE` reflection probe, flat colour ambient at 0.18. No practical lights, no light pools, no rim, no emissive fixtures. | `_build_environment` |
| Environment | ACES, exposure 0.7, SSAO, SSR, glow, depth fog at 0.006 (invisible at 7 m). No volumetric fog in the arena (the stage has it). | `arena_env.tres` |
| Materials | Five G2 PBR sets reused, triplanar on UV-less boxes, told apart by an albedo multiplier. Walls are driven to 1.9 to 2.75x albedo, which blows out to white on steel and titanium (Grinder, Coliseum frames). | `_textured`, `WALL_TINT`, `grinder-fight.jpg` |
| Floor markings | Flat unlit quads per arena (rings, lanes, hatching). Good design intent, reads as paint. | `_add_marking` |
| Hazard meshes | Engine primitives: 6-sided cones for spikes, an 18-segment flat-coloured cylinder for a grinder disc (renders as a black hole, see frames), a box for the ram, a cylinder for a nozzle. None are Blender models, against `graphics-bar.md`. | `_add_spike_patch`, `_add_grinder`, `crush.gd _add_ram` |
| Telegraphing | Only Drop Zone (3 s blink) and Crush (2 s lamp flash plus lit chevrons) warn. Spikes, flame jets and the Coliseum's jets fire with no warning at all. No shared warning language. | per arena below |
| Hazard audio | One-shots on activation only: `spikes`, `pit_open`, `flame_jet` + `flame_loop`, `ram_crush`, `grinder_loop`. **No anticipation sound anywhere**; `pit_open` plays at the open, not in the warning. | `fx.gd on_hazard_fx` |
| Screen shake / haptics on hazards | None. `ImpactShake.kick` is only fed by bot impacts. A 58-impulse wall ram lands without moving the camera. | `fx.gd` line 202 |
| Persistent marks | Damage decals exist (48 pooled, scratch and scorch) but only fights leave them. Flame jets, grinders and rams leave no scorch, no dust, no sparks on the floor. | `damage_decals.gd`, `fight.gd` |
| Ambient motion | None. Nothing moves in any arena except the hazard itself. No fans, flicker, steam, dust motes, cranes, beacons, crowd. | all frames |
| Crowd | Audio only: `crowd_ambience_loop`, two swells and a roar, reacting to BIG HIT, FLIPPED and the KO count. Nothing to see. | `audio-notes.md` §3, §10 |
| Broadcast dressing | None in the 3D world. The Broadcast look (brief v4 §7) lives only in the HUD. No screens, truss, entrance, pyro, camera cranes. | |
| Endgame moment | Key light tints hot over 0.6 s, the camera pulls back, the HUD stings. The arena itself does nothing new that you can see except the hazard rate. | `arena_base.gd _process`, `fight.gd _enter_endgame` |

---

## 2. Per arena

Each section: what is there, then a ranked gap list (1 = biggest win for the player's eye).

### 2.1 The Yard (tutorial, 10 x 10 m, centre spike patch)

**Today.** Cold grey-blue scratched plate with a 1 m seam grid, 0.65 m concrete walls with a
chevron cap. A 3 x 3 patch of 6-sided cone spikes in the middle on a 6 s cycle (1.2 s up), no
warning of any kind; at the endgame the spikes stay up. The frames: blue-grey everywhere,
spikes are small and grey on grey, no sense of place. It is the arena every other arena was
tuned against (`docs/graphics-render-notes.md`), so it is literally the default.

**What a AAA studio ships.** A scrapyard venue with a clear story (the club arena behind a
breaker's yard), warm sodium floods against cold night, containers and scrap forming the
stands, a spike patch that is a piece of machinery with a lit bezel and a countdown.

**Gaps, ranked.**
1. Spike patch has **no telegraph**: add a bezel ring of lamps round the patch that fills
   clockwise over the last 1.5 s of `seconds_to_spike_rise()`, turns red at rise, plus a
   pneumatic "charge" hiss 0.5 s before the existing `spikes.wav`. Presentation only: it reads
   the existing tick clock.
2. No venue: containers and scrap as stands directly behind the walls, two sodium flood
   towers, crowd cards on the container tops, a hanging screen for the reveal.
3. Floor has no identity: oil stains, tyre marks, weld seams, painted circle round the
   patch, a worn "start box" at each spawn (original shapes, brief §3).
4. Spike mesh: a Blender spike block (steel collar, hydraulic shafts visible when risen,
   dirt in the recess), readable at 7 m.
5. Ambient: dust motes in the flood light, a flickering sodium lamp, drifting grit, a
   circling crow or scrap crane in the backdrop for the reveal.
6. Endgame: the patch bezel stays red, the floods swing to face the centre, crowd surge.

### 2.2 The Grinder (10 x 10 m, two always-on floor grinders)

**Today.** Cold steel plate, steel walls tinted 2.3 to 2.6x (blown to near white with a
blue hotspot in the frames), yellow keep-out rings, dark cut lanes. The discs are a flat
grey cylinder with painted teeth that **render as black holes**; sparks only emit while a
part is touching (`sparks.emitting = touching`), so an idle grinder looks dead. The loop
sound runs from the start at -9 dB, which is right.

**What a AAA studio ships.** A machine shop that is always working: discs visibly spinning
with motion-blurred teeth and a constant low spark plume, a lit ring that brightens as a bot
approaches, metal dust hanging in cold fluorescent light, a gantry crane and presses behind.

**Gaps, ranked.**
1. Disc readability: Blender disc with bright machined face, radial blur card on top (a
   shader, not physics), constant idle spark trickle, heavy fountain on contact. The dead
   black circle is the worst single read in the game.
2. Proximity cue: the keep-out ring glows from cyan to hot orange as any bot's distance to
   the disc falls under 1.2 m. Presentation only, read from bot positions in `_process`.
3. Walls: fix the blown-out tint (drop `TINT_WALL` toward 1.3 and let lighting do the work),
   give them a machine-shop profile (tool racks, safety mesh, lamp strip).
4. Venue: tiered metal bleachers behind mesh, gantry crane, fluorescent tube banks (emissive
   plus one flicker), workshop banners with no text.
5. Persistent: grind marks and hot metal filings decals around each well that build up.
6. Contact punch: camera kick and a haptic transient when a part first touches the disc.

### 2.3 Drop Zone (10 x 10 m, central 2.4 m pit with a two-leaf cover)

**Today.** Dark concrete (tint 0.72, metallic 0.12 under a 0.46 key: close to black in the
frames), amber rim strip that blinks at 4 Hz for 3 s before opening, one amber omni over
the pit, cover leaves with an amber seam stripe, approach lines to the corners. Best
telegraph in the game. But the pit when open is a flat black hole, the closed cover reads as
a pale blue square, and the dark floor swallows the bots' shadows and contact.

**What a AAA studio ships.** A bunker: darkness as the identity, with the pit as the light
source. An abyss glowing red from far below with rising haze, rotating amber beacons on the
rim, a klaxon, and a crowd you mostly see as a sea of small lights.

**Gaps, ranked.**
1. The pit interior: a lit shaft (emissive red floor far down, fog card rising, a slow
   drifting ember sheet) so the open pit is the brightest thing on screen, not the darkest.
2. Anticipation: klaxon at T minus 3 s (not at the open), beacons spin up, the rim strip
   runs a chaser toward the seam, a floor-projected countdown ring 3, 2, 1. Move `pit_open`
   to the actual slide (it already is) and add the pre-cue.
3. Floor exposure: raise floor albedo or add a cool top light pool so bots separate from
   the floor; keep darkness in the walls and venue instead.
4. Beacons: four rotating amber lamps on posts at the rim corners, emissive plus a cheap
   additive beam card (no real spot lights needed).
5. Venue: steep dark stands, crowd as silhouettes and phone lights, suspended screen, cold
   volumetric downlights (high tier) with additive cone fallback (medium).
6. The fall: a camera kick, a dust puff and an echoing crowd "ohh" when a bot drops in.
7. Endgame: the pit locks open with the rim strip solid red and the beacons at double speed.

### 2.4 Furnace (10 x 10 m, six wall flame jets and a 2 m conveyor)

**Today.** Warm rust floor and walls, conveyor slats with emissive direction chevrons,
maroon "burn fan" rectangles in front of each nozzle (they read as rugs in the frames), a
dashed safe band. Jets are G4's `FlameCone` (good). They fire with **no warning**: the seeded
8 to 12 s period gives no visible or audible charge. The belt looks static (slats are painted
lines on a static slab; `constant_linear_velocity` moves bodies, not the texture).

**What a AAA studio ships.** A foundry: molten metal and furnace mouths behind, embers in the
air everywhere, heat haze over the floor, nozzles that glow red hot and hiss before they
fire, fresh scorch on the floor where the flame lands, a belt that visibly runs.

**Gaps, ranked.**
1. Jet charge-up: 1.0 s before each bank fires, the nozzle glows red, a pilot flame and a
   gas hiss start, the burn fan on the floor lights amber. Presentation only, read from
   `_ticks_to_fire`.
2. Belt motion: scroll the slat UVs at belt speed (shader), doubled at the endgame. It is
   the arena's defining idea and today it cannot be seen.
3. Burn fans as scorch decals that darken and accumulate each time a jet fires, not maroon
   quads.
4. Venue: foundry backdrop with a crucible pour (animated emissive), catwalk stands lit
   from below, chains and hooks, smoke.
5. Ambient: ember particles and heat haze (the fx code already has heat haze for the
   flamethrower; reuse it over the floor, high tier only).
6. Nozzle hardware: Blender nozzle blocks with fuel lines and heat-stained bezels.
7. Endgame: the whole back wall glows, embers double, the belt's arrows turn red.

### 2.5 The Crush (10 x 10 m, two wall rams, 0.9 m stroke)

**Today.** Concrete floor tinted 0.88 with metallic 0.08: **near black** in every frame. Rams
are textured steel boxes with a chevron face that read as blank white blocks. Two seconds of
warning: a lamp bar flashing at 5 Hz plus the floor chevrons going emissive; `ram_crush.wav`
(with a real sub layer) on press start. No dust, no shake, no pressure build.

**What a AAA studio ships.** A press hall with oppressive scale: hydraulic cylinders towering
behind the walls, rotating yellow beacons, a hydraulic whine that builds, a floor that shakes
and throws dust on the hit, and cracks in the concrete where the rams land.

**Gaps, ranked.**
1. Floor exposure: this arena is currently unreadable on a phone. Raise albedo, add a cold
   work light pool over the centre. First thing to fix, and it is a two-number change.
2. Ram model: Blender ram with visible chrome piston rods on the extend, a striped face, a
   housing in the wall, bolt heads.
3. Impact: camera kick scaled to what is in the stroke, dust burst at the ram face, a
   haptic heavy transient, a crack decal left on the floor at full extension.
4. Anticipation audio: a rising hydraulic whine over the existing 2 s warning, so the
   player hears it coming from off screen.
5. Beacons: rotating yellow beacons over each ram (emissive plus additive beam card).
6. Venue: industrial press machinery above the wall line, gauges with needles that climb
   before a press, steam vents, crowd behind safety glass.
7. Endgame: beacons stay lit, the gauges sit in the red.

### 2.6 Coliseum (12 x 12 m, every hazard plus two turntables)

**Today.** Polished plate (metallic 0.52), titanium walls (blown out, noisy triplanar in the
frames), a gold centre ring, a 12-spoke star, turntables that **render as white discs**,
sixteen flat-colour box banners on poles, one flame jet per long wall with no warning.
The championship arena is the one that looks most like a test scene.

**What a AAA studio ships.** The stadium: tiers of crowd in every direction, camera flashes,
a lighting truss ring with moving heads, a giant screen, pyro columns at the bell, confetti
at the KO, a floor that mirrors the light show.

**Gaps, ranked.**
1. Venue and crowd: this is where the stand kit and crowd impostors must be full size,
   360 degrees, with flashes.
2. Broadcast dressing: truss ring, moving-head beams (additive cards plus two real spot
   lights at most), a jumbotron showing the live camera from a second viewport at low
   resolution (or a looping sting on low tiers).
3. Turntables and walls: fix the blown albedo; turntable rims lit, direction arrows
   scrolling; walls padded with plain blue and red panels.
4. Pyro: flame columns at the bell and at the endgame, confetti on the KO (particles,
   presentation only).
5. Every inherited hazard needs the shared telegraphs from 2.1, 2.2 and 2.4.
6. Banners: cloth-sim is not worth it; a vertex shader sway on a subdivided quad is.

---

## 3. Crowd and audience: techniques for iPhone

What the camera sees of a crowd: a steep top-down band behind one or two walls, 5 to 12 m
away, through a 28 degree lens. That is far enough for impostors and near enough that
motion must exist.

Recommended stack (all presentation, `_process` only, never the shared RNG):

| Layer | Technique | Cost |
|---|---|---|
| Near crowd (first 3 rows behind the wall) | `MultiMeshInstance3D` of camera-facing cards, one atlas of 16 poses x 4 frames rendered from a Blender low-poly crowd (so lighting and palette match the PBR machines). Per-instance custom data: pose, phase, tint, excitement weight. Vertex shader bobs, sways and swaps frames. | 1 draw call per stand section, ~600 to 1,200 cards |
| Far crowd | Same cards at quarter density, or a baked strip texture on the tier geometry with a scrolling noise mask to fake shimmer | 1 draw call |
| Flashes and phone lights | A second `MultiMesh` of tiny additive points with a hashed blink in the shader; density jumps on big moments | 1 draw call, glow does the rest |
| Reactions | One global shader uniform `excitement` (0 to 1) set from the existing `crowd_reaction()` moments (BIG HIT, FLIPPED, KO, ENDGAME): arms up, faster bob, flash burst, then decays over 2 s. The audio swells already fire on these moments, so picture and sound stay in sync from one call site. | free |
| Team colours | Instance tint biases one stand toward the player's livery and one toward the opponent's | free |

Tiers: high all layers; medium near cards at half density, no far cards (baked strip);
low (simulator) the baked strip only. The whole crowd is a single node the quality autoload
can switch.

**PixelLab: I would not use it here.** Brief v3 §13 retired PixelLab for this project, and
pixel-art crowd cards would clash with the PS4-class, Gear.Club Stradale bar the rest of the
frame is held to. Crowd cards should be rendered from Blender (reproducible scripts in
`Tools/blender/`, like the parts), with Recraft only for screen content and signage plates.

## 4. Hazard telegraphing and visual prompts

How the reference games do it: Insomniac telegraphs every hazard in three channels at once
(an emissive colour change on the object, an anticipation sound, a physical wind-up
motion), with a consistent warm-to-red colour grammar across a whole game. Fighting games
use a fixed wind-up time per move so a player learns the rhythm; sports broadcasts put a
clock on screen. Rocket League and Fall Guys show danger as floor light that fills or
flashes before it acts.

**Proposed Roboteer warning language (one grammar, six arenas):**

| Stage | Light | Floor | Sound | Camera / haptic |
|---|---|---|---|---|
| Idle | hazard bezel dim amber | painted zone, unlit | hazard idle loop if any | none |
| Armed (T minus 2 s, 1 s for jets) | bezel pulses amber, beacons spin | zone lights amber, a fill or chaser runs toward the fire point | anticipation cue per hazard (hiss, whine, klaxon, clunk) | none |
| Firing | bezel solid red, flash | zone red | existing activation sound | kick scaled by hazard, one haptic transient if the player is within 2 m |
| Aftermath | fades to dim over 0.5 s | a persistent decal (scorch, crack, grind marks) | tail | none |

Every stage reads the existing tick-derived clocks (`seconds_to_spike_rise`,
`_ticks_to_fire`, ram `cycle` and `phase`, Drop Zone `_open_at`, `hazard_helpers()`), so the
simulation is untouched. One new thing is needed from each arena: a read-only
`hazard_schedule()` that returns each hazard's position and seconds to its next firing, so
the telegraph layer can be one shared node rather than six pieces of arena code. **Flag:**
that is a new method on the arena contract; it does not change behaviour, but it is a code
change in `arena_base.gd` and its subclasses for the implementation round.

**Flag, gameplay:** today the spikes and the flame jets have no warning, and the AI already
reads `next_danger_in_s`, so the opponent can time them and the player cannot. Adding
telegraphs changes how the fight plays for the player (it becomes fairer). No simulation
number changes, but the owner should know the difficulty of those two arenas will drop.

## 5. Environmental effects

All presentation, all in `_process` or GPU particles, none touching physics.

- **Sparks**: idle trickle on grinders, contact fountains (exist), ram-face sparks on contact.
- **Steam**: vents behind the Crush and the Furnace, a puff when a ram retracts.
- **Heat haze**: the existing flamethrower haze reused over the Furnace floor, high tier only.
- **Dust**: ram impacts, pit falls, spike rises, a hanging mote layer in each key light pool.
- **Debris that stays**: detached parts already persist (`Debris` node); add cheap floor
  grit decals where scrap lands. Keep them as decals, not bodies, to protect the sim.
- **Scorch and crack decals**: from hazards into the existing `DamageDecals` pool (48). Raise
  the pool on high tier to 96 and give hazards their own slice so fights cannot evict them.
- **Light flicker**: one or two fixtures per arena flicker on a hashed frame clock.
- **Smoke**: soft billboard sheets at venue height, never over the floor (readability).
- **Screen shake on hazards**: feed `ImpactShake.kick` from `on_hazard_fx` (rams heavy,
  pit fall medium, spikes light, jets light). Settings should get a "reduce shake" toggle.

## 6. Broadcast dressing

- **Screens**: one per arena (a jumbotron in the Coliseum). Content from a low-res second
  viewport of the fight camera on high tier; a looping sting texture elsewhere. Frame is kit.
- **Lighting rigs**: truss segments with moving heads. Beams are additive cone cards; at most
  two real `SpotLight3D`s, no shadows. Volumetric fog on high tier only.
- **Pyro at match start**: flame columns and a spark curtain on "FIGHT", pyro again at the
  endgame horn, confetti at the result. GPU particles on a budget per tier.
- **The entrance**: a 3 to 4 s arena flyover before the countdown (the camera's existing
  reveal pose, not a new camera mode), crowd surge, lights sweep, bots on their marks.
  **Flag:** this lengthens every fight's pre-roll and touches the camera rig. It must be
  skippable with a tap and must not move the countdown tick. Decision 4 below.
- **Endgame moment**: today it is a key light tint. Add beacons to red in every arena, a
  pyro burst, the crowd excitement uniform at 1, a sting on the screens.

## 7. Performance on iPhone

The game already has the right shape: `GraphicsQuality` tiers (high = Forward+ on A15+,
medium = Mobile renderer, low = GL Compatibility) and a documented order to shed cost
(`graphics-render-notes.md`: SSR, volumetrics, MSAA, shadow atlas, soft shadows, SSAO,
renderer). Device frame time is still owed. Rules for the environment work:

- **Draw calls**: target under 250 for the whole arena scene on high, 150 on medium. Stands,
  crowd, flashes and scrap props are `MultiMesh`; static set dressing is merged per material
  in Blender at export (one mesh per atlas), never hundreds of `MeshInstance3D`s.
- **Lights**: no new shadowed lights. Coloured light comes from emissive plus glow and from
  a handful of unshadowed omnis inside the Forward+ cluster budget (8 per arena on high, 3
  on medium). Beacons and moving heads are additive cards.
- **Baked vs dynamic**: bake the venue (stands, backdrop, truss) with `LightmapGI` at a low
  texel density; keep the floor and the machines dynamic so shadows and contact stay live.
  The medium tier gets the same lightmaps, which is where the biggest visual gain per
  millisecond is on older phones.
- **Particles**: a shared per-tier budget (for example 2,000 live GPU particles on high, 800
  on medium, 200 on low) owned by one arena FX node, alongside the fight FX budget.
- **Textures**: one 2048 atlas per arena for dressing plus the kit atlas; ASTC via VRAM
  compression, with the quality audit brief v4 §7 already asks for.
- **What degrades on older phones**: volumetric beams become cards; far crowd becomes a
  baked strip; screen content becomes a loop; heat haze and SSR off; decal pool halves.
  Nothing that carries hazard information may degrade: telegraph light, floor cues and
  anticipation sound are identical on every tier.

## 8. Determinism rules for the implementation round

- Every new visual runs in `_process` or GPU particles and reads the sim, never writes it.
- Nothing new consumes the shared RNG. Randomness in presentation uses a hash of the node
  id and the frame time, or a private `RandomNumberGenerator` seeded from a constant.
- Stands, props and crowd have **no collision**, or sit on a layer that neither
  `LAYER_BOT` nor `LAYER_DEBRIS` masks. Debris that flies out today falls into the void; if
  stands collided with debris, a replay could diverge wherever debris touches a bot again.
- The out-of-arena sensor boxes outside the walls stay exactly as they are.
- Changing floor friction, wall height or hazard timings is a gameplay change and is out of
  scope; albedo, emission and roughness are not.

---

## 9. Top gaps across all six, ranked

1. Nothing exists beyond the walls: no venue, no stands, no crowd in any arena.
2. All six are the same construction (slab, four box walls, chevron cap, two lights) told
   apart only by a tint; no arena is recognisable from a thumbnail of a fight.
3. Three hazards fire with no warning at all (spikes, Furnace jets, Coliseum jets); there is
   no shared warning language across light, floor, sound and a clock.
4. No anticipation sounds: every hazard sound plays at the moment it acts.
5. Hazard hardware is engine primitives: grinder discs render as black holes, turntables
   and rams as blank white blocks, spikes as tiny grey cones.
6. Exposure is broken on two floors (Crush and Drop Zone are near black) and walls blow out
   to white on three (Grinder, Coliseum, Crush rams).
7. Zero ambient motion and no environmental effects: no dust, steam, embers, flicker, haze.
8. Hazards leave no marks and cause no camera shake or haptic; big arena moments feel light.
9. No broadcast layer in the world: no screens, truss, pyro, entrance or endgame spectacle
   to match the Broadcast HUD.
10. Lighting is one flat key plus fill everywhere: no light pools, practicals, rim or colour
    story per arena.

## 10. The plan in one paragraph

Build one ARENA KIT (stands, crowd impostors, truss, screens, beacons, wall trims, decals,
the telegraph layer, ambient FX) once, then dress six venues from it with one hero set piece
each. Fix the two exposure bugs and the three primitive hazards first because they are
cheap and visible in every fight. Effort, kit and decisions: `docs/look/arenas/arenas-v1.html`.
