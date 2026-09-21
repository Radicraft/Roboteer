# Art/ui: the Broadcast asset set

Produced by wave V agent V1 on 2026-09-16 against the manifest in `docs/design-system.md` section 6.
Every image is original art. No show name, no named real robot, no house robot silhouette, no real
person. See `docs/brief-v3.md` section 3.

Tooling: Recraft MCP only. Raster art uses `recraftv4_1_raster` with **no** `input_style`
parameter, because Recraft V4.1 rejects `digital_illustration` outright (recorded in
`docs/stage2-art-direction.md` and confirmed again here). SVG glyphs and badges use
`recraftv4_1_vector`. Two `crisp_upscale` passes and one `remove_background` pass were used where
noted. Total spend 120 credits of the 630 available.

Shared raster language, present in every raster prompt: near black background, hard white stadium
key light, a thin cold cyan rim light, cold grey haze, deep black shadows, faceted low polygon
geometry, flat lightly shaded materials, no gloss, like a painted tabletop miniature, not
photorealistic and not cartoon, and an explicit negative list ending "no text, no letters, no
numbers, no logos, no signage, no user interface, no people, no crowd". Warm colour appears only in
fire, sparks and machine livery, never in chrome.

---

## 1. Tier backdrops, 2436 x 1125 PNG

Model `recraftv4_1_raster`, aspect 2:1, then `crisp_upscale` to 4096 x 2048, then cropped to
2.1653:1 (60 per cent of the trim taken off the top) and resized to 2436 x 1125. Every one keeps the
left third almost empty dark haze so the main menu lower thirds and the display type have somewhere
to sit, exactly as in `docs/look/b-broadcast.webp`.

| File | Venue and machine |
|---|---|
| `backdrop_scrapyard.png` | Night scrapyard, chain link fence, oil drums, pallets, one tripod work lamp. A scuffed low wedge with four wheels, bare steel front ramp, folded self righting arm. |
| `backdrop_regional.png` | Municipal sports hall, roller shutter, stacked folding chairs, a four lamp truss. A boxy four wheeled machine with a hinged front flipper plate on a steel turntable. |
| `backdrop_national.png` | Television studio floor, black drapes, camera crane and pedestal silhouettes, ring of lamps, deep dry ice. A long low six wheeler with a steel drum across its nose. |
| `backdrop_championship.png` | Indoor championship arena, tiered dark seating, huge overhead lamp rig, cyan tier strips. A tracked heavyweight with a vertical disc set into its nose. |
| `backdrop_masters.png` | Stadium bowl, vast light rig, cyan halo round the stage, mirror floor. A six wheeled shell machine wearing a full body spinning ring with cut teeth. |

Prompt shape, using `backdrop_masters.png` as the example:

> Stylised low-poly 3D video game key art, wide cinematic landscape. An original champion combat
> robot, a broad low armoured shell shaped chassis on six wheels, its whole outer shell a bare steel
> full body spinning ring with cut teeth around the rim, flat dark plates with visible hex bolts,
> standing on a raised circular steel stage at the centre of an enormous stadium bowl. Around and
> above it a vast rig of hard white lamps and a ring of cold cyan light, beams cutting down through
> deep haze, the stadium tiers only hinted as black shapes. A cyan halo of light around the base of
> the stage. Deep black shadows, a dark mirror floor with a long reflection, an epic sense of scale.
> The machine sits in the right half of the frame; the left third is almost empty dark haze.
> Faceted low polygon geometry, flat lightly shaded materials, no gloss, chunky readable silhouette
> like a painted tabletop miniature, not photorealistic and not cartoon. Desaturated near black and
> steel grey palette with one cyan accent. No gun, no cannon, no gun barrel, no turret, no lance, no
> text, no letters, no numbers, no logos, no signage, no user interface, no people, no crowd.

The National machine was generated twice. The first pass drew a long horizontal rod that read as a
gun barrel, which is outside the part library in `Shared/parts.json`, so it was regenerated with
"no gun, no cannon, no gun barrel, no turret, no lance, no long pointed spike, no pole, no antenna"
added. Every later machine prompt carries that negative list.

## 2. `menu_keyart.png`, 2436 x 1125

Same pipeline. An empty stage: a bare chequer plate turntable with a cyan rim strip, dry ice, a
truss of hard white lamps, black drapes, no machine at all.

> Stylised low-poly 3D video game key art, wide cinematic landscape, an empty television stage with
> no machine on it. A bare circular steel turntable with a chequer plate surface and a thin cyan
> light strip around its rim stands slightly right of centre on a glossy black studio floor. Thick
> dry ice rolls across the floor and pools around the turntable. Above and behind, a dark overhead
> truss carries a row of hard white stage lamps whose beams cut down through heavy cold haze, and a
> second rank of smaller lamps glows far back in the dark. Black drapes and dark gantry shapes
> recede into blackness. The left third of the frame is almost empty dark haze so that text can sit
> over it. Deep black shadows, a faint reflection in the floor, cold grey and steel palette with one
> cyan accent, warmth nowhere. Faceted low polygon geometry, flat lightly shaded materials, no
> gloss, like a painted tabletop miniature set, not photorealistic and not cartoon. No robot, no
> machine, no vehicle, no text, no letters, no numbers, no logos, no signage, no user interface, no
> people, no crowd.

Note for V2: the chequer plate is the brightest thing in the frame. The `ink` 40 per cent wash from
the design system is not optional over this one, and display type belongs on the left.

## 3. Arena cards, 1200 x 675 PNG

Model `recraftv4_1_raster`, aspect 16:9, native 1344 x 768, centre cropped to 16:9 and resized. Each
card is the empty arena with its hazard visibly working, at the stage 2 camera (about 45 degrees yaw
and 50 degrees pitch, whole floor plan in frame). Hazards follow `Shared/parts.json`.

| File | What is in it |
|---|---|
| `arena_yard.png` | Scrapyard pit, chain link over dented steel walls, oil drums and scrap outside, two rows of floor spikes standing through their slots. |
| `arena_grinder.png` | Banks of floor grinder discs down the left and right flanks, both throwing orange spark fans across scored steel. |
| `arena_drop_zone.png` | Central square pit with its two hinged chevron plates swung down into blackness, faint cyan far below. |
| `arena_furnace.png` | Slat conveyor floor lit from beneath, wall flame jets firing two long flame curtains, scorch blackening. |
| `arena_crush.png` | Two wall sized hydraulic ram plates on guide rails, one driven half way out on three pistons, long gouges in the floor. |
| `arena_coliseum.png` | The grandest: spinning floor discs, an open pit, a grinder bank throwing sparks, wall flame jets, tiers of dark seating, a vast lamp rig. |

Prompt shape, using `arena_grinder.png` as the example:

> Stylised low-poly 3D video game render of a small empty enclosed robot combat arena seen from a
> near orthographic isometric camera at about 45 degrees yaw and 50 degrees pitch, the whole square
> floor plan visible with the low perimeter walls. This arena is a machine shop pit: a scuffed bare
> steel floor with hazard chevrons painted at the edges, low scratched steel perimeter walls, and
> set into the floor along the left and right flanks two long banks of spinning angle grinder discs,
> half sunk in slots, each bank throwing a bright orange spark fan sideways across the floor. Scorch
> marks and grinding scars streak the floor beside them. Hard white lamps above throw pools of light
> down, a thin cold cyan rim light catches the wall tops, cold grey haze in the air, deep black
> shadows, near black background. Faceted low polygon geometry, flat lightly shaded materials, no
> gloss, like a painted tabletop miniature, not photorealistic and not cartoon. Desaturated steel
> grey palette, one cyan accent, warm colour only in the sparks. No robot, no machine, no user
> interface, no HUD, no text, no letters, no numbers, no logos, no signage, no people, no crowd.

Rule bent: `arena_coliseum.png` came back closer to a wide interior shot than a flat isometric plan.
It was kept because it is the only frame in the set that sells scale, which is the whole point of
the Masters arena, and because a card is not a gameplay view. The other five are on camera.

## 4. Boss portraits, 800 x 800 PNG on `ink`

Model `recraftv4_1_raster`, aspect 1:1, native 1024, resized to 800. Each machine is built from its
entry in `Shared/parts.json` (chassis, drive, weapon, utility, livery) so the portrait and the 3D
build agree. Each prompt ends with the machine negatives: no lance, no spike, no gun, no cannon, no
turret, no legs, no face, no eyes, no humanoid shape.

| File | Machine |
|---|---|
| `boss_thresher.png` | Long low grey slab, six wheels a side, front scoop plate, short hydraulic pincer with two blunt jaws open in a V, folded srimech. Deliberately low and wide, never a towering clawed figure. |
| `boss_grudge.png` | Squat dark rust red box on two wide tracks, a full width burner manifold of eight nozzles across the blunt front face, two of them lit, gas bottles on the rear deck. |
| `boss_bandsaw.png` | Fast pale grey two wheeled wedge, ground clearance skirts, a tall narrow continuous band saw loop standing upright on the rear deck. |
| `boss_anvil.png` | A rolling wall: a tall bolted slab of front armour on a short four wheeled chassis, overhead hammer arm on a stout pivot post, held up and back. |
| `boss_cinder.png` | Wide burnt orange six wheeler, full width curved steel scoop hinged at the floor and raised part way, pneumatic ram visible behind it. |

IP notes worth keeping, because these are the assets most at risk under brief section 3:

- Grudge is the flame boss. Its prompt names "no military green, no camouflage, no claw, no turret,
  no dome" precisely so a tracked flamethrower does not drift towards the tracked flamethrower
  everybody remembers. What came back is a slab sided red box with a burner bar, which is a
  different silhouette and a different livery.
- Thresher is the grab and pin boss. Its prompt forbids a lance and any towering or humanoid form,
  and specifies a long low six wheeled chassis, so the "big crusher one" is not a renamed anything.
- Thresher was generated twice. The first pass painted large teal panels on the machine, which
  reads as chrome colour rather than livery, so it was regenerated with "no cyan paint, no turquoise
  paint, no teal panels, no blue panels, no coloured livery anywhere on the machine". Small teal
  edge trim survives on the retry and reads as rim light.
- `boss_anvil.png` was colour corrected after generation. Recraft painted the armour a dusty mauve,
  which is a warm hue and off palette. It was desaturated to 18 per cent and cooled very slightly in
  Pillow so it lands on the slate `#3a4048` the parts file asks for. No other pixel edit was made.
- `boss_grudge.png` came back standing on a light grey floor plane, which would have read as a panel
  behind the machine. It was run through `remove_background` and composited onto exact `ink`
  (#07090C). The cut kept the machine's own cast shadow, so it is still grounded.

## 5. Rival portraits, 800 x 800 PNG on `ink`

Model `recraftv4_1_raster`, aspect 1:1, native 1024, resized to 800. Eight invented people, one per
rival in `Shared/parts.json`, dressed in that team's livery colour, with a face that matches the
personality line. Every prompt ends "Not a likeness of any real person, no celebrity". Varied in
age, sex, heritage, build and bearing, and drawn with respect rather than as types.

Shared style sentence: "Stylised flat cel shaded character portrait illustration of a completely
invented fictional person, head and shoulders, centred, filling the frame, on a plain solid near
black background ... Hard edged flat colour shapes, bold graphic shading, crisp confident line, like
a high end animated title sequence, not a caricature, not a sketch, not painterly, not photographic.
Lighting is broadcast studio: one hard white key light from above and front, a thin cold cyan rim
light along one shoulder and cheek, deep black shadows, a wisp of cold grey haze behind."

| File | Roboteer, and what the portrait carries |
|---|---|
| `rival_clatterbox.png` | Dot Ferris. Twenties, short bleached crop, freckles, caught mid sentence with a headset mic. Slate blue boiler suit. Never stops talking. |
| `rival_penny_dread.png` | Hal Mercer. Forties, shaved head, heavy stubble, arms folded, chin lifted. Brick red boiler suit, ear defenders round the neck. |
| `rival_scuttle.png` | Lena Vosch. Fifties, grey streaked hair pulled back, safety glasses pushed up, completely level. Dark green technician jacket. |
| `rival_hob_nail.png` | Jonty Ash. Thirties, full beard, beanie, slow amused half smile, spanner over the shoulder. Burnt orange hi vis. |
| `rival_cold_snap.png` | Ren Adeyemi. Twenties, close fade, loupe on a headband, one eyebrow raised. Deep teal technical jacket. |
| `rival_brass_neck.png` | Ivor Teale. Sixties, flat cap, grey moustache, jaw set, thoroughly unimpressed. Grey donkey jacket, near monochrome. |
| `rival_marrow.png` | Kit Danvers. Thirties, long plait, round glasses, studying something off camera with great patience. Violet workshop jacket. |
| `rival_tollgate.png` | Bram Fisk. Forties, hair swept back, welding goggles on the forehead, immovable. Bone white canvas jacket, the brightest thing in frame. |

Dot Ferris was generated twice. The first pass came back small, soft and washed in purple, which is
a hue that does not exist in this system. The retry uses the "hard edged flat colour shapes, bold
graphic shading" wording plus "no purple, no magenta, no pink background", and it now matches the
other seven. `rival_hob_nail.png` was lifted 12 per cent in brightness after generation because the
key light barely reached the face; nothing else was edited.

## 6. Glyphs, 64 x 64 SVG, single colour white on transparent

Model `recraftv4_1_vector`, aspect 1:1. Ten weapons, seven utilities, all keyed to the ids in
`Shared/parts.json`.

Every glyph was generated with a variant of one prompt:

> A minimal flat user interface icon on a plain solid black background, drawn only in pure white as
> heavy bold line art with one uniform very thick stroke weight and no fill, no shading, no
> gradient, no colour. The icon is `<subject>`. Geometric, symmetrical, centred in the square frame
> with even margin on all four sides, built on a 64 by 64 pixel grid, flat stroke ends. Simple
> enough to read at 24 pixels. No text, no letters, no numbers, no logo, no background detail, no
> border box.

Subjects:

| File | Subject given to Recraft |
|---|---|
| `glyph_weapon_horizontal_spinner.svg` | A long bar from above, blunt ends, centre hub circle, a rotation arc beyond each end. |
| `glyph_weapon_vertical_spinner.svg` | A toothed drum from the side on a ground line, axle circle, a curved arrow arcing up over the top. |
| `glyph_weapon_flipper.svg` | A flat plate hinged on a circle at the left, swung up to 45 degrees, a straight arrow above it, a ground line under the hinge. |
| `glyph_weapon_lifter.svg` | A two pronged fork on a pivoting arm carrying a small block, ground line under the pivot, no arrows. |
| `glyph_weapon_crusher.svg` | Two thick hooked jaws facing each other like a bolt cutter head, part closed around a small block. |
| `glyph_weapon_axe.svg` | A straight vertical haft, one broad crescent head at the top right, a hinge bracket at the foot. |
| `glyph_weapon_saw.svg` | A circle with eight triangular teeth round the rim, a hub circle, two spokes. |
| `glyph_weapon_ram.svg` | A solid triangular wedge pointing right, three speed lines of decreasing length behind it. |
| `glyph_weapon_flamethrower.svg` | A nozzle block with a round muzzle, three tapering flame tongues streaming right, the middle one longest. |
| `glyph_weapon_full_body_spinner.svg` | A thick ring with eight blunt square teeth outside it and a small square chassis block inside, not touching. |
| `glyph_utility_srimech.svg` | A small box with an arm hinged at its top corner, swung up and out, a curved arrow sweeping over the box. |
| `glyph_utility_rear_wedge.svg` | A body block with a triangular wedge sloping down off its right end, on a ground line. |
| `glyph_utility_skirts.svg` | A wide body block with four short flaps hanging down from its lower edge, almost touching a ground line. |
| `glyph_utility_magnets.svg` | A horseshoe magnet with square poles pointing down, two short down arrows, a ground line. |
| `glyph_utility_scoop.svg` | A curved shovel plate rising from a lip on the ground line with a small block inside the curve. |
| `glyph_utility_spare_battery.svg` | An upright cell with a terminal cap and one bold lightning bolt inside it. |
| `glyph_utility_counterweight.svg` | A trapezoid block, wider at the base, on a ground line, with a closed ring handle on top. |

`glyph_weapon_full_body_spinner.svg` was generated three times. Pass one came back as a crosshair.
Pass two was a saw toothed disc that read as a duplicate of `glyph_weapon_saw.svg`. Pass three, the
one shipped, puts a square chassis inside the toothed ring, which is both truthful to the part and
clearly not the saw.

### What the normaliser does, and the one rule it bends

Recraft returns a 2048 unit SVG whose art is a set of traced filled regions, painted in near white
on an opaque near black plate, with counters drawn as separate dark shapes on top. That is not what
the design system asks for, so every glyph went through one deterministic pass
(`scratchpad/norm.py`, a throwaway):

1. The full frame dark plate is dropped. Every remaining path, light and dark, is merged into one
   `<path fill-rule="evenodd">` so that the dark counters punch holes instead of becoming black
   shapes. The result is white on transparent with real holes.
2. The art bounding box is measured and fitted into a 56 unit box centred in a 64 unit viewBox, so
   every glyph in the set has the same optical size and a 4 unit margin.
3. The line weight is measured by rasterising the normalised art at 4x and taking the median white
   run length. Recraft's own weight lands between 1.0 and 3.75 units on the 64 grid, not the 3 the
   design system specifies, so a white `stroke` is added to the group to make up the difference,
   capped at 1.8 units. Ten glyphs needed 1.0 or more, six needed under 1.0, and
   `glyph_weapon_crusher.svg` and `tier_regional.svg` already measured over 3 and got none.

**Rule bent:** the shipped stroke is a measured 3 units at the 64 grid, but it is achieved by
outlining a filled trace rather than by a real 3 pixel stroked path. The visual result is right and
the file is a single white shape, which is what the arena and Swift need in order to tint it, but
anyone editing these by hand should know the geometry is an outline, not a centreline.

### The three wave P glyphs, drawn by hand (agent H, 2026-09-21)

`shock_prod`, `tesla_arc` and `drill_lance` are NOT Recraft traces. The normaliser above exists
because Recraft's line weight is wrong for a glyph and has to be corrected by outlining a filled
trace; these three are real 3 unit stroked paths on the 64 grid instead, which is what the design
system asked for in the first place. They use only `M`, `L`, `C` and `Z` so the Swift reader in
`DesignSystem.swift` can parse them, and they were checked against the other ten on one contact
sheet before they shipped.

| File | Content |
|---|---|
| `glyph_weapon_shock_prod.svg` | A grip block, a shaft, a two pronged fork at the end of it, and a bolt arcing between the prongs. |
| `glyph_weapon_tesla_arc.svg` | Two electrodes with ball tops on a ground line, an arc leaping between them. |
| `glyph_weapon_drill_lance.svg` | A mount block, a fluted barrel with three helical flutes, a conical point. Deliberately not the ram's plain wedge. |

Copies live in `Arena/assets/ui/` with their `.import` sidecars, the way the other ten do.

## 7. Tier badges, 64 x 64 SVG

Same model, same normaliser, same prompt family, phrased as "a minimal flat single colour badge
emblem ... The badge is an upright hexagon outline with flat top and bottom edges, and inside it,
centred, `<content>`".

| File | Content |
|---|---|
| `tier_scrapyard.svg` | One hex bolt head with a circle in its middle. |
| `tier_regional.svg` | Two chevrons pointing up. |
| `tier_national.svg` | Three chevrons pointing up. |
| `tier_championship.svg` | A five pointed star over two chevrons. |
| `tier_masters.svg` | A five pointed star framed by two curved laurel branches. |

Scrapyard, championship and masters were each generated twice. The first attempts produced two
different hexagon shapes, one lying flat and two elongated like rank patches, which would have made
the five badge tier strip look like three different sets. The shipped five all use the same point up
hexagon. They are still not identical frames down to the vertex, because a generative vector model
will not repeat a shape exactly, so if the tier strip needs perfect registration, V2 should draw the
hexagon in Swift and use these only for the inner mark.

## 8. `blueprint_card.png`, plus `@2x` and `@3x`

Model `recraftv4_1_raster`, aspect 2:3, native 832 x 1280, `crisp_upscale` to 2662 x 4096, cropped
to exactly 2:3 and resized to 400 x 600, 800 x 1200 and 1200 x 1800. This is the only asset in the
manifest with no stated pixel size, so it ships as a normal 1x, 2x, 3x set. The centre is empty on
purpose: it is a frame, and the reward art and the part name go inside it at runtime.

> A blank technical reward card frame for a game interface, portrait orientation, on a near black
> background. The card is a tall rectangle of dark smoked glass with one corner cut off at the top
> right, a very thin bright cyan hairline running around its whole edge and a thicker cyan bar
> across the bottom edge. Inside the card the surface is a dark blueprint field carrying a faint
> fine cyan grid of small squares, with four small cyan corner registration marks set in from each
> corner and a narrow empty banner strip across the top of the card. The centre of the card is
> completely empty dark glass with nothing drawn in it. Flat vector graphic style, crisp edges, no
> perspective, seen straight on, cold and technical, a thin cold haze behind the card. Only two
> colours: near black and cyan, with white only in the thinnest highlight. No text, no letters, no
> numbers, no logo, no signage, no robot, no machine, no illustration inside the card, no people, no
> watermark.

## 9. Hand drawn geometry, not generated

Four files are plain geometry and were written by hand rather than generated. A generative model
cannot place a circle on an exact centre at an exact radius, and these have to line up with the
constants in `controls.gd`, which the design system says do not change.

| File | What it is |
|---|---|
| `glyph_pause.svg` (also in `Arena/assets/ui/`) | Two bars, 8 units wide, 36 tall, on the 64 grid. Called for by design system section 4 but missing from the section 6 table. |
| `Arena/assets/ui/stick_well.svg` | One ring, radius 29.5, stroke 3. The rim only. The glass disc behind it is drawn by `controls.gd` from the tokens. |
| `Arena/assets/ui/stick_knob.svg` | One filled disc, radius 31. |
| `Arena/assets/ui/button_ring.svg` | Weapon button face: a stroke 3 outer rim at radius 29.5 and a stroke 1 inner hairline at radius 24.5. |

All four are pure white so Godot can modulate them to `line`, `lineDim` or `type`.

**Rule bent:** the manifest says V1 produces every asset with Recraft. These four are the exception,
and the reason is precision, not convenience.

## 10. `Arena/assets/ui/`

Holds copies of the ten weapon glyphs, the seven utility glyphs and the pause glyph, plus the three
stick and button faces above. The tier badges are not copied there; nothing in the arena draws them.

The font does not live in `Arena/assets/ui/` either. Design system section 1 puts it in
`Arena/assets/fonts/`, and that is where it is: `BarlowCondensed-Medium.ttf` (500),
`-Bold.ttf` (700), `-ExtraBold.ttf` (800) and `-ExtraBoldItalic.ttf` (800 Italic), with `OFL.txt`
beside them. The same five files are in `Roboteer/Fonts/`. Source is the upstream Barlow repository
(`github.com/jpt/barlow`, `fonts/ttf/`), which is the same SIL OFL 1.1 release Google Fonts serves.

## 11. Colour and legibility

Nothing in this folder is a panel, a lower third, a bug, a rule or a button. Those are drawn from
the tokens in Swift and in Godot, per design system section 6. Everything here is either key art
that lives behind a wash, a portrait that lives inside a frame, or a white shape that gets tinted.
The only warm pixels in the set are fire, sparks and machine livery.
