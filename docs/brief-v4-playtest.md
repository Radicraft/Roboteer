# Roboteer brief v4: the playtest brief

Written 2026-09-16 with the owner, after the first real hands-on session on an iPhone. It sits on
top of brief v3 (`docs/brief-v3.md`); where the two disagree, this one wins. It is the brief the
next two waves of agents build from. Nothing in it is optional.

## 0. Why this brief exists

Until 09:27 on 2026-09-16 nobody had ever driven a bot on a phone. Two bugs stood between a thumb
and the stick (the navigation container swallowing touches, then the kit's touch bridge raising
nothing inside the engine), so every "feel" judgement in the game so far was made by AI fighting
AI in headless tests, and every sign-off that said "controls work" meant "the desktop Godot window
works". The owner's first fights found, in his words: enemy AI is stupid, arenas have no house bots
and nothing opens up at the end, fights are too short, there is no clear career mode, the camera
does not follow the player, the house bots look blurry, the main menu looks amateur, the UI
elements are basic including the controllers.

Standing rule from today: **a feature is done when the owner has played it on the phone.** The
Simulator cannot take a touch, so it is for layout and functional checks only. Every wave ends
with a Release build installed on his iPhone (recipe in the memory file and `docs/stage1-build-notes.md`).

## 1. Decisions locked with the owner on 2026-09-16

| Question | Decision |
|---|---|
| Fight shape | One 3 minute round with an **endgame at 2:00**: the arena escalates, a house bot is released, judges at the bell |
| House bots in career fights | **Corner zone plus endgame**: from Regional up, one house bot guards a marked corner zone all fight and attacks anything that enters; at the endgame it comes out and hunts |
| Camera | **Tracks the player at a fixed angle**, glides to keep the player near centre, zooms out as the opponent gets further, off-screen arrow for the opponent; steering stays screen-relative |
| Career | **Season bracket with a next-fight card**: each tier is a visible bracket of 8, the home screen shows your position, the next opponent with a scouting report, entry fee and prize; win the final to move up |
| Look | **B. Broadcast** (`docs/look/b-broadcast.webp`): the game presents itself as a televised championship |
| Arena HUD | **One system everywhere**: the Game Boy green chrome from v3 §13 is retired; timer, scrap, names, coach, pause and controls all follow the Broadcast system |
| Touch controls | **A styled pad in the Broadcast look**: visible stick well and weapon buttons drawn as parts of the UI, semi-transparent over the arena, pressed states, weapon icons |
| Sequence | **Gameplay wave first, then the visual wave.** Gameplay lands and is played on the phone before the look is applied to settled screens |

## 2. Fight shape

Constants live in `Arena/fight/fight_types.gd` and are read by the HUD, the rules, the replays and
the Swift shell (timer label, replay lengths, result sheet).

- `FIGHT_DURATION_S` 90 -> **180**. `COUNTDOWN_S` 3 and `KO_COUNT_S` 10 stay. `PLAYER_KO_GRACE_S` stays.
- **Phases:** `OPEN` 0:00 to 2:00, `ENDGAME` 2:00 to 3:00, then the bell and the judges if nobody is out. The phase is a field on `fight_state` over the bridge (`phase: "open" | "endgame"`) so the shell and the HUD can react; the replay recorder needs nothing new because the phase is a function of the tick.
- **The endgame moment** at exactly tick 120 s: a horn, the arena lights shift (a cold key light to a hot one, 0.6 s), the HUD stamps ENDGAME for 1.5 s, the camera pulls back 0.6 s to reveal the floor, then returns to tracking. Haptic: one heavy transient. This moment must be unmissable.
- **Arena escalation at the endgame**, per arena (each arena implements `set_phase(phase)` in `arena_base.gd`; `_seed_hazards` keeps its seeded timers for the open phase):
  - Yard: the centre spike patch stays risen for the rest of the fight.
  - Grinder: both flank grinders run continuously.
  - Drop Zone: the pit opens and never closes again (`REOPEN_S` ignored in the endgame).
  - Furnace: jets fire on a 4 s period, the belt runs at double speed.
  - Crush: the rams cycle at half the period.
  - Coliseum: all of the above that it has, plus the floor discs spin at double speed.
- **Judges:** the scoring windows scale with the round: `JUDGE_AGGRESSION_FULL_S` 45 -> 90, `JUDGE_CONTROL_FULL_S` 15 -> 30. Damage scoring unchanged. Test: a fight where neither bot moves is a draw at 3:00.
- **Side events** keep their own clocks (`PAR_S` and friends); they are untouched by this section.
- The house bot is released at the endgame moment (section 3).

## 3. House bots in career fights

The five bosses (`Arena/ai/boss_ai.gd`, `Shared/parts.json` bosses) become part of every career
fight from Regional up. They stay what v3 §8 says they are: enforcers, not competitors. They take
no scrap, score no judges' points, and no win condition looks at them. Damage they do is credited
to the last toucher inside the existing 2 s window (`Rules.TOUCH_CREDIT_S`), so shoving an
opponent into a house bot is a real tactic.

- **One house bot per fight**, named in `rules.enforcer` by the Swift shell (already the contract). Which one: Scrapyard none; Regional CINDER; National BANDSAW or GRUDGE; Championship ANVIL or THRESHER; Masters any, the shell picks per arena so the pair makes sense (CINDER in Drop Zone, GRUDGE in Furnace, THRESHER in the Crush, ANVIL in the Coliseum). Scouting reports name it.
- **The corner zone.** A painted no-go zone in the corner the current gate logic already uses (`_gate_position()`, the +X -Z end of the free diagonal), 2.2 m square, striped in the arena's warning colour. The house bot sits in it from the countdown, visibly idling (turret sweep, saw tick-over). A bot that enters the zone is attacked until it leaves plus 2 s; then the house bot returns to its mark. The existing inactivity rule stays: fifteen seconds without contact and it comes out anyway (`ENFORCER_IDLE_S`).
- **The endgame release.** At 2:00 the zone stripes go red, the house bot leaves its mark and hunts the bot with the lower condition total (`Rules.condition_total`), re-targeting every 5 s. It never withdraws again. It cannot leave the arena and cannot be knocked out; it can be flipped, and rights itself after 4 s.
- **HUD:** entering the zone shows a red edge flash and the house bot's name; the first time in a career, a coach line: "Corner zone. The house bot guards it."
- Test arena and Quick Fight get a toggle for the house bot (Quick Fight defaults on from Regional tier, off at Scrapyard).

## 4. Opponent AI

`Arena/ai/opponent_ai.gd` is one behaviour with per-weapon profiles: standoff ring, circle, strike
on a good angle, back off, right itself, avoid spikes. It has never fought a moving human. It
becomes **skill tiers x personalities**, deterministic as before (fixed draw order on the shared
rng, the replay contract is untouched).

**Skill (one per career tier, also used by Quick Fight and the ladder):**

| Tier | Reaction delay | Aim error | Hazard awareness | Uses walls | Srimech | Counter-build reading |
|---|---|---|---|---|---|---|
| Scrapyard | 0.6 s | 25 deg | spikes only | no | slow | none |
| Regional | 0.45 s | 18 deg | all hazards | no | normal | weapon type |
| National | 0.3 s | 12 deg | all + house bot zone | pin | normal | weapon type + armour faces |
| Championship | 0.2 s | 8 deg | all + endgame plan | pin + shove | fast | full |
| Masters | 0.12 s | 5 deg | all + endgame plan | pin + shove + bait | fast | full |

**Personalities** (from the `personality` line each rival already has in `parts.json`; add a
`temperament` key): `brawler` (closes and trades), `technician` (angles, waits for the flank),
`bully` (wall pins, hazard shoves), `opportunist` (retreats when spun down or damaged, pounces on
an inverted bot), `showboat` (aggression for the judges, over-commits). Fillers draw one at random
from the seed; rivals keep theirs for life.

**New behaviours, all gated by skill:** wall pin (drive the opponent into a wall and hold, release
after 3 s to avoid the pin rule); hazard shove (when behind the opponent and a live hazard is
within 2.5 m ahead of them, push); weapon counters (vs spinner: approach from the side or rear of
the spin; vs flipper: approach at 30 deg off the nose; vs crusher: never stop moving); avoid the
house bot zone and, in the endgame, route around the released house bot; retreat to re-spin when
`READY_DROP`; when inverted, drive nowhere and press the srimech; in the last 20 s, if losing on
the judges' tally, switch to `showboat`.

**Acceptance (headless, `Arena/tests/ai_test.gd`):** Masters beats Scrapyard in at least 85 of
100 seeded fights; a scripted novice driver (straight at the opponent, fires on contact) beats
Scrapyard in at least 60 of 100; no tier ever drives itself into a live hazard more than once per
fight at National or above; every fight is bit-exact on replay.

## 5. Camera

`Arena/ui/camera_rig.gd`, `MODE_FIGHT` only. The workshop and menu modes are untouched.

- Yaw -135 and pitch 50 stay the defaults (behind the player's spawn, so the player's machine is the near one). Manual orbit and tilt stay, easing back after 3 s as now.
- **Look-at** = player chassis position plus a lead of 25 % of the vector to the opponent, capped at 1.2 m, eased with `SUBJECT_EASE_S`. The player is never further than 30 % of the frame from centre.
- **Zoom** = the distance at which both bots fit with `SUBJECT_MARGIN_BOTS` while the opponent is within 4 m; beyond that the zoom holds and the off-screen arrow does the work. Floor: the player never projects smaller than `PLAYER_MIN_FRACTION`.
- No cuts. The endgame pull-back is the only scripted move, 0.6 s out and 0.8 s back.
- The KO count and the result keep the wreckage orbit.
- Test: with the opponent parked 6 m away and the player driving a square, the player's projected position stays inside the centre 60 % of the frame for the whole run.

## 6. Career, as a season you can see

Swift: `CareerHomeView.swift`, `BracketView.swift`, `ScoutingView.swift`, `CareerFightView.swift`,
`CareerEngine.swift` (the bracket already exists: `startSeason`, `simulate`, `openNextRound`,
`finishSeason`). This is presentation and flow, not a new engine.

- **Career home = the season screen.** Top: the tier strip (Scrapyard to Masters, your tier lit, the wall marked where the unlock sits). Middle: the bracket of 8, your slot lit, rounds named Quarter-final, Semi-final, Final, results filled in as the season goes. Bottom: the **next-fight card**: opponent name and roboteer, livery swatch, weapon and chassis, the house bot on duty, the arena, the entry fee, the purse, the scouting line and the grudge line if there is history. One primary button: FIGHT. Secondary: Garage (choose the machine), Repairs.
- **After a fight:** the result slides into the bracket, the purse and repair bill are shown as one settlement, then the next-fight card updates. Winning the final: a season summary (record, scrap earned, blueprints won) and the tier strip advances.
- **Losing:** the season ends, the card says so in one line, re-enter is the primary action (fee shown).
- Every number the player can be charged is on screen before the FIGHT button.
- No new engine rules. If the engine needs a hook (for example the house bot per fight), add it to `CareerEngine` with a self-test case.

## 7. The Broadcast visual system

Concept board: `docs/look/b-broadcast.webp` (the other three, rejected, are beside it for
contrast). The board is a mood, not a spec. The visual wave starts by writing the spec
(`docs/design-system.md`) and getting it signed off before any screen is built.

- **Idea:** the game is a televised championship. Menus are the broadcast package, the fight is the live feed, the career is the season coverage.
- **Palette:** black glass base (near-black with a cool cast), white type, one electric cyan accent for chrome and selection, one warm amber for scrap, damage and warnings (the bolts stay the only warm colour in the arena itself). No other hues in chrome.
- **Type:** big condensed italic capitals for headlines and buttons, a plain condensed face for body. Bundle an open licence family (Barlow Condensed, SIL OFL) in both Swift and Godot so the two halves match to the pixel.
- **Shape:** angular lower-third panels with a consistent skew, hairline cyan rules, a score bug for scrap and the fight clock, a ticker strip for coach lines and season news. Corner cuts on every panel are the same angle everywhere.
- **Motion:** lower thirds slide in from the edge they belong to, 0.25 s ease-out; the ticker scrolls; selection is a cyan sweep, never a scale bounce.
- **Fight HUD:** clock and phase top centre as a score bug, names and condition bars as lower thirds bottom left and right, scrap in the bug, the coach and the corner-zone warning in the ticker. ENDGAME is a full-width broadcast sting.
- **Touch controls:** the stick well and the two weapon buttons are drawn in the same system: black glass discs with a cyan hairline, a weapon glyph on the primary button, pressed state fills cyan, the drive pulse ring stays. Geometry constants in `controls.gd` stay; only the drawing changes.
- **Recraft asset list** (raster unless stated): menu key art backdrop per tier (5), panel and button plates (9-slice), score bug, ticker plate, stick well and button faces, weapon glyphs (vector, 10), utility glyphs (vector), arena cards (6), boss portraits (5), rival portraits (8), tier badges (5, vector), blueprint card art. Recraft V4.1 does not accept the `digital_illustration` style parameter; use the model alone.
- **Blurry house bots:** an audit first. `compress/mode=2` (VRAM compressed) on every texture and the boss parts' embedded textures are the suspects; measure each boss texture's real size on the model, re-export at 1024 or 2048 where the model fills the frame, and set the compression quality per texture. The parts of the player's own machines get the same audit.
- **Swift:** `DesignSystem.swift` becomes the single source of colours, type and panel shapes. No screen defines its own.

## 8. Waves, agents and gates

Every agent runs on Opus. Each owns disjoint files. Each writes a notes file in `docs/`. The
suite (`scripts/test-arena.sh`, 21 files today) must stay green and grows with every agent.

### Wave G, gameplay

| Agent | Owns | Delivers |
|---|---|---|
| G1 fight shape | `fight_types.gd`, `rules.gd`, `fight.gd` phase plumbing, `arena_base.gd` `set_phase`, each `arena/*.gd`, `hud.gd` clock and ENDGAME sting, Swift timer strings | Section 2 |
| G2 house bots | `fight.gd` enforcer section, `boss_ai.gd`, zone markings in `arena_base.gd` (agreed API with G1), `QuickFight.swift` toggle, `CareerEngine` house bot per fight | Section 3 |
| G3 AI | `opponent_ai.gd`, `ai_test.gd`, `parts.json` temperaments | Section 4 |
| G4 camera | `camera_rig.gd`, `stage_camera_test.gd` | Section 5 |
| G5 career | `CareerHomeView`, `BracketView`, `ScoutingView`, `CareerFightView`, `ResultSheet`, `CareerEngine` hooks with self-test | Section 6 |

Cross-agent contracts are written before the wave starts, in `docs/wave-g-contracts.md`: the
`fight_state.phase` field, `arena_base.set_phase`, the zone rectangle getter, the house bot per
fight in the fight config.

**Gate G:** suite green, Release build on the owner's phone, the owner plays three career fights
and a Quick Fight, and says what he found. Nothing from wave V starts until he has.

### Wave V, the look

| Agent | Owns | Delivers |
|---|---|---|
| V0 spec | `docs/design-system.md`, tokens in `DesignSystem.swift` and a Godot theme resource | The written system, signed off by the owner before V1 to V4 start |
| V1 assets | Recraft production per the list, `Art/` and `Arena/assets/ui/` | Every asset, at device resolution |
| V2 arena HUD and controls | `hud.gd`, `controls.gd` drawing only, `ui_test.gd` | The fight feed |
| V3 menus | every Swift screen, `DesignSystem.swift` | The broadcast package |
| V4 textures | boss and part textures, import settings | Sharp machines |

**Gate V:** the owner sees the menu, the career screen and a fight on the phone.

## 9. Kept from today, to strip before shipping

The drive diagnostics in `fight.gd` (`DIAG_SECONDS`, `_diag_events`, `_input`) and the `fwd began`
lines in `FightTouchForwarder`. Keep them through wave G; they are how a phone reports what it
felt. Remove in wave V.

## 10. Open questions for the owner

1. Should a house bot ever appear at Scrapyard, even a gentle one, so the first tier teaches the zone rule?
2. Fight music: does the endgame get its own cue, and is there commentary text in the ticker ("BIG HIT", "PINNED"), or is that too much broadcast?
3. Rumble and the side events: do they get the endgame too, or stay as they are for now?
