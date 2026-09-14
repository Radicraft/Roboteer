# Brief coverage audit (living document; updated 2026-09-13 22:40)

Every numbered section of `docs/brief-v3.md` mapped to what exists, with the stage that owns anything
still open. Status words: DONE (built and verified), PARTIAL (built, gate owed), PLANNED (spec written,
stage named), OWNER (owner decision changed the brief).

| brief | item | status | where |
|---|---|---|---|
| §2 | real 3D, isometric default framing, free camera (pan, zoom, tilt, orbit) | DONE | camera_rig.gd, ui_test |
| §2 | plain-language height readout as a teaching aid | DONE | HUD readout sentence |
| §3 | no show names, no named robots, no house-robot silhouettes, no show logos or typefaces | DONE, re-check at Stage 5 (bosses) | art docs, title-clearance.md |
| §3 | cheap IP opinion before listing | OWED to owner | title-clearance.md gives the facts |
| §4 | Garage -> scouting -> pick bot -> fight -> assessment -> repair loop | PLANNED | stage5-spec.md §2 |
| §5 | weight budget, one class (100 kg) | DONE | BuildRules (Swift + GDScript), parts.json |
| §5.1 | 6 chassis with inverted behaviours | DONE | Arena/bot/chassis, assembly_test |
| §5.2 | 5 drives incl. omni late unlock | DONE (unlock gating PLANNED Stage 5) | Arena/bot/drive |
| §5.3 | 10 weapons, mechanically distinct | flipper + 5 DONE, 4 (spinners, saw) IN PROGRESS (W1) | Arena/bot/weapons |
| §5.4 | 2 utility slots, 7 options | DONE | assembly |
| §5.5 | armour per face, 4 materials, spinner/saw asymmetry | DONE | damage.gd, MATERIAL_FACTOR, cut factor |
| §5.5 | scouting report before each fight | PLANNED | stage5-spec.md §2 |
| §6 | no HP bar: wheels, weapon, panels, drive, core with joint failure | DONE | damage.gd, bot.gd |
| §6 | debris persists as obstacles, grey | DONE | Debris node, DEBRIS_TINT |
| §6 | bolt showers: visualisation not pickups, all five tuning parameters, readability, pool 120 | DONE (magnet needed an alignment term, documented) | Arena/fx |
| §6 | four win conditions; 90 s fight; KO 10 s | DONE (90 s kept as the hypothesis) | rules.gd |
| §7 | six arenas with two-way signature hazards | Yard DONE; five PLANNED | stage5-spec.md §3 |
| §8 | five original bosses, distinct counters, punish inactivity | PLANNED | stage5-spec.md §4 |
| §9 | five tiers, entry fee, purse, blueprints from progression only | PLANNED | stage5-spec.md §6 |
| §9 | stable: capacity 1..5, per-bot damage and repair bill, write-off, names and record | PARTIAL (BotBuild has record + damage; capacity/write-off PLANNED) | BotBuild.swift, stage5 |
| §9 | nothing purchasable in game; single door charge only | DONE by design; wall PLANNED Stage 6 | |
| §9 | 6 to 8 rivals that upgrade in parallel and remember history | PLANNED | stage5-spec.md §5 |
| §10 | Career | PLANNED | Stage 5 |
| §10 | Side events: Sumo, Gauntlet, Pinball, Football, Wall Smash, each rewarding blueprints | PLANNED | Stage 6 |
| §10 | Quick Fight (any bot, any unlocked arena) | PARTIAL (Fight from workshop, Yard only) | Stage 6 |
| §10 | Rumble 3-bot, decided after Stage 4 | DECIDED: keep (measured); build PLANNED | stage4-rumble-decision.md, Stage 6 |
| §10 | Workshop Test Arena with physics overlay and full camera freedom | DONE | test mode, test_overlay |
| §10 | Async ladder (ghost builds driven by AI), no real-time multiplayer | PARTIAL (player-AI driver exists) | Stage 6 |
| §10 | Replay: input/seed replay, free camera, slow motion, shareable clips | PARTIAL (input log recorded, playback in tests, fresh-world determinism proven) | Stage 6 |
| §11 | left thumb stick, right thumb weapon, secondary self-right/handbrake, turn rate as drive stat | DONE | controls.gd, drives |
| §11 | tank twin-stick optional scheme | IN PROGRESS (C) | controls.gd |
| §11 | camera gestures only, auto ease-back, clamps 20 to 70, walls always on screen | DONE | camera_rig.gd |
| owner | physical controller (Xbox, PlayStation) support | IN PROGRESS (C) + Swift entitlement (S) | |
| §12 | SwiftUI shell, SwiftData, StoreKit 2 single product + restore, GameKit, Godot embedded | shell/SwiftData DONE; StoreKit/GameKit PLANNED Stage 6 | |
| §12 | thin data-only bridge, FightConfig in, FightResult out | DONE (signals both ways) | bridge-spec.md |
| §12 | Jolt, rigid-body assemblies, joint breakage, fixed tick, determinism | DONE (fresh World3D per fight required; contact cache off) | |
| §12 | 60 fps on device; body caps; binary size budget | caps DONE; fps and size OWED on device (app 89 MB + pck 69 MB; texture compression to review) | Stage 6 |
| §13 | low-poly stylised look, damage carries the visuals | OWNER raised to PS4 class; parts, PBR, decals, fx DONE; damage decals wiring PLANNED | graphics-bar.md |
| §13 | GBC chrome for menus | OWNER replaced by AAA cinematic menus | stage2-art-direction.md |
| §13 | Blender modular parts with mount sockets; Recraft for icon and store | Blender DONE; icon/screenshots/preview PLANNED Stage 6 | |
| §14 | free = Scrapyard + Regional, Yard + Grinder, CINDER, test arena, garage 2, accelerated drip | PLANNED | Stage 5 content, Stage 6 wall |
| §14 | one £4.99 non-consumable, offered twice, Family Sharing, restore, progress carries, plain store statement | PLANNED | Stage 6 |
| §15 | Stage 1 bridge spike | DONE | stage1-results.md |
| §15 | Stage 2 art direction renders | DONE | Art/direction |
| §15 | Stage 3 one complete fight | DONE | signed off a1a5ad9 |
| §15 | Stage 4 builder; three builds play differently; Rumble decided | NEARLY: builds_test pending W1 + P2 regression fix | |
| §15 | Stage 5 career and stable | PLANNED | stage5-spec.md |
| §15 | Stage 6 everything else; free portion playable before the wall | PLANNED | |
| §16.1 | GDScript | DONE | |
| §16.2 | bridge mechanism | DONE (SwiftGodotKit + own singleton) | |
| §16.3 | determinism under Jolt | DONE with conditions | stage3-rules-notes.md |
| §16.4 | camera during KO: director cut vs player camera, test both | PARTIAL (director cut built with a toggle; settings switch PLANNED Stage 6) | |
| §16.5 | binary size vs cellular limit | DONE (200 MB prompt, disableable); keep app under it | title-clearance.md |
| §16.6 | title clearance | DONE, low risk | title-clearance.md |

Also from the owner during the build: landscape only; iPhone only; the arena renders on the simulator
via a custom OpenGL slice (docs/simulator-rendering.md); physical-device verification owed; App Store
submission is the owner's (never pressed from here).
