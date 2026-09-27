# Wave B: the fight intro

Owner idea (2026-09-27): "before games the camera pans around the dangers of the arena as part
of an intro".

## Where I stopped (2026-09-27)

- BUILT and committed: `3c9d76d` (Godot) and `6fbbaae` (Swift + bridge spec). Not pushed.
- Tests: `tests/intro_test.gd` 60-odd checks, 0 failures (full = short = skipped = none, all six
  arenas). The Swift app builds (`scripts/build-sim.sh`, checked in a clean worktree of HEAD +
  my changes: the shared tree had another agent's half-written `LoadingMachine` in ArenaHost).
- Hash-neutral when no intro is asked for: hazard_determinism_test in clean worktrees at
  3c9d76d~1 and 3c9d76d gives byte-identical hashes in all six arenas. Full suite on the shared
  tree (others' WIP in it): intro 71/0; rules, builds, boost, hitstop and the hazard goldens fail
  from the pacing/boost work in flight (replay rows now 7 wide, the day's sim changes), not this.
- Images: `docs/look/intro/intro-full-contact.jpg` (one row per arena, a frame per shot, the
  drop and the first countdown frame), `intro-short-contact.jpg` (the short intro),
  `coliseum-sequence-strip.jpg` and `sequence/coliseum_000..050.jpg` (the full Coliseum intro
  at 10 fps).
- Owner review pending. Not seen on a phone yet (fps with the ghost flames; tap-to-skip through
  `FightTouchForwarder`, which should work: the skip reads any `InputEventScreenTouch`).
- Gaps / next, in order:
  1. Commentary and crowd AUDIO for the beats: the hooks exist (`Fight.intro_beat`,
     `FightFx.on_intro_beat` if defined) but nothing is heard yet. The audio lead's call.
  2. `VenueKit.intro_marks` is still empty in every venue. The intro honours it (marks[0] -> [1]
     become the establishing move) but falls back to a generated orbit, which reads well. A
     venue that wants its own hero move (a gate, the Coliseum jumbotron) fills it in its build.
  3. Flame jets: the ghost FlameCone reads as fire balls at the nozzle more than a jet across
     the zone (the fight's own flame looks the same from there). The red warning wash carries
     the "this zone burns" message.
  4. The Drop Zone's full intro is only ~4 s (one hazard). Could add a gate or crowd shot.
  5. The "3" of the countdown sits on the YOU tag (pre-existing HUD layout, not the intro).

## How it works

- `Arena/fight/fight_intro.gd` (`FightIntro`): builds the shots from the arena's read-only
  `hazard_schedule()` (grouped by kind, awake kinds first, the Furnace belt added), owns its own
  `Camera3D` (made current for the intro, copies the rig camera's cull mask/attributes/env), and
  hands back to the rig camera at the end. The drop shot eases onto the rig camera's LIVE pose, so
  it lands exactly where the countdown camera is.
- `Arena/ui/intro_overlay.gd` (`IntroOverlay`): Broadcast lower third bottom left (title in
  display type, one line under it), a danger wash in the fill for hazards (no strokes: owner rule),
  "TAP TO SKIP" / "ANY BUTTON TO SKIP" pill bottom right.
- `fight.gd` section "wave B: fight intro" (end of file) plus five tagged hunks ("wave B intro"):
  the hold in `_physics_process`, `_begin_intro(config)` after `_set_state(COUNTDOWN)`,
  `_end_intro()` in teardown, YOU only once the drop is half done (through the intro camera), and
  the countdown/coach/controls held back while the intro runs. The HUD is hidden during the
  fly-past and comes back halfway through the drop.
- `hazard_telegraph.gd` section "Fight intro preview": `preview_frame(overrides, delta)` paints
  every hazard through the layer's own `_stage`/`_paint` while the tree is paused, with the
  featured hazard's `in_s/active/contact` overridden (warning -> strike on the intro clock); no
  strike, no haptic, no wind-up sound. `end_preview()` resets that state.
- Demonstrations are GHOSTS: duplicated meshes of the spike bodies (rise 0.45 m), the rams (the
  0.9 m stroke), the pit cover leaves (slide open, pit light on); fresh FlameCones on the featured
  jet bank (their lights off, they blew the frame out); the grinder discs and turntable tops (paint
  only) are spun. The real meshes are hidden while their ghost plays; everything touched is
  recorded and put back (the test checks every arena mesh's visibility and transform at the end).
- The venue kit is set PROCESS_MODE_ALWAYS for the intro (crowd, lights, plumes keep moving; it is
  hash-inert per venue_kit_test), back to its own mode after and while the user pause is on.
- Hooks: `Fight.intro_beat(beat, info)`: intro_start, intro_arena, intro_hazard, intro_drop,
  intro_skipped, intro_end. The kit gets `excite` (0.35 start, 0.25 per hazard, 1.0 + `fire_pyro
  gate0` at the drop). `FightFx.on_intro_beat` is called if it exists (not yet).

## Timings

| | |
|---|---|
| full | open 1.3 s (1.05 with 4+ kinds), each hazard 3.4 s / n clamped 0.95..1.6 s, drop 1.2 s |
| full, measured | Yard / Grinder / Furnace / Crush 5.7 s, Drop Zone 4.1 s, Coliseum 6.05 s |
| short | one sweep 1.1 s naming the arena and its hazards, drop 0.9 s = 2.0 s |
| skip | straight to a 0.45 s drop |
| in a hazard shot | 0.42 s fly-in (arcs up 0.9 m), warning to 45 %, then the act; ghost retracts 0.3 s after |

## Who gets which (Swift, `Roboteer/IntroPolicy.swift`)

- full: first fight in that arena on this device (UserDefaults `intro.seenArenas`, marked when
  the arena reports the countdown, so a fight that never started does not use it up).
- short: an arena already seen.
- none: test arena; events and replays (`startEvent`/`startReplay` clear `introNextFight`); a quick
  restart (same arena within 180 s of the last start, in memory only).
- `ArenaHost.introNextFight` is injected at send time like `coach`, never stored in
  `lastFightConfigJSON`. Godot: no key or an unknown value = none; a replay block or
  `rules.mode = test` = none whatever the key. Desktop: `--roboteer-intro=full|short` when no key.

## The determinism proof

The intro takes no tick: `_physics_process` returns `take = false` while `FightIntro.holding()`,
the same tree-pause hold hit-stop uses (PhysicsServer does not step, no hazard, bot or AI runs).
`tests/intro_test.gd` fights the desktop fixture in all six arenas with intro none and full (Yard
and Coliseum also short, Crush also full SKIPPED by an injected touch at 0.6 s) and hashes, every
30th ARENA tick from the first (countdown included) to arena tick 480: arena tick, fight tick,
state, both chassis transforms (var_to_bytes), condition, hazard_helpers and every schedule entry
(id, in_s, active, contact). All identical. Also checked: at the intro's end the arena is at tick 0,
the countdown at 0 s, both machines exactly on their spawn transforms, every arena mesh as it was,
no ghost left, the rig camera current; replay and test configs get none. The Coliseum full intro
runs at 1x (6.05 s), the rest at `FightIntro.test_speed = 3` (the intro's own clock only).

## QA

- `Godot --path Arena --audio-driver Dummy --resolution 1206x556 --script qa/intro_capture.gd --
  --intro-shots=DIR [--intro-arenas=a,b] [--intro-mode=short] [--intro-sequence=10]`
- Contact sheets were built from DIR with a small PIL script (one row per arena).
- Desktop fight with an intro: add `-- --roboteer-intro=full` to the autostart run.
