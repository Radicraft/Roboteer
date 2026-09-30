# QA launch flags

Every launch argument the app reads, one line each. Pass them in the scheme (Product > Scheme >
Edit Scheme > Run > Arguments) or after `--` to `xcrun simctl launch`. Anything taking a value is
written as `-flag <value>`.

## Where the app starts

| Flag | What it does |
|---|---|
| `-autoCareer` | Opens straight into CAREER. |
| `-autoWorkshop` | Opens straight into the workshop. |
| `-autoBuilder` | Opens the builder for the selected machine, through the workshop, so BACK lands in the workshop the way it does for a player. |
| `-builderTab <name>` | With `-autoBuilder`, opens the builder on that tab: `chassis`, `drive`, `weapon`, `utility`, `armour` or `livery`. Anything else is `chassis`. Added for the paint picker, which is at the bottom of the livery tab (wave P, agent G). |
| `-builderTape` | With `-autoBuilder`, opens the tale of the tape sheet (the player's strength and weakness lines, wave D walk-outs). |
| `-builderPaint` | With `-autoBuilder -builderTab livery`, leaves the six livery colour rows out so the paint wall is on screen without a thumb. Presentation only, for screenshots; it changes nothing a player sees. |
| `-builderPaintJob <id>` | With `-autoBuilder`, fits that paint job on the machine when the builder opens, so the turntable can be photographed wearing it. Ignored when the id is unknown or the player's Level has not reached it. |
| `-autoTest` | Opens straight into the test arena. |
| `-autoFight` | Opens straight into a quick fight. |
| `-autoEvents` | Opens the side events list. |
| `-autoReplays` | Opens the replay archive. |
| `-autoLadder` | Opens the async ladder. |
| `-autoSettings` | Opens settings. |
| `-autoQuickFight` | Raises the quick fight card over the menu. |
| `-autoBoard` | With `-autoCareer` or `-career`, opens the campaign board: five Series, four matches each. |
| `-autoBracket` | The old name for `-autoBoard`, kept so existing scripts still work. |
| `-autoScouting` | With `-autoCareer` or `-career`, opens the scouting report. |
| `-autoCareerGarage` | With `-autoCareer` or `-career`, opens the career garage. |
| `-autoCareerFight` | With `-autoCareer` or `-career`, starts the next tie straight away, so the fight and then the settlement can be reached without a thumb. |
| `-autoUnlock` | With `-autoCareer` or `-career`, raises the unlock screen over the Series screen. |
| `-autoShop` | With `-autoCareer` or `-career`, opens the shop. |
| `-shopAt <group>` | With `-autoShop`, opens the shop already scrolled to a group: `chassis`, `drive`, `weapon`, `utility`, `material`, or `coming` for the parts still being built. |
| `-openMatchReport [win\|loss\|draw\|decision]` | Wave P: raises the match report on fixture data instead of the game, so the three post-match screens can be read without fighting a match. `decision` (wave B judges) is a loss on the judges with the judges' card and its words. CONTINUE walks on to the rewards screen or the retry prompt, whichever that result leads to. |
| `-openRewards [win\|series\|campaign]` | Wave P: the rewards screen on the same fixture. `series` is the win that finished a Series, `campaign` the win that finished the last one. |
| `-openRetryPrompt [loss\|draw\|broke\|unfit\|stranded]` | Wave P: the retry prompt. `broke` is the same loss with too little scrap to pay the repair bill. Wave A: `unfit` is a destroyed core with the bill affordable (RETRY off, repair and retry on); `stranded` is a destroyed core with the bill over the bank and no other machine (RETRY off, the free patch-up offered). |
| `-openResultSheet decision` | Wave B integration: the quick fight ResultSheet on a fixture judges decision (Clatterbox wins on the cards, 6.1 to 3.9), with both machines' damage and the judges' card, so the sheet can be read without a three minute fight. |
| `-showSpike` | Adds the SPIKE chip to the menu's quiet row: the bridge diagnostic screen. |
| `-autoSendFight` | Sends the Stage 3 spike fixture one second after `arena_ready`, without any screen asking for it. |
| `-skipLoading` | Skips the boot loading screen and the catalogue warm up behind it (docs/stage-bug-2026-09-21.md): the menu shows as soon as the app does, and every model, sound and pipeline loads lazily the way it did before 2026-09-21. `-autoFight`, `-autoTest`, `-autoCareerFight` and `-autoSendFight` imply it, so a fight never starts behind the loading screen. Every other flag that opens a screen waits behind the loading screen and lands on the warmed frame. A headless or dummy run never shows it. |
| `-loadingPose STEP:FRACTION` | Holds the boot loading screen still at one row (0 hull, 1 drive, 2 armour, 3 weapon, 4 stage lights) with the gauge at FRACTION, e.g. `-loadingPose 2:0.41`, for a screenshot of the column. Works on a headless run (the empty-stage still stands behind it). The warm up is never asked for and the menu never appears. |

Each of these also counts as "not a first launch", so the welcome panels stay out of the way,
unless `-resetOnboarding` is passed as well.

## What is in the garage

| Flag | What it does |
|---|---|
| `-build <name>` | Selects the build with that name (case insensitive) instead of whichever was last selected. |
| `-career <fixture>` | Replaces the whole garage and career with a saved one and opens CAREER. Takes a bundle resource name, a bundle resource path or an absolute path. Two fixtures ship: `career-regional.json` (Series 2, match 3, Level 20, a damaged machine, one attempt already made) and `career-masters.json` (every Series won, Level 100, 4,000 scrap, so the completion panel and the board's replay cells can be read). |

## Recipes worth knowing

| Flags | What it shows |
|---|---|
| `-career career-masters.json -locked` | The free game's wall as the ENGINE enforces it (wave P, agent H): a save standing in Series 5 with no entitlement. `ProgressionEngine.nextMatch` hands out no match, and the Series screen says "Series 5 needs the full game / Nothing is lost" with the unlock as its one primary. The save is never altered. |
| `-career career-masters.json -unlocked` | The same save with the game bought: the completion panel, every match replayable. |
| `-autoQuickFight` | The arena picker over all six arenas, the locked four saying "Full game" on their own art, with OPPONENT and RUMBLE under them. |

## The first launch flow

| Flag | What it does |
|---|---|
| `-resetOnboarding` | Puts the welcome panels and the Build/Test/Fight coaching back to a first launch, whatever else is passed. |

## The purchase (DEBUG builds only)

| Flag | What it does |
|---|---|
| `-locked` | Forces the locked half of the game, the free library and the wall after the Regional final. Wins if both are passed. Both flags also settle the entitlement immediately, so `Gates.entitlementSettled` is true from the first frame and the engine's wall is in force without waiting on StoreKit. |
| `-unlocked` | Forces the unlocked half, every circuit and every blueprint, without buying anything. |

## Services

| Flag | What it does |
|---|---|
| `-noGameCenter` | Skips Game Center sign in. The ladder falls back to the local identity. |
| `-noCloudKit` | Skips CloudKit. The ladder runs on local results only. |
| `-controllerHints` | Shows the game pad glyph hints even when no pad has been used yet. |
| `-careerSelfTest` | Runs the career engine self test at launch and logs every check. |

## The arena

| Flag | What it does |
|---|---|
| `-opponentAI idle\|charge\|normal` | What the opponent does in a fight. Anything else is read as `normal`. |
| `-godotDriver <driver>` | Overrides the rendering driver (`metal` on device, `opengl3` on the simulator, `dummy` for no drawing). |
| `-godotMethod <method>` | Overrides the rendering method (`mobile`, `gl_compatibility`, `dummy`). |
| `-godotDisplay <display>` | Overrides the display driver (`embedded`, `headless`). |
| `-godotVerbose` | Passes `--verbose` to the engine. |

A headless or dummy run still has physics, rules and the bridge; the stage behind the menus falls
back to the rendered still, because there is nothing live to show.

## The stage, for screenshots (wave C)

The simulator draws no usable live stage, so these put a real desktop Godot render and its anchors
under the real SwiftUI layer. Composite recipes live in `docs/wave-c-menus-notes.md`.

| Flag | What it does |
|---|---|
| `-stageStill <path>` | Draws that image (jpg or png, absolute path) as the backdrop of every stage screen instead of the live Godot view, the bundled still or the key art: aspect filled and centred over the whole window, safe areas ignored. Each screen's own wash and scene shades still go on top, so the composite is what the phone would show. An unreadable path logs an error and changes nothing. |
| `-stageAnchors <path.json>` | Feeds the file to the app exactly as if the arena had sent `stage_anchors`. The file is either ONE payload (`{"screen": "menu", "settled": true, "hero": [...], "points": {...}, "parts": [...]}`) or an object keyed by screen name whose values are payloads (`{"menu": {...}, "builder": {...}}`); with the keyed form each screen gets its own payload the moment it tells the stage which screen it is, and a payload with no `screen` takes its key. While this flag is on the arena's own `stage_anchors` are ignored. |
| `-stayOnMenu` | With `-career <fixture>`, loads the fixture but leaves the main menu in front instead of opening CAREER, so the menu, the workshop (`-autoWorkshop`) and the builder (`-autoBuilder`) can be photographed with the fixture's career and machine behind them. |

A composite without a live arena at all: `-godotDriver dummy -godotMethod dummy -godotDisplay headless -stageStill /abs/stage.jpg -stageAnchors /abs/anchors.json`.
