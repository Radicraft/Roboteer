# Wave C: blueprint menus in the arena (branch `wave-c-menus`)

Owner decision 2026-09-28: the menus are direction A "Blueprint overlay"
(`docs/look/menus-blueprint.html`) with staging 2 "In the arena" behind it
(`docs/look/menus-blueprint-A2.html`, renders `docs/look/menus-bp-a2/v2-*.jpg`), plus fixes for
the weaknesses the coordinator saw in the mockups (machine too small on the menu, Coliseum grade
washing the livery purple, flat blue crowd, pyro reading as a glowing figure, boxy haze cards).

Worktree `/Volumes/RoboteerBuild2/Code/Roboteer-menus`, from main `549bb41`. Presentation only:
no fight logic, goldens or hashes change.

## Bridge contract (both halves build against this)

### Swift -> Godot: `workshop_config` gains three optional keys

```json
{ "bot": {...}, "mode": "menu", "frame": 0.28, "screen": "menu" }
{ "bot": {...}, "mode": "workshop", "screen": "builder", "focus": "weapon" }
{ "bot": {...}, "mode": "workshop", "screen": "shop", "focus": "weapon" }
{ "bot": {...}, "mode": "menu", "screen": "board", "opponent": {...} }
{ "bot": {...}, "mode": "menu", "screen": "result", "cue": "win" }
```

- `screen`: which menu screen is in front of the stage. Known values and the picture each gets:
  `menu` (main menu: the machine large, left of centre, the bowl behind), `builder` (close, left,
  moving heads through haze behind), `shop` (the `focus` category close up, centre), `board`
  (the machine left, `opponent` across the floor on the right), `result` (the machine centred
  under the gate), `career`, `garage`, `workshop`, `scout`, `rewards`, `retry`, `events`,
  `ladder`, `replays`, `quick`, `settings`. Any other value, and an absent `screen`, is a generic
  framing that honours `frame` exactly as before. `mode` and `frame` keep their old meaning.
- `focus` (existing key): on `shop` and `builder`, the category the camera favours (`weapon`,
  `drive`, `armour`, `chassis`, `utility`, `paint`). The shop pulls it out of the machine as the
  director's `part` shot always did.
- `opponent` (existing key): on `board`, the opponent machine across the floor.
- `cue`: `"win"` on the result screen after a win. Fires the win pyro once when the screen
  becomes `result`; re-sends of the same payload never refire it.

Arrival pyro fires by itself when the screen changes to `menu`, `board` or `result` (the screens
that see a launcher), never more than once in 8 s, never looping.

### Godot -> Swift: `stage_anchors`

Where the parts the leader lines point at are on screen, in the Godot view's own normalised
coordinates (0,0 top left, 1,1 bottom right of the full view, which fills the window ignoring
safe areas):

```json
{ "screen": "menu", "settled": true,
  "hero": [0.08, 0.30, 0.50, 0.78],
  "points": { "centre": [0.29, 0.55], "top": [0.30, 0.40], "weapon": [0.43, 0.66],
              "opponent": [0.78, 0.52] },
  "parts": [ { "key": "wheel_fl", "kind": "wheel", "at": [0.21, 0.70], "near": true },
             { "key": "armour_top", "kind": "armour", "at": [0.30, 0.42], "near": true },
             { "key": "weapon", "kind": "weapon", "at": [0.43, 0.66], "near": true } ] }
```

- `hero` is the machine's projected bounding box (x0, y0, x1, y1).
- `parts[].key` is the Bot's `part_key`, the same keys a fight result's `parts_lost` and the
  condition report use (`wheel_fl`, `wheel_rr`, `armour_front`, `armour_top`, `weapon`,
  `chassis`, ...). `near` is true when the part is on the camera's side of the machine: point a
  leader only at near parts.
- `opponent` is only present on `board`.
- `settled` is false while the camera is moving between screens (hide or fade the leaders) and
  true once it has arrived. Sent once on arrival, then again whenever any point moves by more
  than 0.004 (turntable, orbit, drift), at most 10 times a second.

## Godot side: what is built (lead, 2026-09-28)

- `Arena/workshop/menu_venue.gd` (MenuVenue): the Coliseum instanced round the plinth (venue point
  (1.5, 0, 1.5), turned -15 deg so the entrance gate sits behind the menu lens), hazards hidden, every
  collision object stripped (after the kit has laid its floor), never processed. The venue's lights
  cull the hero layer (bit 17, where the stage moves the machine and the face-off opponent) and cast no
  shadows; ambient neutral and low, so the stage key is the brightest light on the livery. Saturated
  floods turned to 45 %. Crowd staged through `VenueCrowd.stage()` only (depth: warm spill on the front
  rows falling off over 4 m, faint cold rim 0.26, haze to near black 8 to 28 m, phone glints); the crowd
  lead owns the meshes and animation (branch wave-c-crowd). Ring rig: four shafts from the truss ring's
  far sides down in front of the gate (2 real spots on high). Close rig for builder and shop: four moving
  heads behind the machine as soft kit beam cones, no fog boxes. The truss ring's own shafts raised.
  Everything (lights, shafts, crowd glow) follows the loading screen's build level.
- `Arena/workshop/menu_pyro.gd` (MenuPyro): a jet on each of the gate's own pyro pedestals: 150 streaked
  particles at 15 to 18 m/s in a 2 deg cone, thin at the nozzle and widening at the top, smoke after, a
  flash light. Fired on arrival at menu / board / result (once per 8 s, only when the lights are up) and
  twice with gerbs on `cue: "win"`. Never loops. None on low.
- Projected blueprint (`MenuVenue.BLUEPRINT`, one switch): the machine's plan (convex hull of each part
  from above, 1.9x), centre lines, a dimension line and two rings as flat emissive ribbons on the floor,
  turning with the table. Shows most on the board (platform down); `extra-board-noblueprint.jpg` for the
  owner's call.
- `Arena/workshop/stage_director.gd`: `SCREEN_PROFILES` (menu, loading, builder, shop, board, result,
  generic). The menu frames the machine at about 37 % of the width (mockup 17 %), low lens, gate and bowl
  behind. A staged screen coming up from the rig's camera moves from it instead of cutting.
- `Arena/workshop/stage.gd`: `screen` / `cue` handling, the venue up on the first `screen`, the showroom's
  room hidden, `stage_anchors` (normalised, 10 Hz max, only when a host is attached).
- **Found and fixed (worth the owner knowing):** the stage's own machine was a solid, frozen body sitting
  hidden at the world origin of every fight after the first menu visit (fight.gd carries the stage into
  each fight's World). A fight run after any menu came out different from the same fight run before one,
  so an invisible obstacle stood in the middle of the arena and a replay started from the menus could
  not match its fight. `_freeze_bodies` now takes every stage machine body out of the physics space
  (no layer or mask, shapes disabled, DISABLE_MODE_REMOVE). Proven in `tests/stage_menus_test.gd`: a fight
  after the menus (legacy or staged) has the plain fight's hash.
- Also seen: the FIRST fight in a headless process occasionally hashes differently from every later one,
  with no menu involved (pre-existing; determinism_test's three runs cover it). My test discards it.

## Tests (desktop Godot, headless)

stage_menus_test 57/0 (new), stage_director 34/0, stage_seat 66/0, workshop 88/0, stage_animation 145/0,
stage_camera 14/0, stage_build 38/0, warmup 34/0, venue_kit 214/0 (all 35 fight hashes identical to base
549bb41), determinism 42/0, bridge 39/0, render 116/0. hazard_determinism 6 failures, identical on the base
commit (goldens owed before this branch; integration re-recorded them on main, re-run after the merge).

## Tier costs (desktop, main menu, staged vs today's showroom)

| Tier | Draw calls | Lights in frame | Particles | Video mem | Static mem | Venue build |
|---|---|---|---|---|---|---|
| High | 109 (61) | 14 (8) | 706 (246) | +147 MB | +16 MB | ~245 ms once |
| Medium | 109 (61) | 10 (8) | 347 (147) | +89 MB | +15 MB | ~230 ms once |
| Low | 92 (61) | 8 (8) | 120 (80) | +43 MB | +11 MB | ~210 ms once |

No new assets: the pck grows by three scripts only.

## Where I stopped (lead, 2026-09-28, owner: "stop and save all progress")

Done: the whole Godot side above, committed; main (1f0975c) merged in; final stage renders and anchors
at 956 and 874 in `docs/look/menus-arena/stage/built-*.{jpg,json}` plus extras (loading rows, a move,
win, tiers, blueprint off); page generator `docs/look/menus-arena/build_page.py` ->
`docs/look/menus-arena-built.html` (before / mockup / built; built slots empty until the Swift captures).

In progress: the SwiftUI direction A layer (the Swift agent's section below): QA flags committed
(0171142), menu / builder / DesignSystem rewrite was mid way at the stop.

Next steps, in order:
1. Finish the Swift layer (builder, shop, board, result, then the other stage screens), plus the
   integration layout flags: career garage list at 402 pt, retry and replays text over the machine,
   "IRON SPRAT" wrapping on the ladder.
2. Sim captures `sim/built-*` over `stage/built-*` with `-stageStill` / `-stageAnchors`, look at each
   beside the mockup, rebuild the page (`python3 docs/look/menus-arena/build_page.py`).
3. Re-run hazard_determinism after the merge (goldens came in with main), scripts/build-sim.sh, the
   career self test.
4. Phone: frame time with the venue, the venue build hitch at the start of the loading screen (desktop
   ~230 ms; it builds on the first `screen` message, before the warm up), memory (+90 to +150 MB video
   on desktop; the venue stays resident through fights: consider freeing it on fight start on low/medium).
5. Owner calls: the projected blueprint (keep or veto), jet colour (flame vs CO2 white).

## Swift side: where I stopped (2026-09-28, owner's stop)

Commits: `0171142` QA flags, `8769bbe` components + menu + builder, `767155c` shop + board + result +
screen names, `70d8e9b` WIP (last edits NOT compiled).

**Done.** `-stageStill`, `-stageAnchors` (single or keyed payload), `-stayOnMenu` (docs/qa-launch-flags.md);
the QA launch route is pushed 0.35 s late (it was being dropped). `stage_anchors` parsed into
`host.stageAnchors`; `sendWorkshopConfig(... screen:focus:opponent:cue:)` with the old dedupe, and
`host.enterStageScreen(_:)` re-sends the last machine with a new screen. Screens sent: menu, quick,
builder (+focus = tab, livery -> paint), shop (+focus, material -> armour), career, board (+opponent
= next match's bot config), scout, garage, workshop, result (+cue win), rewards, retry, ladder,
events, replays, settings. Direction A tokens and components in DesignSystem.swift (`Blueprint`,
plate + grid, buttons, tabs, part row, mass gauge, menu row, title block, scrap block, payout and
condition rows, leader tag, emblem); `SceneShade` + `StageLeaderLayer` in StageSurface.swift.
Main menu, builder (look then Fit, primary shows Fit/Over by/Done), shop (look then Buy for), board
(schedule plate, FIGHT), match result (payout, condition, leaders to damaged parts via the new
`PartCondition.key`) rebuilt. Befores: docs/look/menus-arena/sim/before-*-{956,874}.jpg (old UI).

**In progress.** `70d8e9b`: leader tag placement by overlap cost (plates, `hero` box, other tags,
window), shop tab size, board unlock link moved to the foot, result plate width. Needs a compile
and a re-capture. built-*-874 captures in sim/ predate these fixes.

**Next.** Compile; capture built-*-{956,874} (`scratchpad/menusA/after.sh <udid> <956|874>`, Pro Max
C4AC945F / Pro D49E6944 sims); iterate on leaders (menu tags landed on the machine at 874); check
the other stage screens (career home, career garage 1-row list, retry and replays text over the
machine, ladder "IRON SPRAT" wrap, rewards, workshop, scouting, events, settings, unlock, loading);
run build-sim.sh and `-careerSelfTest`.

## Resumed 2026-09-30 (lead): page ready for the owner

- Merged local main 0317511 (hazards + size cuts). The hazards' new floor cutouts showed as black holes
  round the plinth with the hazards hidden: `MenuVenue._plug_cutouts()` fills each with the floor's own
  world-planar material. Hidden hazard bodies are dropped whole (their housings with them).
- 70d8e9b compiled clean. Framing retuned against the real SwiftUI layer: the menu machine stands above
  the title block (wider 48 deg lens keeps the bowl and the gate in frame); result and generic framings
  clear of their plates.
- Owner switches, both in `Arena/workshop/menu_venue.gd`: `BLUEPRINT` (projected plan on the floor, on)
  and `JET_STYLE` ("flame", or "co2" for a white cryo jet with no fire and no flash light). Captures of
  the alternatives: `stage/extra-board-noblueprint.jpg`, `stage/extra-jet-co2.jpg`.
- Integration's three flags fixed, plus what the captures turned up: garage lists every machine at 402 pt
  (four secondary buttons on one row when short, record line dropped); retry, replays and events
  sentences on blueprint plates clear of the machine; ladder names never wrap (the roboteer's name
  truncates first); quick fight arena cards no taller than their 48 pt row (their names ran into the
  Opponent heading); scouting report fits or scrolls in its own column (at 874 x 402 it ran off the foot
  and took FIGHT with it) and its machine cards fit name and weight.
- Captures: every stage screen at 956 x 440 (Menus 17 Pro Max sim) and 874 x 402 (Menus 17 Pro sim),
  `docs/look/menus-arena/sim/built-*-{956,874}.jpg`, each over the matching desktop Godot render with its
  own anchors (`-stageStill` / `-stageAnchors`). Page: `docs/look/menus-arena-built.html`
  (`python3 docs/look/menus-arena/build_page.py`).
- Career self test on this build: ALL PASS, 1027 checks, 2 warnings (the two known pacing warnings).
- Godot (headless): stage_menus 57/0, stage_director 34/0, stage_seat 66/0, workshop 88/0,
  stage_animation 145/0, stage_camera 14/0, stage_build 38/0, warmup 34/0, venue_kit 214/0,
  determinism 42/0, hazard_determinism 14/0 (green after the merge), bridge 39/0, render 116/0.
  `scripts/build-sim.sh`: BUILD SUCCEEDED.
- Known, left: the unlock screen's "what the full game adds" list and the settings list scroll inside
  their plates at 402 pt (a sentence sits at the fold); the career home and the loading column keep
  their wave B layouts on blueprint plates (the loading screen is direction A of its own). Phone checks
  still owed: frame time with the venue, the venue build at the start of loading, memory.

## Leader lines fixed, pyro split, crowd C (2026-09-30, later)

- Coordinator's faults: at 874 the menu's "4WD" and "Titanium top" leaders crossed (so each looked
  like it landed on the other's part) and the builder's "Front mount" and "Titanium top" crossed.
  The anchors were right (4WD on `wheel_fr`, the top on `armour_top`); the tag placement was greedy,
  so the first leader took the place the next one needed. `StageLeaderLayer.layout` now finds each
  leader's best clean places (off the plates, off the machine, inside the window) and scores every
  combination together: a crossing, a line through another tag, two tags touching, or two tags
  whose lines make an X (opposite order to their parts across AND down) are ruled out ahead of
  anything else. A tag above the machine and one below it may point past each other (opposite
  across only); their lines cannot meet.
- Automatic check: under `-stageAnchors` the layer writes what it drew to
  Documents/leaders-<screen>.json (targets by part key and kind, points, elbows, tags, the screen's
  plates); the capture step copies it to `docs/look/menus-arena/sim/leaders-<screen>-<w>.json` and
  `docs/look/menus-arena/check_leaders.py` checks it against the anchors that capture was fed: each
  label on the part it names by id (4WD on a wheel, Titanium top on armour_top, a weapon on the
  weapon, a damaged part on its own key), the point equals that part's anchor, the part is near,
  no crossings, no line through a tag, no X, no tag on a plate or off the window, and all ten
  captures present. It fails the original faults (tested with the old geometry). Now 10/10 PASS.
- Merged main 7cfa64b (fitment: narrower Tinribs flipper and front plate) and 1a53b62 (crowd C).
  Crowd C's 3D people read pale under the menu staging: `person_light` 1.0 in CROWD_STAGING (their
  default 1.8), and the ring rig's two real spots 14 -> 9.
- Decided (docs/aaa/decisions-2026-09-30.md section 8): blueprint stays on; pyro is white CO2 when a
  screen opens and flame only on a win. `MenuVenue.JET_ARRIVAL = "co2"`, `JET_WIN = "flame"`; each
  MenuPyro carries both jets and fires the one the cue asks for (CO2 throws no light and leaves no
  smoke). stage_menus_test checks an arrival fires CO2 and a win fires flame (59 checks).
- All stage renders, extras (loading rows, move, tiers, arrival CO2, win flame, blueprint off) and
  both widths of every stage screen recaptured; page rebuilt.
- Seen once: in 1 of 11 runs of stage_menus_test under heavy machine load (a pck export, both
  simulators and another agent's Godot running) the fight after the menus hashed differently from
  the plain fight; the other 10 runs and determinism_test (3 runs) passed. Same flavour as the
  first-fight-in-a-process difference noted above; worth a look by the combat side, not reproduced.
