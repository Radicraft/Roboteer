# Wave E HUD plates: upright, uncut, unstroked (2026-10-01)

The owner's standing rule (docs/design-system.md section 0): no skewed, slanted, cut or stroked
accents anywhere ("reads as Claude design"). The fight feed still had them, noted but not fixed in
wave D (docs/wave-d-figures-notes.md, "Known, left"): the clock bug and the scrap bug had a cut
top-right corner, the name lower thirds, the POWER DOWN / stage sting band, the intro card and the
result banner had slanted ends. Branch `wave-e-hud`, worktree
`/Volumes/RoboteerBuild2/Code/Roboteer-hud`. Page: `docs/look/hud-plates.html` (images in
`docs/look/hud-plates/`).

## What changed

Godot (`Arena/`):
- `ui/broadcast.gd`: ONE plate drawer, `draw_plate(ci, rect, pt, alpha, fill, wash, grid)`: the fill,
  an optional wash, the graph paper (`draw_grid`) and the soft top light (`_draw_top_light`), fills
  only. `panel_points` is a plain four-point rectangle. `draw_panel`, `draw_lower_third`,
  `draw_score_bug` and `draw_pill` all call it, signatures kept. `CUT`, `SKEW_DEG` and `skew()`
  deleted (nothing else used them; checked main and `wave-d-fitment2`). New tokens: `PLATE`
  (rgba 14, 58, 140 at 0.82, direction A's HUD echo, docs/look/menus-blueprint.html `.hud .plate`),
  `PLATE_SOLID` (0.92, the walk-out card), `PLATE_DANGER` (#B8352A at 0.88, the blueprint
  `--dangerbg`), `DANGER_ON_PLATE` (#FF7A66, `--danger`), `GRID_MINOR` / `GRID_MAJOR` / `GRID_STEP`.
  `BAR` kept as an inset only, so the names and condition bars inside the plates do not move.
- The graph paper starts ONE STEP IN from the top and left edges (a bright major line used to sit
  on both, which read as a frame). Same change in Swift `BlueprintGrid`.
- `ui/hud.gd`: clock and scrap bugs plain blue plates (no wash); the urgent clock's numerals and the
  knockout count in `DANGER_ON_PLATE` (new `COL_URGENT_ON_PLATE`; `COL_KO` now that colour), because
  #E5483C on the blue is 2.2:1 and #FF7A66 is 4.1:1. POWER DOWN, ENDGAME and the stage stings on
  `PLATE_DANGER` with white words; a payoff on the blue plate with its words in scrap amber
  (`_sting_word_colour()` replaces `_sting_accent()`). Result banner, readout plate, name plates:
  the blue plate. Every rectangle is the one `_relayout` already computed: nothing reflows.
- `ui/intro_overlay.gd`: the card is an upright plate (the lean's extra width dropped, so its
  padding is even both sides; title and sub now share a left edge), blue, or the danger plate with
  white words for a hazard.
- `ui/tape_card.gd`: draws through `Broadcast.draw_plate` (gains the top light; grid off the edges).
- `arena/kit/kit_screen.gd`: the venue big screen's 3 px gold rule over the name strip is deleted;
  the strip is `PLATE_SOLID` with a soft top light (a GradientTexture2D, white 7 % to 0).
- `tests/ui_test.gd`: the cut/lean checks replaced by: a plate is a four-point upright rectangle at
  1x and 2x; `CUT`, `SKEW_DEG`, `skew()` are gone; plate colours; danger type on the plate and white
  on the danger plate clear 4:1; every plate drawer's source has no draw_line / polyline / arc /
  multiline. The urgent timer check reads `COL_URGENT_ON_PLATE`.
- New QA script `qa/hud_plates_capture.gd` (fight, clock-low, power-down, stage-sting,
  payoff-sting, ko-count, result-judges, coach, intro-card, intro-hazard, walkout-card,
  walkout-compact, big-screen, big-screen-sting; `--hud-safe=l,t,r,b`).

Swift (`Roboteer/`):
- `CutRect` and `LowerThirdShape` were already plain rectangles behind `Blueprint.cutsCorners` /
  `Blueprint.skews` = false. Both shapes, both switches and `Stage.skew` are DELETED; the one shape is
  `PlateRect` (InsettableShape, plain rectangle), 51 uses in 19 files. `LowerThird.leanInset`
  renamed `leadingInset`, same values (no reflow). Comments that described a chamfer or lean fixed.
- BuilderView: the name field is a bare TextField over the stage, no plate; the CutRects there were
  the thickness chips and the livery rows. Now `PlateRect()`.
- Visible Swift change: only the grid moving off the top and left plate edges.

Docs: `docs/design-system.md` sections 0, 1 (spacing), 2 (panel, lower third, score bug).

## Kept on purpose (functional, not decorative)

- Gauges that fill: condition bars, the weapon spin-up ring and gas pips, the boost charge ring.
- Legibility outlines over the live arena: YOU tag and off-screen arrow (ink polyline), the
  OUTLINED_LABELS (countdown, result title and winner, KO count and prompt, pad hints), the big
  screen sting word's black outline.
- Coach leader lines, the workshop test overlay's diagram strokes; in Swift the blueprint leader
  lines, dimension ticks, table rules, the emblem and glyph strokes (diagram content).
- `BlueprintHatch` on locked things: a state texture, not an edge.
- The ticker strip (ink 90 %) and the touch discs (glass): a strip and round thumb furniture.

## Verification

- HEADLESS=1: ui_test 395/0, fx_test 189/0 (2 skipped), intro_test 71/0, walkout_test 88/0,
  commentary_test 245/0, marshal_test 42/0. Full suite (`HEADLESS=1 JOBS=4`): 51 test files, 0 failures.
- `scripts/build-sim.sh`: BUILD SUCCEEDED (pck re-exported, never committed).
- Career self test (HUD 17 Pro sim, dummy driver): ALL PASS, 1098 checks, 2 warnings (the known
  pacing ones). Sim shut down.
- Captures: HUD in desktop Godot at 1748 x 804 and 1912 x 880 (874 x 402 and 956 x 440 at 2x, safe
  area 62 pt sides, 21 pt foot), before and after; Swift on "HUD 17 Pro" and "HUD 17 Pro Max" sims,
  headless over `-stageStill`, 13 screens each, before (Swift changes reverted) and after. Looked at
  every one: same rectangles, nothing reflowed or clipped. Working files in
  `/Volumes/RoboteerBuild2/Scratch/hud`.

## Known, left

- The knockout count's second line sits on the foot of its plate at both shapes (KO_PT x 3 is a
  little short for two lines of stencil). Pre-existing, same before; not resized here (no reflow).
- At 874 x 402 the judges banner covers the DRIVE label and the stick's top. Pre-existing.
- The HUD's grid sits behind the clock numerals; it is the mockup's look. If it reads busy on the
  phone, `draw_score_bug` can pass `grid = false` (one line).

## Where I stopped (2026-10-01)

Done and committed on `wave-e-hud` (not pushed, not merged). Next, if wanted:
1. Merge to main. Any branch that added a `CutRect(...)`, `LowerThirdShape`, `leanInset`,
   `Stage.skew`, `Broadcast.CUT`, `Broadcast.SKEW_DEG` or `Broadcast.skew(` will no longer compile /
   parse: replace with `PlateRect()`, `leadingInset`, or drop the lean.
2. On the phone: a glance at the blue plates over each arena and the red POWER DOWN band.
3. Two sims were created ("HUD 17 Pro" 4954295E, "HUD 17 Pro Max" 700C6479), both shut down; delete
   with `xcrun simctl delete` when no longer needed.
