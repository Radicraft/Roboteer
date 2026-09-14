# Shell notes on the bridge (agent: Swift fight shell, 2026-09-14)

`docs/bridge-spec.md` is the Godot agent's file. These are the shell's side of the three additions
the fight screen now depends on, written here so nothing is lost if they land in the spec later.

## `fight_control` (host -> arena)

`ArenaHost.sendFightControl(_ action: String)` sends `{"action": "pause" | "resume" | "quit"}`.

- `pause` freezes the fixed tick. The shell sends it when the player taps the pause button, and
  when the arena asks with `pause_requested`. The arena never pauses itself.
- `resume` starts the tick again.
- `quit` gives the fight up and takes the arena's existing abandoned path, which comes back as
  `fight_state` `{"state": "abandoned"}`. The shell leaves the screen on that message; if nothing
  arrives within 1.4 s it leaves anyway, so a build of the arena without `fight_control` cannot
  strand a player inside a fight they have quit.

## `pause_requested` (arena -> host)

`{}`. The pad's START button. The shell puts its own overlay up and answers with `fight_control`
pause; it is ignored unless a fight screen is actually on screen. `ArenaHost.pauseRequests` is
bumped once per message.

## `coach` on `fight_config`

Already in `ArenaHost.coachNextFight`. `Roboteer/CoachPolicy.swift` is the shell's policy:

- the test arena is always coached;
- the "Control tips" setting (on by default) coaches every fight;
- with that setting off, the player's first three fights that actually started (counted at the
  countdown, in `UserDefaults` under `coach.fightsStarted`) are still coached.

Nothing new crosses the bridge for the setting. The arena only ever reads `coach` on the
`fight_config` it is handed, and `lastFightConfigJSON` (what replays are built from) never carries
it.

## `stage_camera` (host -> arena)

Added by the Swift layout agent, 2026-09-14. `ArenaHost.sendStageCamera(orbit:pinch:)` sends

```json
{"orbit": [dx, dy], "pinch": 1.04}
```

Either key may be absent; a message with neither is never sent. It is only ever sent while
`host.surface == .stage`, so it belongs to the workshop and menu camera modes and never to a fight.

- `orbit` is a delta in SCREEN POINTS since the last message, +x to the right and +y down. It is
  what the finger just did, not a running total, so the rig adds it to wherever it already is.
- `pinch` is the incremental factor since the last message. Above 1 is zoom in, below 1 is out.
- Deltas are summed and flushed at most once every 16 ms, so a two finger drag is one message per
  frame rather than one per touch event.

The shell reads the gesture itself, in `StageOrbitPad` (`Roboteer/StageSurface.swift`), placed in
the clear left 45 % of every stage screen behind the panels. It has to: the one Godot view is a
sibling BELOW the navigation controller's container view, and that container answers `hitTest` with
itself even when it is clear, so no touch on a menu screen has ever reached `GodotAppView`. The
arena's clamps (pitch 20-70 degrees, zoom limits) stay the arena's business; the shell sends raw
deltas and never tries to know where the camera is.
