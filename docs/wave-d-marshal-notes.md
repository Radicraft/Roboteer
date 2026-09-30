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

## Where I stopped

- WIP committed. NEXT: merge main (7cfa64b), run marshal_test (written, not yet run),
  write mischief_test, pin rule (task 4, not started), Swift finish_beat_s (not started),
  captures + clips + docs/look/marshal.html, full suite, build-sim + self test.
