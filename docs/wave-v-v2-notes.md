# Wave V, agent V2: the fight feed in Broadcast

What changed, what it looks like now, what is still owed. The system itself is
`docs/design-system.md` (sections 1 to 4 are the ones this agent implements) and
`docs/brief-v4-playtest.md` section 7.

Files: `Arena/ui/broadcast.gd` (new), `Arena/ui/broadcast_theme.tres` (new),
`Arena/ui/hud.gd`, `Arena/ui/controls.gd`, `Arena/tests/ui_test.gd`, plus two stale
layout assertions in `Arena/tests/commentary_test.gd` (see "the one file I did not own").
`Arena/project.godot` was NOT touched: the theme is applied in code, so agent R's file
stays agent R's.

## 1. One place for the system

`Arena/ui/broadcast.gd` is a `class_name Broadcast` of static tokens and static drawing
helpers. Nothing in the feed invents a colour, a size or a shape any more:

- **Colours:** `INK GLASS GLASS_LIVE GLASS_EDGE LINE LINE_DIM TYPE TYPE_DIM SCRAP DANGER
  WIN`, the exact hex values of the design system (the test asserts three of them byte for
  byte, so a drift is a failing check, not a subjective argument).
- **Type:** `DISPLAY TITLE BUTTON LABEL BODY NUMERAL CLOCK` and a `TYPE_FLOOR_PT`.
- **Spacing:** `GRID PANEL_PAD GAP GUTTER CUT SKEW_DEG BAR TICKER_H CONDITION_H EDGE_GLOW`.
- **Motion:** `ENTER_S EXIT_S SLAM_S SLAM_HOLD_S SLAM_OUT_S COUNT_S`.
- **Shapes:** `draw_panel`, `draw_lower_third`, `draw_score_bug`, `draw_rule`,
  `draw_ticker`, `draw_condition`, `draw_pill`, `draw_edge_glow`, `draw_disc`,
  `draw_text`, plus `panel_points` and `skew` as pure functions so the geometry can be
  asserted without a frame.

**Units.** The design system quotes points on a 402 pt tall phone. The arena's design
space is 1206 x 556 (`REF_SIZE_PT`), which is the same screen 1.383 times over, so every
size in `broadcast.gd` is the system's iOS point value times `PT_PER_IOS` and is then
multiplied by the HUD's `_pt` (1.0 at the design size, 2.0 on the phone). Label type is
17 arena units = 12 iOS pt; the legibility floor of 11 iOS pt is `TYPE_FLOOR_PT` 15.

**The font.** Agent V1 landed Barlow Condensed in `Arena/assets/fonts/` (Bold,
ExtraBold, ExtraBoldItalic, Medium, plus `OFL.txt`), so the three roles load those files
by name and nothing else: `font_display()` is ExtraBoldItalic, `font_label()` Bold,
`font_body()` Medium. If a file is somehow missing the role returns null and the caller
falls back to the engine face rather than drawing nothing; `Broadcast.fonts_found()`
reports which way it went and `ui_test` asserts all three resolve.

**The theme.** `Arena/ui/broadcast_theme.tres` names Barlow Condensed Bold as its
`default_font` (by uid and path) and carries the label size and the Label colours, so it
is the single source for anything unstyled. `Broadcast.theme()` only injects a face if the
resource somehow came back without one. `hud.gd` puts that theme on `Root`, on both
overlays and on `FightControls`, so any Control anyone adds to the feed later is already
in the system. The test reads the `.tres` past the resource cache
(`CACHE_MODE_IGNORE`) to prove the FILE carries the face, not just the code.

## 2. The feed (`hud.gd`)

Behaviour is untouched. Every public method, every node name under `Root`, every
constant another test names and every timeline is the same; only the drawing and the
placement are new. The drawn chrome lives on one `Chrome` Control which is the FIRST
child of `Root`, so every label sits on its own plate and nothing had to be reordered.

| Thing | Before | Now |
|---|---|---|
| Clock | a 40 pt number top centre | a score bug (`CLOCK_BUG_PT` 168 x 62) top centre, numerals 47, `line` rim, going `danger` under ten seconds |
| Phase | nothing | the word under the bug: OPEN in `typeDim`, ENDGAME in `danger`, new `set_phase()` / `phase_word()`. The sting sets it, and `set_bot_names` (once per fight) puts it back to OPEN, so a second fight never opens in endgame red |
| Names | one "A vs B" line | two lower thirds, player top left (`Names`), opponent top right (`Opponent`), 12 degree skew, 3 pt `line` leading bar |
| Condition | nothing | a 3 pt rule under each name, `line` for the player, `typeDim` for the opponent, `danger` under 25 %. New `set_condition()` / `condition()` |
| House bot | nothing | its name under the opponent's third, in `danger`, while it is out (`HouseBot`) |
| Scrap | "SCRAP 120" in gold | a score bug beside the reserved corner: the word drawn on the plate in `typeDim`, the numerals alone in `scrap`, counting over 0.4 s |
| Pause | "PAUSED" under the clock | the same, in label type under the phase word. The design system's "pause glyph, top right" is the SHELL's button; the feed keeps `CORNER_RESERVE_PT` clear for it, which is the rule that stopped the counter reading "SCRA" |
| Commentary | one centred line under the names | the ticker along the bottom: an `ink` 90 % full-width strip, label type, one line sliding in from the right edge over 0.28 s |
| ENDGAME | a 72 pt stamp that scaled in | a full-width lower third that slams in from the left in 0.12 s, holds 1.2 s, leaves right in 0.18 s, with a `line` flash across the ticker. New `endgame_slide()` |
| Knockout count | gold text | `danger` type on a glass panel with a `danger` rule under it |
| Result | gold winner line | a full-width lower third sweeping in from the left, display type title, `type` winner line |
| Height readout | bottom centre | the row above the ticker, body type on a glass plate sized to the sentence |
| Zone warning | four red bars plus a drawn name | the design system's 6 pt `danger` inner-edge glow (four nested bands, no shader), and the name goes to the TICKER, pushed once per entry |
| Coach callouts | outlined white text | label type on glass pills with the same `lineDim` leader lines |
| Off-screen arrow, YOU tag | white | `type`, unchanged shapes |

New public API, all additive and all defaulting to what an unwired rules layer means:
`set_phase` / `phase_word`, `set_condition` / `condition`, `set_house_bot` /
`house_bot_out` / `house_bot_name`, `endgame_slide`, `commentary_slide`, `ticker_rect`.

Two of those wire themselves without `fight.gd` having to change: `set_zone_warning`
already carries the house bot's name, and the commentary line `HOUSE BOT OUT` already
arrives from `commentary.gd`, so the feed can name the house bot under the opponent's
lower third today. `clear_commentary` (a new fight) clears it again.

### The one judgement call on the ticker

The strip is drawn at the line's own alpha, so it is on screen exactly while there is
something to say, roughly 1.85 s per line. A permanent plate along the bottom would sit
over the bottom of the stick well (the HUD is `CanvasLayer` layer 2 and `Controls` is a
plain Control on layer 0, so the HUD always draws over the furniture), and the stick is
the control the owner already had trouble finding. Design system section 2 still gets
its full-width `ink` 90 % strip; it just is not there when nobody is talking.

## 3. The touch controls (`controls.gd`)

Drawing only. Every geometry constant is untouched: `STICK_ZONE_FRACTION`,
`STICK_BASE_PT`, `STICK_KNOB_PT`, `STICK_THROW_PT`, `PRIMARY_DIAMETER_PT`,
`SECONDARY_DIAMETER_PT`, `EDGE_MARGIN_PT`, `STICK_HOME_INSET_PT`, `SECONDARY_OFFSET_PT`,
`HIT_SLOP` all read exactly as they did, so every hit test and every coach anchor is
where it was.

- Stick well: a `glass` disc with a `lineDim` rim and a `line` knob, and the throw ring
  is now drawn as a `lineDim` hairline at `STICK_THROW_PT`, so how far the thumb has to
  travel for full throttle is visible instead of learned.
- The drive pulse ring stays, in `line`.
- Primary: a `glass` disc with a `line` rim; pressed fills `line` at 30 %. The face is
  the weapon glyph from `res://assets/ui/glyph_weapon_<id>.svg`, modulated to `type`, and
  the weapon's WORD when there is no file. Agent V1's ten landed during this session and
  all ten resolve.
  **The glyph is named for the PART id, not the kind** (`glyph_weapon_horizontal_spinner`
  for kind `spinner`, `vertical_spinner` for `drum`, `full_body_spinner` for `fbs`,
  `flamethrower` for `flame`), and this node only knows the kind, so the two are matched
  by inverting `PartsCatalogue.parts()["weapon"]` once (`weapon_glyph_id()`). No second
  hand written table to drift, and an eleventh weapon gets its glyph for free.
- Secondary: the same disc at its own size. `utility_glyph_id()` is `srimech` when the
  bot is inverted, which is a drawn glyph, and `pivot`, which is not, so an upright bot's
  button says the word PIVOT.
- `Arena/assets/ui/stick_well.svg`, `stick_knob.svg` and `button_ring.svg` are
  deliberately NOT used, and it is worth saying why out loud: opened up, they are a
  stroked circle, a filled circle and two concentric circles on a 64 px grid. Design
  system section 6 is explicit that panels, bugs, rules and buttons are drawn and never
  bitmaps, and a 64 px ring rasterised up to a 240 px stick well on the phone is a blurry
  ring, where `draw_arc` is exact at any size, takes its weight and colour from the tokens
  and tints with the 62/90 alpha for free. The glyphs, which are real artwork, ARE used.
  `glyph_pause.svg` is not used here either: the pause button is the shell's, and the feed
  keeps its corner.
- Alpha over the arena: 62 % at rest, 90 % on the control under the thumb. This is a
  multiplier inside `_c()`, so `draw_alpha()` still means only the countdown's dimming
  and the existing preview tests are untouched.
- Pad hints are the HUD's and are now label type.

## 4. Both renderers

Nothing added here is a shader, a texture, a `CanvasItem` material or a renderer
feature: every shape is `draw_colored_polygon`, `draw_rect`, `draw_line`, `draw_arc`,
`draw_circle`, `draw_polyline`, `draw_texture_rect` or `draw_string`. That is identical
on Forward+ (device), gl_compatibility (simulator) and the dummy renderer the headless
suite runs, which is why the suite exercising `_draw` is worth anything at all.

## 5. Verification

```
Godot --headless --path Arena --script tests/ui_test.gd          # 372 checks, 0 failures
                                        workshop_test.gd         #  86 checks, 0 failures
                                        commentary_test.gd       #  82 checks, 0 failures
                                        enforcer_test.gd         #  78 checks, all passed
                                        fight_shape_test.gd      #  34 checks, 0 failures
                                        test_arena_runs_test.gd  #  24 checks, 0 failures
```

`ui_test.gd` grew from 298 to 372 checks. The new sections are `_test_broadcast_tokens`
(the theme resource and the face it names, the font per role, three colours by hex, the panel's single cut corner and
its scaling, the 12 degree lean measured against `tan`, the type floor, the 0.4 s count,
the optional glyph), `_test_feed_layout` (the chrome is child 0 and touch-proof, the
clock is centred, the phase word is under it, each machine has its own third on its own
side, nothing of the top right reaches the reserved corner, the scrap bug is numerals
alone, the ticker is full width on the bottom safe area, the condition pair clamps, the
house bot appears from the zone name plus the commentary line and clears on a new fight,
no label is under the legibility floor), `_test_ticker` (a line starts off the right
edge, is home after `TICKER_SLIDE_S`, never moves off its row, and the old hold-and-fade
timeline is undisturbed), `_test_endgame_slam` (starts at slide -1, arrives inside
`SLAM_S`, phase word turns danger red) and `_test_feed_draws` (every plate, bug, bar,
pill, strip, sting and glow drawn in one frame, then the urgent clock, the countdown and
the result banner, then the controls at both alphas, pressed and not, for four weapons,
then every weapon kind's glyph id against the catalogue and both utility ids).

The whole suite, run after everything above landed:

```
sh scripts/test-arena.sh     # 27 of 28 test files pass
```

The one failure is `ai_physics_test.gd` ("regional: 2 unpushed hazard entries in yard"),
which belongs to the agent working in `Arena/ai/opponent_ai.gd` and the new
`Arena/ai/context_steering.gd`. Nothing in `Arena/ui` is in its path. Every other file,
`ai_test.gd` included, is green.

### The screenshots that could not be taken

`Arena/qa/shots.gd` saves `vp.get_texture().get_image()`. Under `--headless` Godot forces
the DUMMY rasterizer, whose texture storage returns nothing: the capture errors with
`Parameter "t" is null` and hands back a 0 x 0 image, for the root viewport and for a
`SubViewport` alike. `--display-driver headless --rendering-driver opengl3` does not help;
the headless display driver takes the dummy rasterizer with it. So there are **no PNGs of
the new feed**: a picture needs a window or a device, and this session was not allowed
either. What was done instead is numbers, printed from the real layout pass at both sizes
(safe areas as a phone gives them):

```
2412 x 1112, pt 2.0      clock bug (1038,44) 336x124   scrap bug (1830,44) 312x116
                         player third (162,44) 660x100  opponent third (1590,182) 660x100
                         ticker (0,1010) 2412x60        readout (162,921) 2088x67
                         reserved corner (2166,0) 128x128
874 x 402, pt 0.72       clock bug (376,16) 121x45      scrap bug (706,16) 113x42
                         player third (16,16) 239x36    opponent third (619,66) 239x36
                         ticker (0,359) 874x22          reserved corner (828,0) 46x46
```

Someone with a Simulator or the owner's phone should look at one frame of a real fight
before this is called done. The thing to look at first is the ticker crossing the bottom
of the stick well while a line is up.

## 6. The one file I did not own

`Arena/tests/commentary_test.gd` asserted the wave G layout: "the line is below the names
row" AND "above the knockout count". The second one is the strap's old home under the
names; the design system puts the ticker along the BOTTOM, so it cannot hold and no
layout satisfies both. The wave G HUD's own comment said the strap would become the
broadcast ticker in wave V. I changed those two assertions to the new contract (below the
names row, below the knockout count, inside `ticker_rect()`) and left everything else in
that file alone. It is the only edit outside the files V2 owns and it is worth a glance
from whoever owns the commentary layer.

## 7. Owed, and left for others

- **A glyph for the pivot.** Everything else on the two buttons is a glyph now; an
  upright bot's secondary still reads the word PIVOT because there is no
  `glyph_utility_pivot.svg`. One 64 px file and it is a glyph, with no code change.
- **Condition bars are decorative until the rules layer calls `set_condition`.** They read
  full. `fight.gd` is not this agent's file; one call per presentation frame from the two
  machines' damage state is all it needs.
- **`set_house_bot` should be called properly by the rules layer** when the house bot is
  released and when it is recovered. Until then the feed infers it from the corner warning
  and the `HOUSE BOT OUT` commentary line, which means the name only appears once one of
  those has happened.
- **The countdown has no plate.** It is 96 pt display type with an outline in the middle
  of the frame; a bug behind it would have to scale with the tween, and a scaling panel is
  not in the system. Left as type on the arena.
- **Not mine, failing at the end of this session:** one check in `ai_physics_test.gd`
  (hazard entries in the yard), from the agent working on `Arena/ai/opponent_ai.gd` and
  `context_steering.gd`. Earlier in the session `ai_test.gd` (3 checks, then 2) and
  `commentary_test.gd`'s two crowd bus checks (`Arena/fx/audio_mix.gd`) were red for the
  same reason; both went green as their agents landed. Nothing in `Arena/ui` is in any of
  their paths.

## 8. A warning about running the suite right now

Several wave V agents share this machine and this scratchpad, and more than one of them
runs `scripts/test-arena.sh` at the same time. Two things follow. The script begins with
`--import`, so concurrent runs rewrite `Arena/.godot` under each other; and in one full
run 20 of 25 test files reported their own `PASS ... 0 failures` and then exited **97**,
which the same test re-run on its own does not do (exit 0). Read a suite verdict taken
during a busy session as a concurrency artefact until each failing file has been re-run
on its own. Every test named in section 5 was re-run alone, serially, and every one of
them exits 0.
