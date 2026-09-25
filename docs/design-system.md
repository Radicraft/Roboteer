# Roboteer design system: Broadcast

The one visual system for every screen, the fight HUD and the touch controls. Chosen by the owner
on 2026-09-16 from four boards (`docs/look/`, this one is `b-broadcast.webp`). The idea: the game
presents itself as a televised championship. Menus are the broadcast package, the fight is the
live feed, the career is the season coverage. Everything below is a rule, not a mood.

## 0. OWNER RULE: no line accents (2026-09-21, restated 2026-09-24, enforced 2026-09-25)

"I don't like the line accents on the menu buttons as it's too much like Claude design."

- **No coloured edge strokes, leading bars, diagonal accent lines, outline frames or coloured
  underlines** on any button, card, panel, chip, tile or selected row, anywhere in the app.
- **Emphasis comes from weight, fill, type, the chamfered shape and light.** The primary call to
  action is a solid bright plate (`primaryFill`) with `ink` type. A selected row, segment or tier
  word sits on a `selectedFill` wash. A plate reads as raised through `topLight`, a soft gradient
  across its top, never through a line round it. A chosen picture (arena card, paint tile) is lit,
  the others sit back dimmer.
- **Dividers are neutral**: `divider` (white at 8 %), 1 px, between sections of one panel only.
  Never cyan, never under a heading as decoration.
- In Swift there is no stroke on a plate: `PanelChrome`, `LowerThird`, `BroadcastButtonStyle`,
  `ScoreBug`, `PartRow`, `StageSegments`, `SlotCell`, `TierLine`, `TextLink`, `ArenaCard`,
  `ArenaBand`, `PortraitPlate` and `LiverySwatch` all carry their state in fill. The old
  `LowerThirdBarShape` is deleted. A new component that needs `strokeBorder` or a thin coloured
  `Rectangle` to say "selected" is wrong: use `Stage.selectedFill`.
- Where the older sections below still mention a bar, rim, hairline or underline, this section
  wins. The Godot feed follows it too (2026-09-25): `Arena/ui/broadcast.gd` plates carry a
  per-vertex top light and no edge, lower thirds lose the bar (a colour given is a fill wash),
  score bugs wash instead of rim, the ticker has no top rule, the KO plate washes danger, and
  `controls.gd` discs lose every rim (lit inner disc instead; the throw ring is a faint disc, the
  drive pulse a fading glow). Kept on purpose: the spin-up ring and gas pips (gauges that fill),
  the ink outline on the YOU tag and off-screen arrow (legibility, not colour), the coach leader
  lines, and the workshop test overlay's diagram strokes.

## 1. Tokens

Colours (sRGB hex; Swift `DesignSystem.swift` and the Godot theme both define exactly these names):

| Token | Value | Use |
|---|---|---|
| `ink` | #07090C | page and fight backdrop behind glass |
| `glass` | #0E1218 at 82 % | panel fill; over the live arena 62 % |
| `glassEdge` | #FFFFFF at 10 % | kept for the old name only; no plate is outlined (section 0) |
| `line` | #35D6F0 | selection sweep fill, fill bars (weight, level, condition), accent WORDS; never an edge |
| `lineDim` | #35D6F0 at 45 % | dim fill bars; never a rule or a rim |
| `selectedFill` | #35D6F0 at 22 % | the selected row, segment, tier word or focused link |
| `primaryFill` | #F4F6F8 | the one primary button's solid plate, `ink` label |
| `topLight` | white 7 % to 0, top to centre | the light across the top of every plate |
| `divider` | #FFFFFF at 8 % | the only rule: 1 px, between sections of one panel |
| `type` | #F4F6F8 | primary text |
| `typeDim` | #9CA6B2 | secondary text, labels, units |
| `scrap` | #F0B23A | scrap numbers, purse, the only warm chrome colour |
| `danger` | #E5483C | damage, zone warning, losing states, quit |
| `win` | #5BE38F | won states only, never chrome |

No other hue appears in chrome. Livery colours belong to machines, never to panels.

Type: **Barlow Condensed** (SIL OFL, from Google Fonts), bundled in the app (`Roboteer/Fonts/`)
and in the arena (`Arena/assets/fonts/`). Weights: 800 Italic for display, 700 for labels, 500
for body, 700 tabular for numerals.

| Role | Face | Size (pt on a 402 pt tall phone) | Case | Tracking |
|---|---|---|---|---|
| Display | 800 Italic | 44 | CAPS | -1 % |
| Title | 800 Italic | 28 | CAPS | -0.5 % |
| Button | 700 | 17 | CAPS | +6 % |
| Label | 700 | 12 | CAPS | +10 % |
| Body | 500 | 15 | sentence | 0 |
| Numerals | 700 tabular | 22 / 34 (clock) | | 0 |

Spacing: 4 pt grid. Panel padding 12 pt. Gap between panels 8 pt. Screen gutter 16 pt plus the
safe area. Corner cuts 10 pt. Skew for lower thirds 12 degrees, always leaning right.

## 2. Shapes

- **Panel:** `glass` fill with `topLight`, one cut corner (top-right) at 10 pt. No edge, no bottom hairline. Never a rounded rectangle.
- **Lower third:** a plate skewed 12 degrees, no bar and no outline; a result banner takes its colour as a wash in the fill (`win`, `danger`). Used for names, the next-fight card header, the result banner, every stat strip.
- **Score bug:** a small non-skewed plate, numerals inside, a `label` above; the live one is filled with `line` at 24 %, never rimmed. Used for scrap, the fight clock, the tier badge.
- **Button:** a lower third with no bar and no outline. Primary: a solid `primaryFill` plate with an `ink` label, 1.5x the height of secondary. Ordinary: `glass` with `topLight`, `type` label; focused = the fill sweeps to `line` at 24 % from the leading edge; pressed = fill `line`, label `ink`. Danger: a `danger` wash in the fill and a `danger` label. No focus ring.
- **Ticker:** a full-width strip 22 pt tall on `ink` at 90 %, `label` type in `type`, text slides left to right in from the right edge, one line at a time. Fight commentary and season news live here.
- **Rule:** 1 px `divider` (neutral), never thicker, never a box, never coloured.

## 3. Motion

- Lower thirds enter from the edge they belong to, 0.25 s ease-out, exit 0.18 s ease-in.
- Selection is a sweep of `line` fill from the leading edge, 0.15 s. Never scale, never bounce.
- The ticker scrolls at 120 pt/s; a new line waits for the previous to clear.
- The ENDGAME sting: a full-width lower third slams in from the left in 0.12 s, holds 1.2 s, exits right in 0.18 s, with a `line` flash across the ticker.
- Numbers count (scrap, purse) over 0.4 s.

## 4. The fight feed (Godot, `hud.gd` and `controls.gd`)

Layout on a 402 pt tall landscape phone, safe area respected:

- **Top centre:** the clock as a score bug (numerals 34), the phase word under it as a label ("OPEN", "ENDGAME" in `danger`).
- **Top left / top right:** lower thirds with each machine's name (label) and a condition bar (a 3 pt rule that empties, `line` for the player, `typeDim` for the opponent, `danger` below 25 %). The player's is left. The house bot's name sits under the right one while it is out, in `danger`.
- **Top right, above the opponent's lower third:** the scrap bug (`scrap` numerals) and the pause glyph.
- **Bottom strip:** the ticker, commentary lines.
- **Coach callouts:** `label` type in `type` with the existing leader lines, on `glass` pills.
- **Off-screen arrow:** unchanged shape, `type` colour.
- **Zone warning:** a `danger` inner edge glow on the whole frame, 6 pt, plus the name in the ticker.
- **Touch controls:** the stick well is a `glass` disc with a `lineDim` rim and a `line` knob; the throw ring is a `lineDim` hairline; the drive pulse ring stays. Primary weapon button: a `glass` disc with a `line` rim and the weapon glyph in `type`; pressed = fill `line` at 30 %. Secondary: the same at its smaller size with the utility glyph. Alpha over the arena: 62 % resting, 90 % touched. Geometry constants in `controls.gd` do not change.

## 5. The broadcast package (Swift, every screen)

- **Backdrop:** the live Godot stage (machine on the turntable) on every stage screen; menu screens without a live machine use the tier key art (`Art/ui/backdrop_<tier>.png`) under a `ink` 40 % wash.
- **Main menu (option M1, section 8):** the title as display type top left with one dim machine line; scrap top right as label plus number; one card in the right column naming the next career fight with CONTINUE CAREER as the only primary; Quick fight, Workshop and Events as a text list under it; Ladder, Replays and Settings small bottom right; the ticker along the bottom.
- **Career season (option A, section 8):** a chevron, the tier line of five words, the tier name and one dim record line on the left; one panel on the right holding the next-fight card with FIGHT inside it and Garage / Repair as links; a four-slot bracket strip under the panel; the full board one tap away.
- **Garage / builder:** the machine live on the left; panels on the right column only (the left 45 % stays clear, `frame` 0.28).
- **Result / settlement:** a display-type banner (WON / LOST in `win` / `danger`), stat strips as lower thirds, scrap counting up.
- **Pause:** a `ink` 70 % wash and one panel.
- **Onboarding, settings, store:** panels and buttons from this system, nothing bespoke.

## 6. Asset manifest (V1 produces, V2 and V3 consume by these exact paths)

Raster PNG at 2x and 3x unless stated. Every asset is original art with no show, logo or real robot likeness.

| Path | What |
|---|---|
| `Art/ui/backdrop_scrapyard.png` … `backdrop_masters.png` (5) | 2436x1125 key art: an original machine under stage light, the venue growing grander per tier |
| `Art/ui/menu_keyart.png` | the main menu backdrop when no live stage: dry ice, stage lights, an empty turntable |
| `Art/ui/arena_<id>.png` (6: yard, grinder, drop_zone, furnace, crush, coliseum) | 1200x675 arena cards |
| `Art/ui/boss_<id>.png` (5) | 800x800 portraits on `ink` |
| `Art/ui/rival_<id>.png` (8) | 800x800 roboteer portraits, stylised, no real people |
| `Art/ui/glyph_weapon_<id>.svg` (10) | single-colour weapon glyphs, 64 px grid, 3 px stroke |
| `Art/ui/glyph_utility_<id>.svg` | the utility glyphs, same grid |
| `Art/ui/tier_<id>.svg` (5) | tier badges, single colour |
| `Art/ui/blueprint_card.png` | the blueprint reward card frame |
| `Arena/assets/ui/` | copies of the glyphs and the stick/button faces the arena draws, plus the font |

Panels, lower thirds, bugs, rules and buttons are DRAWN, never bitmaps: Swift shapes and Godot
`draw_*` calls from the tokens, so they are crisp at every size.

## 7. Rules

- One system. If a screen needs something this file does not have, add it here first.
- Nothing warm except `scrap` and `danger`, and never on a panel fill.
- Every text string follows the owner's standing rule: plain sentences, no em dashes, no exclamation marks in chrome.
- Nothing is cut at the screen or panel edge on a 402 pt or a 440 pt tall landscape iPhone: a long part name wraps to a second line, a column that can outgrow the phone scrolls inside its own room (the Series card) rather than pushing the ticker off the foot.
- Legibility floor: label type never below 11 pt, body never below 13 pt, contrast of `type` on `glass` over the brightest arena frame at least 4.5:1 (add the wash if not).

## 8. Hierarchy rules (added 2026-09-16 after the owner's review of the first Broadcast pass)

The first pass put every element on the same skewed panel and the career screen ended up with
sixteen identical boxes. These rules are binding for every screen; the chosen mockups are
`docs/look/menus-options.html` (career screen option A, main menu option M1).

- **One hero per screen.** Exactly one primary button, and it lives inside the one thing the screen is about.
- **At most two boxed panels per screen.** Everything else is plain type on the glass: labels, sentences, links.
- **Navigation that is not the hero is a text link** (label type, `typeDim`, `line` when it leads somewhere important, `danger` when it costs scrap). Never a box.
- **Money is a sentence, not a row of bugs.** "Entry paid 120. The final pays 780. Repairs owing 184." with only the numbers coloured (`scrap` for income, `danger` for costs).
- **The tier strip is a line of five words**, the current one in bright type on a `selectedFill` plate (no underline, section 0), locked ones dimmed with the lock glyph. Never five boxes.
- **Back is a chevron**, top left, never a boxed button.
- **The bracket lives on the career screen** as a four-slot strip under the card (round, opponent, result), and the full board is one tap away.
- **The main menu leads with what happens next**: a card naming the next career fight with one Continue button; Quick Fight, Workshop and Events are a text list; Ladder, Replays and Settings stay small.
- A screen that cannot be read in one glance (where am I, what is next, what do I press) is not finished.
