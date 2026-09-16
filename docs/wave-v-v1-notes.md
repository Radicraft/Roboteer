# Wave V, agent V1: assets

Date: 2026-09-16. Scope: every asset in `docs/design-system.md` section 6, plus the Barlow Condensed
family in both bundle locations. No `.swift`, `.gd`, `.tscn` or project file was touched, and
`Arena/assets/textures` was not opened. Nothing was committed.

The per file prompt log, the model used for each and every rule bent live in `Art/ui/README.md`.
This file is the decisions, the traps and what V2 and V3 need to know.

## What shipped

| Group | Count | Size | Format |
|---|---|---|---|
| Tier backdrops | 5 | 2436 x 1125 | PNG |
| Menu key art | 1 | 2436 x 1125 | PNG |
| Arena cards | 6 | 1200 x 675 | PNG |
| Boss portraits | 5 | 800 x 800 | PNG on `ink` |
| Rival portraits | 8 | 800 x 800 | PNG on `ink` |
| Weapon glyphs | 10 | 64 x 64 | SVG, white on transparent |
| Utility glyphs | 7 | 64 x 64 | SVG |
| Tier badges | 5 | 64 x 64 | SVG |
| Pause glyph | 1 | 64 x 64 | SVG, hand drawn |
| Blueprint card frame | 3 | 400 x 600, 800 x 1200, 1200 x 1800 | PNG |
| Arena stick and button faces | 3 | 64 x 64 | SVG, hand drawn |
| Arena glyph copies | 18 | 64 x 64 | SVG |
| Barlow Condensed + OFL | 5 x 2 | | TTF |

Credits: 120 of 630. Fifty six generations at 2, seven `crisp_upscale` at 1, one
`remove_background` at 1. Ten of the fifty six were retries, listed in the README with the reason.

## Decisions a later agent should not have to rediscover

**Recraft V4.1 will not take `input_style`.** Confirmed again. Every raster call is
`recraftv4_1_raster` with the look carried entirely by prompt text. The stage 2 note was right.

**Signed image URLs cannot be resized by editing them.** `rs:fit:1536:768` in the returned URL is
part of the signature. Asking for 4096 by hand returns an error string, not an image. If a raster
needs to be bigger than what came back, that is a `crisp_upscale` call and one more credit.

**Native sizes by aspect, so the plan can be made in advance.** 2:1 returns 1536 x 768. 16:9 returns
1344 x 768. 1:1 returns 1024 x 1024. 2:3 returns 832 x 1280. `crisp_upscale` roughly triples the
long edge (1536 to 4096, 832 to 2662). Only the 2436 wide backdrops and the 1200 x 1800 card needed
an upscale; everything else was already larger than its target.

**The vector model does not draw strokes.** `recraftv4_1_vector` returns traced filled regions on an
opaque black plate, with every counter drawn as a separate black shape painted on top. Dropping the
dark paths does not give you a hole, it gives you a solid blob: the first normaliser pass produced
five solid hexagons and a solid battery before this was caught. The fix that works is to drop only
the full frame plate and merge everything else into one `<path fill-rule="evenodd">`, because every
remaining dark path is strictly inside a light one. Verified by rasterising all twenty two with an
even odd scanline filler and reading the contact sheet.

**Two traps inside that fix.** First, a `stroke-width` added to a group that carries
`transform="scale(0.034)"` is multiplied by the scale, so 1.25 units becomes invisible. It has to be
divided by the scale factor in the emitted file. Second, measuring line weight has to happen on the
normalised art, not on the source, or the number is in 2048 space and means nothing.

**Recraft's icon line weight is not the design system's.** Measured across the twenty two glyphs it
lands between 1.0 and 3.75 units on a 64 grid, median about 2. The design system wants 3. Asking for
"heavy bold, one twentieth of the icon width" moves it barely at all. The weight has to be corrected
after the fact.

**People need a different prompt register from machines.** The first rival portrait, phrased as
"stylised character portrait, simplified planes, painterly", came back small, soft and purple. The
phrase that produced the other seven, and the retry, is "hard edged flat colour shapes, bold graphic
shading, crisp confident line, like a high end animated title sequence, not a caricature, not a
sketch, not painterly, not photographic". Use that exact sentence for any further portraits so the
set stays one set.

**Machines drift towards weapons the game does not have.** Left alone, two prompts grew a gun
barrel, a lance and a missile pod. Every machine prompt now ends with "no gun, no cannon, no gun
barrel, no turret, no lance, no spike, no legs, no face, no eyes, no humanoid shape". Keep it.

**Livery colour will invade the chrome palette if you let it.** Thresher came back with large teal
panels, which reads as the `line` accent rather than as paint. The fix is to name the forbidden hues
in the prompt, not to correct afterwards. Anvil came back dusty mauve, which is a warm hue and has
no place in this system; that one was cheaper to desaturate in Pillow than to regenerate, and it is
the only asset with a colour edit.

## The IP work, since section 3 of the brief is the risk

Every machine here is described by its entry in `Shared/parts.json`, never by resemblance to
anything. Two bosses needed active steering, and the steering is in the prompts, not just in the
notes:

- **Grudge**, the tracked flame boss, is the obvious collision. Its prompt forbids military green,
  camouflage, a claw, a turret and a dome, and specifies a slab sided box in rust red with a full
  width burner manifold of eight small nozzles. What came back shares the category with the famous
  tracked flamethrower and shares no part of its silhouette or livery.
- **Thresher**, the grab and pin boss, is the other. Its prompt forbids a lance and any towering or
  humanoid form and specifies a long low six wheeled slab with a short bolt cutter style pincer. The
  test in the brief is silhouette, and a low wide six wheeler is not a tall clawed figure.

The other three (a band saw wedge, a hammer wall, a scoop thrower) are conceptually distinct from
each other and from anything on television. No show name, no presenter, no real competitor, no
arena branding, no floor markings copied from anywhere. Every raster prompt carries "no text, no
letters, no numbers, no logos, no signage" and every returned image was looked at.

The eight roboteers are invented people. Every prompt ends "Not a likeness of any real person, no
celebrity". They vary in age from twenties to sixties, in sex, in heritage and in build, and each
one is drawn from its own personality line in `Shared/parts.json` rather than from a type.

## What V2 and V3 should know before consuming these

1. **Paths are exactly as the manifest states them.** The only additions are `glyph_pause.svg`
   (design system section 4 asks for a pause glyph but section 6 forgot it) and the `@2x` and `@3x`
   siblings of `blueprint_card.png`, which is the one manifest entry with no stated size.
2. **`menu_keyart.png` needs its wash.** The chequer plate turntable is the brightest thing in the
   set. The `ink` 40 per cent wash is load bearing here, and the display type and the four lower
   third buttons belong in the dark left third, which every backdrop deliberately keeps empty.
3. **Glyphs are one white shape with real holes.** Tint them. Do not recolour paths individually,
   there is only one path. In Swift they want `.renderingMode(.template)`; in Godot, `modulate`.
4. **The five tier badges are not pixel identical frames.** Same hexagon family, same content
   progression, but a generative vector model will not repeat a vertex. If the tier strip in the
   career screen needs the five badges to register perfectly, draw the hexagon in Swift from the
   tokens and use only the inner mark from these files.
5. **Arena cards are 16:9 and full bleed.** There is no safe area inside them; any label goes on a
   lower third over the card, not baked in.
6. **Fonts are in two places already.** `Roboteer/Fonts/` and `Arena/assets/fonts/`, four weights
   plus `OFL.txt`. The app still needs the `UIAppFonts` entries and the Godot theme still needs the
   font resources; that is V2 and V3 work, not asset work.

## Not produced, and why

Nothing in the manifest is missing. Two things were deliberately not made:

- **No panels, lower thirds, bugs, rules or buttons as bitmaps.** Design system section 6 says those
  are drawn from tokens, so producing them would have been the wrong asset.
- **No font copy inside `Arena/assets/ui/`.** The manifest line says "plus the font", but section 1
  of the same document names `Arena/assets/fonts/` as the arena font location, and a second copy of
  four TTFs in the build for no reason is worse than following section 1. The fonts are there.
