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
| `-autoTest` | Opens straight into the test arena. |
| `-autoFight` | Opens straight into a quick fight. |
| `-autoEvents` | Opens the side events list. |
| `-autoReplays` | Opens the replay archive. |
| `-autoLadder` | Opens the async ladder. |
| `-autoSettings` | Opens settings. |
| `-autoQuickFight` | Raises the quick fight card over the menu. |
| `-autoBracket` | With `-autoCareer` or `-career`, opens the full bracket board. |
| `-autoScouting` | With `-autoCareer` or `-career`, opens the scouting report. |
| `-autoCareerGarage` | With `-autoCareer` or `-career`, opens the career garage. |
| `-autoCareerFight` | With `-autoCareer` or `-career`, starts the next tie straight away, so the fight and then the settlement can be reached without a thumb. |
| `-autoUnlock` | With `-autoCareer` or `-career`, raises the unlock screen over the season screen. |
| `-showSpike` | Adds the SPIKE chip to the menu's quiet row: the bridge diagnostic screen. |
| `-autoSendFight` | Sends the Stage 3 spike fixture one second after `arena_ready`, without any screen asking for it. |

Each of these also counts as "not a first launch", so the welcome panels stay out of the way,
unless `-resetOnboarding` is passed as well.

## What is in the garage

| Flag | What it does |
|---|---|
| `-build <name>` | Selects the build with that name (case insensitive) instead of whichever was last selected. |
| `-career <fixture>` | Replaces the whole garage and career with a saved one and opens CAREER. Takes a bundle resource name, a bundle resource path or an absolute path; the shipped fixture is `career-regional.json`. |

## The first launch flow

| Flag | What it does |
|---|---|
| `-resetOnboarding` | Puts the welcome panels and the Build/Test/Fight coaching back to a first launch, whatever else is passed. |

## The purchase (DEBUG builds only)

| Flag | What it does |
|---|---|
| `-locked` | Forces the locked half of the game, the free library and the wall after the Regional final. Wins if both are passed. |
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
