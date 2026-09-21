# Wave P, agent G: paint jobs

Brief v5 section 7. Ten cosmetic paint jobs, free at Level milestones, art made with Recraft
and Python, hung on the machine in the arena and pickable in the builder.

The art and the tiling method are in **docs/paint-jobs.md**; this file is what I built, what
I measured, what I could not verify, and the dials.

## What landed

**Art** (`Tools/paint/make_paint.py`, one script, re-runnable)

- Ten tileable 1024 overlays, `Arena/assets/textures/paint/<id>_albedo.png`, greyscale with
  coverage in alpha, composited over the player's livery colour at runtime so one texture
  serves all six colours.
- Four normal maps where the pattern is relief: carbon 1024, chequer / circuit / hex 512.
- Ten 512 previews, `Art/paint/<id>.png`, the paint on a neutral lit panel with a cut
  top-right corner, composited with the SAME arithmetic the GPU is asked for.
- Sources: `Tools/paint/sources/`, five picked Recraft generations. **16 credits of the 80
  budget**, 64 unspent. Nothing was left out: all ten are finished and all ten are in the
  picker.

**Arena**

- `Arena/bot/livery.gd` (new): `Livery.begin(bot_config)` / `Livery.clear()` around a build,
  `Livery.painted(base, colour, id)` turns the livery material into the painted one.
- `part_visuals.gd`, the livery section only: `_livery_material` keys the cache by paint as
  well as colour and calls `Livery.painted`; new `_hdpe_livery` does the same for the HDPE
  armour plates. With no paint both return exactly what they returned before.
- `fight.gd` (two lines at each of the two `setup` calls) and `workshop/stage.gd` (one at
  its one) say which paint the machine about to be built wears. See "one thing outside my
  section" below.
- `Arena/tests/paint_test.gd` (new): 157 checks, 0 failures.

**Swift**

- `PaintJobs.swift` replaces the stub, same `previewName` signature, plus `list`, `name`,
  `level`, `unlocked(at:)`, `unlocked(_:at:)`, `preview`, `fitted`, and the `PaintTile` view.
- `BotBuild.paintID: String?`, optional with no default, so an existing garage migrates
  lightweight and every machine saved before this reads back nil and looks as it did. One
  line in `toBotConfig`: `paint` is present or ABSENT, never empty.
- `BuilderView.swift`, the livery section only: a four across wall of previews under the
  colour rows. Unlocked ones are tappable and show the preview; locked ones are drawn,
  dimmed, with "Level N" over them, because the point of a free milestone is being able to
  see it coming.
- `Art/paint` ships as a folder reference beside `Art/ui` (`project.pbxproj`, ids
  `AA0000000000000000000FA2` / `FB2`).

## Verification

| what | how | result |
|---|---|---|
| Godot suite | `scripts/test-arena.sh` | green, `paint_test` 157 checks / 0 failures |
| every paint id binds | `paint_test.gd` | ten ids, overlay bound (not merely on disk), normal bound on the four, blend mode as drawn, UV1 so density matching reaches it |
| no paint is unchanged | `paint_test.gd` | an absent or unknown id gives the same material, property for property, as before this landed |
| no cross-contamination | `paint_test.gd` | two machines, two paints, in the order a fight builds them; then a third that is plain |
| on a real machine | `paint_test.gd` | a config's `paint` key reaches `Livery`, and after `Bot.setup` the chassis livery (6 surfaces) and the HDPE plates (4) carry the overlay while steel, titanium, polycarbonate, rubber and dark_metal do not |
| the SHIPPED pack | ran the probe against `Roboteer/Resources/arena.pck` with `--main-pack` | all ten overlays resolve and load out of the exported pck, which is the thing the phone reads |
| tiling | `make_paint.py --check` | every texture's wrap is at or under the worst boundary already inside it |
| Swift build | `scripts/build-sim.sh` | clean |
| the picker | headless simulator screenshot | `docs/look/paint-picker.png` (the paint wall, `-builderPaint`) and `docs/look/paint-livery-section.png` (the livery tab as a player first sees it, colours then paint) |

## What I could NOT verify, and why

**Nothing on this machine can show the paint ON a machine.** Two reasons, and the second one
cost me an afternoon, so it is written down properly:

1. `--headless` Godot has no renderer, so no test can sample a shader.
2. **The simulator cannot stand in either.** The QA launch flags run the app with
   `-godotDisplay headless`, so the stage behind the menus is a STILL, not a live render. I
   proved it: two runs with two different paint jobs come back pixel identical (mean absolute
   difference 1.7e-05 over the whole machine), and forcing the livery material to flat
   magenta inside `PartVisuals.bind` changed nothing on screen. Every "the paint is not
   working" symptom I chased was that still image. The pipeline was correct all along, which
   the pack probe above confirms independently.

   **Recorded for whoever screenshots the stage next: a headless simulator launch cannot
   photograph anything about the machine.** Only the UI in front of it is real.

So what the paint actually LOOKS like on a machine is owed, and it is owed on a phone:

- Forward+, the clear coat, the reflection probe and the real lighting are the whole point of
  the two metals in particular. Chrome at roughness 0.055 is a mirror of whatever the
  environment gives it, and the environment in the simulator is not the environment on the
  phone.
- The normal maps (carbon, hex, chequer, circuit) are ASTC two channel; block artefacts in a
  normal show up as shading that crawls, and that is a device check.
- Whether the paint reads at FIGHT distance, not just on the turntable, is a judgement I
  cannot make from a still.

The previews in `Art/paint` are the best available stand-in: they are composited from the
shipped textures with the same MIX / MUL arithmetic the shader runs, so they are honest about
the pattern, the value and the coverage. They are not honest about the lighting.

## One thing outside my section, flagged for the coordinator

My row in the contracts gives me `part_visuals.gd`'s livery section. Two things reach past
the literal wording of that, both small, both deliberate:

1. **`_hdpe_livery`.** Paint that stopped at the `livery` slot would be paint nobody sees on a
   clad machine: the chassis's own livery surfaces are 0.96 m2 and most of them sit under the
   armour, while the HDPE plates are 0.62 m2 of the OUTSIDE. HDPE is already the one armour
   material that wears the livery, so it now wears the paint too. `slot_material`'s `hdpe`
   branch and `armour_material` each changed by one word. With no paint they return exactly
   the object they returned before, and `paint_test` asserts it.
2. **`fight.gd` and `workshop/stage.gd`.** The livery material is reached from eleven call
   sites across `bot.gd`, `chassis_base.gd` and six weapon scripts, all of them D1's, D2's or
   E's files and all of them inside `Bot.setup()`. Threading a paint id through all eleven was
   not available to me, so whoever is about to build a machine says what it wears:
   `Livery.begin(config)` before `setup`, `Livery.clear()` after, at the two sites in
   `fight.gd` (the bots and the house bot) and the one in `stage.gd`. Six lines, all inside
   `# --- wave P: paint jobs` comments. `setup()` is synchronous, so two machines with two
   paints in one fight cannot cross, and `paint_test` proves that too. If the coordinator
   would rather the paint id were a parameter on `bind()`, that is a change to eleven files
   in three other agents' hands, which is why it is not this.

## Dials the owner can turn

| dial | where | today | what moves |
|---|---|---|---|
| **pack size** | `Tools/paint/make_paint.py` `SIZE` | 1024 | The set costs **12.3 MB** of the iOS pack, on a 47 MB pack. Halving to 512 saves about 9 MB, but it also HALVES the world size of every pattern (the overlay rides `uv1_scale`, which is chosen from the texture's own size), so hazard stripes would land 8 cm apart instead of 16. It is a design change, not just a quality one. |
| **which paint jobs ship** | `PaintJobs.shipped` | all ten | Removing an id leaves it in the picker, locked, with its Level, and stops it being fittable. Nothing else changes. |
| **what the paint covers** | `part_visuals.gd` `armour_material` | livery + HDPE | Routing `steel` or `titanium` through `_hdpe_livery` too would paint the bare metal plates. I did not, because the art direction's bare steel is load-bearing, but it is one line if a champion gold machine reads as too little gold. |
| **the metals' brightness** | `livery.gd` `METAL_GRAIN_COMPENSATION` | 1.35 | The base albedo texture has a mean of 0.72, so a metal's albedo has to be scaled back up or gold is a duller gold rather than a brighter one. 1.35 lands the mean on the real value and lets the brightest grain run about 18 % over. Lower it if the metals sparkle on device. |
| **clear coat per paint job** | `livery.gd` `JOBS` | carbon 0.85, flames 0.60, circuit 0.45, camo 0.10, metals 0 | This is most of the difference between a show finish and a flat finish. Camo is deliberately the dullest thing on the machine. |
| **chrome roughness** | `livery.gd` `paint_chrome.roughness` | 0.055 | A mirror. If it reads as a white blob on the phone rather than as chrome, raise it towards 0.12 before touching anything else. |
| **how much livery survives in chrome** | `livery.gd` `paint_chrome.livery_mix` | 0.14 | A candy tint, so a chrome machine is still recognisably the player's. 0 is plain chrome. |
| **paint wall columns** | `BuilderView.swift` `paintRows` | 4 | Eleven tiles in three rows. Three across makes the previews bigger and pushes two rows off the panel. |
| **the wear layer's strength** | `make_paint.py`, the `chip` and `swirl` terms | per pattern | This is what stops a drawn pattern reading as a vector graphic. Turn it down and the paint looks printed; turn it up and the machine looks neglected. |

## One edge left open, deliberately

A paint job that stops qualifying (a catalogue rebalance moves its Level up, or its art is
pulled from `PaintJobs.shipped`) comes off the machine when the player next opens the LIVERY
tab, not the moment the app starts. Until then the machine still sends the id and the arena
still paints it, because the arena checks only that the id exists, never the Level. It is
cosmetic and it self corrects on the next visit to the tab, so it did not seem worth a
migration pass over the garage. If it ever matters, the check is `PaintJobs.fitted` and the
place for it is wherever the career loads.

## Owed

- The look on a phone, under Forward+, on the turntable and at fight distance. Everything
  else is proven.
- `-builderPaintJob <id>` (docs/qa-launch-flags.md) fits a paint job when the builder opens
  so a phone QA pass does not need a thumb. It works, but it cannot be checked from a
  headless simulator for the reason above.
- If the owner wants the paint on the ARMOUR metals as well, that is the one line in the
  dials table and a new screenshot.
