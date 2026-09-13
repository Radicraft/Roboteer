# Roboteer — Game Design Brief (v3)

**Working title:** Roboteer *(alternates: Scrap Circuit, Bolt Pit, Wreckyard)*
**Platform:** iPhone / iPad — SwiftUI app shell with an embedded Godot 4 3D arena, built and shipped from Xcode
**Genre:** Physics robot combat with a deep build system
**Reference point:** *Robot Wars: Metal Mayhem* (Game Boy Color, 2000) — rebuilt properly
**Audience:** Players who watched robot combat TV as kids, now 30–45; plus anyone who likes a tinkering loop
**Model:** Free to play the first two circuits; one £4.99 purchase unlocks everything permanently. No subscription, no ads, no second transaction.
**Status:** Brief for staged build. All major decisions locked below.

**Changed in v3:** Named Roboteer, chosen on organic-search grounds. Monetisation settled as free-to-play with a single unlock purchase, and §14 now specifies where the wall sits.

**Changed in v2:** 3D replaces 2D isometric sprites. Free camera (pan, zoom, tilt, orbit). Godot 4 replaces SpriteKit for the arena; SwiftUI keeps everything else. Height bands, resolved flips and 8-direction spriting are all deleted — real physics does that work now. Players maintain a stable of bots rather than one.

---

## 1. The pitch

You are a roboteer. You build fighting robots out of parts you've earned, you drive them into an arena full of saws and pits and flame jets, and you either take your opponent apart or watch your own wheels come off. Then you go back to the workshop and fix what broke.

The original Game Boy game had the right idea and the wrong body. This is the same fantasy — build a bot, enter the tournament, survive the arena — with physics that actually makes the building matter.

## 2. The view, and why 3D

Metal Mayhem's core failure was that it used a **flat top-down view for a fundamentally three-dimensional sport**. Ground clearance, weapon height, wedge angle and chassis shape are the whole substance of robot combat, and none of them are visible or meaningful from directly above. Every robot felt identical: a box with a waggling stick. The builder was pointless because the build couldn't express itself in play.

**Locked decision: real 3D, presented isometrically, with a free camera.** Low-poly models, a near-orthographic default framing that reads as classic isometric, and a camera the player can pan, zoom, tilt and orbit.

Going 3D rather than faking isometric with sprites removes three separate compromises at once:

1. **Height is real.** Ground clearance is an actual gap. A mid-height spinner bar passes over a floor-scraping wedge because the geometry says so, not because a band-mask table says so. No parallel height system to build, tune or debug.
2. **Flips are simulated.** Gravity, mass distribution, angular momentum. Getting thrown, landing inverted, rocking off a wall, firing a srimech — all emergent, all authentic, none of it scripted. This is the single largest gameplay upgrade over v1, and it's the thing the source material is most famous for.
3. **The art combinatorics collapse.** One model per part, rendered at any angle. A stable of bots each built from arbitrary part combinations is now trivial to render. In 2D this was the project's biggest risk.

**The one thing 3D does not give you for free: readability.** A player who can't tell why their spinner is doing nothing will conclude the game is broken. So the HUD keeps a plain-language height readout ("your wedge: floor / their bar: mid") as a *teaching* affordance — it's now describing real geometry rather than driving it.

## 3. Intellectual property — what is off-limits

The format is not protectable. Robot combat, arena hazards, a tournament ladder, house-robot-style arena bosses — all fine. What must be avoided:

**Do not use, reference, or resemble:**
- The names *Robot Wars*, *BattleBots*, *Robotica*, *Techno Games*, or the phrase "Roboteers, ready"
- Any show logo, typeface pastiche, or presenter likeness
- Any named competitor robot — no Chaos 2, Razer, Hypno-Disc, Firestorm, Pussycat, Tornado, Panic Attack. These designs belong to the individual teams that built them, not the broadcasters.
- The house robots — no Sir Killalot, Matilda, Dead Metal, Shunt, Sgt Bash, Growler, Refbot. Not the names, and not the silhouettes.
- The specific arena layouts, floor markings, or the pit-of-oblivion branding

**Design rule for the arena bosses:** each must be conceptually distinct, not a renamed equivalent. If a boss is "the big crusher one", give it a different chassis class, a different number of wheels, a different weapon geometry and a different personality. The resemblance test is silhouette, not name. In 3D this matters more, not less — a recognisable silhouette is now visible from every angle.

*This is a practical summary, not legal advice. Worth a cheap IP opinion before you put a name on the App Store listing.*

---

## 4. Core loop

```
Garage  →  Scouting report  →  Pick the right bot  →  Fight  →  Damage assessment
   ↑                                                                    ↓
   ←────────────  Repair, rebuild, earn scrap and blueprints  ←─────────
```

Every fight leaves the bot damaged. Repairs cost scrap. A pyrrhic win that costs more to repair than it paid out is a real outcome. With a stable of bots (§9), choosing *which* machine to send is now part of the loop rather than an afterthought.

## 5. The builder — where the depth lives

Everything is governed by one constraint: **a weight budget** set by the weight class. Every part costs kilograms. Power costs weight, armour costs weight, weapons cost weight. You cannot have all three.

### 5.1 Chassis (6 archetypes)

Chassis sets footprint, base structure weight, mounting points, centre of mass, and how it behaves inverted. In 3D, centre of mass is a real simulated property — a top-heavy build genuinely tips.

| Chassis | Character | Inverted behaviour |
|---|---|---|
| **Wedge** | Low front ramp, built to get underneath | Useless inverted, needs a srimech |
| **Box** | Generalist, balanced mounting, roomy | Needs a srimech |
| **Pyramid** | Invertible by design, drives either way up | Fully functional inverted |
| **Long/Low** | Hard to flip, hard to get under, poor turning | Slow to recover |
| **Tall Tank** | Heavy, high mounting for overhead weapons | Tips easily, hard to recover |
| **Shell** | Full-body rotating ring, no exposed sides | Immune to flipping, fragile drive |

### 5.2 Drive (5 options)

Affects speed, torque, traction, turn rate, and how many wheels you can afford to lose.

- **2WD** — light, fast, fragile; lose one wheel and you're circling
- **4WD** — the default; good pushing power
- **6-Wheel** — heavy, best pushing, redundancy against wheel loss
- **Tracks** — slow, huge traction, very hard to push, vulnerable to spinners tearing the track off
- **Omni** *(late unlock)* — can strafe and pivot instantly, weak and expensive

### 5.3 Primary weapon (10 options)

The main variety axis. Each must feel mechanically distinct, not a damage-number reskin. In 3D each is a real jointed assembly, so its reach, arc and height come out of the model rather than a stat table.

1. **Horizontal spinner** — long bar; devastating, but needs spin-up and self-destabilises on impact
2. **Vertical spinner / drum** — throws the opponent upward; safer for the wielder, less reach
3. **Flipper** — pneumatic, limited gas charges; wins by throwing bots out or onto their backs
4. **Lifter** — slow, controllable, no launch; excellent for carrying opponents onto hazards
5. **Crusher claw** — grapples and pins, immobilising the opponent while it chews; short reach, high risk
6. **Axe / hammer** — huge single overhead hits, slow reset, great against top armour
7. **Saw** — continuous contact damage, near-zero knockback, rewards staying latched on
8. **Ram / spike** — no moving parts; the entire weight budget goes into speed and armour
9. **Flamethrower** — damage over time plus temporary electronics disruption (weapon or drive cuts out)
10. **Full-body spinner** — chassis-integrated, no exposed weak side, terrible controllability

### 5.4 Utility slots (2 slots, choose from)

- **Srimech** — self-righting arm; non-negotiable unless your chassis is invertible
- **Rear anti-spinner wedge** — reduces damage taken from behind
- **Ground-clearance skirts** — stops opponents getting under you, reduces your own clearance
- **Downforce magnets** — resist flipping, slow you down
- **Scoop** — control tool, herds opponents toward hazards
- **Spare battery** — faster weapon spin-up, more flipper charges
- **Counterweight** — stability, shifts centre of mass, pure weight cost

### 5.5 Armour — per face

Four faces armoured independently: **front, sides, rear, top**. Each gets a thickness and a material:

| Material | Against spinners | Against saws/axes | Weight |
|---|---|---|---|
| **Steel** | Poor (transmits shock) | Excellent | Heavy |
| **Titanium** | Good | Good | Light, expensive |
| **HDPE / plastic** | Excellent (absorbs) | Poor (cuts through) | Very light |
| **Polycarbonate** | Fair | Fair | Light, cheap |

Material choice against a *known opponent* is the pre-fight strategic decision. Scouting reports before each fight tell you what you're facing — and with a stable, they tell you which bot to send.

## 6. Damage model — component, not a health bar

**No single HP bar.** Each bot is assembled from parts with independent condition, and in 3D each significant part is a rigid body attached by a joint. Damage is joint failure.

- **Wheels / tracks** — knocked off individually, physically detaching and rolling away; each loss degrades speed and turning
- **Weapon assembly** — jams, bends, or tears off entirely; a dead weapon means fighting for a judges' decision
- **Armour panels** — deform, then detach, exposing what's behind them
- **Drive motors** — degrade under sustained pushing or flame damage
- **Control core** — the actual kill target, reachable only once armour is gone

Detached parts persist on the arena floor for the rest of the fight and become obstacles. The wreckage tells the story of the fight, and the free camera means the player can orbit it afterwards.

### Bolt showers — damage feedback and scrap, in one effect

Every damage event sprays **bolts**: shorn fasteners, nuts and rivets that scatter, bounce, then magnetise back to the attacking bot and are collected with a rising pitch. Modelled on Ratchet & Clank's bolt feel, adapted so it can't distort the game.

**Locked: bolts are a visualisation of scrap already earned, not pickups.** The damage event awards the scrap; the bolt shower is how the game communicates it. This matters for three reasons:

1. **No perverse incentive.** If bolts were collectible objects, the optimal play would be chasing them instead of finishing an opponent, or farming light hits on a crippled bot rather than taking the KO. Auto-collection removes that entirely.
2. **Determinism is preserved.** Bolts live in the presentation layer, never in the fixed physics tick (§12). They cost nothing in simulation budget and can't desync a replay.
3. **Nothing is ever missed.** Anything still in flight at the bell is already banked. No fumbling for scrap you've earned.

Bolt count scales with damage severity: a saw scrape sheds three or four, a spinner hit that removes an armour panel sheds thirty.

**Tuning parameters, in order of importance:**

| Parameter | Value | Why |
|---|---|---|
| **Scatter delay** | 200–300ms, randomised ±90% per bolt | The pause before the magnet engages is the effect. Zero delay reads as a vacuum cleaner. |
| **Magnet acceleration** | Pull strength scales inversely with distance, so bolts speed up as they close | Constant-velocity travel looks lifeless at any speed |
| **Arrival stagger** | Emergent from the randomised delay — never simultaneous | Produces a stream, which is what makes the audio work |
| **Collect pitch** | Rises roughly a semitone per consecutive bolt, resets after ~380ms without a collect | The single biggest contributor to the feel. Cheap to build, disproportionate payoff. |
| **Haptics** | One light tick per bolt, with the scrap counter animating up with slight overshoot | Ties the visual, audio and tactile together |

**Readability rule:** collectible bolts are bright gold, small and spinning. Structural debris — shorn wheels, detached armour panels — is dull grey, larger, and stays where it lands as an obstacle. These must never be confusable. A player who drives across the arena to collect a wheel has been misled by the game's own art.

**Budget:** pool the bolt instances and cap simultaneous count (~120). For very large showers, spawn fewer bolts of higher value rather than exceeding the cap.

### Win conditions

1. **Knockout** — opponent immobile for a 10-second count
2. **Out of the arena** — thrown over the wall or into the pit
3. **Judges' decision** on time-out, scored on **damage, aggression, control**
4. **Component kill** — control core destroyed

**Fight length:** 90 seconds, tested in Stage 3. Three minutes is authentic but long for mobile; 90 seconds is the hypothesis to beat.

## 7. Arenas (6, each with a signature hazard)

Each arena is an enclosed 3D floor plan sized so the default camera framing fits it on a phone screen. Hazards are placed to be driven into — yours as much as theirs. Floor-plan design is a real lever: hazard placement controls where fights happen and which flanking routes are safe.

1. **The Yard** — tutorial arena, low walls, floor spikes only
2. **The Grinder** — floor-mounted angle grinders on both flanks
3. **Drop Zone** — a central pit with a retracting cover; the pit opens mid-fight
4. **Furnace** — wall flame jets on timers, plus a conveyor floor section
5. **The Crush** — descending wall rams that pin and flatten anything against the sides
6. **Coliseum** — championship arena, every hazard, plus spinning floor discs

Hazards must be genuinely two-way. The player should lose fights to their own arena mistakes.

## 8. Arena bosses (5 originals)

The house-robot analogue: not entrants, but arena enforcers. They appear in gauntlet events and to punish inactivity.

- **THRESHER** — low six-wheeled crusher with a lifting arm. Slow, immovable; ends fights by pinning you and squeezing.
- **GRUDGE** — tracked flamethrower. Doesn't damage much; disables your drive and cooks your electronics.
- **BANDSAW** — fast and light, herds you into a wall and holds you there while it cuts.
- **ANVIL** — a wall with wheels and an overhead hammer. Nothing of yours gets through the front.
- **CINDER** — huge scoop-flipper. Doesn't try to damage you; tries to throw you into whatever hazard is nearest.

Each boss should force a different counter-build, so gauntlet events reward a varied stable rather than one optimised bot.

## 9. Progression

### Circuit tiers

**Scrapyard → Regional → National → Championship → Masters**

Each tier is a bracket. Winning advances you, earns scrap, and unlocks blueprints. Losing costs the entry fee and the repair bill, and you re-enter.

**Weight classes:** one class at launch. Featherweight / middleweight / heavyweight is a post-launch circuit expansion, not a launch feature.

### The garage — a stable of bots

**Locked: players maintain multiple bots, not one.**

- Garage capacity starts at **1 bot** and grows with tier: 2 at Regional, 3 at National, 4 at Championship, 5 at Masters
- Each bot has its own build, its own damage state and its own repair bill
- Scouting reports precede every fight, so sending the right machine is a real decision — and this is what makes the boss counter-build design in §8 pay off
- **A bot can be destroyed beyond economical repair.** This is survivable precisely because you have others, and it's an outcome a single-bot design can't afford to have. Losing a favourite machine in the Championship quarter-final is the kind of thing players tell other people about.
- Bots are named by the player and carry a record: fights, wins, KOs, and what finally killed them

### Currency and unlocks

- **Scrap** — earned from fights, spent on repairs, parts and entry fees
- **Blueprints** — unlock part *types*, earned from tier progression and side events, never purchasable

**Hard rule: nothing inside the game is ever purchasable.** Every weapon, chassis and material is earned by playing. The single unlock (§14) buys access to the rest of the game once and never appears again — it is a door charge, not a shop. The App Store is full of robot builders that gate the fun behind a gacha or a subscription wall and get eviscerated for it in the reviews. Not joining them is most of this game's positioning.

### Rivals

6–8 named AI roboteers with persistent bots that **upgrade in parallel with the player** and remember history. If a rival knocked you out of the Regional semi-final, the game says so when you meet them again in the National quarters. This is the cheapest possible source of narrative and it does most of the emotional work in a game like this.

## 10. Modes

- **Career** — the circuit ladder, the main game
- **Side events** — a direct nod to the original's trial modes, reworked as physics challenges: **Sumo** (push out of a ring), **Gauntlet** (traverse a hazard run against the clock), **Pinball**, **Football**, **Wall Smash**. Each rewards blueprints, so they're not optional filler.
- **Quick Fight** — any bot in the stable, any unlocked arena
- **Rumble** — 3-bot free-for-all. Kept in scope, decided on physics grounds after Stage 4.
- **Workshop Test Arena** — sandbox with a physics debug overlay and full camera freedom; test a build against a dummy before you spend the entry fee. This doubles as the game's real tutorial.
- **Async ladder** — fight other players' *builds*, driven by AI. **No real-time multiplayer.** Async ghost-bot battling gives 90% of the social value for 10% of the netcode risk.
- **Replay** — every fight is recorded as an input/seed replay, re-simulated on playback. Free camera, slow motion, shareable clips. In 3D this is close to free and it is the best marketing asset the game has.

## 11. Controls and camera

### Driving — two thumbs, large zones

- **Left thumb** — analogue stick. Direction sets heading, distance sets throttle; the bot turns toward the stick at a rate set by its drive. Creeping in to get a wedge under someone is a distinct skill from charging.
- **Right thumb, primary** — weapon. Hold to spin up / tap to fire, per weapon type.
- **Right thumb, secondary** — **self-right** when inverted; handbrake pivot when upright.
- Turn rate is a drive stat, not a constant. Tracks turn slowly, omni pivots instantly — so the flanking game is itself something you buy with weight.
- **Tank-style twin-stick** (independent left/right drive) as an optional advanced scheme. More authentic, more expressive, too hard for most players as a default. Offer it, don't require it.

### Camera — free, but not competing for thumbs

The camera must never fight the driving controls. Resolution: gestures only, no on-screen camera controls, and a default framing the player never has to touch.

| Context | Camera |
|---|---|
| **In fight** | Default framing fits the arena. **Pinch** to zoom, **two-finger drag** to orbit and tilt. Auto-eases back to default after ~3 seconds without camera input. Driving is unaffected throughout. |
| **Workshop** | Full turntable orbit, free zoom and tilt. This is the payoff for building — seeing your machine from every angle is most of why a builder is satisfying. |
| **Pre-fight scouting** | Orbit the opponent's bot. Inspect their clearance, weapon height and armour before choosing which of your stable to send. |
| **Replay** | Unrestricted free camera, slow motion, scrub. |

**Clamps:** pitch limited to roughly 20°–70°. Below that you lose the floor plan and can't navigate; above it you're back to flat top-down, which is the mistake the whole project exists to avoid. Zoom clamped so the arena walls always remain on screen at minimum zoom.

**Default framing is authoritative.** The free camera is expression, not a requirement. A player who never touches it must be able to complete the game.

## 12. Technical architecture

### Shape of the app (locked)

**SwiftUI app shell + embedded Godot 4 view for the arena only.**

| Layer | Technology | Responsibility |
|---|---|---|
| **Shell** | SwiftUI | Garage, builder, career, bracket, scouting, store, settings, replays list |
| **Persistence** | SwiftData | Bot builds, stable state, career progress, rival history, replay records |
| **Commerce** | StoreKit 2 | Exactly one non-consumable unlock product, plus a restore flow |
| **Social** | GameKit | Game Center leaderboards, async ladder identity |
| **Arena** | Godot 4, embedded as a library in the iOS app | The fight: 3D rendering, physics, AI, camera, input |

Rationale: Godot is far better than SwiftUI at 3D physics combat, and far worse than SwiftUI at list-and-form UI. Scope each to what it's good at. The shell is also where your existing Swift experience applies directly.

### The bridge — the highest-risk unknown in the project

Swift and Godot communicate through one narrow, versioned contract. Keep it small and keep it data-only.

- **In:** a `FightConfig` JSON payload — both bots' full part lists, materials, damage states, the arena id, the rules, an RNG seed
- **Out:** a `FightResult` JSON payload — outcome, per-component damage, judges' scores, scrap earned, replay input log
- No live chatter mid-fight. The Godot view is handed a fight and returns a result.

This boundary is deliberately thin so that the bridge can be built and tested before any gameplay exists. **See Stage 1** — this gets de-risked first, not last.

### Physics

- Godot 4 with **Jolt** as the 3D physics backend
- Bots are `RigidBody3D` assemblies: chassis body, wheel bodies, weapon body, detachable armour panels, connected by `HingeJoint3D` / `PinJoint3D` / generic 6DOF joints with breakage thresholds
- **Damage is joint failure.** Exceed a joint's threshold and the part detaches into a free body. No parallel damage system.
- Fixed physics tick, deterministic given the seed and input log — this is what makes replays and the async ladder possible, so **determinism is a requirement, not a nice-to-have**
- Target 60fps with the physics budget sized for it; 120fps on ProMotion only if it comes free

### Stability discipline

- Cap bodies per bot: chassis + up to 6 wheels + weapon + up to 4 detachable panels
- Cap simultaneous bots at 2 for career; Rumble's third bot is tested last and cut without regret if the tick budget suffers
- Joint chains stay shallow. No part attached to a part attached to a part.
- **Preserve working gameplay over adding sophistication.** If a system makes something that already worked unreliable, take the simpler version.
- Binary size: embedding Godot costs roughly 30MB. Budget for it and don't be surprised.

## 13. Art direction

**Locked: stylised low-poly 3D.** Chunky readable silhouettes, flat or lightly-shaded materials, strong contrast between chassis and weapon. Not photoreal, not cartoon — closer to a well-made tabletop miniature. Damage carries the visual load: scratch decals, scorch marks, bent panels, dust and sparks accumulating over a fight.

Robot combat is the ideal subject for low-poly modelling because the parts *are* primitives. A wedge is a cut cube. A drum is a cylinder. A bar spinner is a box. The entire part library is achievable in Blender with modest modelling skill, and the constraint keeps the style coherent.

The GBC homage now lives entirely in the **SwiftUI chrome**: menus, the bracket, loading screens and pre-fight stat cards use a four-tone green palette and a bitmap face. The arena is full colour and full 3D. This is easier to execute in SwiftUI than it was going to be in SpriteKit.

### Asset pipeline — changed from v1

Going 3D retires the sprite pipeline entirely.

- **Blender** — the part library. One model per part, modular, with defined mount sockets so any chassis + drive + weapon + armour combination assembles at runtime. Low poly counts, shared materials, one texture atlas.
- **Optional AI 3D generation** (Meshy, Tripo, or similar) for base meshes to retopologise by hand. Useful for the boss robots, where silhouette distinctiveness matters and modelling from scratch is slowest.
- **Recraft** — app icon, SwiftUI chrome, bracket and menu furniture, App Store screenshots. Unchanged from v1 and still the right tool.
- **PixelLab is no longer part of this project.** It's a pixel art tool; there are no sprites left to generate. Worth noting explicitly so the earlier plan doesn't get half-implemented.

**Mount sockets are the pipeline's load-bearing convention.** Every chassis exposes named sockets (weapon, drive, armour faces, utility); every part declares which socket it fits. Get this right in the first ten models and the other fifty are straightforward.

## 14. Monetisation

**Locked: free to download and play, with a single non-consumable purchase that unlocks the rest of the game permanently.** One purchase, one price, offered in one place. No subscription, no ads, no cosmetic store, no gacha, no energy timers, no second transaction of any kind.

This is a door charge with a playable demo in front of it, not monetisation inside the game — and the distinction has to hold in practice. Nothing a player does in a fight is ever made worse in order to sell the fix. The unlock is never offered mid-fight, never on a timer, never at a discount.

### Where the wall goes — the only decision that matters here

The purchase happens at the wall, so **the free portion must contain the game's best moment, not its tutorial.** A player who reaches the wall having only driven a starter wedge around The Yard has seen the least interesting version of the game and won't pay.

**Free:**

- Scrapyard and Regional circuits
- The Yard and The Grinder
- One boss encounter (CINDER)
- The workshop test arena, with full camera freedom
- Garage capacity 2
- An **accelerated blueprint drip**, so the player earns three or four weapons and two chassis inside the free portion

That is enough to build two genuinely different machines, land a flipper throw, watch a wheel come off, and collect a proper bolt shower. All three of the game's distinctive pleasures are in the free half.

**Unlocked by the purchase:** National, Championship and Masters circuits; the remaining four arenas; four more bosses; the full part library; garage capacity up to 5; side events; replays and sharing; the async ladder.

### Rules for the wall

- **Progress carries across the purchase.** Every bot, every blueprint, every rival grudge survives. Nothing resets, ever.
- **State it plainly on the store page:** free to play the first two circuits, one £4.99 purchase unlocks everything forever, no other purchases, no ads, no subscription. Surprise walls earn one-star reviews; a stated wall is a selling point in a category defined by gacha.
- **Offer it twice at most** — once on completing the Regional circuit, and permanently in settings. Never again unprompted.
- Non-consumable, restorable across devices, and **enabled for Family Sharing.** Cheap goodwill for one checkbox.

### Price

**£4.99.** The earlier £2.99 figure was set by cold-purchase resistance; a player who has just won a Regional final and wants the next circuit is a warm buyer and will pay more. Net proceeds land around £3.50 after VAT and Apple's 15% Small Business Program rate. Start there — dropping a price later is easy, raising one is not.

### What this fixes

Going free also addresses the launch-velocity problem. The app competes in the far larger free-download pool, and it accumulates ratings from players who never pay — and rating volume is precisely what lets it climb over the abandoned five-rating shovelware currently occupying this category's keywords.

The corresponding risk is one-star reviews from players who object to the wall on principle. The mitigation is entirely in the honesty of the store listing and in never nagging.

## 15. Build stages

Build in this order. Do not proceed until the previous stage works.

**Stage 1 — The bridge spike.** No gameplay, no art. A SwiftUI screen that hands a hardcoded JSON payload to an embedded Godot view showing a grey cube on a grey floor, and receives a JSON result back. Measure launch time, binary size and memory. **This is the single highest-risk unknown in the project and it must be settled before anything else is built.** If embedding Godot in an iOS app proves unworkable, that needs to surface in week one, not month four.

**Stage 2 — Art direction.** Three renders, no code: one bot in the workshop, one arena mid-fight, one GBC-styled bracket screen. Validate the visual target.

**Stage 3 — One complete fight.** One chassis (Wedge), one weapon (Flipper), one arena (The Yard), one opponent, in Godot. Real physics, joint-failure damage, bolt showers with magnetism and the pitch ramp, all four win conditions, both control thumbs, gesture camera, haptics, 90-second timer. This stage proves or kills the design — if a flipper throw and the bolt shower that follows it don't feel good here, nothing later saves it.

**Stage 4 — The builder.** Weight budget, all chassis, all drives, all weapons, armour per face, utility slots, mount-socket assembly, the test arena. Verify three different builds genuinely play differently against the same opponent. Decide on Rumble.

**Stage 5 — Career and stable.** Five tiers, six arenas, five bosses, rivals with persistent history, garage capacity growth, scrap economy, repair and write-off costs, blueprints, SwiftData persistence.

**Stage 6 — Everything else.** Side events, replays and sharing, async ladder, Game Center, the single unlock product with its restore and Family Sharing flows, and the store page assets — icon, screenshots and preview video. The free portion defined in §14 must be playable end to end before the wall is implemented, so that the wall is placed against a real experience rather than a planned one.

## 16. Open questions

1. **GDScript or C# for the arena?** GDScript is faster to iterate and better documented for Godot 4; C# is more familiar territory coming from Unity. Recommendation: GDScript, because the Godot-specific answers you'll be searching for are written in it.
2. **Bridge mechanism** — settled in Stage 1. Options are Godot's iOS library embedding versus running the arena as a full Godot scene with SwiftUI presented over it. The spike decides.
3. **Determinism under Jolt** — replays and the async ladder both assume identical results from identical seed and inputs. Verify early in Stage 3; if it doesn't hold, replays become recorded video and the async ladder needs rethinking.
4. **Camera during KO** — does the camera take over for the knockout moment, or stay where the player left it? A director cut is more dramatic and slightly disempowering. Test both.
5. **Binary size versus App Store download limits** — ~30MB for Godot plus models and audio. Check against current cellular download thresholds before Stage 5.
6. **Title clearance** — Roboteer is chosen. No games-class registration surfaced in US or UK searches, and it reads as the genuine word for a robot builder rather than a show reference. Still to do before art is finalised: search the exact name in the App Store Search tab on two storefronts, and run UK IPO and USPTO free searches in class 9 (software) and class 41 (entertainment). Note "Roboteers, stand by" is a show catchphrase, but "roboteer" is a pre-existing generic noun, which is the basis for treating the risk as low.
