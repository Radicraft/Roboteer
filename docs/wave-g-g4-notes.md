# Wave G, agent G4: the camera

Brief v4 (`docs/brief-v4-playtest.md`) §5, built 2026-09-16. One file of engine code changed,
`Arena/ui/camera_rig.gd`, plus one new test and two rewritten checks in an existing one.
`MODE_FIGHT` only: the workshop turntable and the menu drift are byte-for-byte what they were.

## What the owner reported

> the camera does not follow the player

He was right, and the old code says why in its own comments. The fight aim was
`centre.lerp(midpoint_of_the_pair, t)`: it started at the arena centre and slid toward a
weighted midpoint of the two machines, and the slide was clamped so that no visible metre of
ground could ever fall outside the floor rectangle. At the distance the framing actually
rests at (about 11.6 m on an iPhone 17 landscape viewport) that clamp computes to **zero**:
the visible ground already overhangs the floor on every side, so the aim was pinned to the
arena centre and the player drove around inside a fixed wide shot. The 2026-09-14 pass had
noticed half of this and added a "player-priority floor" escape for the DISTANCE, but the
AIM kept the old clamp, so the camera got closer without ever following anybody.

## What it does now

1. **Aim = player + lead.** `_fight_look()` takes `_target_a` (the player, by contract) and
   adds `LOOK_LEAD_FRACTION` (25 %) of the vector to the opponent, capped at
   `LOOK_LEAD_MAX_M` (1.2 m), flattened to the floor plane so a machine thrown into the air
   cannot tip the camera up with it. Eased with `SUBJECT_EASE_S`, which is unchanged.
2. **The player stays near the middle, always.** `_hold_player_in_frame()` is a leash applied
   to the aim AFTER the ease, every frame, so the guarantee holds mid-charge and not only
   once the ease has settled. It is exact, not iterative: the projected offset of the player
   is a ratio of two affine functions of the scale applied to the aim offset, so the largest
   admissible scale drops out of one division per screen axis (`_axis_scale`).
3. **Where the old footprint clamp survives.** The floor-footprint rule is not deleted, it is
   blended: at the tracking pose the aim may go anywhere on the floor, and as the player
   pinches out toward `CAM_ZOOM_MAX` it returns, reaching the old behaviour exactly at the
   walls-on-screen fit. So pinching out still gives the composed, centred, whole-arena shot
   (three existing tests depend on that), and letting go gives the tracking camera back.
4. **Zoom.** `_subject_distance()` fits the pair with `SUBJECT_MARGIN_BOTS` as before, but the
   opponent is first clamped to `TRACK_PAIR_RANGE_M` (4 m) from the player. Clamping the
   position rather than switching rule keeps it continuous: at exactly 4 m the two agree, and
   past it the distance simply holds. `PLAYER_MIN_FRACTION` is still the hard ceiling.
5. **`endgame_reveal()`**, the only scripted move in a fight: `REVEAL_OUT_S` 0.6 s out to the
   arena fit, `REVEAL_BACK_S` 0.8 s back, smoothstep on both legs so it starts, turns and
   lands with no kink. It is MIXED OVER the tracking pose rather than replacing it (the rig
   keeps `_track_look` / `_track_distance` underneath), which is why it lands back exactly
   where tracking had got to instead of near it. No input, no cut, and a second call restarts
   rather than stacks. It is a no-op outside `MODE_FIGHT`, so G1 can call it unguarded.
6. **Steering is safe.** `fight.gd._heading_to_world()` rotates the stick vector by the fight
   camera's yaw, so a camera that turned itself would turn the controls under the owner's
   thumb mid-fight. Nothing here ever changes yaw: the tracking moves the AIM and the
   DISTANCE only, and the endgame reveal pulls straight back along the same yaw. The stick
   mapping is therefore exactly as stable as it was, including through the reveal.
7. **Untouched:** yaw -135 / pitch 50 defaults, manual orbit and tilt, the 3 s ease back, the
   wreckage orbit for the KO count and the result, the QA `--roboteer-*` arguments, the impact
   shake, `set_targets(a, b)`, `set_mode`, and every workshop and menu constant.

## Measured, headless, 1206 x 556 (iPhone 17 landscape)

| | |
|---|---|
| Worst the player ever sat from frame centre, driving a 3 m square at 2.5 m/s for 584 frames with the opponent parked 6 m away | **16.2 %** of the frame (the brief allows 30) |
| Lead carried, worst case over that run | 1.200 m, the cap exactly |
| Tracking distance, 1.5 m apart | 9.88 m |
| Tracking distance, 3 m / 4 m / 6 m / 9 m apart | 11.60 m at all four: the `PLAYER_MIN_FRACTION` ceiling takes over at about 3 m, and the 4 m hold behind it |
| Player's on-screen size, worst case | 10.2 % of the frame height (the floor is 10 %) |
| Opponent 6 m away | 36 % out, so past the centre band: that is the frame the HUD arrow is drawn for |
| Endgame reveal | 11.6 m out to 28.7 m and back; biggest single frame 0.711 m, 4 % of the move |

## The two judgement calls worth arguing with

- **`PLAYER_LEASH_LIMIT` 0.25 against the brief's 0.30.** The leash measures the player's
  GROUND point, which is cheap and exact. The chassis origin stands about 0.25 m above it
  (roughly 3 % of the frame at the tracking distance) and the impact shake moves the camera
  by up to 7 cm (about 1 %). Holding the ground point at 25 % is what makes the MACHINE
  obey the brief's 30 %, and `camera_track_test.gd` measures the machine, not the ground
  point, so the brief's rule is what is actually under test.
- **`PLAYER_MIN_FRACTION` stays at 0.10.** The brief names the constant, so I did not move
  it, but it is now the binding constraint for most of a fight: past about 3 m of separation
  the camera sits at the distance where a nominal machine is 10 % of the screen height
  (55 pt on a 556 pt screen) and stays there. If the owner still says "too far" on the phone,
  that one number is the lever, and nothing else needs to change to pull it.

## Contract changes

Written into `docs/wave-g-contracts.md` under Camera (G4): three new public methods
(`is_revealing`, `reveal_blend`, `look_lead`), seven new constants, the widened meaning of
`is_player_floored()` (now "the camera is holding", which is the same thing it always meant
to the HUD), and one removal, `PLAYER_LOOK_WEIGHT`, which brief v4 §5 makes
meaningless. Its only users outside the rig were two checks in `Arena/tests/ui_test.gd`,
rewritten in place to assert the lead rule. No wave-G agent owns that file (V2 owns it in
wave V) and nothing else in the repo referenced the constant.

`docs/bridge-spec.md`'s "Default fight framing" section still described the midpoint aim and
the 65/35 lean as current, and still said "yaw 45" when the default has been -135 since the
camera was moved behind the player's spawn. Both corrected in place; the paragraph now says
what the code does. Nobody owns that file in wave G and the edit is one paragraph about the
camera only.

## Tests

- **New: `Arena/tests/camera_track_test.gd`**, 30 checks, green. Everything is measured
  through a real `SubViewport` and the camera's own `unproject_position`, never through the
  rig's own arithmetic, because the rig believing it framed the player is precisely the bug.
  Covers the brief's own test (the square drive), the lead cap, the zoom hold at 4 m, the
  `PLAYER_MIN_FRACTION` floor, the reveal out-and-back including a no-cut check on the
  largest single frame, that tracking resumes afterwards, and that manual orbit and the 3 s
  ease back still work and still keep the player in the band.
- **`Arena/tests/stage_camera_test.gd`**: unchanged and green (14 checks). It checks the
  workshop and menu modes and that fight mode ignores forwarded stage gestures; nothing in
  this work touches any of that.
- **`Arena/tests/ui_test.gd`**: green (298 checks), with the two `_test_bot_framing` checks
  described above rewritten. Its other camera checks were left alone deliberately and they
  are the reason the pinched-out composition was preserved rather than deleted.
- **`Arena/tests/workshop_test.gd`**: green (86 checks), untouched. `render_test.gd` (104
  checks) too: it poses the fight camera, so it is the fifth file worth re-running after any
  change in here. The five together are the whole camera surface: `camera_track_test`,
  `stage_camera_test`, `ui_test`, `workshop_test`, `render_test`.
- Whole suite run to completion before finishing: **24 of 25 test files green**. The one red
  is `ai_test.gd` (160 checks, 9 failures), which is G3's own file being built at the same
  time; it was green earlier in the same session and none of its failures touch the camera.
  `determinism_test` passed in the same run (42 checks, 0 failures, drift 0.000000000 m),
  which is the check that matters here: the camera is presentation only and a replay must
  stay bit-exact whatever it does.

## What a phone would have to tell us

Everything above is geometry, and geometry is exactly what a headless run can prove. What it
cannot say is how the tracking FEELS in the hand:

- whether `SUBJECT_EASE_S` 0.35 reads as smooth or as lag when you reverse into a slam;
- whether a 1.2 m lead is a helpful nudge toward the fight or a camera that drifts;
- whether 10 % of the screen is a machine or still a dot on a 6.3 inch panel;
- whether the endgame pull-back lands as a moment or as an interruption at 2:00;
- whether the leash is ever visible. On the numbers it binds only when the ease is more than
  about two metres behind the player, which no measured frame of the square drive reached, so
  it should never be seen. If the camera ever feels like it is being tugged, that is the
  thing to look at first.
