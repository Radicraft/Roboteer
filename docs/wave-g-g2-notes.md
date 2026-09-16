# Wave G, agent G2: house bots and the corner zone

Brief v4 §3 plus §10 item 1, against `docs/wave-g-contracts.md` (the "Corner zone and house bot"
row). Everything below is built, headless-tested and green; nothing in it has been felt on a
phone yet, because a house bot is a thing you have to stand next to.

## What is on the floor now

A career fight (`rules.mode == "fight"`) that names `rules.enforcer` gets a house bot from the
countdown. It stands on its mark in a marked 2.2 m corner, sweeping and ticking its weapon over.
Anything that drives into the corner is attacked until it leaves plus two seconds, and then the
house bot goes back to its mark. Fifteen seconds of the two machines not touching each other
still brings it out (the Stage 5 rule, unchanged). At the endgame the stripes go red, it leaves
the corner and hunts whichever machine has the lower `Rules.condition_total`, picking again every
five seconds, and it never goes home again.

It is still not a competitor: no scrap, no judges' points, not in `_bot_ids`, so no win condition
can name it. What it does to you is credited to whoever shoved you into it inside
`Rules.TOUCH_CREDIT_S`, exactly as a hazard's damage is.

## The three rules keys

| key | values | default |
|---|---|---|
| `rules.enforcer` | a boss id ("thresher") or an ai_mode ("pin"), "" for none | "" (unchanged) |
| `rules.enforcer_mode` | `"zone"`, `"idle_only"`, `"off"` | `"zone"` when `enforcer` is set, `"off"` when it is not |
| `rules.enforcer_speed` | 0.05 to 1.0 | 1.0 (Scrapyard sends 0.5) |

`"idle_only"` is the Stage 5 behaviour and only that: nothing on the floor until fifteen seconds
of no contact, then in from the gate, then home once the two of them are fighting again. Nothing
about the endgame touches it.

**One line changed in another agent's file.** `Arena/tests/rules_test.gd` `_test_enforcer()` now
asks for `"enforcer_mode": "idle_only"` in its rules dictionary, because the behaviour it asserts
is now one of three and the default is the new one. G1: that is the only edit G2 made to your
test, and it is the edit the contracts file anticipated ("idle_only, the old behaviour, for
existing tests").

## Speed

`enforcer_speed` scales the DRIVE and the TURN, never the weapon: a half speed THRESHER still
crushes at full strength, it just takes twice as long to reach you and twice as long to come
about. Drive is the throttle (the length of the heading). Turn is done by slewing the commanded
direction at `FightTypes.TURN_RATE_4WD * speed` rather than handing the machine a new direction
every tick, because the drive module always turns as fast as it can toward whatever direction it
is given, so limiting the machine means limiting the command. The maths is one pure static
function, `Fight.enforcer_heading_step(previous, want, speed, delta)`, so the test drives it
without a physics world.

## The corner zone

`Arena/arena/corner_zone.gd`, `class_name CornerZone`, a `Node3D` added under the arena node (it
dies with the world the fight built). API exactly as the contracts file has it:
`zone_rect() -> Rect2` (floor XZ in metres), `contains(position: Vector3) -> bool`,
`set_zone_state("idle" | "alert" | "released")`, plus `centre(y)` for the mark, `zone_state()`,
`marking_colour()` and the static `rect_in_corner(corner, half_extent)`.

- The square is 2.2 m on a side, held 0.3 m off the walls, in the corner `fight.gd`'s existing
  `_gate_position()` already uses (+X -Z). It is built from the arena's real half extent, so the
  Coliseum's corner hugs the Coliseum's walls rather than the Yard's.
- Drawn as ten `MeshInstance3D` boxes (a four bar frame plus six stripes) sharing one
  `StandardMaterial3D` with emission. No shader, no transparency, no decal, no `ArrayMesh`
  tricks: it draws the same on `gl_compatibility` (the phone fallback and the Simulator) and on
  Forward+, and a state change is one albedo write.
- Colour comes from the arena when the arena publishes `warning_colour()`, and from the shared
  amber otherwise. Alert lights the same amber; released is red.

## HUD

`hud.gd` gained one section: `set_zone_warning(on, name)` raises a pulsing red band inside the
safe area with the house bot's name under it, and `show_zone_coach()` draws
"Corner zone. The house bot guards it." for four and a half seconds. The warning draws on its own
`ZoneOverlay` control with its own `_process`, so no existing HUD drawing or frame loop was
touched. `zone_warning_visible()`, `zone_warning_name()`, `zone_coach_visible()` and
`zone_step(delta)` exist for the headless test.

The coach line is shown once per fight, the first time the PLAYER's machine is in the corner, and
only when the HUD's coach is enabled. That is the closest honest reading of "the first time in a
career": `CoachPolicy` is what arms the coach for a player's first fights, and the arena has no
idea what a career is. If the owner wants it strictly once ever, the flag belongs in Swift and
`show_zone_coach()` should be called from there.

## AI context

`_ai_context()` now carries `house_bot_position: Vector3`, `zone_rect: Rect2` and `phase: String`
for G3. All three are present always and harmless when there is no house bot (`Vector3.ZERO`, an
empty `Rect2`, `"open"`). Reading them draws nothing from the rng.

The phase comes from G1's `fight_phase()` when it exists and from the clock when it does not, and
the release is driven by G1's `phase_changed` signal with the same poll as a fallback, so the
release lands whichever half of wave G is on disk.

## Swift

- `CareerEngine.houseBot(tier:arena:) -> (id: String, speed: Double)`: Scrapyard THRESHER 0.5,
  Regional CINDER, National BANDSAW (GRUDGE in the Furnace), Championship ANVIL (THRESHER in the
  Crush), Masters paired to the arena through `CareerEngine.bossForArena`. This replaced G5's own
  stub, which asked to be replaced in its comment; `houseBotName` and `houseBotLine` are G5's and
  were left alone. **G5: `CareerFightView` already calls it; nothing needs to move.**
- `CareerSelfTest.checkHouseBotChoice()` checks every tier and arena pair, the two the brief names
  outright, and the Quick Fight default. (G5's `checkHouseBots()` was being called twice in
  `run()` after our edits crossed; the duplicate call is gone.)
- `QuickFightChoice.houseBot: Bool?` and `houseBotOn(tier:)`: unset means the tier decides, on
  from Regional up and off at Scrapyard, and a rumble never has one (three machines and a house
  bot is four; brief §10 item 3 leaves rumble alone). Remembered in `UserDefaults` only once the
  player has actually moved it. The picker has a HOUSE BOT row and the pad can reach it.
- The wiring: `FightView` -> `ArenaHost.startFight(houseBot:)` -> `FightConfigFixture.fightJson`,
  which writes `enforcer`, `enforcer_speed` and `enforcer_mode: "zone"` into the rules. Both of
  those are G1's files and both changes are one optional parameter plus three lines, in their own
  block.

## Tests

`Arena/tests/enforcer_test.gd` (new), 78 checks: zone geometry and the three states, the renderer
safety of the marking, the speed limiter (half throttle and twice as long to come about), zone
mode from the countdown, the attack and the two second return, the fifteen second rule still
firing, the leash that keeps it inside the walls, the three new `ctx` keys, `idle_only` and `off`,
the endgame release and its five second re-target, "it never scores" including the shove credit
and its expiry, and the HUD warning and coach line.

`rules_test.gd` still passes (one line changed, above), `determinism_test.gd` still passes: no
fight in the suite carries an enforcer, so no replay changed. Inside a zone fight the house bot's
driver draws from the shared rng on a fixed cadence like every other driver, so a replay of a
house bot fight lands on the same ticks.

## What could not be verified here

- How it FEELS: whether the corner reads as somewhere you do not go, whether the two second
  return is long enough to hurt, whether a half speed THRESHER is gentle or just slow.
- The look of the marking under the arena lighting, and whether the red is legible on the phone.
- The self righting (four seconds, then the machine is stood back up where it lies): it fires in
  headless code but has never been watched.
- The HUD flash against the real safe area on a notched phone.
