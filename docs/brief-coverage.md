# Brief coverage audit (living document; updated 2026-09-14 09:20)

Every numbered section of `docs/brief-v3.md` mapped to what exists, with the stage that owns anything
still open. Status words: DONE (built and verified), PARTIAL (built, gate owed), PLANNED (spec written,
stage named), OWNER (owner decision changed the brief).

| brief | item | status | where |
|---|---|---|---|
| §2 | real 3D, isometric default framing, free camera (pan, zoom, tilt, orbit) | DONE | camera_rig.gd, ui_test |
| §2 | plain-language height readout as a teaching aid | DONE | HUD readout sentence |
| §3 | no show names, no named robots, no house-robot silhouettes, no show logos or typefaces | DONE, re-check at Stage 5 (bosses) | art docs, title-clearance.md |
| §3 | cheap IP opinion before listing | OWED to owner | title-clearance.md gives the facts |
| §4 | Garage -> scouting -> pick bot -> fight -> assessment -> repair loop | DONE (Swift career screens + engine self-test 172 checks) | stage5-swift-notes.md |
| §5 | weight budget, one class (100 kg) | DONE | BuildRules (Swift + GDScript), parts.json |
| §5.1 | 6 chassis with inverted behaviours | DONE | Arena/bot/chassis, assembly_test |
| §5.2 | 5 drives incl. omni late unlock | DONE (unlock gating PLANNED Stage 5) | Arena/bot/drive |
| §5.3 | 10 weapons, mechanically distinct | DONE (weapons_a/b tests; three-builds test proves the builds differ) | Arena/bot/weapons |
| §5.4 | 2 utility slots, 7 options | DONE | assembly |
| §5.5 | armour per face, 4 materials, spinner/saw asymmetry | DONE | damage.gd, MATERIAL_FACTOR, cut factor |
| §5.5 | scouting report before each fight | DONE (ScoutingView + stage scout mode) | |
| §6 | no HP bar: wheels, weapon, panels, drive, core with joint failure | DONE | damage.gd, bot.gd |
| §6 | debris persists as obstacles, grey | DONE | Debris node, DEBRIS_TINT |
| §6 | bolt showers: visualisation not pickups, all five tuning parameters, readability, pool 120 | DONE (magnet needed an alignment term, documented) | Arena/fx |
| §6 | four win conditions; 90 s fight; KO 10 s | DONE (90 s kept as the hypothesis) | rules.gd |
| §7 | six arenas with two-way signature hazards | DONE (arenas_test 108 checks); visual pass OWED when windows are allowed | stage5-arenas-notes.md |
| §8 | five original bosses, distinct counters, punish inactivity | DONE (boss_ai.gd, enforcer, signature parts, silhouette sheet reviewed) | |
| §9 | five tiers, entry fee, purse, blueprints from progression only | DONE (catalogue career key, CareerEngine) | |
| §9 | stable: capacity 1..5, per-bot damage and repair bill, write-off, names and record | DONE | CareerGarageView, DamageAssessmentView |
| §9 | nothing purchasable in game; single door charge only | DONE (StoreKit 2 single non-consumable, Gates, one Unlock screen offered twice) | stage6-store-notes.md |
| §9 | 6 to 8 rivals that upgrade in parallel and remember history | DONE (8 rivals, upgrade paths, grudge lines) | |
| §10 | Career | DONE | |
| §10 | Side events: Sumo, Gauntlet, Pinball, Football, Wall Smash, each rewarding blueprints | Swift DONE; Godot events IN PROGRESS (E6) | stage6-events-replays-notes.md |
| §10 | Quick Fight (any bot, any unlocked arena) | PARTIAL: any bot yes; arena picker for quick fight OWED (one picker over the six arena ids) | |
| §10 | Rumble 3-bot, decided after Stage 4 | DONE in the arena (rules.mode rumble, eliminations); Swift entry point OWED (a Rumble option in quick fight) | |
| §10 | Workshop Test Arena with physics overlay and full camera freedom | DONE | test mode, test_overlay |
| §10 | Async ladder (ghost builds driven by AI), no real-time multiplayer | DONE (CloudKit public DB with offline ghosts, Elo, Game Center leaderboards); owner must enable iCloud + Game Center on the App ID | stage6-ladder-notes.md |
| §10 | Replay: input/seed replay, free camera, slow motion, shareable clips | DONE (bit-exact re-simulation proven, replay bar, ReplayKit clips) | |
| §11 | left thumb stick, right thumb weapon, secondary self-right/handbrake, turn rate as drive stat | DONE | controls.gd, drives |
| §11 | tank twin-stick optional scheme | DONE (settings scheme, turn input) | controls.gd |
| §11 | camera gestures only, auto ease-back, clamps 20 to 70, walls always on screen | DONE | camera_rig.gd |
| owner | physical controller (Xbox, PlayStation) support | DONE in code (pad input, HUD glyphs, pad-navigable menus); OWED: a real pad on a real phone to confirm the embedded engine receives GCController events | |
| §12 | SwiftUI shell, SwiftData, StoreKit 2 single product + restore, GameKit, Godot embedded | DONE | |
| §12 | thin data-only bridge, FightConfig in, FightResult out | DONE (signals both ways) | bridge-spec.md |
| §12 | Jolt, rigid-body assemblies, joint breakage, fixed tick, determinism | DONE (fresh World3D per fight required; contact cache off) | |
| §12 | 60 fps on device; body caps; binary size budget | caps DONE; size DONE (device app 127 MB: 83 MB code, 27.8 MB pack; under the 200 MB prompt); 60 fps OWED on the phone | |
| §13 | low-poly stylised look, damage carries the visuals | OWNER raised to PS4 class; parts, PBR, fx DONE; damage decals API exists, wiring to damage events OWED | graphics-bar.md |
| §13 | GBC chrome for menus | OWNER replaced by AAA cinematic menus | stage2-art-direction.md |
| §13 | Blender modular parts with mount sockets; Recraft for icon and store | Blender DONE; icon DONE; screenshots and preview video OWED (need visible runs) | store-copy.md |
| §14 | free = Scrapyard + Regional, Yard + Grinder, CINDER, test arena, garage 2, accelerated drip | DONE (Gates); OWED: CareerEngine must refuse to advance past Regional when locked (noted in store notes) | |
| §14 | one £4.99 non-consumable, offered twice, Family Sharing, restore, progress carries, plain store statement | DONE in code and copy; Family Sharing and price are App Store Connect settings for the owner | store-copy.md |
| §15 | Stage 1 bridge spike | DONE | stage1-results.md |
| §15 | Stage 2 art direction renders | DONE | Art/direction |
| §15 | Stage 3 one complete fight | DONE | signed off a1a5ad9 |
| §15 | Stage 4 builder; three builds play differently; Rumble decided | DONE (builds_test green) | |
| §15 | Stage 5 career and stable | DONE | |
| §15 | Stage 6 everything else; free portion playable before the wall | DONE except the Godot side events (in progress) and the owed items above | |
| §16.1 | GDScript | DONE | |
| §16.2 | bridge mechanism | DONE (SwiftGodotKit + own singleton) | |
| §16.3 | determinism under Jolt | DONE with conditions | stage3-rules-notes.md |
| §16.4 | camera during KO: director cut vs player camera, test both | DONE (Settings toggle routed to the rig); the A/B is the owner's call by playing | |
| §16.5 | binary size vs cellular limit | DONE (200 MB prompt, disableable); keep app under it | title-clearance.md |
| §16.6 | title clearance | DONE, low risk | title-clearance.md |

Owed for the handover (all need the owner or a visible run): physical-device verification (fps, pad events, haptics), App Store Connect setup (IAP product, Family Sharing, Game Center leaderboards ladder_rating and career_wins, iCloud container iCloud.com.radicraft.roboteer), visual passes of the five arenas, five events and the boss fights, sound judged by ear, screenshots and preview video.

Also from the owner during the build: landscape only; iPhone only; the arena renders on the simulator
via a custom OpenGL slice (docs/simulator-rendering.md); physical-device verification owed; App Store
submission is the owner's (never pressed from here).
