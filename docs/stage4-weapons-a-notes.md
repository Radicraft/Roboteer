# Stage 4 weapons A notes (agent W1)

The four spinning weapons: horizontal spinner, vertical spinner (drum), full body
spinner and saw, written against `Arena/bot/weapons/weapon_base.gd` with
`flipper.gd` as the worked example. Owned files:

```
Arena/bot/weapons/horizontal_spinner.gd
Arena/bot/weapons/vertical_spinner.gd
Arena/bot/weapons/full_body_spinner.gd
Arena/bot/weapons/saw.gd
Arena/tests/weapons_a_test.gd
docs/stage4-weapons-a-notes.md
```

Test command, headless, exits 0:

```bash
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path Arena --script tests/weapons_a_test.gd   # 12 checks
scripts/test-arena.sh                                                                                    # the lot
```

## 1. How a hit is delivered, and why it is delivered that way

Three of the four are impulse weapons and share one mechanism. The saw is the
exception and is described in section 4.

A spinner body is a real `RigidBody3D` (a `BotPart` subclass) on a motorised hinge,
registered with `bot.register_part(body, FightTypes.PART_WEAPON, "weapon", mass())`.
That gives it, free, everything the Bot owns: contact reporting in both directions,
the `weapon` condition (so a bar bends and eventually jams), freeze, detach and the
internal collision exclusions. Nothing here reaches into another bot: damage goes
out through `bot.opponent_damage_tick` and impulses go onto bodies the contact list
handed us.

What the solver CANNOT give us is the spinner's stored energy. Jolt drives a hinge
motor to its target velocity and **ignores `PARAM_MOTOR_MAX_IMPULSE`** (measured in
Stage 3, written down in `flipper.gd`), so the bar has no momentum budget to spend:
it simply carries on turning. So the weapon adds the energy itself, in two halves:

1. **Inside the step.** The body subclass overrides `_integrate_forces`, calls
   `super(state)` (which is what feeds `Bot.report_contact`, so the ordinary
   mechanical damage still happens), then hands the weapon the contact list.
   `_note_contacts` is read only: it sums the contact impulses per collider, the
   way `BotPart` does, keeps the strongest FOREIGN part, and records it. Ties are
   broken by instance id so the choice never depends on the order Jolt reports
   contacts in.
2. **Outside the step**, in `physics_tick`, where applying impulses and touching
   the damage model is safe. `_spend_hit` applies

   | | |
   |---|---|
   | to the victim | `impulse * spin` N s along the weapon's tangential velocity at the contact point, divided by the victim's `flip_resistance` (the flipper divides its throw the same way) |
   | to the victim | `bot.opponent_damage_tick(part, severity, "impact")`, where `severity` comes off the SAME `FightTypes.BREAK_MIN` / `BREAK_MAX` curve `BotDamage.apply_impulse_damage` uses, including that plate's thickness scaling, read from the victim's `damage.threshold_scale` |
   | to the wielder | the reaction, per weapon (section 2) |
   | to the weapon | the spin it cost |

   Using the same curve is the point: a 180 N s bite and a 180 N s ram shove are
   worth the same condition, and `opponent_damage_tick` then applies the victim
   material's `impact` factor, so HDPE still shrugs off spinners.

**The bite costs spin.** That is the whole tactical shape of a spinner: the
horizontal spinner spends 62 percent of its remaining spin per bite and needs 2.5 s
to get it back, so one hit and you are disarmed until you disengage. This is what
spec section 6's "spinners spin up before engaging and disengage to re-spin" needs
from the weapon side.

## 2. The numbers, per weapon

Everything in the `catalogue` column is read from `Shared/parts.json` at runtime and
is not repeated in the script. Everything in the `here` column is a model parameter
rather than a design choice, which is why it lives in the script.

### horizontal_spinner (24 kg, `kind: spinner`)

| catalogue | here |
|---|---|
| reach 0.55, spin_up_s 2.5, impulse 180, self_destabilise 0.6, band mid | bar 1.10 x 0.06 x 0.15 m, MAX_OMEGA 12 rad/s, coast 6 s, bite cost 0.62, bite cooldown 0.30 s, reaction linear 0.22 / torque 0.55, destabilise gate 0.60 spin |

A 1.10 m bar (0.55 each side, the catalogue reach at the tip, matching the .glb) on
a VERTICAL hinge at `socket_weapon_front`. `pressed` ramps the commanded spin to 1.0
over `spin_up_s * bot.spin_up_factor()`; the motor target is `MAX_OMEGA * spin`.

The reaction is what makes it the bar: on a bite the wielder's chassis takes an
equal and opposite impulse applied as a small central shove plus a torque about the
contact offset, scaled by `self_destabilise` and divided by the hull's
`tip_resistance()`. Below 60 percent spin only 35 percent of it is applied, because
a half-spun bar is not carrying enough to upset anything. Measured in the test: the
wielder's peak per-tick angular velocity change is 6.5 rad/s with the reaction and
3.1 without, on the same scripted engagement.

The reaction is deliberately NOT one big impulse into the floor. `flipper.gd`
records that dumping 210 N s into your own chassis in one step reads as damage on
your own wheels; the linear share here is 22 percent and the yaw share carries the
lurch.

### vertical_spinner (20 kg, `kind: drum`)

| catalogue | here |
|---|---|
| reach 0.25, spin_up_s 1.8, impulse 150, launch 0.7, band floor | drum r 0.118 x 0.40 m wide, MAX_OMEGA 16 rad/s, coast 4 s, bite cost 0.35, cooldown 0.18 s, self_destabilise 0.12 (not in the catalogue: it is the safe one), tumble 0.06 x impulse |

A drum on a hinge along the bot's +Z at the front, turning so the FRONT face climbs
(a point at +X from the axis has velocity `omega_z * (Z x X) = omega_z * Y`, so a
positive motor target lifts it). The bite direction is `launch` of the way rotated
to straight up, so 70 percent of a drum hit goes upward, and a tumble torque about
the drum's own axis lands the victim on its back. The reaction is a fifth of the
bar's and is forced DOWNWARD, so a drum plants itself while it works. Bites cost
less spin and recover sooner, so a drum grinds where a bar gets one swing.

### full_body_spinner (30 kg, `kind: fbs`, Shell only)

| catalogue | here |
|---|---|
| reach 0.45, spin_up_s 3.5, impulse 200, control_penalty 0.5, band mid | ring disc r = reach, from the hull's `floor_y()` up to 0.10, MAX_OMEGA 6 rad/s, coast 9 s, bite cost 0.5, cooldown 0.30 s, recoil 0.12, shield above 0.30 spin |

`chassis/shell.gd` already did its half of the handover: the moment this script
exists `has_own_ring()` goes false, the hull shrinks its collision to the hub and
hides the `ring` mesh in `shell.glb`. The weapon then owns ONE ring body on a
vertical hinge at `socket_weapon_shell`, wearing `full_body_spinner.glb` (the
toothed version, teeth at 0.45, the catalogue reach). Its collision is a solid disc
rather than an annulus: the hub, the wheels and the plates all live inside it and
are collision excluded from it anyway, so twelve boxes would buy nothing. Its
vertical span is clipped to the hull underside so the ring can never become the
bot's ground contact, even though the model's teeth hang 40 mm lower.

**Control penalty.** `Bot.apply_input` drives FIRST and hands the weapon the button
second, so by the time `apply_input` runs here the drive has already written this
tick's wheel motor targets. `_scale_drive()` multiplies them in place by
`lerp(1, control_penalty, spin)`. That scales the forward speed and the differential
together, so a fully spun Shell drives at half pace and turns at half rate, and the
weapon needs to know nothing about arcade steering. Measured: 0.497 against the
catalogue's 0.50. A jammed or disrupted weapon never gets `apply_input`, so
`physics_tick` does the same scaling whenever no input has arrived for two ticks,
which means a coasting ring still costs you control.

**No weak side, through the existing damage path.** Above 30 percent spin the armour
panel bodies are taken out of the collision world: `collision_layer` AND
`collision_mask` both go to zero, which is what Godot needs (a pair collides if
EITHER side's layer is in the other's mask). A body nothing can touch never reaches
`BotPart._integrate_forces`, so it never reaches `Bot.report_contact`, so no damage
event can name `armour_front`, `armour_sides` or `armour_rear` while the ring is
up. Nothing else changes: the plates are welded with all six degrees of freedom
locked, so they do not fall, do not need the floor and ride along. The hub is
shielded the ordinary way, by geometry, because the 0.45 m ring stands proud of the
0.328 m hub all the way round. Hits on the ring land on a body whose part key is
`weapon`, so they spend the WEAPON's condition, which is the spec's "the ring is the
armour" exactly: grind the ring to zero, `Bot._handle_zero` jams the weapon, the
ring coasts below 30 percent, the plates come back into the world and the Shell is
an ordinary bot with very little armour. `freeze()` restores them too, so nothing is
left in a state the next fight could inherit.

### saw (12 kg, `kind: saw`)

| catalogue | here |
|---|---|
| reach 0.30, dps 0.06, knockback 0.05, band mid | blade r 0.155 x 0.022 m, MAX_OMEGA 14 rad/s, spin up 0.4 s (spec section 4, the catalogue has no row), coast 1.2 s, cutting Area3D = blade + 18 mm |

See section 4.

## 3. Two mounting traps, both measured

1. **A rotating HEAD cannot hang on the arm socket.** `socket_weapon_front` on a
   wedge is the FLIPPER's pinned pivot at x = 0.1115 (docs/stage4-assembly-notes.md
   section 3), which is 0.36 m BEHIND the nose, because a flipper arm reaches
   forward from it. A 0.118 m drum or a 0.155 m blade mounted there sits entirely
   inside the hull: the bot's own front plate touches first and the weapon never
   contacts anything at all. That is exactly what happened on the first run of the
   test, where the drum and the saw did no damage whatsoever in two seconds of
   driving into a target. The drum and the saw now carry their pivot forward to
   `half_len() + PLATE_PROUD + 0.03 - radius`, so the leading edge stands 30 mm
   proud of the hull's front armour. The bar does not need this: it reaches 0.55 m
   from its pivot and clears the nose on its own.
2. **Nothing may reach the floor.** `flipper.gd` records the pogo trap: a part that
   touches the ground becomes a third ground contact, lifts the front wheels and the
   bot bounces around the arena. The drum and the blade lift their pivot to put
   their underside `GROUND_CLEAR` (10 mm) above the floor, and the bar clamps the
   same way.

## 4. The saw, and one deliberate deviation from the spec text

The saw is the only one of the four that is not an impulse weapon. A small Area3D
rides on the blade and is read once per tick in `physics_tick`. Every foreign part
inside it takes

```gdscript
bot.opponent_damage_tick(victim_part, dps * dt * spin, "cut")
```

**The spec text says to pass `dps * dt * cut_factor`. This does not, on purpose.**
`Bot.take_direct_damage` ALREADY resolves the material factor from the catalogue for
a direct damage source, and it is the only place that knows the victim's material.
Passing the factor as well would square it: the table would run 0.16 to 2.56, a
sixteen-fold spread that makes a steel plate effectively immune and an HDPE one
vanish. Applied once, the measured per-cut condition is 0.00160 on HDPE against
0.00040 on steel, **exactly the catalogue's four to one**, which is the number the
test asserts.

Overlaps are sorted by instance id before anything is applied, because the order an
Area3D reports them in is not part of the contract and the damage events would
otherwise land in a different order between two runs of the same seed.

Knockback is a per-tick impulse of `knockback * spin` N s (0.05 at full speed, which
is 3 N s per second of contact) along the blade's tangential velocity. That is two
orders of magnitude below `BREAK_MIN`, so a saw never scores an impact hit of its
own; it is there so a part being cut visibly shudders.

## 5. Tip speed is a physics budget, not a design number

Two separate ceilings held every `MAX_OMEGA` down, and both were measured:

1. **Tunnelling.** 60 Hz discrete collision cannot see a 0.06 m thick bar that moves
   0.37 m between steps: it passes straight through an opponent and nothing happens.
   The rule of thumb used here is that the working surface must travel well under
   0.15 m per step, which is 12 rad/s at 0.55 m. `continuous_cd` is on for the bar,
   the drum and the blade as a second line of defence.
2. **A weapon that destroys itself.** A hinge motor cannot be stalled (Jolt ignores
   `PARAM_MOTOR_MAX_IMPULSE`), so a fast head held against a plate resolves as an
   enormous contact impulse EVERY step, and the head is a real part on the "weapon"
   BREAK row. At the first numbers tried (saw 30 rad/s, drum 26, ring 9) the saw and
   the drum ground their OWN condition to zero inside ten seconds of contact, which
   makes a grinding weapon useless. At 14, 16 and 6 the blade finishes five seconds
   of continuous cutting on steel at condition 1.00. The energy of a spinner lives
   in the impulse model in section 1, not in the surface speed, so lowering these
   cost the weapons nothing.

## 6. Presentation

There is none here, per the brief: no particles, no sound. The weapons emit
`weapon_fired` (through `bot.emit_weapon_fired()`) once when spin reaches 1.0, and
re-arm below 0.5, so the FX layer has a "it is up to speed" event to work with.
`status_text()` returns `SPIN 68%` (or `SAW 68%` for the saw, and `JAMMED`), and
`readiness()` is the spin fraction, which is what the AI in spec section 6 steers on.
`tip_height()` is implemented on all four so the HUD's height band reads the live
part rather than the catalogue row.

## 7. What the test proves, and the one thing it cost

`Arena/tests/weapons_a_test.gd`, 12 checks:

1. every weapon assembles on wedge, box or shell with no build errors, as a body
   registered part_kind "weapon" with the catalogue reach; the Shell hands its ring
   over;
2. readiness rises 0 to 1 over `spin_up_s` (checked at the half way point too) and
   coasts down when released;
3. each weapon takes condition off an armour face of a target parked in reach,
   inside the 2 s the spec asks for, WITHOUT grinding its own condition below 0.5;
4. the horizontal spinner's wielder lurches on a hit, against the same run with
   `self_destabilise` zeroed;
5. the saw survives 5 s of grinding on steel, and its per-cut severity on HDPE is
   four times its severity on steel;
6. the full body spinner scales the wheel motor targets by `control_penalty`, its
   faces are out of the collision world above 30 percent spin, and a stopped ring
   gives them back;
7. a jammed weapon spins down, reads JAMMED, reads readiness 0 and delivers nothing;
8. two runs of a four bot, four weapon, 600 tick engagement agree exactly.

**Every scenario builds its world inside its own `SubViewport` with
`own_world_3d = true`, exactly as `fight.gd` does, and that is load bearing.** Two
scenarios run back to back in the SHARED root physics space do not reproduce each
other: with recycled body RIDs the solver's ordering changes and four bots driving
into a wall diverged by a metre in ten seconds, with no weapon involved at all (the
same run with four flipper bots diverged identically, which is how it was pinned on
the harness rather than on this code). R2 found the same thing in Stage 3 and wrote
it into `fight.gd._build_world`'s comment. In its own space the run repeats to the
last bit.

## 8. Known weaknesses

1. **The bar sweeps through its own bot.** A 1.10 m bar pivoting 0.36 m behind the
   nose covers the front half of the hull and the front wheels on every turn. They
   are collision excluded so the physics is right, but on screen the bar will pass
   through the wheels. The honest fixes are a taller pivot (which would then miss a
   low opponent's plates entirely) or a shorter bar (which is not the catalogue).
   This is the first thing to look at in the desktop window pass.
2. **A bite that lands on bare hull is credited to the top plate.** The face a
   direct damage hit belongs to is `Bot.take_direct_damage`'s decision, not the
   weapon's, and it routes any chassis hit through `armour_top` while the top plate
   lives. `report_contact` routes the same hit through `face_for_contact` instead.
   A plate only covers the middle 0.6 m of a 0.8 m flank, so a bite on the front or
   rear corner of an opponent shows up as top armour damage. It is P2's rule for
   every direct-damage weapon (the saw, the crusher and the flame all have it), and
   changing it belongs in `bot.gd`, not here.
3. **Double counting, bounded but real.** A spinner hit is paid for twice: once by
   the mechanical contact the solver produced (through the ordinary
   `report_contact` path) and once by the bite. The bite is the larger of the two
   and the mechanical share is what makes armour thickness and the weapon's own
   condition behave, so this was left alone; a build that wanted one number would
   have to suppress the victim's own contact report, which the weapon cannot do.
4. **The drum's `self_destabilise` is not in the catalogue.** The row has no such
   key, so the 0.12 lives in the script. If the catalogue ever grows one, delete the
   constant and read it.
5. **The full body spinner's shielding is all or nothing at 30 percent spin.** There
   is no partial protection and no directional protection: a ring at 31 percent
   shields exactly as well as one at 100. A smooth version would need the damage
   path to know about the ring, which means a change in `bot.gd`.
6. **The saw's Area3D cuts anything it overlaps**, including a wheel or the
   opponent's own weapon, and the cut factor only applies to armour faces (that is
   `take_direct_damage`'s rule). Sawing a wheel is therefore material independent.
7. **Nothing here has been seen on screen.** Every number in this file is headless.
   The bar's sweep (weakness 1), the drum's mounting height and whether the ring
   reads as the Shell's own body are all questions a frame answers and a test
   cannot.

## 9. The one thing that stops these weapons working in a fight (for R2)

**Every W1 weapon is inert under the normal AI, and the cause is in
`Arena/ai/opponent_ai.gd`, not here.** This is what `builds_test` case (b) is
reporting when it says the spinner build removes no panel.

Measured, `scripts/test-arena.sh` on 2026-09-13:

```
wedge / 4wd / flipper          weight  86.6 kg  panels off 0  throws 0  push 13.70 m  damage 1.00
box / 6wd / horizontal_spinner weight 112.6 kg  panels off 0  throws 0  push  2.31 m  damage 0.00
long_low / tracks / ram        weight  90.3 kg  panels off 0  throws 0  push  6.85 m  damage 0.00
```

Sixty seconds of AI against AI and the bar did nothing at all, while the same
weapon against a target it can actually reach takes 0.81 condition off in four
seconds (`weapons_a_test`, the reaction check prints it). The weapon is not the
problem. The button is:

- `PROFILES` marks `spinner`, `drum`, `fbs` and `saw` with `spin_up: true` and
  `hold: true`, which is right;
- in normal mode the ONLY thing that sets `fire` is `_should_fire()`;
- `_should_fire()` line 338: `if bool(profile["spin_up"]) and ready < READY_DROP:
  return false`, with `READY_DROP = 0.45`;
- `ready` is `weapon_readiness()`, which for a spinner is the spin fraction, and the
  spin fraction only rises while `pressed` is true.

So the button is never pressed because the weapon is not spun up, and the weapon is
never spun up because the button is never pressed. It starts at zero and stays
there for the whole fight. The comment right above that line ("holding the button
while it spins up is the point") says what the code was meant to do.

W1 is not going to paper over it: spec section 4 says `pressed` spins the weapon up
over `spin_up_s`, and a weapon that spins itself up with no input would be a worse
lie than the bug. The fix belongs in the AI, and it is small: a held, spinning
weapon should press the button whenever it is holding station or closing, and use
`READY_ENGAGE` / `READY_DROP` only to decide whether to CLOSE, which is what spec
section 6 describes ("spinners spin up before engaging and disengage to re-spin").
Something like

```gdscript
# A held weapon presses to spin up; readiness gates the approach, not the button.
if bool(profile["hold"]) and bool(profile["spin_up"]):
    fire = true
```

before the `spin_up` disengage branch would do it, leaving the tap weapons alone.
The other five `builds_test` failures (the 112.6 kg fixture, the flipper's throws,
the ram's push and damage ordering) involve no W1 code.
