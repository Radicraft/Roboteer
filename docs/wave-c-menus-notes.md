# Wave C: blueprint menus in the arena (branch `wave-c-menus`)

Owner decision 2026-09-28: the menus are direction A "Blueprint overlay"
(`docs/look/menus-blueprint.html`) with staging 2 "In the arena" behind it
(`docs/look/menus-blueprint-A2.html`, renders `docs/look/menus-bp-a2/v2-*.jpg`), plus fixes for
the weaknesses the coordinator saw in the mockups (machine too small on the menu, Coliseum grade
washing the livery purple, flat blue crowd, pyro reading as a glowing figure, boxy haze cards).

Worktree `/Volumes/RoboteerBuild2/Code/Roboteer-menus`, from main `549bb41`. Presentation only:
no fight logic, goldens or hashes change.

## Bridge contract (both halves build against this)

### Swift -> Godot: `workshop_config` gains three optional keys

```json
{ "bot": {...}, "mode": "menu", "frame": 0.28, "screen": "menu" }
{ "bot": {...}, "mode": "workshop", "screen": "builder", "focus": "weapon" }
{ "bot": {...}, "mode": "workshop", "screen": "shop", "focus": "weapon" }
{ "bot": {...}, "mode": "menu", "screen": "board", "opponent": {...} }
{ "bot": {...}, "mode": "menu", "screen": "result", "cue": "win" }
```

- `screen`: which menu screen is in front of the stage. Known values and the picture each gets:
  `menu` (main menu: the machine large, left of centre, the bowl behind), `builder` (close, left,
  moving heads through haze behind), `shop` (the `focus` category close up, centre), `board`
  (the machine left, `opponent` across the floor on the right), `result` (the machine centred
  under the gate), `career`, `garage`, `workshop`, `scout`, `rewards`, `retry`, `events`,
  `ladder`, `replays`, `quick`, `settings`. Any other value, and an absent `screen`, is a generic
  framing that honours `frame` exactly as before. `mode` and `frame` keep their old meaning.
- `focus` (existing key): on `shop` and `builder`, the category the camera favours (`weapon`,
  `drive`, `armour`, `chassis`, `utility`, `paint`). The shop pulls it out of the machine as the
  director's `part` shot always did.
- `opponent` (existing key): on `board`, the opponent machine across the floor.
- `cue`: `"win"` on the result screen after a win. Fires the win pyro once when the screen
  becomes `result`; re-sends of the same payload never refire it.

Arrival pyro fires by itself when the screen changes to `menu`, `board` or `result` (the screens
that see a launcher), never more than once in 8 s, never looping.

### Godot -> Swift: `stage_anchors`

Where the parts the leader lines point at are on screen, in the Godot view's own normalised
coordinates (0,0 top left, 1,1 bottom right of the full view, which fills the window ignoring
safe areas):

```json
{ "screen": "menu", "settled": true,
  "hero": [0.08, 0.30, 0.50, 0.78],
  "points": { "centre": [0.29, 0.55], "top": [0.30, 0.40], "weapon": [0.43, 0.66],
              "opponent": [0.78, 0.52] },
  "parts": [ { "key": "wheel_fl", "kind": "wheel", "at": [0.21, 0.70], "near": true },
             { "key": "armour_top", "kind": "armour", "at": [0.30, 0.42], "near": true },
             { "key": "weapon", "kind": "weapon", "at": [0.43, 0.66], "near": true } ] }
```

- `hero` is the machine's projected bounding box (x0, y0, x1, y1).
- `parts[].key` is the Bot's `part_key`, the same keys a fight result's `parts_lost` and the
  condition report use (`wheel_fl`, `wheel_rr`, `armour_front`, `armour_top`, `weapon`,
  `chassis`, ...). `near` is true when the part is on the camera's side of the machine: point a
  leader only at near parts.
- `opponent` is only present on `board`.
- `settled` is false while the camera is moving between screens (hide or fade the leaders) and
  true once it has arrived. Sent once on arrival, then again whenever any point moves by more
  than 0.004 (turntable, orbit, drift), at most 10 times a second.
