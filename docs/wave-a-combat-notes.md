# Wave A: combat feel notes

2026-09-24, combat feel engineer. Status: **STOPPED at the session limit, WIP commit.** Every
file below parses (checked headless, one by one, after the last edit). The full suite was NOT
run after the last edits; `hitstop_test` passed (below). Note: `Arena/fx/fx.gd` with my
feel-tier edits was committed by the hazards engineer in `5ae1f3c`, not by me.

## Where I stopped (read this first)

Done and in the WIP commit (unverified by the full suite unless said):

1. **Hit-stop as a tick-clock hold** (`Arena/fight/hit_stop.gd`, `fight.gd` `_physics_process`,
   `_hold_sim`, `_set_presentation_live`). Its own path, not `_set_paused`: the controls are
   never released, the FX tree and the camera rig opt out of the tree pause for the hold, so
   sound, sparks and the camera kick play through it. Dials in `HitStop.DIALS` (120 ms cap,
   250 ms gap, quarter-speed slow motion). Physics interpolation is on in `project.godot`, OFF
   at the root and ON only for `Bots` and `Debris`.
2. **B1 fixed.** Replay 0.25x / 0.5x are holds (one tick in 4 / 2 iterations), never
   `Engine.time_scale`. The seek runs the tick rate at 60 x 16 with the clock scaled by 16
   (a POWER OF TWO, so the step is bit for bit 1/60) and stops on the exact target tick.
   The old replay pause let bodies run on without inputs; it is now a hold too.
3. **Proof so far** (`Arena/tests/hitstop_test.gd`, first run at 600 ticks): 0.25x replay,
   0.5x replay and a seek to tick 300 all gave the identical damage-event hash and 0.000000 m
   drift against the reference. The hit-stop-on run matched the hash but was snapshotted 3
   ticks late (a test artefact: the loop checked the tick once a frame). I added
   `fight.halt_at_tick(n)` so every run is snapshotted on exactly the same tick, raised the
   test to 1200 ticks / seek 600. **Rerun PASSED, 20 checks, 0 failures**: hit-stop on (5
   stops, 31 held iterations, plus FX tiers), 0.25x replay (4172 held iterations), 0.5x
   replay and seek-to-600 all end on tick 1200 with hash 549dedd8... and 0.000000000 m drift
   for both machines. Weakness: this fixture only lands 3 damage events in 20 s; a busier
   fixture would be stronger evidence.
4. **Engine.get_physics_frames() removed from sim rules** (it counts held frames): `Bot.sim_ticks()`
   (ram rearm, damage `tick`, axe), full-body spinner counts its own ticks. Balance runs on
   seed 424242 reproduced the teardown's numbers exactly before the spinner change, so these
   changed no fight.
5. **B2** `source` on every damage event (`bot.gd _flush_damage`); **B11** `_is_burn` reads it.
6. **Feel tiers** (`Arena/fx/feel_tiers.gd`): scuff / hit / heavy / smash from weapon,
   severity, impulse, detach and struck material; drive sound, sparks, shake, directional kick,
   zoom punch, haptic, hit-stop (and slow motion on a part coming OFF only). FightFx emits
   `impact_felt`; the fight turns it into holds.
7. **B3 / Q1 / Q4**: per-kind `on_weapon_fired` (no more flipper blast on spinners, napalm,
   arc, prod); `axe_hit` layered on axe blows, `ram_hit` on ram blows, `crusher_clamp` on a
   new grip. Deliberate choice: the crusher and the ram do NOT emit `weapon_fired`, because that
   signal feeds the judges' `weapon_hits` tally and would change fight outcomes; the sounds
   come from the damage path instead.
8. **B5 / Q2**: continuous damage coalesced per attacker/victim pair (a bite every 0.035
   condition, a throttled spark stream between); no decal, line, shake or sound for the
   stream events.
9. **B6 / Q5**: `flipper.throws()` counter; `WeaponFx.flipper_threw()`; throw = clang, heavy
   tap, dust ring, kick up, heavy hit-stop; dry fire = valve at -3 dB and a light tap.
10. **B9**: haptics drop the same kind inside 30 ms.
11. **S6 white-out**: flash pool dims/shrinks past 3 young flashes; light pops halve per young
    light. Not yet checked by eye.
12. **ONE SHAKE BUDGET**: `ImpactShake.add_trauma(amount, source)` with per-source ceilings
    (hit 1.0, hazard 0.7, landing 0.5, continuous 0.3), `kick_direction`, `punch_zoom`,
    `rotation()`, `zoom_punch()`. The hazards engineer's uncommitted `_hazard_shake` already
    calls `add_trauma(strength, "hazard")`. Contract text owed in docs/wave-a-contracts.md
    section 3 (not written yet).
13. **Camera**: rig applies rotation + zoom punch on the Camera3D child; steering reads the
    rig's `steering_basis()` so kicks never twist the stick; `FIGHT_CLOSER = 0.87` (13 %
    closer, pitch 50); airborne pull-out; `PLAYER_LEASH_LIMIT` 0.21 -> 0.19 to keep the 30 %
    rule. **camera_track_test / ui_test not run since.** The arena kit lead has NOT been told
    yet (owed: a line in docs/wave-a-contracts.md).
14. **Aim assist** (`fight.gd` `AIM_ASSIST`, touch only, applied before the record).
15. **B7** bodies keep moving after the result (`Bot.stop_for_result()`), frozen when the
    3.5 s beat ends; slow motion follow on KO / ring-out / kill. **B8** Swift
    `FinishBeatGate` (FightView.swift) holds the sheet / Match Report 3.5 s, tap to skip.
    Swift NOT built yet. **B12** result banner moved to the lower third (`hud.gd`).
16. **B4** decals parented to the struck body (`Bot.body_for_part`). **B10** napalm button is
    "napalm" (tap).
17. **Spinner balance** (`WeaponBase.spinner_bite`, cap 0.5 x spin). Seeds 424242 / 777,
    AI vs a box flipper, 120 s:

    | weapon | before: fight ends, hits, one-hit part kills | after |
    |---|---|---|
    | horizontal | 120 s / 99.9 s; 3 / 9 hits; weapon, wheels in 1 | 96.3 s / 92.9 s; 12 / 7 hits; parts in 2 (weapon once 3) |
    | drum | 92.6 s / 27.3 s; 6 / 9 hits | 120 s / 14.9 s; 7 / 7 hits; no part lost in 1 |
    | full body | 63.0 s / 38.0 s; 6 / 7 hits; weapon, top, wheel in 1 | 68.3 s / 113.6 s; 6 / 10 hits; parts in 2 |
    | vortex | 26.4 s / 8.3 s; 7 / 1 hits | 94.3 s / 85.6 s; 4 / 6 hits; weapon in 3 |

    Tried and dropped: scaling by contact-normal angle (Jolt normals read almost every bite
    as glancing, parts took 5 hits).

## Session 2 (2026-09-25): suite greening and the not-done list

Suite failures at 0a69d7a, each decided:

| test | failure | verdict | change |
|---|---|---|---|
| rules | decal scratch/scorch (0) | intended (B4 decals attach to the body) | FakeDecals take the `attach_to` arg |
| fx | flip haptic on weapon_fired | intended (B6: dry fire = light tap, throw = heavy) | check is now "no flip haptic on a dry fire" |
| fx | wheel sheds nuts (0) | pre-existing flake (unseeded pick, ~1 in 30 at 12 pieces) | wheel shower 40 pieces |
| builds | spinner removes a panel (0) | intended (spinner bite, 2-3 hits a part) | fights 120 s (12 hits, 1 panel) |
| weapons_a | drum takes no armour in 2 s | intended (the rear wheel survives the first bite now) | drum counts running gear |
| hazard determinism | crush, coliseum | intended (B7 bodies move through the finish beat) | result row hashes no transforms; proven by re-freezing at the result on 7dd1f62 = ac12e1e hashes; goldens re-recorded on 1fbb1b5 with the new row |
| hazard determinism | grinder (later) | intended (AI recovery window) | proven: recovery_s 0 gives the old hash; re-recorded |
| fight ui (7), camera track (3 of 5) | player 10 % of frame, frame bias, frustum corners | **REAL REGRESSION**: physics interpolation (project-wide since 7dd1f62) reached the rig camera under the world SubViewport, which drew and unprojected through a stale pose | rig + camera set interpolation OFF; the fight world SubViewport set OFF explicitly (measured: Arena/CameraRig/FX off, Bots/Debris on). The stage lead's workshop_test workaround can now go (theirs to remove) |
| camera track (2) | 27 % cap, opponent framed to 2.6 m | intended (13 % closer) | 0.30 and 2.4 m |

Done: `rules.endgame_at_s` (contracts 6), contracts section 3, AI recovery window (Scrapyard 0.8 s /
1.0 m, Regional 0.6 / 0.75, National 0.4 / 0.5; measured in AI vs AI fights: Scrapyard up to 7
windows a minute, Championship none), axe wind-back (`Arena/bot/axe_windup.gd`, model only).
Swift FinishBeatGate was already written in 7dd1f62; it only needed building.

Owed: the ai_test "punisher beats Regional" acceptance test from combat-feel.md; feel tiers by eye on
the phone; the wheel sink / wedge stall, KO-while-latched, lifter self-flip and white-out gauntlet bugs
(in progress, see the commits after this note).

## Not done (next, in order)

1. Run `hitstop_test`, then the whole `scripts/test-arena.sh`; expect fixture/golden and
   camera/ui test adjustments (spinner balance and the closer camera change outcomes and
   framing BY DESIGN: regenerate deliberately and say so).
2. Contracts: section 3 (shake API) and the camera-closer note for the kit lead.
3. AI recovery windows (Scrapyard to National): not started (`opponent_ai.gd` dart logic
   around lines 861-904 is where a missed dart should overshoot and pause).
4. Axe wind-up (visual only, `part_anim` / `part_visuals`): not started.
5. Feel-tier numbers by eye in a windowed desktop fight; evidence frames into
   docs/aaa/img/wave-a/combat/ (none taken yet).
6. `scripts/build-sim.sh` (Swift FinishBeatGate is unbuilt), after the " 2" dupe check.
