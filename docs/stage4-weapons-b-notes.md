# Stage 4 weapons B notes (agent W2)

The lifter, the crusher, the axe, the ram and the flamethrower: what each one is,
the numbers that are measured rather than chosen, and the traps that cost real
time. Owned files: `Arena/bot/weapons/{lifter,crusher,axe,ram,flamethrower}.gd`,
`Arena/tests/weapons_b_test.gd`, this file.

Test commands, headless, both must exit 0:

```bash
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path Arena --script tests/weapons_b_test.gd
scripts/test-arena.sh
```

Everything here is built against `Arena/bot/weapons/weapon_base.gd` and follows
`flipper.gd`, which is the reference implementation. Read
`docs/stage4-assembly-notes.md` section 8 first; this file only adds what is
specific to these five.

## 1. What each weapon is, in one line and one number

| weapon | the mechanism | the catalogue number that decides it |
|---|---|---|
| lifter | forks on a strong slow hinge at the front socket | `lift_rate` 1.2 rad/s to 70 degrees, so a full lift takes 1.02 s |
| crusher | a jaw over the nose that bites, pins and chews | `clamp_force` 900 N caps the grip, `dps` 0.08 chews |
| axe | an overhead arm, 130 degrees in 0.15 s, then dead for `reset_s` | `impulse` 220 N s, `top_bonus` 1.6 on a lid |
| ram | a spike at the front lip, no moving parts | `impulse_bonus` 1.4 times the blow, once per impact |
| flamethrower | a cone Area3D of fire, 20 seconds of gas | `fuel_s` 20, `dps` 0.03 per part, `disrupt_s` 1.5 |

They are mechanically distinct by construction: one is a held hinge with no
launch, one is a held hinge that fights the other bot's drive, one is an edge
triggered single blow with a long dead time, one has no input at all, and one
spends a resource that never comes back.

## 2. The five decisions the spec left open

1. **How the crusher pins** (spec offers "fight the victim's drive, or apply an
   opposing force"): **both**. `victim.disrupt("drive", 0.2)` re-applied every
   tick while clamped is the gameplay half, and a capped spring-damper between the
   clamped body and the jaw's bite point, with the reaction on our own chassis, is
   the physics half. Disruption alone is an invisible hand that stops wheels;
   a grip alone lets a 6WD bot drive out of the claw. The cap is the catalogue
   `clamp_force` at `Bot.MASS_SCALE`, so the number in the shop is the number in
   the fight.
2. **The axe's sign convention.** The spec says the arm "swings from rest (-70
   degrees) to +60". Measured from the forward horizontal with positive up, that
   is rest **+60** (cocked, head high and forward) and strike **-70** (head driven
   down in front of the nose). The spec's own signs put the rest position head
   down at the floor and the strike pointing at the sky. Same two numbers, same
   130 degree sweep, opposite sign.
3. **The ram's bonus is momentum, not damage, and it is one kick per blow.** The
   extra impulse goes on the victim and the victim's damage model still only sees
   the contact it really took: that is what R2's three builds test expects from a
   ram (the highest push distance and the LOWEST damage removed) and it is brief
   section 5.3's "everything into speed and armour". The hurt comes from the wall
   it drives you into. The extra is `(impulse_bonus - 1) * reduced_mass *
   charge_speed` applied once per impact, NOT a multiplier on the per-tick contact
   impulses. See section 4 traps 5 and 6 for the two measurements that forced
   that.
4. **Fire ignores armour material.** The flame reports its damage with source
   `"burn"`, which no armour material has a factor for, so every material takes it
   at 1.0. The catalogue's factor table is about impact and cutting; a burn that
   read the `"cut"` row would have made the flamethrower a second saw, best
   against the same material and worst against the same one. This way it is the
   answer to the armour everything else is wrong about.
5. **The flame's disrupt alternates, seeded once.** The spec says "alternating,
   decided by the shared rng". The FIRST kind is drawn from the rng
   (`rng.randf() < 0.5`) and it alternates from there, so a long burn always takes
   both systems instead of rolling weapon four times running. One rng draw per
   bot, at build time, which is all the determinism budget this needs.

## 3. THE ONE THING TO UNDERSTAND: a front socket is not the front of the bot

This cost more time than everything else here put together, and it will cost the
next agent the same time if it is not written down.

`chassis_module.weapon_socket("front")` on a **wedge** returns **x = 0.1115**, and
the wedge's nose is at **x = 0.45**. The socket is the flipper's pinned hinge
point (`docs/stage4-assembly-notes.md` section 3), 0.34 m behind the nose, and it
is pinned there because the flipper's whole tuning hangs off it. A weapon that
mounts a 0.2 m body at that socket puts it **entirely inside its own bodywork**.

`weapon_socket("top")` is no better for reach: on a wedge it is **x = 0.05**, the
middle of the deck.

Measured consequences, all three found the same way (nothing happened in a fight
that obviously should have):

- the **ram** bolted at the front socket delivered **zero** bonus impulses in a
  full speed head on charge, and the ram bot pushed its victim LESS far than a bot
  carrying a dead plate, because the only thing ever touching the opponent was the
  hull. It now places its own body at the front lip, `RAM_PROUD` = 0.18 m past the
  hull (0.10 was not enough: the armour plates behind the spike joined the
  collision a millisecond later) and `RAM_CLEAR` = 0.03 m off the floor;
- the **crusher** hinged at the deck socket closes a 0.30 m jaw on the middle of
  its own lid. Its hinge moves forward to `half_len - 0.12`;
- the **axe** hinged at the deck socket crosses an opponent's lid height at
  x = 0.61, and two touching wedges have their centres 0.90 m apart, so the head
  comes down inside the wielder's own nose and `top_bonus` could never be paid.
  Its hinge moves forward to `half_len - 0.12` as well, which puts the same arc at
  x = 0.91: an opponent's deck, nose to nose.

The rule the assembly notes already state ("the WEAPON decides first and the hull
second") is doing real work here. A weapon is allowed to know where its business
end has to be.

## 4. Traps, measured

1. **An Area3D's offset must go on the NODE, not on its CollisionShape3D.**
   `flipper.gd` offsets the shape, which is fine because it only asks "is anything
   in here". Both of mine ask WHERE: the crusher's `bite.global_position` is the
   point the grip pulls the victim onto, and the axe's `head.global_position` is
   the point `face_for_contact` reads. With the offset on the shape, the Area's
   own origin stays at the body's centre, so the crusher was dragging its victim
   0.19 m back into the hinge (it read as a pin that threw the victim around at
   0.4 m/s) and the axe was reporting its blow 0.25 m behind the head.
2. **The axe's 0.15 s is how long the MOTOR drives, not how long the arm takes.**
   A strike detected only inside that window found nothing at all, three
   placements out of three: the motor cannot take a 9 kg arm to 11.5 rad/s in one
   tick, and a victim slows it further, so the head arrives after the window
   closes. Detection now runs through the limp part of the reset as well.
   It cannot be gated on "the arm is still descending" either: **an arm that has
   landed on somebody stops dead**, which is exactly the tick the hit happens.
3. **The yard's spike patch is 1.6 m square on the ORIGIN and its phase comes from
   the seed.** Two weapon checks written at z = 0 with different seeds get
   different answers: the crusher's pin measured 0.03 m/s under one seed and
   1.56 m/s under another, and the difference was the spikes coming up under the
   victim and throwing it out of the claw. `weapons_b_test.gd` runs every scenario
   in a lane at z = 3.
4. **Two bots placed 0.8 m apart are INSIDE each other.** A wedge is 0.9 m long,
   so nose to nose the centres cannot be closer than 0.90 m and the bots pop apart
   at spawn, ride up each other and settle at odd heights (a chassis at y = 0.42
   instead of 0.105). Several early "the weapon does not work" readings were two
   bots climbing out of each other. Check the settled chassis height before
   believing any placement.
5. **A body is only told about its own share of a collision.** Multiplying the
   contact impulses Jolt reports to the ram body is the obvious implementation and
   it is wrong: measured head on, box against box, the ram body saw **6.3 N s** of
   contact while the victim's momentum changed by **32 N s**, so multiplying by 1.4
   moved the victim 2 percent. It also fires every tick of a shove rather than once
   per hit. The ram now computes the blow itself, from the charge speed and the two
   bots' reduced mass, once per impact, and a shove never re-triggers it because a
   shove has no closing speed.
6. **By the time a body reports a contact, the closing speed is already gone.**
   The ram's first foreign contact came in at **0.73 m/s** off a charge that was
   doing **2.03 m/s** a fifth of a second earlier, which priced the blow at a third
   of what the catalogue promises (5.0 N s instead of 15.1). The bonus is a bonus
   ON the charge, so the charge is what it reads: the ram keeps the last 12 ticks
   of its own forward speed and takes the highest. Same collision, same seed, the
   victim went from 4 percent faster than a bent ram to **20 percent** faster.
7. **A ram in sustained contact is not a ram, it is a bulldozer.** A bot that
   keeps its throttle down after the hit pushes the victim up to its own top
   speed whatever it hit it with: 1.632 m/s with the bonus and 1.632 without. The
   bonus only shows in the impulse of the hit, so `weapons_b_test` cuts the
   throttle at contact and measures what the collision alone did.
8. **A test victim must not carry a weapon that sticks out.** A flipper's arm
   reaches 0.55 m past its owner's front socket, so the first ram check was a
   charge into a 4 kg arm on a hinge: `get_colliding_bodies()` said "Flipper" for
   45 ticks and nothing else, the arm gave way, and the bonus had almost nothing to
   multiply. In a real fight that is correct behaviour; in a measurement it is the
   wrong thing being measured.
9. **The honest control for a ram is a BENT ram, not a bot with no weapon.** An
   inert plate is a different shape in a different place (on a box it stands
   0.18 m proud of the nose, on a wedge it is buried), so a bot carrying one is
   not the same bot minus the bonus. `set_jammed()` leaves the mass and the spike
   exactly where they are and turns the multiplier off, and it is a state the game
   really reaches when the ram's condition hits zero.
10. **`ceil()` on a float fuel gauge reads one too many.** 180 ticks off a 20 s
   bottle leaves 17.000000001 s and `int(ceil())` shows "FUEL 18s". There is an
   epsilon in `status_text()`.
11. **Jolt ignores `PARAM_MOTOR_MAX_IMPULSE` on a hinge** (measured by P in Stage 3
   and still true). Every hinge motor here is a velocity constraint, so
   `clamp_force` could never have been the crusher's motor strength. It is the cap
   on the grip force instead, which is a number that does something.

## 5. What the numbers do in the hand

- **Lifter**: 0 to 70 degrees in 1.02 s, still holding at 1.5 s, and back down in
  the same time. Fork friction 0.6 where the flipper's arm is 0.08, because a bot
  being carried must not slide off the moment the wielder turns. The wielder's own
  chassis never goes above 0.108 m while lifting: there is no launch in this
  weapon anywhere.
- **Crusher**: bites in about 0.5 s of closing, pins from 0.3 s of held contact,
  and a pinned bot on full throttle makes **0.027 m/s**. It chews 0.08 a second
  through the catalogue's `cut` factor, so it eats HDPE (1.6) and gnaws at steel
  (0.4).
- **Axe**: 98.7 degrees of sweep on a wedge (the full 130 needs a deck 0.4 m up;
  the strike stops where the head would reach the floor), 1.4 s of reset, and a
  blow of 0.352 condition on a lid against 0.220 anywhere else, before the
  victim's own impact factor. On the test's HDPE lid that is 0.176 a hit, so three
  clean overhead blows take the plate off and they are 1.55 s apart.
- **Ram**: one extra kick per impact, `(1.4 - 1)` times the blow an inelastic head
  on collision delivers, which at a 2.0 m/s charge between two 34 kg (simulated)
  bots is **15.1 N s**. Against the same bot with the ram BENT (`set_jammed()`,
  which is what a ram at zero condition becomes) at the same closing speed, the
  victim is **20 percent faster 0.13 s after the hit** (1.12 against 0.94 m/s),
  12 percent faster at its peak, and ends up 20 percent further away. It is faster
  at every tick of the separation, not just at one sample.
- **Flamethrower**: 20.00 s of gas, burned at exactly one second per second; 0.03
  a second on EVERY part in the cone (a bot presents about three), so a full
  bottle is worth roughly 1.8 condition spread over whatever is in front of it;
  the victim's electronics go after 1.0 s of continuous exposure and again every
  second after that, alternating weapon and drive.

## 6. Known weaknesses

1. **Nothing here has been seen on screen.** Every number in this file is
   headless. The model placements in particular are argued from
   `Arena/assets/parts/manifest.json` sockets and not from a render: the crusher
   and the axe undo their model's authored arm angle and re-seat it on the hinge,
   and the ram lines its model's point up with its collision face. All three are
   the kind of thing that looks obviously wrong the first time it is drawn.
2. **The crusher has no anvil collision.** The model draws one; the jaw closes
   onto whatever is between it and the hull, and the grip force does the holding.
   A real lower jaw would be a second body, and the body budget allows exactly two
   weapon bodies, so it is affordable if it turns out to matter.
3. **The axe's `_is_top_face` trusts the armour plate it found first.** For a bare
   hull it asks the victim's own `face_for_contact`, which is the same test the
   damage model uses, but for a plate it takes the plate's key. On a bot whose top
   plate is gone the same blow is judged by geometry instead, which can disagree
   at the boundary (the face test is 79 percent of hull height).
4. **The ram's bonus is free momentum, and it is modelled rather than measured
   from the solver.** There is no reaction on the wielder, and the file says why
   (with one, the ram measured WORSE than no weapon). The kick is computed from
   the closing speed and the reduced mass rather than read off the contact, which
   means it assumes a head on inelastic hit: a glancing blow gets the same kick
   along the charge direction that a square one does. It is the only place in
   these five where momentum is not conserved.
5. **The flame cone is a convex hull, not a swept volume.** A victim that crosses
   the cone between two ticks at speed can be missed. At 60 Hz and a 0.7 m cone
   nothing in this game moves fast enough for that to matter, but a 30 Hz phone
   build would want checking.
6. **The lifter carries by friction, not by a grab.** That is the spec ("pure
   physics"), and it means a lifted bot slides off on a hard turn. Whether that
   reads as a feature is a question for the phone.

## 7. Where the suite stood when this landed

`Arena/tests/weapons_b_test.gd`: **38 checks, 0 failures**, including the
determinism pair (two fresh child processes, 265 components identical at tick
600).

`scripts/test-arena.sh`: **12 of 13 test files green**. The one red is
`builds_test.gd` (R2's), and none of its six failures is one of these five
weapons:

- two of them are its own fixture being **12.6 kg over the weight budget**
  (`box / 6wd / horizontal_spinner`), which `BuildRules` rejects before any
  weapon runs;
- "the spinner build removes at least one panel" is W1's horizontal spinner,
  which landed the same day;
- "the flipper build throws the opponent above 0.4 m at least twice" is the
  Stage 3 flipper and R2's AI;
- "the ram build pushes furthest" compares the OPPONENT's total travel over the
  fight (`builds_test.gd` line 215), not distance pushed by the wielder, so it is
  mostly a drive and AI measurement: tracks at 6.85 m against a 4WD flipper build
  at 13.70 m, with the spinner build last at 2.31 m;
- "the ram build removes the least condition" is a strict `<` against a **tie at
  0.00**. The ram removing no condition of its own is the design (section 2.3);
  the comparison wants `<=`.

The flipper feel probe (`tests/_feel_probe.gd -- --pai=normal --oai=normal
--secs=45`) after these five landed: fires 8 and 3, 22 damage events, 282 ticks
within 1 m, minimum distance 0.72 m, peak chassis heights 0.45 and 0.38 m. The
first two gates pass; the peak is under the 0.5 m the assembly notes record.
**That cannot be these weapons**: both bots in the probe are wedge / 4WD /
flipper, so `Bot._build_weapon` loads `weapons/flipper.gd` and none of these five
scripts is ever parsed, let alone run. It is worth attributing before Stage 4
closes, but the owner of it is whoever changed the flipper's world, not W2.
