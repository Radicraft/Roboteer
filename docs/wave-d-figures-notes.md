# Wave D figures: Saira with tabular figures replaces B612 Mono (2026-09-30)

Decision 7 (docs/aaa/decisions-2026-09-30.md): B612 Mono's fixed pitch put a full cell after ".",
":" and "," ("89. 5 kg", "2: 58", "1, 200", "3. 1" on the judges card). All figures move to the UI
face with tabular figures. Branch `wave-d-figures`, worktree `/Volumes/RoboteerBuild2/Code/Roboteer-figs`.
Page: `docs/look/figures.html` (images in `docs/look/figures/`).

## The face

- The shipped Saira Semi Condensed statics were Google Fonts' `ofl/sairasemicondensed`, v0.072:
  GSUB has `aalt case ccmp dnom frac liga locl ordn salt sups titl zero`, no `tnum`.
- The family's current release, Omnibus-Type/Saira v1.101 (commit c9d45ed, `Saira/fonts/ttf/`),
  is what Google builds its variable `ofl/saira/Saira[wdth,wght].ttf` from. Its SemiCondensed
  statics add `lnum onum pnum tnum sinf subs numr ss01 ss02`, keep the PostScript names
  (`SairaSemiCondensed-Bold`, `-Medium`) and the vertical metrics (1135 / -439), and move advance
  widths by 0.3 % on average. Tabular figures 0.553 em (Bold), point / colon / comma 0.269 em.
- So: no second family. Both static files swapped for v1.101 (unmodified, OFL 1.1, no reserved font
  name in that release; `OFL-SairaSemiCondensed.txt` is its licence), and figures are the Bold file
  with `tnum` on. Checked on CoreText (1111 and 8888 both 221.2 at 100 pt with `tnum`, 139 / 234
  without) and in Godot (ui_test).
- B612 Mono earned no place: there are no part codes in the UI; its only code-like use was the menu
  row numbers "02 / 03 / 04", which read fine in Saira. Removed from `Roboteer/Fonts`,
  `Arena/assets/fonts`, `UIAppFonts`. Net about -0.21 MB over app + pack.

## What changed

- Swift `Roboteer/DesignSystem.swift`: `BroadcastType.figureFont(size:)` (the Bold face plus
  `kCTFontOpenTypeFeatureTag "tnum"` via `UIFontDescriptor.featureSettings`) backs the `.numerals`
  role; system fallback is condensed bold `.monospacedDigit()`. `figureGrowth = 1.09` (Saira figures
  0.696 em tall, B612's 0.758): `scale(.numerals)` = 0.8 x 1.09 and `exact(.numerals)` x 1.09, so
  every readout stands as tall as before and every string is narrower. `faces` no longer lists a
  numeral file. `Blueprint.mono` renamed `Blueprint.figures`; `monoKern` (-0.03 em for the mono)
  deleted with its seven call sites. New `Blueprint.inlineFigures(px)` for a figure inside a
  sentence (words' own size: shop "Level 20", bracket record, match report tally, MoneySentence).
- Saira's line box (1.574 em) is taller than the mono's (1.215 em), which grew every figures-only
  line by up to half its size: the garage's second machine lost its parts line at 874 x 402, the
  judges card lost its verdict line, the builder list lost a row. New `View.figureLine(size,
  exact:)` pads a figures-only line back to the mono's box (top 0.25, bottom 0.21 of the drawn
  size; glyphs untouched). Applied in ScoreBug, ScrapBadge, the mass gauge, the title block, the
  payout and ledger rows, StageStat, the judges card scores, the builder and shop stat footers, the
  rewards and result-sheet banked totals, and every standalone `Stage.numerals` Text (ladder,
  events, career home, garage, workshop, replays, scouting, builder).
- Godot `Arena/ui/broadcast.gd`: `FONT_FILES["numerals"]` is the label file; `_font("numerals")`
  wraps it in a `FontVariation` with `opentype_features {tnum: 1}` (`NUMERAL_FEATURES`).
  `NUMERAL_PT` 24 -> 26, `CLOCK_PT` 38 -> 41 (same figure height as the mono). `kit_screen.gd` clock on
  `Broadcast.font_numerals()` at 33 x s (was 30). `tape_card.gd` values on the figures face.
  `broadcast_theme.tres` comment. `tests/ui_test.gd`: figures tabular, colon and point under 0.6 of
  a digit, figures = a FontVariation over the label face.
- New QA script `Arena/qa/figures_capture.gd` (clock 2:58 + scrap 1280, 0:10 + 45, POWER DOWN, KO
  count, judges result).
- Docs: `docs/third-party-fonts.md`, `docs/design-system.md` (type now), `docs/look/figures.html`.
- Merged main 3a3b23a (Marshal, POWER DOWN) before the final captures.

## Verification

- Godot, HEADLESS=1, after the merge: ui_test 383/0, fx_test 189/0 (2 skipped), commentary_test
  245/0, walkout_test 88/0, intro_test 71/0.
- `scripts/build-sim.sh`: BUILD SUCCEEDED (pck re-exported, 89.5 MB, never committed).
- Career self test on the final build (Figs 17 Pro sim, dummy/headless): ALL PASS, 1098 checks,
  2 warnings (the known pacing ones). Sim shut down.
- Captures, both widths (Figs 17 Pro 874 x 402, Figs 17 Pro Max 956 x 440, headless, over the
  menus' stage renders): menu, builder, shop, board, garage, match report win and judges, quick
  result sheet, rewards, ladder, quick fight card, settings, loading. HUD at both shapes in desktop
  Godot; walk-out card. Looked at every one beside its before: no clip, panel heights as before.
  Working files (captures, scripts, before app) in `/Volumes/RoboteerBuild2/Work/figs`.

## Known, left

- Quick fight card at 874 x 402 now sits at its 16 pt margin; before it overflowed the phone by a
  line (so "One on one." showed). The Rumble line now scrolls inside the list like the House bot row.
- Quick fight result sheet: the two machine plates under the judges card are thin strips at both
  widths, before and after (pre-existing, not a figures change).
- Baked textures: the kit and decal textures carry Barlow as pixels (wave B); none has B612 figures.
  Nothing re-baked.
- HUD shapes the coordinator asked to note, not fix: the clock bug and the scrap bug have a cut
  top-right corner; the name lower thirds and the POWER DOWN / sting band have slanted ends.
- Numbers inside sentences that do not go through a figures helper use Saira's proportional
  figures; they have no punctuation gap either way.

## Where I stopped (2026-09-30)

Done and committed on `wave-d-figures` (not pushed, not merged). Next, if wanted:
1. Merge to main (the only conflicts to expect are in DesignSystem.swift if another branch touched
   the type helpers or renamed `Blueprint.mono` call sites; any new `Blueprint.mono(` becomes
   `Blueprint.figures(`, any new `monoKern` goes).
2. On device: glance at the fight clock ticking and the scrap counting up for jitter (tabular, so
   none expected).
3. Two sims were created for this work ("Figs 17 Pro" 8E7D455B, "Figs 17 Pro Max" 6A6F6CF0),
   both shut down; delete with `xcrun simctl delete` when no longer needed.
