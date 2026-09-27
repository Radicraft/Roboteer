# Wave B fonts: the Blueprint type swap (2026-09-27)

Owner decision: type system "01 Blueprint" (docs/look/fonts-options.html): Saira Stencil One
(display), Saira Semi Condensed 500/700 (UI), B612 Mono 700 (numbers). Credits:
docs/third-party-fonts.md.

## What changed

- Swift `Roboteer/DesignSystem.swift`: `BroadcastType` now has four faces. Every call site still asks
  for the old Barlow size; `BroadcastType.scale` draws display and numerals at 0.8 of it and the UI
  face at 0.94, never under the floors (label 11, others 13; `drawnSize`). `floorScale` and the
  `Stage.Tracking` helpers measure the drawn size. Label tracking 8 % (was 10), display +1 % (was -1).
  New `Stage.figure(text, size:)`: B612 Mono when the value is a figure, the label face when it is a
  word ("Arcade", "listed, not used"); used by ScoreBug, the setting/quick fight value cells, the
  builder figure cells, the stat line and the result sheet's score cells.
- `Roboteer/Info.plist` UIAppFonts, `Roboteer/Fonts/` (folder reference, no pbxproj change).
- Godot: `Arena/ui/broadcast.gd` FONT_FILES + new `font_numerals()`; tokens scaled (DISPLAY 60->48,
  TITLE 39->31, BUTTON 23->22, LABEL 17->16, BODY 21->20, NUMERAL 30->24, CLOCK 47->38);
  `hud.gd` KO 34->27, COUNTDOWN 96->77, clock and scrap bug on B612 Mono;
  `broadcast_theme.tres` (Saira SC Bold, 16); `arena/kit/kit_screen.gd` (stencil sting and tag,
  Saira names, mono clock, sizes x0.8); `tests/ui_test.gd` font check text + numerals role.
- Tools (`Tools/textures/make_decals.py`, `Tools/blender/arena_kit/make_kit_textures.py`) point at
  the new files (sizes x0.8); textures NOT re-baked, the shipped ones still carry Barlow as pixels.
- Barlow removed from both folders. Font files: 665 KB -> 441 KB per copy, so about -0.45 MB over
  app + pack; the re-exported pck went 97.58 MB -> 97.48 MB.
- `scripts/build-sim.sh` printed a STALE app path (`ls | head -1` over three DerivedData trees);
  now `ls -dt`. Install from the path it prints.
- New QA script `Arena/qa/type_capture.gd` (stamps every slam, KO count and results in a window).

## Verification

- `HEADLESS=1 JOBS=2 scripts/test-arena.sh ui_test fx_test commentary_test intro_test pacing_test
  stage_build_test`: 6 files, 0 failures.
- `scripts/build-sim.sh`: BUILD SUCCEEDED.
- Career self test: ALL PASS (1021 checks, 2 warnings) on A18A1779, BUT that run installed the
  stale app (see build-sim fix). Logic is untouched by this wave, still: re-run it on the new build.
- Captures (iPhone 17 Pro Max sim, 956 x 440, headless; desktop Godot 1206 x 556):
  `docs/look/fonts/built-{menu,garage,shop,report,loading,settings,builder,board}.jpg`,
  `built-hud-{slams,clock,countdown,ko-count,result-judges}.jpg`, `built-intro-furnace.jpg`.
  Looked at every one except the intro frame: no slam, title, name or number clips.

## Known looks, not clips

- B612 Mono is fixed pitch, so the point and the colon take a full cell: "89. 5 kg", "2: 58".
  That is the face; a -0.02 em number tracking (the review's value) is not applied anywhere yet.
- Match report part names at 11 pt wrap to two lines more often ("FOUR WHEEL / DRIVE"); that
  wrap is the designed fallback (QA 2026-09-25) and the panel still fits.
- Settings row names use `Stage.display(15)`, so they are in the stencil at 12 pt; legible.

## Where I stopped (2026-09-27)

Stopped on the coordinator's wrap-up call (owner at 98 % weekly usage). Committed as WIP.
Next steps, in order:
1. Re-run the career self test on the NEW build (A18A1779, muted, dummy/headless) and shut the sim.
2. Look at `docs/look/fonts/built-intro-furnace.jpg` (and the other intro frames from
   `Godot --path Arena --script qa/intro_capture.gd -- --intro-shots=DIR --intro-arenas=furnace`)
   for the machine names on the intro overlay; not yet checked by eye.
3. Capture the 874 x 402 width (iPhone 17 sim) for the menu, garage, match report and loading
   column; only 956 x 440 was checked.
4. Screens not captured: rewards, retry prompt, unlock, events, ladder, replays, scouting, quick
   fight card, workshop, onboarding coach overlays in a fight. Check them for clipping.
5. Decide whether to re-bake the kit and decal textures in the new faces (owner call).
6. Commit Roboteer/ResultSheet.swift's one-line `Stage.figure` hunk if it was left out (the file
   also carries the judges agent's work), and the pck is never committed.
