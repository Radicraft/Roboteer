# Combat feel: teardown and ranked plan

2026-09-24. Gameplay and combat feel lead, with the audio lead hat on. Pre-production: **no game
code was changed.** This is the plan the owner reviews before any of it is built.

The bar is Insomniac's weapon feel in Ratchet & Clank: every weapon has an anticipation you can
read, an impact you can feel, a beat of hit-stop, a camera that answers, layered particles, big
sound and haptics that match, and enemies that telegraph so a player can learn them.

**How this was checked.** I read all three briefs, the coverage audit, the fx, audio and wave notes,
and the code in `Arena/fight`, `Arena/bot`, `Arena/ai`, `Arena/fx`, `Arena/ui` and the six Swift
files named in the task. Then I measured four things:

1. **Every hit in real fights, per weapon.** A QA harness that lives outside the repo (appendix A)
   loads the real `fight.tscn`, runs an AI against AI fight with a chosen weapon, and logs every
   `damage_event` and `weapon_fired`. 16 weapons, 120 s each, at normal speed.
2. **Whether hit-stop can be added without breaking replays.** Two techniques tried against the
   same fight, compared by a hash of every damage event (time, part, severity). One works; one does
   not (section b, S4).
3. **Every sound file, numerically.** Length, RMS, spectral centroid, the share of energy below
   200 Hz (where a phone speaker plays almost nothing) and the attack time. Nothing was listened
   to for this. Table in appendix B.
4. **Frames from windowed desktop runs** of the same harness, saved at the hit, +90 ms and +300 ms
   for big hits, around flipper fires, and after the result. Contact sheets in
   `docs/aaa/img/combat/` (appendix C).

Line numbers are against `HEAD` (`81a743d` plus this doc). Wave A is being built in the same tree
right now (`docs/wave-a-contracts.md`): its hazards engineer is adding hazard telegraphs with
wind-up sounds and a hazard camera shake (`FightFx.on_hazard_warning` / `on_hazard_strike`,
uncommitted), and its venue lead has entrance, pyro and excitement hooks on `VenueKit`. Where this
plan touches the same thing it says so and builds on theirs rather than beside it. The measured
runs loaded the working tree of 2026-09-24 about 20:00, wave A edits included.

---

## Verdict in ten lines

1. The fight has good bones: real physics, a deterministic tick, 66 sound files built from physical
   models, bolt showers, decals, a broadcast HUD, commentary and an endgame. The machinery exists.
   What is missing is almost entirely **the moment of impact**.
2. **Every hit gets the same kind of feedback, sized only by how much condition it took off.** One
   function (`FightFx.on_damage_event`) picks the sound, sparks, shake and haptic from `severity`,
   and 0.3 is the only threshold. The weapon, the material struck and the force behind the blow are
   ignored. Result: spinner hits are all maximum (median severity 1.0), the axe's median hit is 0.30
   (half its hits play the *light* sound), and nothing in between exists.
3. **A flipper throw has no impact at all.** The flipper plays the same valve-and-gas sound and the
   same tap whether it launches a machine or fires at thin air. In two minutes of flipper against
   flipper the player's flipper fired 9 times and produced **zero damage events of its own**. The
   flip is the game's signature move (brief v3 §15: "if a flipper throw ... does not feel good
   here, nothing later saves it"), and when it connects the game says nothing. The frames agree:
   seven fires captured, and in none of them does the opponent visibly move (two are in
   `flipper_fires_sheet.jpg`).
4. **The continuous weapons flood the feedback path.** The saw produced 3,209 damage events in
   120 s, peaking at 146 in one second; the drill 202 in one second; up to five in a single tick.
   Each one kicks the camera by at least 0.10 trauma, restarts a spark emitter, asks for a hit
   sound and a haptic, and places a decal. While a saw cuts, the camera shake saturates at maximum
   and the hit sound retriggers every frame.
5. **There is no hit-stop, no slow motion, no rotational camera kick and no zoom punch.** The shake
   is a translation of at most 7 cm on a 28 degree lens, so an axe hit moves the frame by well
   under 1 % of its height.
6. **The biggest hits white out the screen.** At +300 ms after a full spinner bite or a part coming
   off, the additive flashes and the bolt shower cover both machines (`hspin_full_bite_sheet.jpg`,
   `hspin_detach_sheet.jpg`). The reward hides the consequence: you cannot see what came off or
   where the victim went.
7. **The finish is thrown away.** At a knockout or ring-out every body is frozen in place (a machine
   going over the wall stops in mid-air), the banner lands across the middle of the frame where the
   wreck is, and on the same frame the Swift shell covers the arena with the result sheet (Quick
   Fight) or leaves for the Match Report (career).
8. **Nothing reads before it happens.** No weapon has a wind-up; the axe goes from rest to the floor
   in 0.15 s. The AI decides to dart, pin or shove and nothing says so. At `HEAD` four of six arenas'
   hazards fire without warning (wave A is adding telegraphs now). Damage does not show on the machines: scratch decals are placed in world
   space and do not follow the bot.
9. **Audio is thorough, clever and entirely synthesised.** Impacts have one material, a centroid
   near 400 Hz and half-second tails. No music except a 4 s endgame drone, no stings, no announcer,
   and a pad player gets no controller rumble. Six files are mostly below 200 Hz and inaudible on a
   phone speaker.
10. The order to fix it: the bugs that make weapons feel wrong today (quick wins), then a real
    impact tier system with hit-stop and camera, then the finish, then tells and readability, then
    recorded audio. Sections (g) and (h) are the ranked list and the owner's decisions.

---

## (a) The moment-to-moment loop today, honestly

**Before the bell.** The shell sends a `fight_config`; the arena builds a world and runs a 3 s
countdown: a HUD numeral, a tick at 880 Hz (pitch 1.5 for FIGHT), a "YOU" tag over the player. The
machines are already in place, the crowd bed is already running. There is no entrance, no
introduction of the two machines, no crowd swell at FIGHT and no camera move.

**The open phase (0:00 to 2:00).** You drive with a floating left stick (screen relative, turned
into the world by the camera yaw) and hold or tap one weapon button. The camera tracks you at a
fixed angle, fairly high and far (pitch 50, FOV 28; the machines are about a tenth of the frame
height in the captures) and zooms to fit both machines. The AI circles at a standoff ring and darts
in when it has an angle. Contact comes in short bursts. Between contacts the soundscape is drive
whine, tyre roll, skid and scrape (wave F's `MachineAudio`, good work) under a crowd bed.

**When something connects**, all from `FightFx.on_damage_event` (`Arena/fx/fx.gd:193-219`), one
path for everything:

| severity | sound | haptic | shake (trauma) | particles | other |
|---|---|---|---|---|---|
| < 0.3 | `impact_light` (0.13 s) | `.medium` impact | 0.10 to 0.34 | spark burst, 30 to 50 % size | scratch decal |
| >= 0.3 | `impact_heavy` (0.5 s) | `.heavy` impact | 0.34 to 0.90 | full sparks; light pop at >= 0.45 | BIG HIT line and crowd swell |
| part off | + `wheel_off` / `panel_off` | same | same | + white core flash, dust, chips | a grey debris body |
| any scrap | bolt shower 25 to 475 ms later, rising collect ramp | a tick per bolt | | torn-metal pieces | HUD counter rolls |

Measured over whole fights, the player's weapon against a box 4WD flipper, both AI driven, seed
424242, the Yard, 120 s at normal speed. "Hits" are the player's own damage events on the opponent;
severity is condition removed.

| weapon (chassis) | finish | fires | hits | >= 0.3 | parts off | median sev | max sev |
|---|---|---|---|---|---|---|---|
| flipper (wedge) | none | 9 | **0** | 0 | 0 | 0 | 0 |
| horizontal spinner (box) | none | 6 | 3 | 3 | 1 | **1.00** | 1.00 |
| vertical spinner, drum (wedge) | 92.6 s | 4 | 6 | 2 | 0 | 0.20 | 0.80 |
| full-body spinner (shell) | 63.0 s | 4 | 6 | 3 | 1 | **0.96** | 1.00 |
| vortex spinner (shell) | 26.4 s | 3 | 7 | 5 | 2 | 0.63 | 1.00 |
| axe (tall tank) | none | 11 | 6 | 2 | 1 | **0.30** | 0.35 |
| crusher (box) | none | **0** | 3,156 | 0 | 1 | 0.0005 | 0.0005 |
| saw (box) | none | 14 | **3,209** | 0 | 0 | 0.0004 | 0.0010 |
| twin saw (box) | none | 10 | 3,048 | 0 | 0 | 0.0004 | 0.0011 |
| drill lance (box) | none | 2 | 3,787 | 0 | 2 | 0.0009 | 0.0013 |
| ram (wedge) | none | 0 | 0 | 0 | 0 | 0 | 0 |
| lifter (wedge) | none | 0 | 0 | 0 | 0 | 0 | 0 |
| flamethrower (box) | none | 0 | 311 | 0 | 0 | 0.0005 | 0.0005 |
| napalm cannon (box) | none | 5 | 1,379 | 0 | 0 | 0.0005 | 0.0005 |
| shock prod (box) | none | 10 | 2,001 | 0 | 0 | 0.0006 | 0.0006 |
| tesla arc (box) | none | 29 | 26 | 0 | 0 | 0.09 | 0.09 |

Peak event rates for the continuous weapons: drill 202 in one second, saw 146, flamethrower 75,
crusher 60; up to five events in one tick.

So the game has **three kinds of weapon**: spinners whose every hit is a maximum; a flipper, ram and
lifter whose work (a throw, a shove, a carry) produces no event of its own, only a later landing or
wall contact credited by the 2 s rule; and continuous weapons that produce hundreds of invisible
events. The ladder between "scrape" and "part gone" is nearly empty, and the 0.3 line cuts the
axe's hits in half at random.

**The endgame (2:00).** The best-built moment in the fight: horn, crowd roar, drone on the music
bus, a hot light shift, the camera pulls back 0.6 s and returns, the HUD slams ENDGAME, one heavy
haptic, the arena escalates and the house bot comes out. It is the template for what the other
moments should get.

**The finish.** Knockout (a 10 s count with a tightening tick and a crowd roar), ring-out, core kill
or judges at 3:00. `fight.gd:_finish` freezes every body static (`bot.gd:1331-1343`: velocities
zeroed, `freeze = true`), plays the bell, starts the wreckage orbit and slides the banner in. The
banner sits across the centre of the frame, which is where the wreckage orbit puts the wreck
(`vortex_finish_sheet.jpg`). On the same frame the shell reacts to `fight_state = result`:
`FightView.swift:65` presents the result sheet and `CareerFightView.swift:143` leaves for the Match
Report. The player never sees the knockout they scored.

**What it feels like, in one sentence:** a well-instrumented physics sandbox in which the machines
bump, the spinners flash white, and nothing in between lands with weight.

---

## (b) Weapon feel, family by family

### The shared problems first

These apply to every family, so each family below lists only what is its own.

**S1. Feedback is keyed to condition removed, not to the blow.** Severity is armour-adjusted
condition loss, the right number for the rules and the wrong one for the senses: an axe slamming a
steel lid takes little condition and is a huge event; a saw tick takes little and is tiny. The
event already carries `impulse` (0 for continuous damage, newton-seconds for a blow), the attacker
and the part. The fix is a **feel tier** computed in presentation from weapon, impulse, severity,
detach and struck material together (backlog rank 1).

**S2. Continuous damage is not rate-limited for presentation.** One event per part per tick
(`damage.gd:221-247`) is right for the ledger. The FX layer must coalesce: a cutting (burning,
chewing, boring) *state* per attacker-victim pair that drives a loop, a spark stream and a rumble,
plus a discrete *bite* event each time a threshold of accumulated condition is crossed (rank 2).

**S3. `weapon_fired` has no payload and the default sound is the flipper's.** `fx.gd:223-238`
matches `axe`, `ram` and `crusher` and plays `flipper_fire` for everything else. The spinners, saw,
twin saw and drill emit `weapon_fired` when they reach full spin (`horizontal_spinner.gd:175-179`
and the same lines in the others), so **a spinner reaching full speed plays a pneumatic valve, a
gas blast and a rigid tap**, again every time it re-spins past 50 %: 14 times in the saw's fight,
29 in the tesla arc's. The napalm cannon, tesla arc and shock prod play it on top of their own
sounds. Meanwhile the crusher and the ram never emit `weapon_fired`, so `crusher_clamp.wav` and
`ram_hit.wav` are never heard, and `axe_hit.wav` has no caller anywhere (bug B3).

**S4. Hit-stop, done without touching the simulation.** The tick must never change length and must
never change rate. Measured on this Mac with Godot 4.6.3:

- `Engine.time_scale` scales the physics delta (0.25 gives a 0.0042 s tick): not usable.
- `time_scale = k` **with** `physics_ticks_per_second = 60k` keeps the delta at exactly 1/60 s, and
  still produces **a different fight**: the same seed at 0.5x, 2x and 10x each ended differently
  from 1x (the horizontal spinner fight at 10x ended at 9.9 s; at 1x it runs the full 120 s).
  Something in the engine or Jolt reads the configured tick rate. Running the same fight at 1x but
  capped at 6 fps (ten ticks a frame) matches 1x exactly, so frame rate is not the problem; the
  tick rate setting is. **Not usable either.**
- **Holding the tick clock** works. The fight's own pause (`fight.gd:874-889`: tree paused, fight
  tick gated, proven by `pause_test.gd`) used as a hit-stop of 70 ms and of 140 ms on every hit of
  a 30 s drum fight gave **the identical event hash** to the fight with no stops (16 events, every
  time, part and severity to six decimals). Audio is not paused by a tree pause, so the impact rings
  on through the stop, which is exactly the effect wanted.

So hit-stop is a **hold**: the physics tick simply is not taken for N frames. Two conditions for the
build (rank 3):

- it must be its own path, not `_set_paused`: `_set_paused` disables the controls, and
  `controls.gd:536-541` then calls `_release_all()`, which would drop the player's thumb off the
  stick at every hit. It also sends `fight_state: paused` to the shell and shows PAUSED;
- slow motion is the same hold applied rhythmically (take one tick, hold three frames = 0.25x), with
  Godot's 3D physics interpolation switched on so it is smooth rather than stop-motion. Interpolation
  is render-side, but `determinism_test.gd` must prove it changes nothing before it ships. It also
  removes judder on a 120 Hz ProMotion screen, which today draws 60 Hz physics with no
  interpolation.

Tiers: scuff 0 ms, hit 40 ms, heavy 75 ms, part off 110 ms, finisher goes to slow motion. Never two
stops inside 250 ms, never in a replay seek, never while paused. Camera, particles and HUD keep
running through a stop (they are presentation); the bots do not move.

**S5. The camera answers too little and in one way only.** `ImpactShake` is a positional offset on
the Camera3D child, max 7 cm, trauma squared (`impact_shake.gd:47`). At the fight distance (3 to 6 m,
FOV 28 degrees) full trauma is about 3 % of the frame height; an axe hit at 0.30 gives trauma about
0.34, squared 0.12, which is under 1 cm, well under 1 % of the frame. Missing: a **directional kick**
away from the blow that springs back, a **rotational** component (0.5 to 1.5 degrees of roll and
pitch), a **FOV punch** on heavy hits (28 to 25 degrees in 60 ms, back in 250 ms), trauma by feel
tier, and an **airborne pull-out** (in `hspin_light_hit_sheet.jpg` the player's own machine, thrown
by its spinner's recoil, ends up under the top HUD). **Trap:** the stick is turned into a world
heading from the fight camera's basis (`fight.gd:1834-1850`, `cam.global_transform.basis`). A
rotational kick on the Camera3D would twist the player's steering for the length of the kick. The
heading must be read from the rig's yaw before any rotational shake ships (rank 5).

**S6. The spectacle hides the consequence.** At +300 ms after a full bite the flash quads, light pop,
detach core and the bolt-shower streaks are all additive and all peak together, and the frame goes
white over both machines. AAA practice is to frame the victim: flashes short (one or two frames),
bloom clamped, the bolt scatter delayed until the victim's reaction has read, and the brightest
element placed at the contact point rather than over the hull (rank 6).

**S7. Haptics are five fixed taps.** `HapticsPlayer.swift:62-81` maps six message kinds to
`UIImpactFeedbackGenerator` styles with no intensity; Core Haptics (`CHHapticEngine`) is not used.
No rising spin-up rumble, no buzz for a saw in a cut, no two-stage clunk for an axe, no heartbeat
for the KO count. A player on a pad gets **nothing**: `ControllerObserver.swift` never touches
`GCController.haptics`, and a DualSense's adaptive triggers are unused (rank 8).

### Spinners (horizontal bar, drum, full-body, vortex)

| | today | AAA target |
|---|---|---|
| anticipation | spin-up loop pitched 0.55 to 2.10 by readiness (good); a spin ring on the button; SPINNING UP line | the bar visibly blurs past 60 %, a whine layer that tops out with a short "ready" ring-over, a rumble haptic that grows with RPM |
| at full spin | **plays `flipper_fire` and a rigid tap** (S3) | a short lock-on chirp, no haptic |
| impact | heavy sound and tap, sparks, light pop, BIG HIT, crowd swell, then a white-out (S6) | a glancing bite (sparks along the tangent, ring, no stop) vs a full bite (75 ms stop, FOV punch, kick opposite the tangent, a metal shriek layer, a plate chunk flying); the victim stays visible |
| recoil | real physics reaction on the wielder | a counter-shake on the wielder and the weapon's pitch dropping as the bar loses RPM |
| decals | world-space scratch that does not follow the bot (bug B4) | gouges on the struck panel |

Balance note that defeats any feel fix: a spinner's hits are all near 1.0, so each one takes a
whole part. The vortex ended its fight in 26.4 s after seven hits. There is no "small spinner hit".
Owner decision D4.

### Flipper (and lifter)

| | today | AAA target |
|---|---|---|
| anticipation | none: the arm fires on the press | a 60 ms pressurise hiss and arm shiver from the press (presentation only, the ram fires on the same tick as today); gas pips on the button |
| connect vs whiff | **identical**: same sound, same tap (`flipper.gd:220-233`) | whiff: valve and gas only, a light tap. Connect: valve, a metallic clang of arm on hull, a 75 ms stop at the top of the stroke, the camera tilts up with the victim, a heavy haptic, a floor dust ring, a crowd "ooh" rising while it is airborne |
| the flight | nothing | a trail on the victim while above 0.3 m, the zoom eases out to keep it framed |
| the landing | `chassis_thud` from `MachineAudio` only (no haptic, no dust, no shake) | dust ring and a small shake by fall speed; landing inverted: FLIPPED, a cheer, a heavy tap |
| lifter | silent: no fire event, nothing on raise or carry | hydraulic whine while raising, creak under load, a set-down thunk |

The highest-leverage fix in the game. The flipper is the starter weapon and the move the brief says
the design lives or dies on. It needs a monotonic `throws()` counter on the flipper, read by
`WeaponFx` the way wave P reads `arcs()` and `shocks()`, not a change to the signal (quick win Q5).

### Hammers and axes

| | today | AAA target |
|---|---|---|
| anticipation | **none**: at rest the head is already cocked, the strike is 0.15 s | a visible 120 ms wind-back on the press (presentation only, or a real wind-up: owner D5) |
| swing | `axe_swing` whoosh (good) | whoosh pitched by head speed |
| impact | median severity 0.30: half the hits play `impact_light`; `axe_hit.wav` never plays | the axe's own hit layered over a material layer, a 75 ms stop, a downward camera kick, a floor dust ring under the victim |
| reset | the arm lifts back silently over `reset_s` | a hydraulic reset sound so you hear it is ready |

### Crushers

| | today | AAA target |
|---|---|---|
| anticipation | the jaw closes while held, in silence | a pump whine while closing |
| the bite | **silent**: 0 fire events, `crusher_clamp.wav` never plays; 3,156 invisible chew events feed the flood (S2) | the clamp sound on first grip, a creak loop while holding, a crunch every 0.4 s of chewing with a spark spit and a haptic pulse, PINNED |

### Wedges and rams

| | today | AAA target |
|---|---|---|
| anticipation | none; a ram has no button | an engine rev that rises with closing speed toward the opponent (the run-up is the anticipation) |
| impact | no event of its own; `ram_hit.wav` never plays | a ram tier keyed on **impulse**: the bonus kick is the ram's whole identity (`ram.gd` header), so the hit must sound and shake like momentum |
| wall slam | whatever the later wall contact gives, credited by the 2 s rule | wall slams credited to a ram or a flipper get the heavy tier and a dust burst off the wall |
| wedge under | nothing | a scrape-lift sound and a tap when the opponent's wheels leave the floor on your wedge |

### Flamethrower and heat (flamethrower, napalm cannon, overcharge core)

| | today | AAA target |
|---|---|---|
| anticipation | `flame_loop` on hold; napalm: muzzle smoke, flash and `napalm_launch`, **plus `flipper_fire`** (S3) | an igniter tick and a pilot light on the nozzle |
| burn | the cone; burn events feed the flood (S2); scorch decals only via the attacker-weapon fallback, because `source` never reaches `fight.gd` (bug B2) | heat haze, paint blistering on the panel, a crackle layer that thickens with exposure, the victim's lights flickering when the burn disrupts it |
| core cook | glow, smoke, a tightening warning tick (wave P, good) | fine once B2 lands |

### Arc and electric (tesla arc, shock prod)

Wave P's work here is the best in the game: a crackle that climbs with the charge, an electrode glow,
an `ArcBolt` to the actual struck part, flashes at both ends, sparks and a heavy tap; the prod's
bolt across its prongs; the stalled machine's arc walking round its hull. Missing: a stop on the
discharge (70 ms), a one-frame exposure lift, the victim's lights dying for the stall, and removing
the duplicate `flipper_fire` (S3; 29 times in one fight).

### Saws, drill, twin saw

| | today | AAA target |
|---|---|---|
| anticipation | spin-up loop, spin ring | the same, plus a blade blur |
| in the cut | spark streams from the rim (twin saw, drill: good) **plus** the flood (S2): shake pinned at maximum, `impact_light` retriggered every frame, 8 spark emitters restarted every frame, a decal a frame | a cutting state: the saw's pitch **drops under load** (the most recognisable saw sound there is), a screech layer, a continuous low haptic buzz, a bite every ~0.05 condition with a chunk and a spark spit; the panel glows at the cut |

### Wave P drives and armour

Hover skirt dust, walker footfalls, the reactive plate's shove and the vortex lift all have feedback
and it is well made. Two gaps: the footfalls and leg servo carry 74 to 83 % of their energy below
200 Hz, so a phone speaker plays nearly nothing (appendix B); and a reactive-plate hit sends two
haptic taps on one frame (B9).

---

## (c) Readability

### Opponent tells

The AI has rich intent (`opponent_ai.gd:384-392`: escape, pin, shove, retreat, respin, backoff,
close, ring) and exposes none of it. Proposed, all presentation, all read from a new read-only
`intent()` accessor on `OpponentAI`:

- **dart / close**: a rev spike on the drive whine and a headlight flare as it commits (the tell
  plays at the commitment; it does not delay it, so AI timing and determinism are untouched);
- **weapon armed**: spinners already sound it; a flipper hisses when it has you on its wedge
  (`opponent_on_wedge()` already exists);
- **pin / shove**: the scrub layer rises, PINNED sooner;
- **respin / retreat**: its weapon pitch audibly falls (it does) and, for Scrapyard to National
  only, a small RESPIN chip appears over it;
- **house bot**: its warning light turns red two seconds before it leaves its mark.

### Hazard tells

At `HEAD` only the Drop Zone warns (amber rim lamp, `drop_zone.gd:34`, 3 s); the Yard's spikes,
the Furnace's jets, the Crush's rams and the Grinder fire with no warning. **Wave A's hazards
engineer is building exactly this now**: a shared `HazardTelegraph`, four wind-up sounds
(`warn_spikes`, `warn_flame`, `warn_ram`, `warn_pit`) and a hazard shake. What this plan adds on top
(rank 11): the lead time must be at least what the AI gets (it reads the clocks 1.5 to 2.4 s ahead),
the hazard shake must share one trauma budget with the impact shake (two sources kicking
`ImpactShake` independently will stack to the clamp in a hazard clinch), and a hazard that hits
*the player* should get its own feel tier so it is distinguishable from an opponent's blow.

### Damage on the machines

| state | today | target |
|---|---|---|
| scratches | world-space decals that **do not follow the bot** (`damage_decals.gd:138-158`) | decals parented to the struck panel, or a per-part damage mask in the part shader (better: no decal limit) |
| heavy damage | nothing persists | per-part condition: below 50 % a smoke wisp from that corner, below 25 % intermittent sparks and a flickering light, below 10 % dark smoke and the machine sitting low on the damaged corner |
| loose panels | attached or gone | at 20 % a panel hangs by one corner (mesh only, no physics) and rattles |
| weapon jammed | JAMMED on the button, WEAPON DEAD line | the jammed weapon smokes and stops with a clunk |
| core low | nothing | a pulsing red light under the hull, and a heartbeat haptic on your own |

### HUD clarity

The broadcast HUD is clean and legible. Gaps: one condition bar per machine hides **which part** is
failing, and the brief's damage model is per part, so the player cannot aim for a weak face. A
five-pip strip under each name (wheels, weapon, armour, core) turns damage into tactics. The bars
need a hit-confirm: flash and drop with a lagging chunk, so a hit reads even when the camera is
busy. The height readout flips to "Your box: high" while your machine is airborne or upside down,
which reads as noise; freeze it while airborne.

### Prompts

The coach callouts and the "drive to stop the count" pulse are good. Missing: a FLIP NOW pulse on
the button when the opponent is on your wedge, and a pulse on the self-right button when you are
inverted (it already relabels).

### The endgame

Already the strongest moment. Add: a 1 s shake as the arena escalates, and the last ten seconds of
the round (clock turns red and ticks, the crowd rises).

### The knockout and the win

The biggest readability hole after the flipper. Target (rank 4):

1. On the deciding tick the rules finish as today: the result is built, **not yet sent**.
2. The simulation keeps running for the presentation with scoring off: `bot.freeze()` is split
   into "stop scoring and stop driving" (what the rules need) and "stop moving" (what nobody
   needs). The result is already built, so the extra ticks cannot change it, and a replay ends on
   the same tick.
3. Slow motion at 0.25 for 1.2 s (the S4 hold) on the loser, camera pushed in; a ring-out follows
   the machine over the wall; a core kill gets a small blast and a smoke column.
4. Real time again: the banner slams **above or below** the wreck, never across it; crowd roar; the
   winner gets a spotlight and a short victory spin-up; a win sting; a success haptic pattern.
5. After about 3.5 s, or on a tap, `fight_result` goes over the bridge and the shell takes over.

The shell change is small: present the sheet on `fight_result` arrival rather than on
`fight_state = result`. Replays and the async ladder are unaffected because the result is built
before the beat.

### The match intro

Today it is a countdown. Target (rank 14, owner decision D2):

- a 4 s entrance: the camera starts on the opponent (name and roboteer as a lower third, its
  weapon spinning up once), moves to the player's machine with the same, then pulls to the fight
  framing for 3, 2, 1. Wave A's venue kit already offers the stage for it:
  `VenueKit.play_entrance(side)` (a 3.5 s light sweep, gate chaser and pyro),
  `intro_camera_marks()` for the flyover poses and `skip_entrance()`;
- the crowd swells on each name and roars on FIGHT, with a short sting;
- skippable with a tap, skipped by itself on a retry of the same match.

---

## (d) Controls and camera feel

**Touch stick.** Floating origin at the first touch in the left 45 % of the screen, 60 pt throw,
linear, **no dead zone in the controls** (`controls.gd:651-662`); the drive ignores throttle below
0.05 (`drive_base.gd:269`), which is 3 pt. A resting thumb's micro-movement turns the machine
toward a random heading at a crawl, and there is no fine band for the creep the brief asks for
("creeping in to get a wedge under someone is a distinct skill"). Target (quick win Q8):

- a 6 pt radial dead zone and a response curve (throttle `x^1.6`, or smoothstep over the first
  40 % then linear), so the inner third of the throw is a creep;
- a **following origin**: past the throw, the origin follows the thumb, so the stick never
  saturates in a direction the thumb has left;
- steering is screen relative and the fight camera does not yaw on its own, which is right. One
  trap: after a manual orbit the camera eases back over `CAM_EASE_BACK_S` while the thumb is still
  held, so the machine's heading turns under a still thumb. Hold the ease-back while the stick is
  live.

**Pad.** A 0.18 radial dead zone with a linear rescale (`controls.gd:874-880`), fire on A or the
right trigger, secondary on B or the left trigger, the right stick orbits. Add the same curve, an
option for **analogue** trigger spin (a partial trigger holds a partial spin target), and rumble
(S7). START pauses (good).

**Aim assist.** None. A light **steering magnetism** when the opponent is inside the weapon's engage
cone at close range (a 10 to 15 degree bias of the heading toward the target, fading with stick
deflection) would make the flipper and the drum far more forgiving on glass. It changes the input
the simulation receives, so it belongs in the input sampler before the record is written
(deterministic, replay safe). Owner decision D3.

**Camera tracking.** Wave G's tracking is careful: look-ahead toward the opponent, a leash that keeps
the player in the middle 60 %, a zoom that fits both. Missing: a small lead in the direction of
travel at speed, the impact reactions in S5, and a pull-out while either machine is airborne. Worth
an owner look: the default framing is high and far, and the machines are small (about a tenth of
the frame height in every capture); a 10 to 15 % closer default would put more of every effect on
screen.

---

## (e) AI: personality and exploitable mistakes

The AI is solid engineering: context steering with danger masking, five skill tiers by five
temperaments, reaction delay, aim error and hesitation as the only weaknesses ("no tier may ever
look stupid", the owner's rule), all deterministic. As a *character* it reads as one careful driver
at different speeds.

- **Personality is statistical, not visible.** A brawler and a technician differ in thresholds;
  nothing the player sees says "this one is a bully". Give each temperament one signature behaviour
  visible in the first 20 seconds: the showboat spins up and does a victory circle after a hit; the
  bully drives at you and stops short, twice, before committing; the technician circles the other
  way; the opportunist hangs back and only pounces on an inverted machine.
- **Mistakes are hidden inside smoothing.** Aim error and reaction delay make it slower and wider;
  they never produce a *mistake* the player can punish. AAA enemies commit to an attack and pay a
  recovery window. Proposed: after a committed dart that misses, the AI overshoots 0.5 to 1 m and
  takes 0.4 to 0.8 s (by tier) to turn round, rear exposed. A spinner that bites backs off to
  re-spin with its pitch falling (it does, make it audible). A flipper that fires dry has a 0.7 s
  cooldown the player should be able to hear (Q5's dry-fire sound).
- **Tells** (section c) turn all of this into something learnable.

Keep `ai_test.gd`'s acceptance tests; add one: a scripted "punisher" that attacks only inside the
recovery window beats Regional more often than the plain novice does.

---

## (f) Audio

### What exists

66 WAV files (55 sounds with variants), 44.1 kHz 16-bit, mono except the crowd bed, all
**synthesised** by `scripts/gen-sounds.py` from physical models (modal banks, waveguides,
circular-convolution reverb). Every file is normalised to -3 dBFS peak and balanced by a per-sound
dB table (`AudioMix.LEVELS`). Four buses (Music, SFX with a small room reverb, Ambience, UI) into a
limiter, polyphony caps with oldest-voice stealing, a no-repeat variant picker, positional 3D
voices, and the crowd ducked under the bell, horn and KO tick. This is a better audio *system* than
most mobile games ship. What it lacks is content and layering.

Measured (appendix B): the heavy impacts sit at a spectral centroid of 380 to 420 Hz with 0.44 to
0.56 s tails; the light impacts at 660 to 810 Hz, 0.13 to 0.15 s; three variants each and one
material. Six files carry more than 60 % of their energy below 200 Hz and are close to silent on a
phone speaker: the footfalls (80 and 83 %), the leg servo (74 %), the superseded `motor_loop` (71 %),
the fire patch (64 %) and the endgame drone (63 %, after G6 already raised it once).

### Against a AAA list

| AAA element | here | status |
|---|---|---|
| layered impacts: transient + body + material + tail + debris | one file per hit, three variants, one material | **missing layers.** A four-layer impact: transient (crack), body by weapon (bar, drum, axe head, ram, arm), **material** by the struck face (steel ring, titanium ping, HDPE thock, polycarbonate crack), debris tail (bolts, rattle). `AudioMix` can play four keys at once; the choice logic is new (rank 9) |
| weapon loops, pitch by RPM | spinners, saws, drill, vortex, arc crackle, flame | **good.** Add load: pitch drops in a cut and after a bite |
| spin-up with a "ready" moment | readiness drives pitch; at full spin a flipper blast plays (B3) | fix B3, add a lock-on chirp |
| per-drive movement | whine, roll, skid, scrape, landing, tracks, omni, hover, legs | **good** (wave F) |
| hazard sounds | grinder, disc, flame jet, spikes, pit, crush ram | good; **tells** missing (c) |
| reactive crowd | bed, two swells, a roar; reacts to BIG HIT, FLIPPED, the KO count, the endgame | **thin.** Add: "ooh" on a near miss and on airtime, a groan when the player is hit hard, a rising count-along under the KO count, boos for a house bot attack, a cheer on a win, a flat murmur for a judges decision. Intensity should follow the fight: one slow *excitement* value driven by hits, airtime and closeness, fed to the mixer and to wave A's `VenueKit.set_excitement()` so the crowd you see and the crowd you hear move together |
| announcer or stings | none; the ticker is text | **missing.** Stings on FIGHT, big hit, flip, KO and win are small and high value. A voiced announcer is the biggest single "TV broadcast" lift and the biggest licence and localisation cost (D6) |
| adaptive music | a 4 s drone in the endgame | **missing.** Minimum: intro sting, a low open-phase bed, the endgame layer on top, KO, win and loss stings; horizontal re-sequencing between intensity levels driven by the excitement value |
| UI sounds | countdown tick, bell | the countdown and FIGHT want a broadcast sting; ENDGAME and the result slam want a whoosh-hit |
| mix and ducking | limiter; crowd ducks under three cues | add a **duck of everything under a heavy hit** (3 dB, 150 ms), a low-pass on the whole mix during hit-stop and slow motion, a music duck under the KO count |
| per-arena ambience | one crowd bed everywhere | a room-tone layer per arena (furnace roar, grinder hum, crush hydraulics) and a crowd size per Series (Scrapyard: a few dozen in a shed; Masters: a stadium) |
| haptics matched to audio | five fixed taps | Core Haptics patterns authored beside each impact (S7) |

### Synthesised versus recorded, and what to source

The generator's own notes say "nobody should ship them if a licensed source is available"
(`docs/audio-notes.md` §6), and the drop-in table there (names, lengths, loop rules) is the right
spec. By category:

| category | keep synthesised | source recorded | why |
|---|---|---|---|
| UI ticks, countdown, KO tick, cook warning | yes | | abstract, must be exact |
| drive whine, gear, servo loops | yes, as a layer | a real brushed motor under it | the models track pitch well |
| metal impacts and material layers | | **yes** | the ear knows real metal; synthesis shows most here |
| debris, bolts, rattles, panels off | | **yes** | |
| saw, grinder, drill | | **yes** | the notes call these the weakest; friction is hard to model |
| flame, napalm, fire patch | | **yes** | |
| crowd beds, swells, cheers, boos | | **yes** | crowds are hard to synthesise; the no-words rule still applies |
| endgame horn, bell | either | a real air horn and ring bell | cheap to find |
| music and stings | | **commission or license** | |
| announcer | | **record** (D6) | |

**Where to source, with the licence checks** (terms must be re-read on the day; every file's source
and licence goes in an `Arena/audio/LICENCES.md` beside it):

- **Sonniss GameAudioGDC bundles**: large, professionally recorded, royalty free for commercial
  games without attribution; the raw files may not be redistributed, which a compiled app does not
  do. Strong on impacts, metal, machinery, fire and crowds.
- **Freesound, CC0 only**: public domain dedication, no attribution. Quality varies; every file must
  be checked for CC0 (not CC BY, not CC BY-NC).
- **BBC Sound Effects**: the free licence covers personal, educational and research use, **not
  commercial**. Not usable in the game without a paid licence.
- **Paid libraries** (Boom Library, Soundly, A Sound Effect): the reliable route for crowds and
  metal if the free sources fall short; one-off per-library licences.
- **Generated audio**: usable for variants and fills if the tool's terms grant commercial use; not
  for the signature sounds.

A sourcing agent can build a candidate board (file, source, licence, measured centroid and
low-frequency share) for the owner to audition, then drop the picks in under the existing names;
a like-for-like swap needs no code change.

---

## (g) Ranked backlog

Impact is player impact (High, Medium, Low). Cost is agent-days. "Owner" says whether a decision is
needed first. Ranked by impact over cost, with dependencies respected.

### Quick wins (under half a day each)

| # | item | impact | cost | files | owner |
|---|---|---|---|---|---|
| Q1 | Stop spinners, saws, drill, napalm, arc and prod playing `flipper_fire` and the rigid tap: route `on_weapon_fired` by weapon id; the full-spin announce gets a chirp or nothing (B3) | High | 0.25 | `Arena/fx/fx.gd` | no |
| Q2 | First cut of S2: for `impulse == 0` events below a bite threshold, skip shake, hit sound, haptic, decal and commentary, and accumulate per pair | High | 0.4 | `Arena/fx/fx.gd`, `Arena/fight/fight.gd` (`_mark_damage`, `_commentary_damage`) | no |
| Q3 | Forward `source` in the damage event (B2): one line | Medium | 0.1 | `Arena/bot/bot.gd:997-1006` | no |
| Q4 | Play the unused sounds: `axe_hit` on an axe hit, `crusher_clamp` on first grip, `ram_hit` on a ram blow (read the attacker's weapon in `on_damage_event`) | Medium | 0.3 | `Arena/fx/fx.gd` | no |
| Q5 | Flipper connect vs dry fire: a read-only `throws()` counter, and `WeaponFx` plays a clang, a heavy tap and a dust ring on a connect, valve only on a whiff (B6) | High | 0.5 | `Arena/bot/weapons/flipper.gd` (counter only), `Arena/fx/weapon_fx.gd` | no |
| Q6 | Hold the result sheet and the Match Report 3 s after `result` (shell side), so the banner, bell and orbit are seen before rank 4 lands (B8) | High | 0.25 | `Roboteer/FightView.swift`, `Roboteer/CareerFightView.swift` | no |
| Q7 | Landing feedback: a haptic, a dust ring and a small shake on `MachineAudio`'s landing thud, by fall speed | Medium | 0.3 | `Arena/fx/machine_audio.gd`, `Arena/fx/fx.gd` | no |
| Q8 | Touch stick dead zone and response curve; hold the camera ease-back while the stick is live | Medium | 0.3 | `Arena/ui/controls.gd`, `Arena/ui/camera_rig.gd` | no |
| Q9 | Move the banner off the wreck (above or below the orbit's subject) | Medium | 0.15 | `Arena/ui/hud.gd` | no |
| Q10 | Clamp the white-out: cap simultaneous flash quads at a hit, shorten the flash to two frames, and delay the bolt scatter until 150 ms after a part-off flash (S6) | High | 0.4 | `Arena/fx/impact_particles.gd`, `Arena/fx/flash_pool.gd`, `Arena/fx/bolt_shower.gd` | no |
| Q11 | Retune the phone-quiet files (footfalls, leg servo, fire patch) upward, the method F2 used for `ram_hit` | Low | 0.25 | `scripts/gen-sounds.py`, `Arena/audio/` | no |

### The main list

| rank | item | impact | cost | files | owner |
|---|---|---|---|---|---|
| 1 | **Feel tiers.** A presentation classifier (weapon kind x impulse x severity x part off x struck material) giving five tiers (scuff, hit, heavy, smash, finisher) that drive sound, sparks, shake, haptic, hit-stop and crowd; tuned so a clean axe or flipper connect is "heavy" | High | 1.5 | `Arena/fx/fx.gd`, new `Arena/fx/feel_tiers.gd`, `Arena/fx/impact_particles.gd`, `Arena/fight/commentary.gd` | no |
| 2 | **Continuous-damage states** (full S2): cutting, burning, chewing and boring per pair, with loops, spark streams, a rumble and periodic bites | High | 1.0 | `Arena/fx/fx.gd`, `Arena/fx/weapon_fx.gd`, `Arena/fx/audio_mix.gd` | no |
| 3 | **Hit-stop and slow motion as a tick hold** (S4), its own path beside `_set_paused` that keeps the controls live, 3D physics interpolation on, and a determinism test that runs a fight with random holds and compares the result JSON byte for byte | High | 1.5 | `Arena/fight/fight.gd` (a small presentation-clock section), `Arena/project.godot`, new `Arena/tests/hitstop_test.gd` | yes (D1) |
| 4 | **The finish beat**: keep simulating after the result with scoring off, slow-motion follow, the winner moment, `fight_result` delayed, the shell presents on arrival (B7, B8) | High | 1.5 | `Arena/fight/fight.gd` (`_finish`), `Arena/bot/bot.gd` (`freeze` split), `Arena/ui/camera_rig.gd`, `Arena/ui/hud.gd`, `Roboteer/FightView.swift`, `Roboteer/CareerFightView.swift` | yes (D8) |
| 5 | **Camera impact grammar** (S5): directional and rotational kick, FOV punch, trauma by tier, airborne pull-out; move the stick-to-world mapping onto the rig's yaw first | High | 1.0 | `Arena/fx/impact_shake.gd`, `Arena/ui/camera_rig.gd`, `Arena/fight/fight.gd:1834-1850` | no |
| 6 | **Flipper and lifter feel** beyond Q5: pressurise hiss, arm clang, flight trail, landing, lifter hydraulics; plus S6's "frame the victim" pass on every big hit | High | 1.0 | `Arena/fx/weapon_fx.gd`, `Arena/fx/bolt_shower.gd`, `scripts/gen-sounds.py` or sourced audio | no |
| 7 | **Damage on the machines**: panel-parented decals (B4), per-part smoke, sparks and hanging panels by condition, jammed-weapon smoke | High | 2.0 | `Arena/render/damage_decals.gd`, `Arena/bot/part_visuals.gd`, new `Arena/fx/damage_state_fx.gd` | no |
| 8 | **Haptics v2** (S7): Core Haptics patterns per tier and per weapon state (spin-up rumble, cutting buzz, KO heartbeat) with intensity in the message; controller rumble through `GCController.haptics`; DualSense trigger resistance for the spinner | High | 2.0 | `Roboteer/HapticsPlayer.swift`, `Roboteer/ControllerObserver.swift`, `Arena/fx/haptics.gd`, `docs/bridge-spec.md` (message gains `intensity`) | no |
| 9 | **Impact audio layers**: transient + weapon body + material + debris tail, with recorded metal and debris | High | 1.5 build + sourcing | `Arena/fx/audio_mix.gd`, `Arena/audio/` | yes (D6) |
| 10 | **AI tells and readable recovery windows**; temperament signatures | High | 2.0 | `Arena/ai/opponent_ai.gd` (read-only `intent()`, recovery windows), new `Arena/fx/tell_fx.gd`, `Arena/tests/ai_test.gd` | yes (D7) |
| 11 | **Hazard tells, the combat side**: wave A is building the telegraphs; this item is the parity check against the AI's lead time, one shared trauma budget for hazard and impact shake, and a "hit by the arena" feel tier | Medium | 0.5 | `Arena/fx/fx.gd`, `Arena/fx/impact_shake.gd` (after wave A lands) | no |
| 12 | **Music and stings** with an excitement value that drives music, the crowd and wave A's venue (`VenueKit.set_excitement`) | High | 1.5 build + sourcing | `Arena/fx/audio_mix.gd`, new `Arena/fx/excitement.gd` | yes (D6) |
| 13 | **Crowd v2**: excitement-driven intensity, ooh, groan, boo and cheer sets, crowd size per Series, room tone per arena | Medium | 1.0 + sourcing | `Arena/fx/audio_mix.gd`, `Arena/audio/` | no |
| 14 | **Match intro**: entrance, names, crowd, sting, skippable, on wave A's `VenueKit.play_entrance` and `intro_camera_marks` | Medium | 1.25 | `Arena/fight/fight.gd` (countdown section), `Arena/ui/camera_rig.gd`, `Arena/ui/hud.gd` | yes (D2) |
| 15 | **HUD per-part strip and hit-confirm on the bars** (mockup first, the owner's standing rule) | Medium | 1.0 | `Arena/ui/hud.gd` | no |
| 16 | **Aim assist** (steering magnetism) | Medium | 0.75 | `Arena/fight/fight.gd` (input sampler), `Arena/tests/determinism_test.gd` | yes (D3) |
| 17 | **Weapon anticipation visuals**: spinner blur disc, axe wind-back | Medium | 1.0 | `Arena/bot/part_anim.gd`, `Arena/bot/part_visuals.gd` | yes if the wind-up is real (D5) |
| 18 | **Camera**: travel lead, a closer default framing, pad analogue-trigger option, following touch origin | Low to Medium | 0.75 | `Arena/ui/camera_rig.gd`, `Arena/ui/controls.gd`, `Arena/fight/fight_types.gd` | yes for the framing (D9) |
| 19 | **Announcer** | High if yes | 3.0 + recording | new `Arena/fx/announcer.gd`, `Arena/audio/vo/` | yes (D6) |
| 20 | **Spinner hit sizing** (balance, not feel, but it defeats every feel fix for that family) | High | 0.5 to 1 | `Arena/bot/weapons/*spinner*.gd`, `Shared/parts.json` | yes (D4) |

About **8 agent-days** buys all the quick wins plus ranks 1 to 6: the difference between "sandbox"
and "hits land". Ranks 7 to 13 are another **12 to 14 days** plus sourcing.

**Suggested waves.** FEEL-1, parallel on disjoint files: the quick wins first, then ranks 1, 2 and 5
on one agent (they share `fx.gd`; wait for wave A's `fx.gd` hazard section to be committed), rank 3 on a second (the `fight.gd` presentation clock and its
test), rank 4 on a third (`_finish`, `bot.freeze`, the shell), rank 6 on a fourth (`weapon_fx.gd`,
`bolt_shower.gd`). The owner plays. FEEL-2: ranks 7, 8, 10 and 11. AUDIO: ranks 9, 12 and 13 with a
sourcing agent in front.

---

## (h) Decisions needed from the owner

- **D1. Hit-stop strength.** Subtle (heavy hits and up only, 50 to 80 ms) **or** Ratchet-strong
  (every hit from "hit" up, to 120 ms, plus slow motion on every part coming off)?
- **D2. The match intro.** A 4 s skippable entrance on every fight **or** only on Series finals and
  rival fights, with the plain countdown elsewhere?
- **D3. Aim assist.** Light steering magnetism on touch (off on a pad) **or** none, driving stays
  fully manual?
- **D4. Spinner hits.** Size a spinner's bite by spin and angle so a glancing hit is small and it
  takes two or three clean bites to remove a part **or** keep every spinner hit a whole part as the
  spinner's identity?
- **D5. Axe wind-up.** A real 0.1 s wind-up in the weapon (a balance change the AI must learn) **or**
  presentation only (the model tilts back while the hinge fires on the same tick)?
- **D6. Audio spend and voice.** Free sources only (Sonniss GDC bundles, Freesound CC0) **or** a paid
  library budget for crowds and metal? And a voiced announcer **or** stings and the text ticker
  only?
- **D7. AI recovery windows.** Every tier gets a readable, punishable recovery after a missed commit
  (Masters shortest) **or** only Scrapyard to National, with Championship and Masters kept clean?
- **D8. The finish.** A fixed ~3.5 s beat before the result screen **or** hold until the player
  taps?
- **D9. Default framing.** Bring the fight camera 10 to 15 % closer so the machines and their
  effects are bigger **or** keep today's wider view of the floor?

---

## Bugs found while reading

| id | where | what | effect |
|---|---|---|---|
| B1 | `Arena/fight/fight.gd:773-783` (`_set_replay_speed`), `:785-789`, `:803-832` (seek) | `Engine.time_scale` scales the physics delta in Godot 4.6 (measured: 0.0042 s at 0.25, **0.4 s** at the seek's 24). And the obvious fix, raising `physics_ticks_per_second` to keep the delta at 1/60, still changes the fight (measured at 0.5x, 2x and 10x). The comment at `:741-743` is wrong for every speed but 1x | slow-motion replays and every seek re-simulate a **different fight**; at 0.4 s steps a seek will tunnel. Fix with the S4 hold (one tick, then hold frames), never with the clock or the tick rate |
| B2 | `Arena/bot/bot.gd:997-1006` (`_flush_damage`) | the damage event is emitted without `source`, although `damage.gd:175` and `:240` now record it (commit `c69b84f` fixed half the path). Measured: none of the events in 16 fights carried `source` | burns, heat and the overcharge cook are drawn as scratches unless the attacker's weapon kind is `flame`; arena flame jets never scorch a machine |
| B3 | `Arena/fx/fx.gd:223-238`, with `emit_weapon_fired` in `horizontal_spinner.gd:177`, `vertical_spinner.gd:174`, `full_body_spinner.gd:202`, `saw.gd:189`, `twin_saw.gd:189`, `drill_lance.gd:174`, `napalm_cannon.gd:376`, `tesla_arc.gd:169`, `shock_prod.gd:161` | every weapon kind but axe, ram and crusher falls to the default branch: `flipper_fire` plus a `flip` haptic | spinners and saws "fire a flipper" every time they reach full spin; napalm, arc and prod play it over their own sounds. Also: crusher and ram never emit `weapon_fired`, so `crusher_clamp` and `ram_hit` never play, and `axe_hit` has no caller |
| B4 | `Arena/render/damage_decals.gd:138-158` | scratches and scorches are world-space `Decal` nodes, never parented to the bot | a machine drives out from under its own damage; the decal box later paints whatever passes through it |
| B5 | `Arena/fx/fx.gd:193-206`, `Arena/fight/fight.gd:3054-3060` | no presentation rate limit on continuous damage (saw 146 events in one second, drill 202, up to five in a tick). Each kicks the shake (0.10 trauma minimum, so trauma saturates at 1.0), restarts one of 8 spark emitters, plays `impact_light` (cap 4, oldest stolen every frame), asks for a haptic and places a decal (the 48-decal pool recycles in under a second) | while cutting, chewing or burning the camera shakes at maximum, the hit sound machine-guns, sparks flicker, and the frame cost climbs |
| B6 | `Arena/bot/weapons/flipper.gd:220-233` with `Arena/fx/fx.gd:237-238` | `weapon_fired` fires on a dry fire and a real throw alike | a whiff and a throw feel identical |
| B7 | `Arena/bot/bot.gd:1331-1343` via `Arena/fight/fight.gd:3019-3022` | `freeze()` zeroes every velocity and makes every part static at the finish | a machine thrown over the wall stops dead in mid-air |
| B8 | `Roboteer/FightView.swift:64-65`, `Roboteer/CareerFightView.swift:143` | the result sheet / Match Report is presented on the frame `fight_state = result` arrives | the in-arena banner, bell and wreckage orbit are covered at once |
| B9 | `Arena/fx/weapon_fx.gd:392` with `Arena/fx/fx.gd:204` | a reactive-plate hit sends `impact_heavy` from `WeaponFx` and `impact_*` from `FightFx` on the same frame | two haptic taps for one blow (minor) |
| B10 | `Arena/ui/controls.gd:159-172` | `WEAPON_HOLDS["flame"] = true` and the word FIRE also apply to the napalm cannon (kind `flame`), which fires on the edge | the coach tells a napalm player to hold (minor) |
| B11 | `Arena/fight/fight.gd:3255-3259` (`_is_burn`) | the comment says a damage event carries no source; after B2 hazard flames and heat must be classified here too | stale comment; correct once B2 lands |
| B12 | `Arena/ui/hud.gd` result banner placement with `Arena/ui/camera_rig.gd:774-790` | the result banner is centred on the frame and the wreckage orbit centres the wreck | the banner covers the wreck it is framing (`vortex_finish_sheet.jpg`) |

Worth knowing, not bugs: `Arena/tests/_rumble_probe.gd:31` sets `Engine.time_scale` with B1's
caveat, so its numbers are not the fights a player gets; and the endgame's presentation calls
(`fight.gd:1627-1645`) run inside the physics tick, so a seek plays the horn and the haptic while
the picture is off.

---

## Appendix A: the measurement harness

`feel_harness.gd` lives in the session scratchpad, not the repo (this round writes only this file
and its images). About 200 lines: it instantiates `res://fight/fight.tscn`, calls `start_fight` with
the Stage 3 fixture altered (player weapon and chassis chosen, opponent a box 4WD flipper, both on
the `normal` AI, seed 424242, the Yard, 180 s rules), connects to both bots' `damage_event` and
`weapon_fired`, and prints the counts, a severity summary, peak event rates and an MD5 of every
event (time to 5 decimals, victim, part, severity to 6 decimals). Options: `--hitstop=ms` holds the
tick through the fight's own pause after every hit; `--speed=k` sets `time_scale = k` with
`physics_ticks_per_second = 60k` (the experiment in S4 and B1); `--maxfps` caps the frame rate;
`--shots=dir` saves frames around big hits, flipper fires and the result.

Determinism results (same seed, same fight):

| run | outcome |
|---|---|
| horizontal spinner, 1x, twice | identical (12 events, 3 hits, 1 part off) |
| same, 1x capped at 6 fps (ten ticks a frame) | identical to 1x |
| same, 10x / 2x / 0.5x by tick rate with delta held at 1/60 | **three different fights** (ended 9.9 s; 4 events; 5 events) |
| drum, 30 s, hit-stop 0 / 70 / 140 ms through the pause path | **identical event hash** `7eecdbf5...` (16 events) |

Worth adding to `Arena/tests/` as `_feel_sweep.gd` (skipped by the suite, like `_feel_probe.gd`) in
the first feel wave: every item above should move these numbers, and the hash comparison is a
ready-made hit-stop regression test.

## Appendix B: every sound file, measured

Peak is -3 dBFS on every file by design. `<200 Hz` is the share of energy below 200 Hz; the centroid
is the spectral centroid; attack is the time to 90 % of peak. **phone-quiet** marks files with more
than 60 % of their energy below 200 Hz.

| file | length s | RMS dBFS | <200 Hz % | centroid Hz | attack ms |
|---|---|---|---|---|---|
| `adaptive_track_loop` | 1.00 | -20.2 | 5 | 955 | 501 |
| `arc_crackle_loop` | 1.50 | -19.0 | 33 | 2698 | 557 |
| `arc_discharge_1` | 0.55 | -24.7 | 21 | 3046 | 0 |
| `arc_discharge_2` | 0.55 | -23.3 | 27 | 3454 | 2 |
| `axe_hit` | 0.52 | -20.5 | 56 | 256 | 1 |
| `axe_swing` | 0.34 | -16.5 | 0 | 1208 | 170 |
| `bell` | 2.60 | -22.8 | 0 | 641 | 12 |
| `bolt_collect` | 0.05 | -18.4 | 0 | 742 | 1 |
| `chassis_thud_1` | 0.42 | -23.4 | 8 | 912 | 30 |
| `chassis_thud_2` | 0.48 | -18.2 | 53 | 594 | 34 |
| `chassis_thud_3` | 0.54 | -19.6 | 3 | 637 | 13 |
| `cook_warning` | 0.20 | -22.3 | 0 | 3653 | 1 |
| `countdown_tick` | 0.09 | -21.2 | 0 | 1017 | 1 |
| `crowd_ambience_loop` | 8.00 | -17.1 | 0 | 1343 | 527 |
| `crowd_roar` | 3.40 | -14.7 | 0 | 2577 | 412 |
| `crowd_swell_1` | 2.20 | -15.0 | 0 | 2417 | 178 |
| `crowd_swell_2` | 2.60 | -15.5 | 0 | 2467 | 235 |
| `crusher_clamp` | 0.90 | -22.9 | 43 | 374 | 701 |
| `disc_spin_loop` | 1.00 | -13.4 | 9 | 518 | 289 |
| `drill_grind_loop` | 1.20 | -16.2 | 25 | 2337 | 28 |
| `drive_whine_loop` | 1.00 | -11.4 | 2 | 642 | 2 |
| `endgame_drone_loop` **phone-quiet** | 4.00 | -11.6 | 63 | 178 | 3536 |
| `endgame_horn` | 1.80 | -21.2 | 9 | 782 | 18 |
| `fire_patch_loop` **phone-quiet** | 2.00 | -12.0 | 64 | 303 | 42 |
| `flame_jet` | 0.70 | -17.9 | 9 | 2439 | 0 |
| `flame_loop` | 2.00 | -7.9 | 50 | 457 | 7 |
| `flipper_fire` | 0.40 | -20.4 | 47 | 3066 | 123 |
| `footfall_1` **phone-quiet** | 0.34 | -19.5 | 80 | 202 | 2 |
| `footfall_2` **phone-quiet** | 0.34 | -19.6 | 83 | 273 | 2 |
| `grinder_loop` | 1.50 | -14.5 | 5 | 805 | 329 |
| `hover_fan_loop` | 1.00 | -13.4 | 52 | 661 | 17 |
| `hover_skirt_loop` | 1.00 | -15.2 | 39 | 2304 | 186 |
| `impact_heavy_1` | 0.44 | -15.8 | 14 | 421 | 1 |
| `impact_heavy_2` | 0.50 | -16.8 | 21 | 405 | 1 |
| `impact_heavy_3` | 0.56 | -18.7 | 44 | 380 | 3 |
| `impact_light_1` | 0.13 | -20.1 | 0 | 658 | 3 |
| `impact_light_2` | 0.14 | -20.8 | 0 | 808 | 3 |
| `impact_light_3` | 0.15 | -20.6 | 0 | 682 | 0 |
| `ko_tick` | 0.14 | -19.0 | 21 | 285 | 2 |
| `leg_servo_loop` **phone-quiet** | 1.00 | -19.1 | 74 | 192 | 929 |
| `motor_loop` **phone-quiet** | 1.00 | -11.5 | 71 | 248 | 103 |
| `napalm_launch` | 0.45 | -21.6 | 38 | 428 | 5 |
| `panel_off` | 0.72 | -20.6 | 6 | 544 | 4 |
| `pit_open` | 1.10 | -16.7 | 6 | 700 | 212 |
| `prod_zap_1` | 0.32 | -24.8 | 12 | 2351 | 25 |
| `prod_zap_2` | 0.32 | -23.4 | 1 | 2935 | 7 |
| `ram_crush` | 0.85 | -19.0 | 30 | 365 | 2 |
| `ram_hit` | 0.46 | -16.6 | 10 | 346 | 1 |
| `reactive_clang_1` | 0.75 | -21.8 | 58 | 230 | 0 |
| `reactive_clang_2` | 0.75 | -22.5 | 16 | 448 | 5 |
| `roll_omni_loop` | 1.00 | -18.3 | 2 | 1288 | 842 |
| `roll_wheel_loop` | 1.00 | -15.7 | 1 | 1316 | 293 |
| `saw_cut_loop` | 1.20 | -15.8 | 12 | 2961 | 501 |
| `scrape_loop` | 1.00 | -16.0 | 0 | 1677 | 122 |
| `skid_loop` | 1.00 | -17.7 | 0 | 1775 | 0 |
| `spikes` | 0.44 | -17.4 | 4 | 495 | 88 |
| `spin_up_loop` | 1.00 | -9.1 | 16 | 460 | 24 |
| `track_clatter_loop` | 1.20 | -16.1 | 1 | 1180 | 444 |
| `twin_saw_loop` | 1.20 | -15.1 | 10 | 3240 | 161 |
| `vortex_spin_loop` | 1.00 | -12.3 | 25 | 449 | 293 |
| `vortex_throw` | 0.60 | -21.4 | 8 | 535 | 4 |
| `warn_flame` | 1.20 | -24.8 | 0 | 5078 | 225 |
| `warn_pit` | 1.20 | -11.8 | 0 | 682 | 399 |
| `warn_ram` | 1.20 | -10.5 | 0 | 513 | 1081 |
| `warn_spikes` | 1.20 | -21.1 | 0 | 1778 | 966 |
| `wheel_off` | 0.62 | -25.2 | 18 | 363 | 1 |

## Appendix C: frames

All from windowed desktop runs of the harness at 1206 x 556 (the phone's point size), fight camera,
nothing edited. Each sheet is three frames top to bottom.

| file | what it shows |
|---|---|
| `img/combat/hspin_full_bite_sheet.jpg` | a full horizontal-spinner bite (severity 1.0) at the hit, +90 ms and +300 ms: by +300 ms the frame is white over both machines (S6) |
| `img/combat/hspin_detach_sheet.jpg` | a bite that takes a part off: the bolt-shower streaks and flashes cover the victim at +300 ms |
| `img/combat/hspin_light_hit_sheet.jpg` | a small hit (0.067) that throws the player's own machine by recoil; it ends up under the top HUD because the camera does not pull out for airtime |
| `img/combat/flipper_fires_sheet.jpg` | two flipper fires at the press, +150 ms and +450 ms: nothing visibly happens to the opponent (S3, B6) |
| `img/combat/vortex_finish_sheet.jpg` | the last big hit, then the result at +0.3 s and +1.5 s: CORE DESTROYED lands across the middle, the wreckage orbit puts the wreck behind it, the bolt streaks are still flying (B7, B8, B12) |
