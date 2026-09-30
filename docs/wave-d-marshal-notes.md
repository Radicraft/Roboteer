# Wave D: the Marshal, house bot mischief, crowd verdict (branch wave-d-marshal)

Owner decisions 30 Sept 2026 (docs/aaa/decisions-2026-09-30.md). Worktree
/Volumes/RoboteerBuild2/Code/Roboteer-marshal.

## What is built (so far)

- **Model** `Tools/blender/marshal/build_marshal.py` -> `Arena/assets/marshal/marshal.glb`
  (4,738 tris authored). Four-duct hover drone, flat octagonal body (light grey shell over a
  dark keel), light bar of 10 segments across the TOP of the nose (tipped 25 degrees forward
  so the steep fight camera and the finish orbit both see it), mast beacon, chin nozzle,
  winch ring, skids, card slot on the right flank. Not a person: no head, arms, chest panel
  or stripes. Drawn at 1.35x in Godot (`MODEL_SCALE`) so the bar reads at fight distance.
- **Arena/fight/marshal.gd** (`FightMarshal`): presentation only (no body/collider/area,
  no rng). Driven by fight.gd's presentation drain with wall delta x hit-stop pace
  (`HitStop.pace()`, new, read only). Modes: start (3/2/1 blocks amber, FIGHT all green,
  lift away), patrol (just out of the top of the frame), count (segments = HUD seconds
  left, red at 3), tow / unstick (arms on the rules' own timers at 35 %, tow lines drawn
  on the impulse tick), spray (burn/heat damage or a live arena flame within 1.1 m), stop
  (all red), card (yellow card, bar yellow). Wobble when anything > 1.6 m/s passes within
  0.6 m. Placement is IN THE FIGHT CAMERA'S FRAME: a screen spot beside the subject, clear
  of the HUD (SAFE_X/SAFE_Y), cut at a height above the subject (`_show_spot`).
- **Arena/fight/mischief.gd** (`FightMischief`): pure planner for the finishing ritual
  (wait 30 RESULT ticks, approach behind the loser detouring round the winner, shove at
  the nearest hazard, optional late hit 40 ticks, back off 70 ticks). Kind = hash of the
  seed, 1 in 4 late; `presentation.mischief` / `--roboteer-mischief=` force it.
- **fight.gd wave D section** (end of file) + hooks: `_show_moment` queued from the tick
  (fight_start, lockup, unstick, result, house), drained in `_show_present`; POWER DOWN on
  the HUD band (delayed 1.4 s after a payoff sting) and the venue screens; verdict
  clear/close (margin <= 2 of 10 points) -> crowd after 0.9 s; mischief planned in
  `_finish` AFTER the result is built, run in `_tick_finish`; finish beat +3.0 s ritual /
  +4.8 s late, sent as `finish_beat_s` on fight_state result; wider orbit (5 m, 48 deg)
  when mischief runs (`begin_wreckage_orbit` got optional distance/pitch).
- bot.gd `resume_for_show()` (house bot only), drive_base `thaw()`.
- Commentary hooks via `_show_event(key, ctx)` -> `_commentary.call_event` if present.
  `show_events` keeps the keys for tests. unstick uses `lockup_tow` with ctx.kind "unstick".
- Crowd: `crowd_boo.wav` (gen-sounds.py `crowd_boo`, `--only` flag added), AudioMix
  `crowd_boo` (-3 dB, same RMS as the roar, measured), swells `verdict_clear` (roar) and
  `verdict_close` (boo). Picture: kit `crowd_react(kind, strength, origin)` if present,
  else crowd `react(String,...)`, else kit `excite`. audio_test: 3 new checks, 120/0.

## Traps found

- `scripts/gen-sounds.py --patch-imports` now FIGHTS the size wave: it resets 16 imports
  back to PCM. Revert them if you run it (done here); only crowd_boo.wav.import is new.
- Replay scripts are SPARSE: a tick with no row is idle. Hold a stick = one row per tick.
- The fight camera frames the player tightly (fov 28); a world-placed Marshal was never in
  shot. The finish orbit is 2.6 m from the wreck: the Marshal keeps out of close shots.

## Hash proof (so far)

- marshal_test: the fixture with the Marshal ON and OFF hashes the same, tick for tick
  (chassis transforms, conditions, hazards, scrap every 30th tick, var_to_bytes): Yard
  c814ec9e2c1a3b19 (= the hazard_determinism golden), Coliseum 68fa59d64e8fd474 to tick 900,
  and a forced shoving match broken by the rules (1 break both ways) 21d3109041d831a7.
- mischief_test (Grinder, GRUDGE, 3 s count, the player's machine KO'd at tick 2635): OFF,
  RITUAL and LATE give the same fight_result (every key but the two wall clock stamps under
  diagnostics), the same 2635 replay rows and the same hash 4f82b6dabfa94fc0 through the
  first RESULT row; the house bot drove 4.1-4.2 m after the result; neither machine's
  condition moved after the result; the LATE fight's replay hashes the same. Player wins:
  target is ai-1, house bot never nearer the player than 2.3 m. Judges: no mischief.
- Approach chosen: run AFTER the result is sealed (not a presentation copy). The result is
  built and sent in `_finish` before the plan exists; the house bot first moves on RESULT
  tick 30; competitors are `stop_for_result`ed so no damage lands (bot.gd refuses it).

## The pin rule (task 4): evidence and decision

Pacing gauntlet (qa/pacing_gauntlet.gd, 6 arenas x flipper/hspinner/crusher/saw x seeds
11, 22 = 48 AI-vs-AI fights; the player side is a National brawler that pins, the opponent
a Regional that cannot; new columns pins / pin_s / pin_longest_s / lockup_breaks /
pin_breaks):

| run | judges | ring-outs | pin s / fight | longest pin | lock-up breaks | blows/min |
|---|---|---|---|---|---|---|
| before (AI lets go at 3 s, no rule) | 22 % | 8 | 19.9 | 3.0 s | 54 | 9.05 |
| AI release removed | 35 % | 3 | 30.8 | 28.1 s | 95 | 8.15 |

Removing the fake rule made pins oppressive (and pushed decisions back up toward the 33 %
the owner complained about on 27 Sept). So, per the brief, a REAL pin rule instead:
fight.gd `_tick_pin_limit` / `PIN_LIMIT_S = 4.0`: a machine held on a wall (<= 0.95 m) by
the other (within 1.35 m, stick into it, dealing it no damage for 2 s, victim < 0.3 m/s)
for 4 s is freed: the Marshal tows the pinner back at 1.2 m/s (impulse, sim tick, replays
match), `lockup_tow` with ctx.kind "pin". The AI keeps its 3 s release, now honest.
First cut without the "no damage" clause fired 107 times in 48 fights (wall grinds by
spinners and saws counted as pins) -- narrowed.

| final: real 4 s rule, AI release kept | 25 % | 8 | 22.0 | 3.0 s | 48 (+11 pin breaks in 5 fights) | 9.25 |

32 of 48 fights identical to "before"; the rest diverge after a break. Goldens: only
hazard_determinism drop_zone moved (3c8a0a72052ca8cf -> ba6a58ff2e2a9c78); with
`fight.gd pin_rule_enabled = false` (a test-only static) it gives back the old hash
exactly, and the test now proves that on every run. The other five are unchanged.

## Other changes worth knowing

- Swift: `ArenaHost.finishBeatSeconds` from `fight_state` result `finish_beat_s` (clamped
  3.5..10 s, reset per fight); `FinishBeatGate(started:seconds:)` in FightView and
  CareerFightView.
- Commentary (main's `call_event`): `_show_event` goes through main's `_commentary_event`.
  fight_start and verdict_* are NOT sent from here (the commentary fires them itself via
  step / note_result with the same 2 point margin); they are still recorded in
  `show_events`. Keys sent: fight_stop, count_start (once per fresh count), count_out,
  lockup_tow (ctx.kind lockup | unstick | pin), fire_out, marshal_wobble, house_finish,
  house_late_hit, house_card.
- Crowd: `VenueKit.on_crowd_reaction("verdict_clear" / "verdict_close")` (crowd C's route),
  plus the mixer swell of the same key. The late hit boos, the delivered shove cheers
  ("big_hit").
- camera_rig `begin_wreckage_orbit(center, distance, pitch)`: optional args; mischief uses
  5 m / 48 degrees so the house bot's run in is in shot.
- MAIN HAD A DUPLICATE `_commentary_event` after the commentary merge (a parse error that
  hangs every fight test); fixed on main 24c5741 and never reintroduced here.
- DISK: `--write-movie` PNGs filled the system disk (2 GB) once, which also broke a suite
  run writing to /var/folders. Movies and suite temp now go to
  /Volumes/RoboteerBuild2/marshal-scratch (delete it when done; 2 GB).

## Review page

docs/look/marshal.html (+ docs/look/marshal/: 34 JPEG stills, 6 WebP clips, 7.4 MB).
Capture: `Godot --path Arena --audio-driver Dummy --resolution 1206x556 --script
qa/marshal_capture.gd -- --marshal-shots=DIR [--marshal-scenario=...]`; turnaround
qa/marshal_turnaround.gd; clips: add `--write-movie DIR/clip.png --fixed-fps 30` for one
scenario, then docs/look/marshal/make_clips.py.

## Where I stopped

DONE (branch wave-d-marshal, merged with main 313539e, not pushed, not merged):
- Full suite HEADLESS=1 JOBS=2 (the 2-process cap; JOBS=6 would have been 6 Godot procs):
  51 test files, 0 failures. marshal_test 42/0, mischief_test 34/0, hazard_determinism 16/0,
  audio_test 120/0.
- scripts/build-sim.sh: BUILD SUCCEEDED (pck 89.5 MB in the worktree, not committed).
  Career self test on one iPhone 17 sim: ALL PASS (1098 checks, 2 pacing warnings, the same
  two as before); sim shut down.
- Review page docs/look/marshal.html (not published; publish with its docs/look/marshal/
  folder as supporting files).

OPEN / OWED:
- Owner calls on the page: the look, the pin rule (gameplay change), the 7.1 / 8.5 s finish
  beat with mischief, the Marshal keeping out of the 2.6 m wreck close-up, an ear check on
  the generated boo.
- Phone: frame time with the Marshal (one omni light, 10 materials, 48 particles) not
  measured on device; the Swift finish_beat_s path is compiled but only exercised on a phone
  or sim fight (self test does not fight).
- Swift unit coverage for finishBeatSeconds: none (a one-line clamp).
- The venue screens' POWER DOWN uses VenueKit._sting (a private method, has_method guard);
  a public `show_word` on the kit would be cleaner.
- /Volumes/RoboteerBuild2/marshal-scratch holds only logs now (movies deleted).
