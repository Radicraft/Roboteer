# Stage 6 spec: everything else

Brief §15 Stage 6: "Side events, replays and sharing, async ladder, Game Center, the single unlock product
with its restore and Family Sharing flows, and the store page assets. The free portion defined in §14 must
be playable end to end before the wall is implemented." Plus the owner's additions: physical controllers
(done in Stage 4), Rumble (kept), Editor's Choice polish. Read brief §10, §14, §16.4, §16.5 and the Stage 5
notes first. Landscape, AAA chrome, no em dashes.

## 1. Side events (Godot E6 + Swift S6)

Each is a `rules.mode` with its own arena scene, a 60 to 90 s clock, a score, and a blueprint reward on
first clear (and a smaller scrap reward on repeats). Rules live in `Arena/fight/events/<mode>.gd`
(extends a small `EventRules` base that fight.gd delegates to when `rules.mode` is not fight/test), arenas
in `Arena/arena/events/`.
- **Sumo**: a 6 m circular raised platform, no walls; an AI opponent; first to push the other off wins;
  best of three within 90 s.
- **Gauntlet**: a 24 x 6 m corridor of hazards (spikes, a grinder pair, a flame gate, a crush section);
  reach the far pad against the clock; time and damage taken scored; no opponent; an arena boss chases
  from behind after 20 s (uses the boss builds from Stage 5).
- **Pinball**: a 10 x 14 m table with bumpers (kinematic pads that kick on contact and score), a ramp and
  two drop targets; 60 s; score.
- **Football**: a 12 x 8 m pitch, a 0.5 m sphere ball (RigidBody3D), two goals, an AI opponent; most goals
  in 90 s.
- **Wall Smash**: a corridor of breakable wall segments (RigidBody3D bricks on breakable joints using the
  existing damage path); break through five walls against the clock; score is time.
Swift: an Events screen listing the five with locked/unlocked state, best score, reward; the Godot side
sends `event_result` {mode, score, cleared, time_s} instead of fight_result; FightLog records it.

## 2. Replays and sharing (Godot R6 + Swift S6)

- The recorder already logs the player's inputs; add a `replay` key to FightConfig: `{"inputs": [...]}`.
  When present, fight.gd drives the player bot from the log (ReplayRecorder playback) and the AI from the
  seed, in a fresh world, with the HUD replaced by a replay bar sent to Swift via `replay_state` {tick,
  total}. Controls: play/pause, slow motion 0.25x/0.5x/1x (Engine.time_scale in the arena only; physics
  tick rate unchanged so determinism holds), restart, free camera with no ease-back (mode "replay").
  Scrubbing backwards re-simulates from the start at 8x headless-visible speed (skip rendering by
  running N physics steps per frame) then resumes; document the cost.
- Swift: Replays screen listing FightLogs (date, opponent, outcome, arena), "Watch", and "Share clip":
  ReplayKit `RPScreenRecorder` records the replay playback for the chosen span (max 30 s), then presents
  the share sheet with the video; the recording is of the Godot view plus the replay bar.

## 3. Async ladder and Game Center (Swift L6, Godot none beyond player-AI)

- Identity: GameKit `GKLocalPlayer.authenticate`; if unavailable, a local guest name.
- Storage: CloudKit public database (container from the app's entitlements) record type `LadderBuild`:
  {ownerID, displayName, buildJSON, rating, wins, losses, updatedAt}; the player's current build is
  published when they enter the ladder; opponents are fetched near the player's rating (query by rating
  window, 20 records, cached). Offline or no iCloud: fall back to eight generated ghost builds from the
  catalogue at the player's tier so the mode always works.
- A ladder fight = fight_config with the ghost build as `controller: "ai"`; result updates the player's
  rating locally (Elo K=32) and the CloudKit record; the ghost owner's record gets a pending result written
  as a `LadderResult` record so their app can reconcile on next launch (their rating moves when they
  play). Leaderboards: GameKit `ladder_rating` and `career_wins` reported after each fight.
- Never real-time; never blocks the UI; all failures degrade to local.

## 4. Rumble (Godot R6)

`rules.mode = "rumble"`, three bots (player + two AI), win = last mobile bot or judges over three at
90 s; the third bot uses the per-fight world already built; body cap check; Quick Fight offers it.

## 5. The unlock (Swift P6)

- StoreKit 2: one non-consumable `com.radicraft.roboteer.unlock` (display price from the store; the
  brief's £4.99 is set in App Store Connect by the owner), `Product.products(for:)`, `purchase()`,
  `Transaction.currentEntitlements` on launch and on `Transaction.updates`, "Restore purchases" via
  `AppStore.sync()`; Family Sharing is the ASC checkbox (note it for the owner). `Entitlement` published
  from a `StoreService`; every gate reads it.
- Gates per brief §14: free = Scrapyard + Regional tiers, Yard + Grinder, CINDER, the test arena, garage
  capacity 2, the accelerated drip; locked = National/Championship/Masters, the other four arenas, four
  bosses, the full part library (the builder greys locked parts with "Unlocks with the full game"), garage
  3 to 5, side events, replays and sharing, the ladder.
- The wall is offered twice at most: an Unlock screen after winning the Regional final (once) and a row
  in Settings; never mid-fight, never on a timer, never discounted. Progress carries across.
- A StoreKit configuration file in the project for local testing (`Roboteer/Store/Roboteer.storekit`).

## 6. Store page assets and copy (Art A6)

- App icon via Recraft (1024, no text, the bot's wedge nose under stage light), all sizes generated with
  sips into the asset catalog. iPhone-only screenshots: 6.9 inch set (1320 x 2868 portrait not allowed
  for landscape apps? App Store accepts landscape 2868 x 1320) captured from the simulator via
  `simctl io screenshot` on real screens with curated states (never live data): menu, builder, arena
  mid-throw with a bolt shower, bracket, damage assessment, replay. Preview video 15 to 30 s from
  `simctl io recordVideo` of a real fight. Copy: title "Roboteer", subtitle, keywords (no competitor
  names), description with the plain sentence about the wall, What's New, Review notes; no em dashes.
  The owner submits.

## 7. Polish and gates before handover

- Onboarding: first launch routes Build -> Test arena (the real tutorial per brief §10) -> first fight.
- Sound: the Stage 3 placeholders are synthesised; recorded or sampled sounds need a licensed source
  (the owner can supply a Freesound API key or an asset pack); until then improve the synthesis.
- Device measurements owed: 60 fps on the iPhone 17 with Forward+, app size under 200 MB (texture
  compression to ASTC/ETC2 at import if the pck stays near 70 MB), launch time, thermal.
- The brief-coverage audit (docs/brief-coverage.md) must show no PLANNED rows at the end.
