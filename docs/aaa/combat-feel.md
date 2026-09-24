# Combat feel: teardown and ranked plan

2026-09-24. Gameplay and combat feel lead, with the audio lead hat on. Pre-production: **no game
code was changed.** This is the plan the owner reviews before any of it is built.

The bar is Insomniac's weapon feel in Ratchet & Clank: every weapon has an anticipation you can
read, an impact you can feel, a beat of hit-stop, a camera that answers, layered particles, big
sound and haptics that match. Enemies telegraph so a player can learn them.

**How this was checked.** I read all three briefs, the coverage audit, the fx, audio and wave notes,
and the code in `Arena/fight`, `Arena/bot`, `Arena/ai`, `Arena/fx`, `Arena/ui` and the six Swift
files named in the task. Then I measured three things:

1. **Every hit in real fights, per weapon.** A QA harness that lives outside the repo (appendix A)
   loads the real `fight.tscn`, runs an AI against AI fight with a chosen weapon, and logs every
   `damage_event` and `weapon_fired`. It ran headless for 16 weapons at 10x speed. The fast forward
   keeps the physics step at 1/60 s, so these are the same fights a player would get (see bug B1
   for why that matters).
2. **Every sound file, numerically.** Length, peak, RMS, spectral centroid, the share of energy
   below 200 Hz (where a phone speaker plays almost nothing) and the attack time. Nothing was
   played for this. Table in appendix B.
3. **Frames from a windowed desktop run** of the same harness, saved around the biggest hits and
   after the result, in `docs/aaa/img/combat/` (appendix C).

---

## Verdict in ten lines

1. The fight has good bones: real physics, a deterministic tick, 60 sound files built from physical
   models, bolt showers, decals, a broadcast HUD, commentary and an endgame. The machinery exists.
   What is missing is almost entirely **the moment of impact**.
2. **Every hit in the game gets the same kind of feedback, sized only by how much condition it
   took off.** One function (`FightFx.on_damage_event`) decides the sound, the sparks, the shake and
   the haptic from `severity`, and 0.3 is the only threshold. The weapon that landed the blow, the
   material it struck and the physical force behind it are ignored.
3. **A flipper throw has no impact at all.** The flipper plays the same valve-and-gas sound and the
   same tap whether it launches a machine or fires at thin air. Over two minutes of flipper
   against flipper, the player's flipper fired 13 times and scored zero damage events. The flip is
   the game's signature move (brief v3 §15: "if a flipper throw ... does not feel good here,
   nothing later saves it"), and at the moment it connects the game says nothing.
4. **The continuous weapons flood the feedback path.** A saw produced **50,197 damage events in
   120 s** (about 420 a second), a flamethrower 8,579 in 46 s. Each one kicks the camera by at least
   0.10 trauma, restarts a spark emitter, asks for a hit sound and a haptic, and places a decal.
   While a saw cuts, the camera shake is pinned at maximum and the hit sound retriggers every frame.
5. **There is no hit-stop, no slow motion, no rotational camera kick, no zoom punch.** The camera
   shake is a translation of at most 7 cm on a 28 degree lens, so a typical hit moves the frame by
   well under 1 % of its height. Only a spinner hit shows at all.
6. **The finish is thrown away.** At a knockout or a ring-out every body is frozen in place (a
   machine going over the wall stops in mid-air), the bell rings, and the Swift shell covers the
   arena with the result sheet (Quick Fight) or leaves for the Match Report (career) on the same
   frame. The wreckage orbit and the KNOCKOUT banner play behind it.
7. **Nothing reads before it happens.** No weapon has a wind-up. The axe goes from rest to the floor
   in 0.15 s with no cocking. The AI decides to dart in, pin or shove, and nothing on screen or in
   the speaker says so. Four of the six arenas' hazards fire with no warning.
8. **Damage does not show on the machines.** Scratch decals are placed in world space and do not
   follow the bot, so a machine drives out from under its own scratches. There is no persistent
   smoke, sparking or loose panel on a damaged machine, and the HUD shows one condition bar each.
9. **Audio is thorough, clever and entirely synthesised.** 63 files. Impacts sit at a spectral
   centroid around 400 Hz with half-second tails and no material layers. There is no music apart
   from a 4 s endgame drone, no stings, no announcer, and a pad player gets no controller rumble.
10. The order to fix it: the three bugs that make weapons feel wrong today, then a proper impact
    tier system with hit-stop and camera, then the finish, then tells and readability, then
    recorded audio. Sections (g) and (h) are the ranked list.

---

## (a) The moment-to-moment loop today, honestly

**Before the bell.** The shell sends a `fight_config`; the arena builds a world and runs a 3 s
countdown: a HUD numeral, a tick at 880 Hz (pitch 1.5 for FIGHT), a "YOU" tag over the player for
4 s. The machines are already in place and the crowd bed is already running. There is no entrance,
no introduction of the two machines, no crowd swell at FIGHT, no camera move. The first frame of
the fight is the last frame of the countdown.

**The open phase (0:00 to 2:00).** You drive with a floating left stick (screen relative, rotated
into the world by the camera yaw) and hold or tap one weapon button. The camera tracks you at a
fixed angle and zooms to fit both machines. The AI circles at a standoff ring and darts in when it
has an angle. Contact happens in short bursts. Between contacts the soundscape is the drive whine,
tyre roll, skid and scrape (wave F's `MachineAudio`, good work) under a crowd bed.

**When something connects** (all from `FightFx.on_damage_event`, one path for everything):

| severity | sound | haptic | shake (trauma) | particles | other |
|---|---|---|---|---|---|
| < 0.3 | `impact_light` (0.13 s) | `.medium` impact | 0.10 to 0.34 | spark burst, 30 to 50 % size | scratch decal |
| >= 0.3 | `impact_heavy` (0.5 s) | `.heavy` impact | 0.34 to 0.90 | full sparks; light pop at >= 0.45 | BIG HIT line and crowd swell |
| detach | + `wheel_off` / `panel_off` | same | same | + white core flash, dust, chips | debris body |
| any with scrap | bolt shower 25 to 475 ms later, collect ramp | 1 tick per bolt | | torn-metal pieces | HUD counter rolls |

Measured over whole fights (harness, appendix A), per weapon, hits by the player on the opponent:

| weapon | fight | player hits | at or above 0.3 | median severity | notes |
|---|---|---|---|---|---|
| flipper | 120 s, time | **0** | 0 | 0 | 13 fires; a throw is not a damage event |
| horizontal spinner | **ended 9.9 s** | 1 | 1 | 1.00 | one hit, fight over |
| vertical spinner (drum) | ended 20.8 s | 8 | 7 | 0.79 | 3 parts off |
| full-body spinner | ended 11.2 s | 1 | 1 | 1.00 | one hit, fight over |
| axe | 120 s, time | 2 | 2 | 0.35 | just over the heavy line |
| crusher | ended 12.0 s (lost) | 0 | 0 | 0 | 0 fires |
| saw | 120 s | **50,197** | 0 | 0.0000 | continuous, one event per part per tick |
| flamethrower | ended 45.7 s | **8,579** | 0 | 0.0000 | continuous |
| ram | 120 s | 0 | 0 | 0 | a ram's hurt is the wall, credited later |
| lifter | ended 102.4 s | 0 | 0 | 0 | |
| (wave P rows) | see appendix A | | | | |

So the game has two kinds of weapon: **one-shot spinners** whose single hit ends the fight before
the feedback has finished, and **everything else**, whose hits never cross the heavy line or are not
hits at all. The feedback ladder between "light scrape" and "fight over" is nearly empty.

**The endgame (2:00).** This is the best-built moment in the fight: horn, crowd roar, drone on the
music bus, a hot light shift, the camera pulls back 0.6 s and returns, the HUD slams ENDGAME, one
heavy haptic, the arena escalates and the house bot comes out. It is a template for what the other
moments should get.

**The finish.** Knockout (a 10 s count with a tightening tick and a crowd roar), ring-out, core
kill or judges at 3:00. At the finish, `fight.gd:_finish` freezes every body static (`bot.freeze`
zeroes velocities, `fight.gd:3019-3022`), plays the bell, starts the wreckage orbit and shows the
banner. On the same frame the shell reacts to `fight_state = result`: `FightView.swift:65`
presents the result sheet and `CareerFightView.swift:143` leaves for the Match Report. The player
never sees the knockout they just scored.

**What it feels like, in one sentence:** a well-instrumented physics sandbox where the machines
bump, the spinners delete each other, and nothing in between lands with weight.

---

## (b) Weapon feel, family by family

### The shared problems first

These apply to every family, so each family below only lists what is its own.

**S1. Feedback is keyed to condition removed, not to the blow.** `fx.gd:193-206` sizes everything
by `severity`. Severity is armour-adjusted condition loss, which is the right number for the
rules and the wrong number for the senses: an axe slamming a steel lid takes little condition and
is a huge event; a saw tick takes little condition and is a tiny one. The payload already carries
`impulse` (0 for continuous damage, newton-seconds for a blow), the attacker and the part; the
fix is a **feel tier** computed in presentation from weapon kind, impulse and severity together
(item F1 in the backlog).

**S2. Continuous damage is not rate-limited for presentation.** One damage event per part per tick
(`damage.gd:221-247`) is right for the ledger. The FX layer must coalesce them: one "cutting"
state per attacker-victim pair that drives a loop, a spark stream and a rumble, plus a discrete
"bite" event when a bite threshold of accumulated condition is crossed (item F2).

**S3. `weapon_fired` has no payload and the default sound is the flipper's.** `fx.gd:223-238`
matches `axe`, `ram`, `crusher` and plays `flipper_fire` for everything else. The spinners, saw,
drill and twin saw emit `weapon_fired` when they reach full spin (`horizontal_spinner.gd:175-177`
and the same lines in the others), so **a spinner reaching full speed plays a pneumatic valve and a
gas blast and a rigid haptic**, and does it again every time it re-spins past 50 %. The napalm
cannon and the tesla arc play it on top of their own launch and discharge sounds. Meanwhile the
crusher and the ram never emit `weapon_fired` at all, so `crusher_clamp.wav` and `ram_hit.wav` are
never heard, and `axe_hit.wav` has no caller anywhere (bug B3).

**S4. No hit-stop exists, and it can be done without touching the simulation.** The deterministic
tick must never change length. It does not have to: hit-stop can dilate the **real-time rate at
which ticks are taken** while every tick stays exactly 1/60 s. Measured headless on this Mac with
Godot 4.6.3: `Engine.time_scale = 0.25` alone makes the physics delta 0.0042 s (a different fight),
but `Engine.time_scale = k` **with** `Engine.physics_ticks_per_second = 60 * k` gives a physics
delta of exactly 0.016667 s at k ticks per real second. Input is sampled per tick and recorded per
tick, so a replay is identical. Audio is not scaled by `time_scale`, so the impact sound rings on
through the freeze, which is exactly the effect wanted. Rules for it (item F3):

- tiers: light 0 ms, medium 45 ms, heavy 80 ms, detach 110 ms, KO or ring-out goes to slow motion;
- a floor of k = 0.08 rather than a true zero, so the frame breathes;
- never two in a row inside 250 ms, never in a replay seek, never while paused;
- the HUD clock and `_process` presentation run on real time, not scaled time, during the stop;
- enable Godot's 3D physics interpolation (`physics/common/physics_interpolation`) so a slowed tick
  rate is smooth rather than stop-motion. That also fixes judder on a 120 Hz ProMotion screen, which
  today draws 60 Hz physics with no interpolation.

The alternative, a visual-only freeze that holds the bots' meshes while physics runs on, desyncs
what you see from where things are and breaks contact reads; I do not recommend it.

**S5. The camera answers too little and in one way only.** `ImpactShake` is a positional offset on
the Camera3D child, max 7 cm, trauma squared (`impact_shake.gd:47`). At the fight distance (3 to
6 m, FOV 28 degrees) full trauma is roughly 3 % of the frame height; a 0.35 axe hit gives trauma
about 0.38, squared 0.14, which is 1 cm, about 0.4 % of the frame. Missing: a **directional kick**
along the hit (the frame is shoved away from the blow and springs back), a **rotational** component
(roll and pitch, 0.5 to 1.5 degrees), a **FOV punch** on heavy hits (28 to 25 degrees in 60 ms, back
in 250 ms), and trauma sized by the feel tier rather than severity. **Trap:** the player's stick is
turned into a world heading from the fight camera's basis (`fight.gd:1834-1850`,
`cam.global_transform.basis`). A rotational kick on the Camera3D would twist the player's steering
for the length of the kick. The heading must be read from the rig's yaw, not the camera node,
before any rotational shake ships (item F4).

**S6. The finish.** See (c).

**S7. Haptics are five fixed taps.** `HapticsPlayer.swift:62-81` maps six kinds to
`UIImpactFeedbackGenerator` styles with no intensity, and the arena sends only those six. Core
Haptics (`CHHapticEngine`) is not used, so there are no patterns: no rising spin-up rumble, no
continuous buzz for a saw in a cut, no two-stage "clunk then ring" for an axe, no heartbeat for the
KO count. A player on a pad gets **nothing**: `ControllerObserver.swift` never touches
`GCController.haptics`, and a DualSense's adaptive triggers are unused (item F9).

### Spinners (horizontal bar, drum, full-body, vortex)

| | today | AAA target |
|---|---|---|
| anticipation | spin-up loop pitched 0.55 to 2.10 by readiness (good); a spin ring on the button; "SPINNING UP" line | the bar visibly blurs (motion-blur disc mesh past 60 %), a rising whine layer that tops out with a "ready" ring-over, a steady rumble haptic that grows with RPM, heat shimmer at full |
| at full spin | **plays `flipper_fire` and a rigid tap** (S3) | a short "locked" chirp, no haptic, nothing that sounds like gas |
| impact | heavy sound, heavy tap, sparks, light pop, BIG HIT, crowd | tiered: a glancing bite (sparks, ring, no stop) vs a full bite (80 ms stop, FOV punch, kick opposite the tangent, a metal "shriek" layer, sparks along the tangent not a radial burst, a chunk of the victim's plate flying) |
| self-destabilise | real physics reaction on the wielder | a counter-shake on the wielder's side and a gyro whine dip in pitch as the bar loses RPM |
| KO by one hit | fight ends that frame, body frozen | slow-motion follow of the victim, 1.2 s, then the normal finish |
| decals | world-space scratch (does not follow the bot, bug B4) | gouge decals parented to the struck panel |
| missing | RPM-dependent spin-down after a bite; tangent-aligned sparks; a vortex lift has its own dust burst (wave P did this) but plain spinners do not | |

The one-hit fight is a balance issue as much as a feel one: two of three spinner fights ended on
their first contact (9.9 s and 11.2 s). A single 100 % bite ending a three-minute round will make
the spinner feel like a lottery ticket no matter how good the hit looks. Flagged for the owner (D4).

### Flipper (and lifter)

| | today | AAA target |
|---|---|---|
| anticipation | none: the arm fires on the press. The AI fires on proximity | a 60 ms "pressurise" hiss and arm shiver before the valve (presentation only: the hinge fires on the same tick as today, the hiss plays from the press), the gas pips on the button |
| connect vs whiff | **identical**: same sound, same tap, whether a machine was on the arm or not (`flipper.gd:220-233`) | whiff: valve and gas only, a light tap. Connect: valve, a big metallic "clang" of arm on hull, 60 ms hit-stop at the top of the stroke, camera tilt up following the victim, heavy haptic, dust ring on the floor, crowd "oooh" rising while the victim is airborne |
| the flight | nothing | a trail on the victim's chassis while airborne above 0.3 m, the camera zoom eases out to keep it framed |
| the landing | `chassis_thud` from `MachineAudio` (no haptic, no dust, no shake) | landing dust ring and a small shake scaled by fall speed; if it lands inverted, FLIPPED, crowd cheer, a heavy tap |
| lifter | silent: no fire event, no sound on raise or carry | hydraulic whine loop while raising, creak under load, a "set down" thunk |

This is the highest-leverage fix in the game. The flipper is the starter weapon, the only one in
the free half's first hour, and the move the brief says the design lives or dies on. Item F5 needs a
monotonic `throws()` counter on the flipper (read by presentation, the same pattern wave P used for
`arcs()` and `shocks()`), not a change to the signal.

### Hammers and axes

| | today | AAA target |
|---|---|---|
| anticipation | **none**: at rest the head is already cocked, the strike is 0.15 s | a 120 ms visible wind-back on the button press (presentation: the model tilts back further while the hinge waits; or a real 0.1 s wind-up in the weapon, which is a balance change, owner call D5) |
| swing | `axe_swing` whoosh (good) | whoosh pitched by head speed |
| impact | severity 0.35, heavy line barely crossed; `impact_heavy`, not `axe_hit` (never played) | the axe's own `axe_hit` layered over a material layer, 90 ms hit-stop, a downward camera kick, a floor dust ring under the victim, the victim's suspension visibly compresses (it does, physically; the camera must show it) |
| reset | the arm lifts back limply over `reset_s` | a hydraulic reset sound so the player hears when it is ready |

### Crushers

| | today | AAA target |
|---|---|---|
| anticipation | jaw opens while held; no sound | pump whine loop while closing |
| the bite | **silent**: `crusher_clamp.wav` exists and is never played (S3) | the clamp sound on first grip, a creak loop while holding, a periodic "crunch" every 0.4 s of chewing with a spark spit and a haptic pulse, a PINNED line |
| hold | continuous damage floods FX (S2) | the coalesced hold state drives it |

### Wedges and rams

| | today | AAA target |
|---|---|---|
| anticipation | none; a ram has no button | engine rev layer that rises with closing speed toward the opponent (the "run up" is the anticipation) |
| impact | `ram_hit.wav` never plays (no fire event); impact sound by severity only, often light | a ram impact tier keyed on **impulse**, not severity: the bonus kick is the ram's whole identity (`ram.gd` header), so the hit must sound and shake like momentum |
| wall slam | whatever the wall contact severity gives | wall slams credited to a ram get the heavy tier and a dust burst off the wall |
| wedge under | nothing | a scrape-lift sound and a small tap when the opponent's wheels leave the floor on your wedge (the height readout already knows) |

### Flamethrower and heat (flamethrower, napalm cannon, overcharge core)

| | today | AAA target |
|---|---|---|
| anticipation | `flame_loop` on hold; napalm: muzzle smoke, flash, `napalm_launch`, **plus `flipper_fire`** (S3) | igniter tick and pilot light glow on the nozzle before the jet |
| burn | cone mesh (`flame_cone.gd`); continuous damage floods FX (S2); scorch decals only via the attacker-weapon fallback because `source` never reaches `fight.gd` (bug B2) | heat haze on the victim, paint blistering (albedo darkening on the panel), a crackle layer that thickens with exposure, the disruption moment ("SYSTEMS DOWN" flicker on the victim's lights) |
| core cook | glow, smoke, tightening warning tick (wave P, good) | fine as is once the heat damage stops producing impact sounds (bug B2 side effect) |

### Arc and electric (tesla arc, shock prod)

Wave P's work here is the best in the game: a crackle that climbs with charge, an electrode glow,
an `ArcBolt` to the actual struck part, a flash at both ends, sparks, `arc_discharge` and a heavy
tap; the prod's bolt across its prongs; the stalled machine's arc walking round its hull. What is
missing: a **hit-stop on discharge** (the discharge is the moment, 70 ms), a camera flicker (one
frame of exposure lift), the victim's lights dying for the stall, and removing the duplicate
`flipper_fire` (S3).

### Saws, drill, twin saw

| | today | AAA target |
|---|---|---|
| anticipation | spin-up loop, spin ring | same, plus a blade blur |
| in the cut | spark streams from the rim (twin saw, drill: good), **plus** the flood (S2): the camera shake pinned at maximum, `impact_light` retriggered every frame, 8 spark emitters restarted every frame, a decal a frame | a cutting state: the pitch of the saw loop **drops under load** (the most recognisable saw sound there is), a screech layer rides on top, a continuous low haptic buzz, one bite event every ~0.1 condition with a chunk and a spark spit; the victim's panel glows at the cut line |

### Wave P additions, briefly

Hover skirt dust, walker footfalls, the reactive plate's shove, vortex lift throws, fire patches and
the core cook all have feedback and it is well made. Two gaps: footfalls (80 % of their energy under
200 Hz, so silent on a phone speaker; appendix B) and the reactive plate's `impact_heavy` tap firing
on the same frame as the ordinary impact tap (two taps, the rate limiter lets both through).

---

## (c) Readability

### Opponent tells

The AI has rich intent (`opponent_ai.gd:384-392`: escape, pin, shove, retreat, respin, backoff,
close, ring) and exposes none of it. A player learns an enemy by its tells, and today the only tell
is movement. Proposed, all presentation, all read from a new read-only `intent()` accessor:

- **dart / close**: a rev spike on the drive whine and the machine's headlights flare 250 ms before
  it commits (the AI already has `_dart_until_tick`; the tell plays at commitment, it does not
  delay it, so AI timing and determinism are untouched);
- **weapon ready**: spinners already sound it; flippers get a hiss when the AI has a target on its
  wedge (`opponent_on_wedge()` already exists);
- **pin / shove**: the tyre-scrub layer rises and the ticker says PINNED sooner (the line exists);
- **respin / retreat**: the machine's weapon pitch falls audibly (it does) and a small "RESPIN" chip
  appears over it for skill tiers up to National only (teaching tiers show more);
- **house bot**: it already idles with a sweep and a weapon tick-over; give it a warning light that
  turns red two seconds before it leaves its mark to attack.

### Hazard tells

Only the Drop Zone warns (amber rim lamp, `drop_zone.gd:34`, 3 s). The Yard's spikes, the Furnace's
jets, the Crush's rams and the Grinder give no warning. Each needs a 1 to 1.5 s tell: a floor lamp
under the spike patch, a pilot flame and hiss before a jet, a hydraulic groan and a light before a
ram stroke. The AI already reads the hazard clocks 1.5 to 2.4 s ahead; the player should get
something comparable (item R3).

### Damage state on the machines

| state | today | target |
|---|---|---|
| scratches | world-space decals that **do not follow the bot** (`damage_decals.gd:138-158` places them in the world; the node is a sibling of the bots) | decals parented to the struck panel, or a per-part damage mask in the part shader (better, no decal count limit) |
| heavy damage | nothing persists | per part condition drives: below 50 % a smoke wisp from that corner, below 25 % intermittent sparks and a flickering light, below 10 % dark smoke and a limp (the drive already loses power; the machine should also sit lower on the damaged corner visually) |
| loose panels | a panel is attached or gone | at 20 % a panel hangs by one corner (visual only: rotate the panel mesh about a hinge corner, no physics) and rattles |
| weapon jammed | JAMMED on your button, WEAPON DEAD line | a jammed weapon smokes and stops dead, the victim's weapon sound cuts with a clunk |
| core low | nothing | a pulsing red light under the hull and a heartbeat haptic for your own |

### HUD clarity

The broadcast HUD is clean and legible. Gaps: one condition bar per machine hides **which part** is
failing (the brief's whole damage model is per part), so the player cannot aim for a weak face. A
small five-pip strip under each name (wheels, weapon, armour faces, core) would turn damage into
tactics. No hit confirm on the opponent's bar: the bar should flash and drop with a lag chunk (the
familiar "white bar catches up" pattern) so a hit reads even when the camera is busy.

### Prompts

The coach callouts and the "drive to stop the count" pulse are good. Missing: a prompt when the
opponent is on your wedge ("FLIP NOW" pulse on the button, the tell above in reverse), and a prompt
when you are inverted and have a srimech (the button already relabels; pulse it).

### The endgame

The strongest moment already. Two additions: a 1 s camera shake as the arena escalates, and the
countdown of the last ten seconds of the round (the clock turns red and ticks, the crowd rises).

### The knockout and the win

This is the biggest single readability hole after the flipper. Target (item F6):

1. On the deciding tick: the rules finish as today (result built, `fight_result` held, not sent).
2. The simulation keeps running for the presentation, with scoring off: `bot.freeze()` is split into
   "stop scoring and stop driving" (what the rules need) and "stop moving" (what nobody needs). The
   result is already built, so the extra ticks cannot change it; a replay ends at the same tick.
3. Slow motion at 0.25 for 1.2 s (S4's tick dilation) on the loser, camera pushed in; ring-outs
   follow the machine over the wall; core kills get a small explosion and smoke column.
4. Real time again; KNOCKOUT slams (it exists), crowd roar, winner's machine gets a spotlight and a
   short victory spin-up of its weapon, a win sting on the music bus, a success haptic pattern.
5. After about 3.5 s, or on a tap, `fight_result` goes over the bridge and the shell takes over.

The shell change is small: present on `fight_result` arrival instead of on `fight_state = result`,
or have the arena send `result` only when the beat is over. Replays and the async ladder are
unaffected because the result is built before the beat.

### The match intro

Today it is a countdown. Target (item R5, owner decision D2 on length):

- a 4 s entrance: the camera starts on the opponent (name and roboteer as a broadcast lower third,
  their weapon spinning up once), cuts to the player's machine with the same, then pulls to the
  fight framing for 3, 2, 1;
- the crowd swells on each name and roars on FIGHT, with a short sting;
- skippable with a tap, and skipped automatically on the second attempt at the same match.

---

## (d) Controls and camera feel

**Touch stick.** Floating origin at the first touch in the left 45 % of the screen, 60 pt throw,
linear, **no dead zone in the controls** (`controls.gd:651-662`); the drive ignores throttle below
0.05 (`drive_base.gd:269`), which is 3 pt. Consequences: a resting thumb's micro-movement turns the
machine toward a random heading at a crawl, and there is no fine band for the creep the brief asks
for ("creeping in to get a wedge under someone is a distinct skill"). Target:

- a 6 pt radial dead zone and a response curve: throttle = `smoothstep` over the first 40 % then
  linear (or `x^1.6`), so the inner third of the throw is a creep;
- a **following origin**: when the thumb drags past the throw, the origin follows it, so the stick
  never saturates in a direction the thumb has moved away from;
- steering is screen relative, and the fight camera does not yaw on its own, which is right. One
  trap: after a manual orbit the camera eases back over `CAM_EASE_BACK_S` while the thumb is still
  held, so the machine's heading rotates under a still thumb. Hold the ease-back while the stick is
  live.

**Pad.** A 0.18 radial dead zone with a linear rescale (`controls.gd:874-880`), fire on A or right
trigger, secondary on B or left trigger, right stick orbits. Add the same response curve, trigger
**analogue** use for the spinner (partial trigger = partial spin target) as an option, and
controller rumble (S7). START pauses (good).

**Aim assist.** None. A light **steering magnetism** when the opponent is inside the weapon's
engage cone at close range (a 10 to 15 degree bias of the heading toward the target, fading with
stick deflection) would make the flipper and the drum far more forgiving on glass. This changes the
input the simulation receives, so it belongs in the input sampler before recording (deterministic,
replay safe) and it is an owner decision (D3).

**Camera tracking.** Wave G's tracking is careful and good: look-ahead toward the opponent, a leash
that keeps the player in the middle 60 %, a zoom that fits both. Missing: a small **lead in the
direction of travel** at speed (the camera sees where you are going, 0.3 m at top speed), the impact
reactions in S5, and a **pull-out when either machine is airborne** so a throw never leaves frame.

---

## (e) AI: personality and exploitable mistakes

The AI is solid engineering: context steering with danger masking, five skill tiers by five
temperaments, reaction delay, aim error and hesitation as the only sources of weakness ("no tier may
ever look stupid", the owner's rule), all deterministic. As a *character*, though, it reads as one
careful driver at different speeds:

- **Personality is statistical, not visible.** A brawler and a technician differ in thresholds;
  nothing a player sees says "this one is a bully". Give each temperament one signature behaviour
  that is visible in the first 20 seconds: the showboat spins its weapon up and does a victory
  circle after a hit; the bully drives at you and stops short, twice, before committing; the
  technician circles the other way to the others; the opportunist sits back and only pounces on an
  inverted machine.
- **Mistakes are hidden inside smoothing.** Aim error and reaction delay make it slower and wider;
  they do not produce a readable *mistake* the player can punish. AAA enemies commit to an attack
  with a recovery window. Proposed: after a committed dart that misses, the AI overshoots by 0.5 to
  1 m and takes 0.4 to 0.8 s (by tier) to turn round, with its rear exposed. A spinner that bites
  has to re-spin (it does) and should visibly back off with its weapon pitch falling. A flipper that
  fires dry has a 0.7 s cooldown (it does) that the player should be able to hear (the dry fire
  sound, F5).
- **Tells** (section c) turn all of this into something learnable.

The acceptance tests in `ai_test.gd` stay; add one measuring that a scripted "punisher" driver who
attacks only during the recovery window beats Regional more often than the plain novice does.

---

## (f) Audio

### What exists

63 WAV files, 44.1 kHz 16-bit, mono except the crowd bed, all **synthesised** by
`scripts/gen-sounds.py` with physical models (modal banks, waveguides, circular-convolution
reverb). Every file is normalised to -3 dBFS peak and balanced by a per-sound dB table
(`AudioMix.LEVELS`). Four buses (Music, SFX with a small reverb, Ambience, UI) into a limiter,
polyphony caps with oldest-voice stealing, a no-repeat variant picker, positional 3D voices, crowd
ducking under the bell, horn and KO tick. This is a better audio *system* than most mobile games
ship. What it lacks is content and layering.

Measured (appendix B): the heavy impacts have a spectral centroid of 380 to 420 Hz and tails of
0.44 to 0.56 s; the light impacts sit at 650 to 810 Hz, 0.13 to 0.15 s. There are three variants of
each and one material. The walker footfalls, the leg servo and the endgame drone have 64 to 83 % of
their energy below 200 Hz, which a phone speaker barely reproduces.

### Against a AAA list

| AAA element | here | status |
|---|---|---|
| layered impacts: transient + body + material + tail + debris | one file per hit, three variants, one material | **missing layers.** Needs a 4-layer impact system: a transient (crack), a body by weapon (bar, drum, axe head, ram, arm), a **material** layer by the struck face (steel ring, titanium ping, HDPE thock, polycarbonate crack), a debris tail (bolts, rattle). `AudioMix` can play four keys at once; the choice logic is new |
| weapon loops with pitch by RPM | spinners, saws, drill, vortex, arc crackle, flame | **good.** Add load: pitch drops in a cut (saw) and after a bite (spinner) |
| spin-up with a "ready" moment | readiness drives pitch; at full spin a flipper blast plays (bug B3) | fix B3, add a lock-on chirp |
| per-drive movement | whine, roll, skid, scrape, landing, tracks, omni, hover, legs | **good** (wave F) |
| hazard sounds | grinder, disc, flame jet, spikes, pit, crush ram | good; **tells** missing (c) |
| crowd reactive bed | bed + 2 swells + roar; reacts to BIG HIT, FLIPPED, KO count, endgame | **thin.** Needs: an "ooh" on a near miss and on airtime, groans when the player is hit hard, a rising "count along" under the KO count, a boo for a house bot attack, cheers on a win and a flat reaction to a judges decision. Crowd intensity should follow the fight (a slow excitement value driven by hits, airtime and closeness) |
| announcer or stings | none; the ticker is text only | **missing.** Stings on FIGHT, big hit, flip, KO and win are a small, high value set. A voiced announcer is an owner call (D6): it is the biggest single "TV broadcast" lift and the biggest licence and localisation cost |
| adaptive music | a 4 s drone in the endgame; nothing else | **missing.** Minimum: an intro sting, an open-phase bed at low level, an endgame layer on top (exists, extend), a KO / win / loss sting. Horizontal re-sequencing between intensity levels driven by the same excitement value as the crowd |
| UI sounds | countdown tick, bell; Swift menus unknown to this audit | countdown and FIGHT need a proper broadcast sting; the ENDGAME slam and the result slam want a whoosh-hit |
| mix and ducking | limiter, crowd ducks under three cues | add: a **sidechain duck of everything under a heavy hit** (3 dB, 150 ms), a low-pass on the whole mix during hit-stop and slow motion (the classic "time slows" filter), a music duck under the KO count |
| per-arena ambience | one crowd bed everywhere | each arena gets its own room tone layer (furnace roar, grinder hum, crush hydraulics) and each Series its own crowd size (Scrapyard: a few dozen in a shed; Masters: a stadium) |
| haptics matched to audio | five fixed taps | Core Haptics patterns authored alongside each impact (S7) |

### Synthesised versus recorded, and what to source

The generator's own notes say it plainly: "nobody should ship them if a licensed source is
available" (`docs/audio-notes.md` §6), and the drop-in table there (names, lengths, loop rules) is
the right spec. My recommendation by category:

| category | keep synthesised | source recorded | why |
|---|---|---|---|
| UI ticks, countdown, KO tick, cook warning | yes | | abstract, needs to be exact |
| drive whine, gear, servo loops | yes, as a layer | a real brushed motor underneath | the models are good at pitch tracking |
| impacts (metal on metal), material layers | | **yes** | the ear knows real metal; this is where synthesis shows most |
| debris, bolts, rattles, panels off | | **yes** | |
| saw, grinder, drill | | **yes** | the notes call these the weakest; friction is hard to model |
| flame, napalm, fire patch | | **yes** | |
| crowd beds, swells, cheers, boos | | **yes** | crowds are hard to synthesise; the word-free rule still applies |
| endgame horn, bell | either | a real air horn and ring bell | cheap to find |
| music and stings | | **commission or license** | nothing to synthesise here |
| announcer | | **record** (owner decision) | |

**Where to source, and the licence checks.** Candidates to verify before use (licence terms must be
re-read on the day, and every file's licence stored beside it in `Arena/audio/LICENCES.md`):

- **Sonniss "GameAudioGDC" bundles**: large, professionally recorded, royalty free for commercial
  games with no attribution. Their licence forbids redistributing the raw files, which is fine in a
  compiled app. Strong on impacts, metal, machinery, fire and crowds.
- **Freesound, CC0 filter only**: public domain dedication, no attribution. Quality varies; every
  file must be checked for the CC0 tag (not CC BY, not CC BY-NC).
- **BBC Sound Effects**: the free licence is personal, educational and research use, **not
  commercial**. Do not use in the game without a paid licence.
- **Paid libraries** (Boom Library, Soundly, A Sound Effect): the reliable route for crowds and
  metal if the free ones fall short; a one-off per-library licence.
- **Generated** (AI sound models): usable for variants and fills if the generator's terms grant
  commercial use; not for the signature sounds.

An audio sourcing agent can build a candidate board (file, source, licence, measured centroid,
low-frequency share) for the owner to audition, then drop the chosen files in under the existing
names (the pipeline needs no code change for a like-for-like swap).

---

## (g) Ranked backlog

Impact is player impact (High, Medium, Low). Cost is agent-days. "Owner" says whether an owner
decision is needed first. The list is ranked by impact over cost, with dependencies respected.

### Quick wins (under half a day each)

| # | item | impact | cost | files | owner |
|---|---|---|---|---|---|
| Q1 | Stop spinners, saws, drill, napalm, arc and prod playing `flipper_fire` and the rigid tap: route `on_weapon_fired` by weapon id, silence the "reached full spin" announce or give it a chirp (B3) | High | 0.25 | `Arena/fx/fx.gd` | no |
| Q2 | Rate-limit continuous damage in the FX path: skip shake, hit sound, haptic and decal for `impulse == 0` events below a bite threshold; accumulate them per attacker (first cut of F2) | High | 0.4 | `Arena/fx/fx.gd`, `Arena/fight/fight.gd` (`_mark_damage`, `_commentary_damage`) | no |
| Q3 | Forward `source` in the damage event (B2): one line | Medium | 0.1 | `Arena/bot/bot.gd:997-1006` | no |
| Q4 | Play the unused sounds: `axe_hit` on an axe hit, `crusher_clamp` on first grip, `ram_hit` on a ram blow (read attacker weapon in `on_damage_event`) | Medium | 0.3 | `Arena/fx/fx.gd` | no |
| Q5 | Distinguish flipper connect from dry fire with a `throws()` counter read by `WeaponFx` (clang layer, heavy tap, dust ring on connect; valve only on a whiff) | High | 0.5 | `Arena/bot/weapons/flipper.gd` (read-only counter), `Arena/fx/weapon_fx.gd` | no |
| Q6 | Hold the result sheet / Match Report for 3 s after `result` (shell side), so the KO banner, bell and wreckage orbit are seen even before F6 lands | High | 0.25 | `Roboteer/FightView.swift`, `Roboteer/CareerFightView.swift` | no |
| Q7 | Landing feedback: haptic, dust ring and a small shake on `MachineAudio`'s landing thud, scaled by fall speed | Medium | 0.3 | `Arena/fx/machine_audio.gd`, `Arena/fx/fx.gd` | no |
| Q8 | Touch stick dead zone and response curve, and hold the camera ease-back while the stick is live | Medium | 0.3 | `Arena/ui/controls.gd`, `Arena/ui/camera_rig.gd` | no |
| Q9 | Retune the phone-inaudible files (footfalls, leg servo) upward, same method F2 used for `ram_hit` | Low | 0.25 | `scripts/gen-sounds.py`, `Arena/audio/` | no |
| Q10 | Fix the replay speed and seek to keep dt at 1/60 (B1) | High (replays diverge today) | 0.3 | `Arena/fight/fight.gd:773-832` | no |

### The main list

| rank | item | impact | cost | files | owner |
|---|---|---|---|---|---|
| 1 | **F1 feel tiers**: a presentation-side classifier (weapon kind x impulse x severity x detach x struck material) giving five tiers (scuff, hit, heavy, smash, finisher) that drive sound, sparks, shake, haptic, hit-stop and crowd; retune so a clean axe or flipper connect is "heavy" | High | 1.5 | `Arena/fx/fx.gd`, new `Arena/fx/feel_tiers.gd`, `Arena/fx/impact_particles.gd`, `Arena/fight/commentary.gd` | no |
| 2 | **F2 continuous-damage states**: cutting, burning, chewing, boring as coalesced states per pair with loops, spark streams, a rumble and periodic "bite" events | High | 1.0 | `Arena/fx/fx.gd`, `Arena/fx/weapon_fx.gd`, `Arena/fx/audio_mix.gd` | no |
| 3 | **F3 hit-stop and slow motion by tick dilation**, with 3D physics interpolation on; replay-safe by construction; a determinism test that runs a fight with random hit-stops and compares the result JSON bit for bit | High | 1.5 | `Arena/fight/fight.gd` (a small "presentation clock" section), `Arena/project.godot`, new `Arena/tests/hitstop_test.gd` | yes (D1: strength) |
| 4 | **F6 the finish beat**: keep simulating after the result with scoring off, slow-motion follow, winner moment, delayed `fight_result`, shell presents on arrival | High | 1.5 | `Arena/fight/fight.gd` (`_finish`), `Arena/bot/bot.gd` (`freeze` split), `Arena/ui/camera_rig.gd`, `Roboteer/FightView.swift`, `Roboteer/CareerFightView.swift` | no |
| 5 | **F4 camera impact grammar**: directional and rotational kick, FOV punch, trauma by tier, airborne pull-out; move the stick-to-world mapping onto the rig's yaw first | High | 1.0 | `Arena/fx/impact_shake.gd`, `Arena/ui/camera_rig.gd`, `Arena/fight/fight.gd:1834-1850` | no |
| 6 | **F5 flipper and lifter feel** (beyond Q5): pressurise hiss, arm clang, flight trail, landing, lifter hydraulics | High | 1.0 | `Arena/fx/weapon_fx.gd`, `scripts/gen-sounds.py` or sourced audio | no |
| 7 | **F9 haptics v2**: Core Haptics patterns per tier and per weapon state (spin-up rumble, cutting buzz, KO heartbeat), intensity carried in the message; controller rumble on `GCController.haptics`; DualSense trigger resistance for the spinner | High on phone, High on pad | 2.0 | `Roboteer/HapticsPlayer.swift`, `Roboteer/ControllerObserver.swift`, `Arena/fx/haptics.gd`, `docs/bridge-spec.md` (message gains `intensity`) | no |
| 8 | **R2 damage on the machines**: panel-parented decals (fix B4), per-part smoke, sparks and hanging panels by condition, jammed weapon smoke | High | 2.0 | `Arena/render/damage_decals.gd`, `Arena/bot/part_visuals.gd`, new `Arena/fx/damage_state_fx.gd` | no |
| 9 | **A1 impact audio layers**: transient + weapon body + material + debris tail; source recorded metal and debris (A3) | High | 1.5 build + A3 | `Arena/fx/audio_mix.gd`, `Arena/audio/` | yes (D6 for spend) |
| 10 | **R1 AI tells and readable recovery windows**; temperament signatures | High | 2.0 | `Arena/ai/opponent_ai.gd` (read-only `intent()`, recovery windows), `Arena/fx/weapon_fx.gd` or new `Arena/fx/tell_fx.gd`, `Arena/tests/ai_test.gd` | yes (D7: recovery windows change the AI's strength) |
| 11 | **R3 hazard tells** in the Yard, Furnace, Crush, Grinder and Coliseum | Medium | 1.0 | `Arena/arena/*.gd` (presentation children only, timers already seeded) | no |
| 12 | **A2 music and stings**: intro sting, open bed, endgame layer, KO, win, loss; an excitement value that drives music and crowd | High | 1.5 build + sourcing | `Arena/fx/audio_mix.gd`, new `Arena/fx/excitement.gd` | yes (D6) |
| 13 | **A4 crowd v2**: excitement-driven intensity, ooh / groan / boo / cheer sets, per-Series crowd size, per-arena room tone | Medium | 1.0 + sourcing | `Arena/fx/audio_mix.gd`, `Arena/audio/` | no |
| 14 | **R5 match intro** (entrance, names, crowd, sting), skippable | Medium | 1.5 | `Arena/fight/fight.gd` (countdown section), `Arena/ui/camera_rig.gd`, `Arena/ui/hud.gd` | yes (D2) |
| 15 | **R4 HUD per-part strip and hit-confirm on the bars** | Medium | 1.0 | `Arena/ui/hud.gd` | no (mockup first, owner rule) |
| 16 | **C1 aim assist (steering magnetism)** | Medium | 0.75 | `Arena/fight/fight.gd` (input sampler), `Arena/tests/determinism_test.gd` | yes (D3) |
| 17 | **C2 camera travel lead**, pad analogue trigger option, following touch origin | Low | 0.5 | `Arena/ui/camera_rig.gd`, `Arena/ui/controls.gd` | no |
| 18 | **W1 weapon anticipation**: spinner blur disc, axe wind-back (presentation) | Medium | 1.0 | `Arena/bot/part_anim.gd`, `Arena/bot/part_visuals.gd` | yes if the wind-up is real (D5) |
| 19 | **A5 announcer** | High if yes | 3.0 + recording | new `Arena/fx/announcer.gd`, `Arena/audio/vo/` | yes (D6) |
| 20 | **Spinner one-hit balance** (not feel, but it defeats every feel fix for that family) | High | 0.5 to 1 | `Arena/bot/weapons/*spinner*.gd`, `Shared/parts.json` | yes (D4) |

Roughly **8 agent-days** gets ranks 1 to 6 plus all the quick wins, which is the difference between
"sandbox" and "hits land". Ranks 7 to 13 are another **12 to 14 days** plus sourcing.

**Suggested waves.** Wave FEEL-1 (parallel, disjoint files): Q1 to Q10, then ranks 1, 2 and 5 on
one agent (they share `fx.gd`), rank 3 on a second (`fight.gd` presentation clock, tests), rank 4
on a third (`_finish`, `bot.freeze`, the shell), rank 6 on a fourth (`weapon_fx.gd`). Owner plays.
Wave FEEL-2: ranks 7, 8, 10, 11. Wave AUDIO: ranks 9, 12, 13 with a sourcing agent in front.

---

## (h) Decisions needed from the owner

- **D1. Hit-stop strength.** Subtle (heavy hits only, 50 to 80 ms) **or** Ratchet-strong (every
  hit from "hit" upward, up to 120 ms, plus slow motion on every part coming off)?
- **D2. The match intro.** A 4 s skippable entrance on every fight **or** only on Series finals and
  rival fights, with the plain countdown elsewhere?
- **D3. Aim assist.** A light steering magnetism on touch (off on a pad) **or** none, keeping the
  driving fully manual?
- **D4. Spinner one-hit fights.** Cap a single bite so a spinner needs at least two or three clean
  hits to finish a healthy machine **or** keep the one-hit kill as the spinner's identity?
- **D5. Axe wind-up.** A real 0.1 s wind-up in the weapon (a balance change the AI must learn) **or**
  presentation only (the model tilts back while the hinge fires on the same tick)?
- **D6. Audio spend and voice.** Free sources only (Sonniss GDC bundles, Freesound CC0) **or** a paid
  library budget for crowds and metal? And a voiced announcer **or** stings and the text ticker
  only?
- **D7. AI recovery windows.** Every tier gets a readable, punishable recovery after a missed
  commit (Masters shortest) **or** only Scrapyard to National, keeping Championship and Masters
  clean?
- **D8. The finish.** Hold the arena for a fixed ~3.5 s beat before the result screen **or** hold
  until the player taps?

---

## Bugs found while reading

| id | where | what | effect |
|---|---|---|---|
| B1 | `Arena/fight/fight.gd:773-783` (`_set_replay_speed`), `:785-789`, `:803-832` (seek) | `Engine.time_scale` scales the physics delta in Godot 4.6. Measured: at 0.25 the tick is 0.0042 s, at the seek's 24 it is **0.4 s**. The replay's 0.25x and 0.5x speeds and every seek re-simulate a different fight, which contradicts the comment at `:741-743` and the "bit-exact replay" claim for anything but 1x. Fix: set `Engine.physics_ticks_per_second = 60 * time_scale` alongside (measured: delta stays 1/60) and restore both | slow-motion replays and seeks diverge from the fight; the seek at 0.4 s steps is likely to tunnel and explode |
| B2 | `Arena/bot/bot.gd:997-1006` (`_flush_damage`) | the damage event is built without `source`, although `damage.gd:175` and `:240` now record it (commit `c69b84f` fixed half of it). Measured: 0 of 58,000+ events carry `source` | burns, heat and the overcharge cook are drawn as scratches unless the attacker's weapon kind is `flame`; arena flame jets never scorch the machine |
| B3 | `Arena/fx/fx.gd:223-238` with the `emit_weapon_fired` calls in `horizontal_spinner.gd:177`, `vertical_spinner.gd:174`, `full_body_spinner.gd:202`, `saw.gd:189`, `twin_saw.gd:189`, `drill_lance.gd:174`, `napalm_cannon.gd:376`, `tesla_arc.gd:169`, `shock_prod.gd:161` | every weapon kind but axe, ram and crusher falls to the default branch and plays `flipper_fire` plus a `flip` haptic | spinners and saws "fire a flipper" each time they reach full spin; napalm, arc and prod play it on top of their own sounds |
| B4 | `Arena/render/damage_decals.gd:138-158` | scratches and scorches are placed as world-space `Decal` nodes and never parented to the bot | a machine drives out from under its own damage; the decal box can paint whatever passes through it later (the other machine, the floor) |
| B5 | `Arena/fx/fx.gd:193-206`, `Arena/fight/fight.gd:3054-3060` | no rate limit on continuous damage events in presentation: a saw produced about 420 events a second. Each kicks the shake (minimum 0.10 trauma, so trauma saturates at 1.0), restarts one of 8 spark emitters, plays `impact_light` (cap 4, oldest stolen every frame), asks for a haptic and places a decal (the 48-decal pool is recycled every few frames) | while cutting or burning, the camera shakes at maximum, the hit sound machine-guns, sparks flicker, and the frame cost climbs |
| B6 | `Arena/fx/fx.gd:237-238` and `Arena/bot/weapons/flipper.gd:220-233` | the flipper emits `weapon_fired` on a dry fire and a real throw alike; presentation cannot tell them apart | a whiff and a throw feel identical (the feel gap in (b)) |
| B7 | `Arena/bot/bot.gd:1331-1343` via `Arena/fight/fight.gd:3019-3022` | `freeze()` zeroes every velocity and makes every part static at the finish | a machine thrown over the wall stops dead in mid-air; the knockout moment is a freeze-frame |
| B8 | `Roboteer/FightView.swift:64-65`, `Roboteer/CareerFightView.swift:143` | the result sheet / Match Report is presented on the same frame as `fight_state = result` | the in-arena KO banner, bell and wreckage orbit are covered immediately |
| B9 | `Arena/fx/weapon_fx.gd:392` with `Arena/fx/fx.gd:204` | a reactive-plate hit sends `impact_heavy` from `WeaponFx` and `impact_*` from `FightFx` on the same frame | two haptic taps for one blow (minor) |
| B10 | `Arena/ui/controls.gd:159-172` | `WEAPON_HOLDS["flame"] = true` and the button word FIRE apply to the napalm cannon (kind `flame`) too, which fires on the edge | the coach tells a napalm player to hold (minor) |
| B11 | `Arena/fight/fight.gd:3255-3259` (`_is_burn`) | its comment says a damage event carries no source, which B2's fix makes false; once B2 lands, hazard flames and heat must be checked here, not only the attacker's weapon kind | stale comment; behaviour right after B2 |

Not bugs, but worth knowing: `Engine.time_scale` is also set by the rumble probe
(`Arena/tests/_rumble_probe.gd:31`) with the same caveat as B1; and the endgame's presentation
calls (`fight.gd:1627-1645`) run inside the physics tick, so a seek plays the horn and the haptic
while the picture is off.

---

## Appendix A: the measurement harness and the full sweep

`feel_harness.gd` lives in the session scratchpad, not the repo (this round writes only this file).
It is 150 lines: it instantiates `res://fight/fight.tscn`, calls `start_fight` with the Stage 3
fixture altered (player weapon and chassis chosen, opponent a box 4WD flipper, both driven by the
`normal` AI, seed 424242, the Yard, 180 s rules), connects to both bots' `damage_event` and
`weapon_fired`, and prints a summary. `--speed=k` sets `Engine.time_scale = k` **and**
`physics_ticks_per_second = 60k`, which is B1's fix, so the sweep ran at 10x with a 1/60 s tick.
Worth adding to `Arena/tests/` as `_feel_sweep.gd` (skipped by the suite, like `_feel_probe.gd`) in
the first feel wave, because every item above should move these numbers.

Full sweep (player's hits on the opponent, severity is condition removed):

SWEEP_TABLE_PLACEHOLDER

## Appendix B: every sound file, measured

Peak is -3 dBFS on every file by design. `<200 Hz` is the share of energy below 200 Hz; `centroid`
is the spectral centroid; `attack` is the time to 90 % of peak.

AUDIO_TABLE_PLACEHOLDER

## Appendix C: frames

CAPTURE_PLACEHOLDER
