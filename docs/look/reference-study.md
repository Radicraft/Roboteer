# Reference study: showroom front ends and garages

Written 2026-09-24 after the owner rejected the main menu and garage mockups as "not refined PS4 like graphics". The question: what do the best console and mobile front ends actually do with light, camera, materials, post and interface, in numbers, and what should Roboteer copy.

How to read this file:

- **Sourced** facts carry a link.
- **est.** marks an informed estimate: observed from footage and screenshots, derived from photography practice, or worked out from our own frame. Treat every est. number as a starting value to tune on the iPhone, not as a measurement.
- Section 3 is the spec. It supersedes the accent bars in `docs/design-system.md` for the main menu and garage (see 3.0).

---

## 1. The games

### 1.1 Gear.Club Stradale (Eden Games, Apple Arcade)

**What it does.** Your cars live at a Tuscan villa with a garage and workshop; the owner named its main menu as our model: the car as the lit hero, the options as a calm row of tiles along the bottom ([App Store](https://apps.apple.com/us/app/gear-club-stradale/id1544427904), [autoevolution](https://www.autoevolution.com/news/apple-arcade-exclusive-gearclub-stradale-is-all-about-driving-luxury-supercars-183730.html), `docs/graphics-bar.md`). A later update restructured the main menu to be "simpler, clearer", splitting it into a Main Menu and a Play Menu, and added an "At a Glance" inspection where you can open the doors and bonnet ([patch notes](https://gear.club/patchnotes.html)).

**Graphics modes.** iOS and tvOS offer three presets: Quality, Performance and Energy Saving ([patch notes](https://gear.club/patchnotes.html)). This matches the graphics-modes idea already queued for Roboteer.

**The lesson reviewers keep making.** The car models "look like they were pulled straight out of a console game" while "the environments are very disappointing visually, which creates a weird contrast" ([autoevolution review](https://www.autoevolution.com/news/gearclub-stradale-review-a-grindy-racer-that-favors-style-over-substance-ios-app-188288.html)). The menu still reads as premium because the hero gets the whole budget and the room is kept dark and simple. That is the right trade for a phone.

**Lighting, camera, post (est., from footage).** Near-neutral key from high front, large soft overhead source that lays long highlights along the bodywork, a dark glossy floor with a blurred reflection, a slow drifting camera at a long-ish lens (roughly 50 to 70 mm equivalent), shallow background blur, mild vignette. The tiles are flat, dark, translucent, with the focused one brightened; no outlines.

### 1.2 Gran Turismo 7 (Polyphony Digital)

**Front end.** The main menu is a 3D-modelled island world map with hubs (Café, Brand Central, Used Cars, Legendary Cars, Garage), a return to the Gran Turismo 4 structure ([GT Wiki](https://gran-turismo.fandom.com/wiki/Menu_Styles), [Game Informer](https://gameinformer.com/2022/02/02/gran-turismo-7-state-of-play-showcases-world-map-music-modes-car-museums-and-more)). Yamauchi's brief was "a paradise, a vacation resort that celebrates car culture"; the Café hands out 39 collection "menus" ([racinggames.gg](https://racinggames.gg/article/gran-turismo-7s-new-gt-cafe-is-a-celebration-of-car-culture)). The point for us: every menu is a place, and the objects on the table are crafted to the same bar as the cars.

**Where the rendering budget goes.** Ray tracing runs only outside racing: the Café, Scapes, the garage and replays; on track it falls back to cube maps ([GamingBolt](https://gamingbolt.com/gran-turismo-7-graphics-analysis-a-ps5-masterpiece)). Digital Foundry estimates the RT reflections at about a quarter resolution, roughly 1080p ([GTPlanet on DF](https://www.gtplanet.net/gt7-ps5-pro-visuals-df-20240918/)). So even a PS5 flagship spends its best reflections on the showroom and accepts reduced resolution to do it.

**Tone and colour.** GT7 tonemaps brightness and colour separately in a uniform colour space so saturated paint and red brake lights keep their hue as they get bright; auto exposure models short-term (seconds) and long-term eye adaptation and deliberately avoids a "perfectly exposed" image ([GTPlanet](https://www.gtplanet.net/why-gran-turismo-7-graphics-look-20250902/)). Polyphony photograph real locations for Scapes and measure real paint ([GTPlanet](https://www.gtplanet.net/display-tech-is-finally-catching-up-to-gran-turismo-7-20260731/)).

**Camera.** Photo mode exposes a real lens: focal length 10 to 800 mm, manual f-stop, circular bokeh, single and tracking autofocus ([GT Wiki, Photo Mode](https://gran-turismo.fandom.com/wiki/Photo_Mode), [Red Bull guide](https://www.redbull.com/ca-en/gran-turismo-7-photo-mode-guide)). Showroom and Brand Central shots sit at long lenses (est. 50 to 85 mm) with the car on a slowly turning plinth (est. one revolution in 60 to 90 s).

**Interface and sound (est.).** Light type on dark translucent panels, focus by fill brightening, soft piano and lounge music in the Café, quiet short clicks for navigation. Nothing shouts; the car and the music carry the mood.

### 1.3 Forza Motorsport (2023) and Forza Horizon 5

**Inspection.** Forzavista (Forza Motorsport 5 onwards) lets you walk around the car in a dedicated "homespace", open doors, bonnet and boot, sit in and start the engine; Forza Motorsport 2023 renamed it "View Car" and dropped the narration ([Forza Wiki](https://forza.fandom.com/wiki/Forzavista)). The pattern: the car is the menu, hotspots on the model open detail.

**Materials.** Physically based materials where carbon fibre, leather and glass each respond differently; "thick coats of shiny paints and chrome"; RT reflections and RT ambient occlusion give soft contact shadows under the body ([GamingBolt](https://gamingbolt.com/forza-motorsport-graphics-analysis-a-new-visual-benchmark-for-racing-games)).

**Front end (est., from footage).** Forza Horizon 5 uses large flat rectangular tiles in a horizontal row or grid over a live car scene, strong solid fill colour on the focused tile, bold condensed type, fast (about 150 ms) focus changes, and a distinct "whoosh plus click" on page changes. The garage UI was designed by the Playground UI team ([William Emery, ArtStation](https://www.artstation.com/artwork/lD1oL5); the page blocked automated reading, so the layout notes here are from footage).

### 1.4 Armored Core VI: Fires of Rubicon (FromSoftware)

**The ASSEMBLY screen.** Part slots down the left, the AC centred in a dark hangar, two spec windows (Part Specs and AC Specs) that expand to the full list, with a toggle to show every stat ([Fextralife](https://armoredcore6.wiki.fextralife.com/Stats)). When a candidate part is highlighted the stat list shows the current value, the new value and an up or down arrow per line (est., from footage: better values in blue, worse in red, unchanged dim). The camera frames the slot being edited (est.).

**Budget.** On PC, ray tracing is available only in the garage, never in missions ([GameSpot](https://www.gamespot.com/articles/armored-core-6-has-demanding-pc-requirements-if-you-plan-to-enable-its-garage-exclusive-ray-tracing/1100-6516854/), [TechSpot](https://www.techspot.com/news/99781-armored-core-vi-has-relatively-light-system-requirements.html)). Second flagship, same decision as GT7: the static showroom gets the expensive light.

**Lighting (est.).** A dark industrial hangar, high cool overhead sources, a hard rim from behind, the machine lit mostly by top and back light so painted plates show edge wear and panel breaks; very low fill (key to fill est. 6:1 or harder).

**Sound.** UI sounds sit in the high frequencies as quick chirps while lows and mids belong to weapons and thrusters; changing legs or generators audibly changes the machine's own sounds ([Carter Menary](https://www.cartermenary.com/blog/armored-core-vi-design-sound-of-rubicon)). The UI never competes with the machine in the mix.

### 1.5 Ratchet & Clank: Rift Apart (Insomniac)

**Lighting pipeline, sourced from the GDC 2022 talk** ([GDC Vault](https://www.gdcvault.com/play/1027792/Recalibrating-Our-Limits-Lighting-on), [slides](https://media.gdcvault.com/GDC+2022/Speaker+Slides/RecalibratingOurLimits_Mullen_Brian.pdf)):

- "Stylized or not, follow a realistic, PBR lighting workflow."
- Order of work: set base exposure (EV) first, then key light intensity, both then **locked**; then probes and lights; then bake; post comes **last**.
- Exposure examples on the slides: adaptation anchor 8 versus 12, adaptation range 2, emissive 0.5; a wrong exposure silently breaks every emissive and effect.
- Direct to indirect ratio measured with a grey card at 2 pm in Los Angeles: **about 3:1**, reproduced in engine.
- "Less is more": a room lit by 3 to 5 large overlapping lights beats 10 to 15 small ones, for both looks and performance. Every light is motivated; no phantom lights on Ratchet.
- Every light casts shadows; losing shadows cost contrast, pathing and "character impact" (Ratchet lost his highlights under a flat multi-light setup).
- Post: saturated grade, pushed contrast, softening fog "to match the quality of feature animation", and refined bloom, **chromatic aberration** and colour correction.

**Hero objects (est., from footage).** Weapons at the vendor and in the wheel are shown as 3D models on a dark ground, turning slowly, with a bright rim from behind and above that traces the silhouette, a warm or cool key from the front, and an emissive accent (screens, energy cells) that blooms. Materials are stylised in form but physically based in response: painted metal with worn edges, chrome with sharp environment reflections, rubber grips at high roughness. The weapon wheel slows time and uses large clear icons on a radial layout. UI art was by Jose Ciceraro and team ([Behance](https://www.behance.net/gallery/161745519/Ratchet-and-Clank-A-Rift-Apart-UI-Art), screens indexed at [Interface In Game](https://interfaceingame.com/games/ratchet-clank-rift-apart/)).

### 1.6 Televised robot combat, for tone only

No names, marks, robot designs or graphics are taken from any show. What the genre's broadcasts do as a tone: hard metallic stage, smoke, sodium-orange and cold-white stage light, pyrotechnic stings, a tale-of-the-tape card per competitor (weight class, weapon type, record), fast cuts, loud confident type. We keep the tone (stage light, haze, tale-of-the-tape facts) and drop the decoration (the line bars and sweeps our Broadcast system borrowed).

---

## 2. Cross-cutting patterns in numbers

### 2.1 Where the budget goes

| Pattern | Evidence |
|---|---|
| The static showroom gets the expensive light (RT, higher quality reflections) | GT7 and AC6, sourced above |
| The hero gets the budget, the room stays dark and simple | Stradale review, sourced above |
| Few large lights, all shadowing, locked exposure | Insomniac GDC 2022, sourced |

### 2.2 Light rig

| Item | Value | Source |
|---|---|---|
| Direct to indirect (key to ambient) | 3:1 outdoors | Insomniac, sourced |
| Key to fill, product and car studio | 3:1 to 4:1; 2:1 reads flat, 8:1 reads dramatic | portrait ratio convention [Envato Tuts+](https://photography.tutsplus.com/tutorials/high-key-low-key-an-introduction-to-lighting-ratios--photo-14768), [Adorama](https://www.adorama.com/alc/working-in-studio-key-fill-lighting-101/); car figure est. |
| Rim to key | 1.0x to 1.5x key energy, because it grazes | est. |
| Overhead source | one huge soft source above the car, larger than the car | [Lightmap](https://www.lightmap.co.uk/blog/lighting-for-automotive-rendering/), [Spyne](https://www.spyne.ai/blogs/car-photography-lighting) |
| Overhead "flying flat" size | 3 x 9 m or 4.5 x 12 m for a car, about 1.5x to 2.5x the subject length | car photography guides ([Spyne](https://www.spyne.ai/blogs/car-photography-lighting), [Mammoth](https://www.mammoth.london/post/what-is-the-best-lighting-for-car-photography)); sizes seen in search summaries, not re-read on the page |
| Strip lights | long narrow sources draw "a hard reflection line" along body lines | [Lightmap](https://www.lightmap.co.uk/blog/lighting-for-automotive-rendering/) |
| Black flags | line the floor and surroundings with black so the shape reads; a white room erases the form | [Fstoppers](https://fstoppers.com/automotive/studio-lighting-cars-2649) |
| Colour temperature | studio tungsten 3200 K, daylight and flash 5500 to 6000 K, overcast 6500 K, screens 6500 to 9500 K | [Wikipedia](https://en.wikipedia.org/wiki/Color_temperature) |
| Warm key and cool rim | key 3800 to 4500 K, rim 7500 to 9000 K, fill 6000 to 6500 K | est. (games convention) |

**Why chrome and paint need the room, not just the lights.** A metal surface has no diffuse colour; it shows what it reflects. A metal part under point lights in a black void reflects nothing but a pin highlight and reads as grey plastic. The studio fix is large bright shapes (softboxes, strips) against black, so every panel carries a clean white-to-black gradient. This is the single biggest reason our parts read as toys.

### 2.3 Camera

| Item | Value | Source |
|---|---|---|
| Lens range available to players | 10 to 800 mm | GT7 photo mode, sourced |
| Hero car or product lens | 50 to 85 mm full-frame equivalent | est. |
| Vertical FOV for a 36 x 24 mm frame | 35 mm = 37.8 deg, 50 mm = 27.0 deg, 70 mm = 19.5 deg, 85 mm = 16.1 deg | computed, 2 x atan(12 / f) |
| Turntable | 4 to 6 deg/s (one turn in 60 to 90 s) | est. |
| Camera drift | yaw plus or minus 6 to 10 deg, height plus or minus 3 to 5 cm, dolly plus or minus 3 to 5 %, over 15 to 30 s cycles with unrelated periods | est. |
| Section-to-section camera move | 600 to 900 ms, ease in-out | est. |

### 2.4 Depth of field

| Item | Value | Source |
|---|---|---|
| Showroom feel | f/2 to f/4 at 50 to 85 mm: the subject sharp, the room soft, highlights as round bokeh | GT7 circular bokeh sourced; f-stops est. |
| Focus | on the subject centre; far blur starts just behind the subject | est. |
| Near blur | off for menus (the UI sits in front); on only for close inspection shots | est. |

### 2.5 Materials

| Surface | Value | Source |
|---|---|---|
| High gloss clearcoat roughness | 0.02 to 0.05 | [88Cars3D, UE5 car paint](https://88cars3d.com/2025/12/02/unreal-engine-5-car-paint-crafting-hyper-realistic-automotive-shaders/) |
| Satin clearcoat | 0.2 to 0.4 | same |
| Matte | clearcoat 0.5 to 0.8 with rough base | same |
| Micro-scratches | fine directional noise in the clearcoat roughness only | same |
| Brushed metal | anisotropic highlight along the grain; needs tangents | [Godot BaseMaterial3D](https://docs.godotengine.org/en/stable/classes/class_basematerial3d.html) |
| Roughness breakup | plus or minus 0.05 to 0.12 around the base value at 2 to 3 frequencies | est. |
| Edge wear | 2 to 6 mm chips on convex edges from a curvature mask, 3 to 8 % of painted area | est. |
| Cavity grime | albedo darkened 15 to 25 %, roughness plus 0.1 to 0.2, from AO | est. |

Godot facts: `clearcoat` default 1.0 and `clearcoat_roughness` default 0.5 once enabled; `anisotropy` default 0.0 and needs mesh tangents; rim is a stylised term, not physical ([docs](https://docs.godotengine.org/en/stable/classes/class_basematerial3d.html)). Clearcoat renders wrongly when base roughness is exactly 0.0 in Forward+ and Mobile ([godot#95207](https://github.com/godotengine/godot/issues/95207)); never use 0.0.

### 2.6 Post

| Item | Value | Source |
|---|---|---|
| Order | exposure and key locked first, post last | Insomniac, sourced |
| Tonemapping | hue-preserving highlights for saturated paint | GT7, sourced |
| Grade | saturation and contrast pushed; fog to soften | Insomniac, sourced |
| Bloom | only emissives and speculars above white; threshold at or just above 1.0 | est. |
| Vignette | corners 15 to 30 % darker, starting at 55 to 65 % of the half diagonal | est. |
| Chromatic aberration | 0 to 1.5 px at the frame corners on a 1320 px tall frame, 0 at centre | est.; Insomniac used CA, amount not published |
| Film grain | luminance only, 1 to 2.5 % amplitude, grain 1.5 to 2 px | est. |

Godot 4 defaults for reference ([Environment docs](https://docs.godotengine.org/en/stable/classes/class_environment.html)): glow intensity 0.3, strength 1.0, bloom 0.0, HDR threshold 1.0, HDR scale 2.0, levels 1 to 7 = 0, 0.8, 0.4, 0.1, 0, 0, 0, blend Screen; tonemappers Linear, Reinhard, Filmic, ACES, AgX (AgX contrast 1.25, white 16.29); SSAO radius 1.0, intensity 2.0, power 1.5; SSR 64 steps, fade in 0.15, fade out 2.0, depth tolerance 0.5; volumetric fog density 0.05, length 64. DOF defaults ([CameraAttributesPractical](https://docs.godotengine.org/en/stable/classes/class_cameraattributespractical.html)): blur amount 0.1, far distance 10 m, far transition 5 m, near distance 2 m, near transition 1 m; a negative transition switches to physically based scaling. Docs are the stable (4.7) pages; check each default in 4.6 before relying on it.

### 2.7 Interface and motion

| Item | Value | Source |
|---|---|---|
| Mobile transition | 300 ms typical, full screen 375 ms, enter 225 ms, exit 195 ms, small changes 150 to 200 ms | [Material Design](https://m1.material.io/motion/duration-easing.html) |
| Tile row | 4 to 6 tiles visible, one focused | est., Stradale, Forza, GT7 |
| Tile aspect | 3:2 to 16:9 | est. |
| Focus state | solid bright fill (often near white with dark type), lift 4 to 8 pt, scale 1.03 to 1.06, soft drop shadow; never an outline alone | est., Forza and GT7 footage |
| Stat compare | current value, candidate value, delta arrow; better and worse in two distinct hues, unchanged dim | AC6, est. from footage |
| UI sound | short high clicks and chirps, kept out of the machine's frequency band | AC6, sourced |

---

## 3. What Roboteer should adopt

Target: Godot 4.6 Forward+, iPhone 17 and 18 Pro Max, 2868 x 1320 px (956 x 440 pt at 3x), 60 fps. All numbers below are starting values; every one is est. unless it restates a sourced fact, and all must be measured on the phone.

### 3.0 What this supersedes

For the main menu and garage, this spec replaces these parts of `docs/design-system.md`:

1. The 3 pt `line` bar on the leading edge of lower thirds and buttons: **removed**.
2. The 1 px `line` hairline along panel bottoms, the `line` rim on score bugs and the `line` focus ring: **removed**.
3. "Selection is a sweep of `line` fill from the leading edge. Never scale": **replaced** by the focus state in 3.5.
4. The 12 degree skew for menu buttons and cards: **removed** here. Shapes are upright rectangles with the existing 10 pt cut corner.

No coloured edge strokes, skewed accent lines or cyan edge bars on any button, card or panel. Emphasis comes from weight, fill, type size, the chamfered shape and stage light. `line` survives only as a fill colour for small data (stat delta segments) and never as a border. `docs/design-system.md` should be updated to match when this is built.

### 3.1 Light rig (main menu and garage share one stage)

The current rig in `Arena/workshop/stage.gd` is a cold key 7.0, fill 2.6 and warm rim 2.4 (key to fill about 2.7:1, rim well under key), no strip lights and no reflection probe. Replace with:

1. **Exposure first.** Lock `tonemap_exposure` (start 1.0 with AgX, or keep 1.25 with ACES) and no auto exposure in menus. Set it once, then tune lights, never the reverse (Insomniac order).
2. **Key: SpotLight3D**, front left, 35 deg above the bot, 2.6 m away, `spot_angle` 28, `light_energy` 7.0 (keeps today's measured brightness), colour 4300 K (sRGB about 1.00, 0.84, 0.70), shadows on, `light_size` 0.15 for soft contact edges, `shadow_blur` 1.5.
3. **Fill: SpotLight3D**, front right, low (15 deg), `light_energy` 1.75 (**key to fill 4:1**), 6500 K (1.00, 0.98, 0.98), shadows off.
4. **Rim: SpotLight3D x 2**, behind left and behind right, 25 to 30 deg up, `light_energy` 8.5 each (**1.2x key**, grazing), 8500 K (0.86, 0.90, 1.00), shadows off, aimed to catch the top and side edges only.
5. **Top softbox: emissive plane**, 1.6 x 0.6 m, 2.2 m above the stage, `emission_energy_multiplier` 3.0, unshaded, not visible to the camera (above frame), plus a weak OmniLight3D under it (`light_energy` 1.2, 5600 K, range 3 m, shadows off) for its diffuse contribution. The plane exists to be reflected.
6. **Two strip lights: emissive boxes** 2.4 x 0.08 m at 45 deg either side behind the stage, `emission_energy_multiplier` 4.0, 6500 K. They draw the long highlight lines along plates and weapon blades. Keep them just out of frame or visible as soft practicals at the room edge.
7. **ReflectionProbe** centred on the stage, box 8 x 4 x 8 m, `box_projection` on, `interior` on, `update_mode` ONCE, re-captured only when the room changes. This is where the softbox and strips reach the metal, at near zero per-frame cost (the GT7 and AC6 lesson: spend on the static showroom).
8. **Black flags.** Walls and floor beyond 3 m are near black (albedo 0.02 to 0.03 linear) so reflections read as clean light shapes on dark, never a grey room.
9. **Room accent.** Keep the existing amber mover as the one saturated warm in frame (existing rule in `stage.gd`), 2100 to 2500 K, and the dry ice haze. It lights the room and the haze, not the bot.
10. **Ambient** stays at 0.05 energy; with the probe on, direct to indirect on the bot lands near the 3:1 Insomniac figure. Check it with a grey sphere (albedo 0.18) on the stage: lit side to shadow side 3:1 to 4:1 in the captured frame.

Colour temperatures: if physical light units are off, set `light_color` from the sRGB values given (Kelvin to RGB approximations, est.); if they are on, use `light_temperature`.

### 3.2 Camera

1. **Main menu hero:** `Camera3D.fov` 27 deg vertical (50 mm), distance 2.8 m, height 0.55 m above the stage top, pitched down 8 deg. The bot occupies 36 to 42 % of frame height, centred horizontally, centre at 42 % from the top so it clears the tile row. At this distance 1 px is about 1 mm on the bot.
2. **Turntable:** 5 deg/s (72 s per turn; today 8 deg/s). Pauses on touch, resumes 4 s after release with a 1.2 s ease-in.
3. **Drift** (added to the camera, not the bot): yaw plus or minus 7 deg over 23 s, height plus or minus 4 cm over 17 s, dolly plus or minus 3 % over 29 s, all sine, unrelated periods so it never visibly loops. Max camera speed stays under 1 deg/s so it reads as breathing, not motion.
4. **Garage overview:** 35 mm (37.8 deg) is too wide; use 40 mm (33.4 deg), bot framed in the left 55 % of the frame (existing rule: left side clear of panels), distance 2.6 m.
5. **Garage part focus:** 70 mm (19.5 deg), distance 1.3 to 1.8 m, aimed at the socket of the selected category, moved over 750 ms ease in-out cubic, the focus distance pulled on the same curve.
6. **Drag to orbit** in the garage: 0.25 deg per pt, pitch clamped 2 to 35 deg, inertia with a 0.35 s decay.
7. **DOF with `CameraAttributesPractical`:** menu: `dof_blur_far_enabled` true, `dof_blur_far_distance` = camera to bot distance + 0.7 m (about 3.5 m), `dof_blur_far_transition` 2.5 m, `dof_blur_amount` 0.07, near off. Part focus: far distance = focus + 0.35 m, transition 1.2 m, amount 0.09; near on at 0.6 m with transition 0.3 m. Project settings: bokeh shape Circle, bokeh quality Low on medium tier and Medium on high tier, jitter on (costs nothing extra with TAA off, est.). `CameraAttributesPhysical` (50 mm at f/2.8) is the alternative if we move to physical light units; do not mix the two.

### 3.3 Materials per part class (Godot `StandardMaterial3D`, material slots from `docs/graphics-bar.md`)

Common to every part: bevels **4 to 8 mm** on major plate edges (today 2 to 4 mm, which is 2 to 4 px at the menu distance and too thin to hold a rim highlight), weighted normals, a baked curvature map and AO map per atlas, roughness never uniform.

| Slot | Albedo (linear) | Metallic | Roughness | Extras |
|---|---|---|---|---|
| `steel` (brushed) | 0.56, 0.57, 0.58 | 1.0 | 0.32, breakup plus or minus 0.08 | `anisotropy` 0.7 with a flowmap along the brush direction (export tangents from Blender); scratch normal at 1024 |
| `titanium` | 0.54, 0.50, 0.45 | 1.0 | 0.28, breakup plus or minus 0.06 | `anisotropy` 0.3; heat tint (straw to blue gradient) within 15 mm of welds; this reads as a premium metal |
| `dark_metal` (powder coat) | 0.04 to 0.06 | 0.0 | 0.55 | edge wear to bare steel on curvature, 2 to 4 mm |
| `hdpe` | per livery, value capped at 0.7 | 0.0 | 0.60, breakup plus or minus 0.10 | gouges and stress whitening: albedo lightened 20 % and roughness 0.8 in scuffs; no clearcoat |
| `polycarbonate` | tint 0.85, 0.9, 0.95 | 0.0 | 0.10, scratches to 0.35 | `transparency` Alpha Depth Pre-Pass, alpha 0.4; smoked for the dark look; scratches catch the strip lights |
| `rubber` | 0.03 to 0.04 | 0.0 | 0.90 | tread normal; dust in grooves (albedo 0.10, roughness 1.0 via AO) |
| `livery` paint | the livery colour, value capped at 0.75 | 0.0 (0.3 for metallic liveries) | base 0.40 | `clearcoat` 1.0, `clearcoat_roughness` 0.05 (gloss) or 0.25 (satin livery option); micro-scratches only in the clearcoat roughness; edge wear from curvature exposing primer then steel, 2 to 6 mm, 3 to 8 % of painted area; cavity grime from AO, albedo minus 20 %, roughness plus 0.15; decals (numbers, stencils, original marks only) baked into the livery atlas |
| `core_glow` | | | | emission 2.5 to 4 (above the glow threshold), the only thing on the bot that blooms |

Never set base roughness to exactly 0.0 on a clearcoated material (godot#95207). Damage in fights keeps adding decals on top (existing system).

### 3.4 Post (Godot `Environment` for the stage)

| Setting | Value | Today |
|---|---|---|
| `tonemap_mode` | AgX, `tonemap_agx_contrast` 1.4; A/B against ACES on a red and a yellow livery, keep whichever holds hue in the rim highlights (the GT7 lesson) | ACES, exposure 1.25, white 1.4 |
| `glow_hdr_threshold` | 1.1 (only emissives, strips and speculars bloom, never lit paint) | 0.95 |
| `glow_intensity` / `glow_strength` / `glow_bloom` | 0.45 / 1.0 / 0.0 | 0.6 / 1.05 / 0.05 |
| `glow_levels` | 2 = 0.3, 3 = 0.8, 4 = 1.0, 5 = 0.6, 6 = 0.2 | similar, keep |
| `glow_blend_mode` | Screen | Additive |
| SSAO | on, radius 0.5 m, intensity 1.8, power 1.5, detail 0.5, half size | on |
| SSR | on for the glossy stage floor only (floor roughness 0.22), max steps 32, fade in 0.15, fade out 2.0, depth tolerance 0.2; first thing dropped on the medium tier | on |
| Volumetric fog | keep, density 0.02, length 16, anisotropy 0.55; volume size 48, depth 32 in project settings on high tier | on |
| Adjustments | contrast 1.08, saturation 1.06, brightness 1.0 | contrast 1.08 |
| Vignette | full-screen shader in Godot (not the Swift overlay, so it sits under the UI): corners 22 % darker, start at 60 % of the half diagonal, smooth | none |
| Chromatic aberration | 0.8 px at corners, 0 at centre, off on the medium tier | none |
| Film grain | luminance only, 1.5 % amplitude, 2 px grain, animated at 24 Hz | none |
| Anti-aliasing | MSAA 2x plus FXAA; no TAA (ghosting on the turntable) | check |
| 3D resolution | 0.75 scale with FSR 1 sharpening 0.3 on high tier, measure before settling | check |

Budget target (est., to be measured): shadows 2 ms, opaque 5 ms, SSAO 1 ms, SSR 1.5 ms, volumetric fog 1.5 ms, DOF 1 ms, glow and post 1 ms, total under 14 ms for headroom. Drop order when over: SSR, then volumetric fog to the fake haze, then DOF quality, then soft shadows (matches `docs/graphics-bar.md`). Ship the three Stradale-style modes: Quality (all on), Performance (the drop order applied, 60 fps locked), Energy Saving (Performance at 30 fps, no fog).

### 3.5 Interface

**Main menu layout** (pt at 3x; px in brackets). Safe insets in landscape 62 pt left and right, 21 pt bottom (est.). Usable width 832 pt.

1. **Tile row** along the bottom, 5 tiles visible, bottom edge 35 pt above the frame bottom, tile height 96 pt (288 px), so the row fills y 309 to 405 of 440 and the bot owns the top 70 %.
2. **Primary tile** (the next career fight, Continue): 232 x 96 pt (696 x 288 px), aspect 2.4:1, always first on the left. Holds the title (Barlow Condensed 800 Italic, 22 pt), one body line naming the opponent and round (15 pt, `typeDim`), and a small 3D render of the opponent's machine.
3. **Four standard tiles** (Quick fight, Garage, Events, Ladder): 140 x 96 pt (420 x 288 px), aspect about 3:2, gap 10 pt (30 px). Each has a rendered thumbnail in the top 60 % (lit with the same rig, captured offline) and a label bottom left, 17 pt 700 caps. Replays and Settings stay small at the top right as text links.
4. **Resting tile:** fill `glass` #0E1218 at 72 % over a 12 pt background blur, label `type`, the 10 pt cut corner top right, no border of any kind.
5. **Focused tile** (the current selection; the primary is focused on arrival): fill `type` #F4F6F8 at 94 %, label and body switch to `ink`, lift 6 pt, scale 1.04, drop shadow `ink` 45 %, 0 x 10 pt offset, 24 pt blur. One focused tile at a time. That is the whole emphasis system: fill, weight, lift, light.
6. **Pressed:** scale 0.97 over 90 ms, release springs back in 160 ms, then the action.
7. **Stage reacts to focus:** focusing Garage eases the camera 4 deg toward the weapon side and raises the rim 10 %; focusing Quick fight warms the room accent. The 3D scene is the emphasis, not decoration on the tile.
8. **Title and scrap:** title top left as display type (44 pt), scrap top right as a plain numeral with its label, no bug rim.

**Garage layout.**

1. Bot in the left 55 % (existing rule).
2. **Category row** along the bottom, same metrics as the menu: Chassis, Drive, Weapon, Armour, Utility, Paint, 6 tiles at 128 x 80 pt, gap 10 pt, row 818 pt wide.
3. **Part list:** selecting a category raises a second row of part cards directly above it (5 visible, 150 x 112 pt, horizontal scroll with 10 pt peek of the sixth), each card a studio render of the part on black with name and one key number. The camera moves to that socket (3.2 item 5).
4. **Compare panel** (the AC6 pattern) in the right column, one panel only: each stat as a label, the current value as a `typeDim` bar, and the candidate's difference as a filled segment, `line` fill where better and `danger` fill where worse, with the new numeral in 700 tabular; unchanged stats dim to 50 %. Fills, never outlines.
5. **Equip** plays the part's bolt-on animation on the stage (0.5 s) before the stats settle.

**Motion timings.**

| Event | Duration | Curve |
|---|---|---|
| Focus in / out | 140 ms / 110 ms | ease-out cubic / ease-in quad |
| Pressed / release | 90 ms / 160 ms | ease-out / spring, damping 0.8 |
| Tile row enters | 260 ms per tile, 35 ms stagger, from 24 pt below, opacity 0 to 1 | ease-out cubic |
| Screen change (menu to garage) | 320 ms UI; camera 750 ms under it | ease in-out cubic |
| Part row raise | 220 ms | ease-out cubic |
| Stat bars resolve | 300 ms; numbers count over 400 ms (existing rule) | ease-out |
| Parallax | tiles shift 0 pt, the 3D scene carries all depth; UI never parallaxes | |

**Sound and haptic cues** (mixed so UI sits above 2 kHz and the machine owns the lows, the AC6 principle):

1. Focus change: short dry tick, 30 to 50 ms, centred near 3 kHz, minus 18 dBFS; light haptic.
2. Confirm: tick plus a low metal "clunk" with a short ring, 180 ms; medium haptic.
3. Back: the tick reversed and darker, 60 ms.
4. Category open: a pneumatic hiss, 250 ms, under the camera move.
5. Part equip: impact wrench burst plus bolt seat, 350 to 500 ms; rigid haptic on the seat.
6. Paint apply: spray hiss 250 ms.
7. Stat better / worse: rising / falling two-note chirp, 120 ms.
8. Cannot afford: a dull thud, 120 ms; warning haptic; no tile shake.
9. Room tone under everything: ventilation hum, a faint electrical buzz from the practicals, distant crowd murmur for the stage, minus 30 dBFS; the turntable motor at minus 36 dBFS.

### 3.6 Attract and idle mode

1. After 25 s without a touch, tiles and title fade out over 600 ms; scrap and the top links go too.
2. The camera runs a shot list, 5 shots, 7 s each, joined by 0.8 s crossfades: slow push-in on the weapon (85 mm, 2 % per second), low three-quarter orbit (40 mm, 3 deg/s), rim-light pass (a strip light sweeps across in 4 s), top-down turn over the stage (50 mm), and a wheel or drive close-up at 70 mm with shallow DOF. The amber mover sweeps once per cycle.
3. Any touch restores the UI in 200 ms and returns the camera to the hero framing over 700 ms; the touch is not treated as a tap on a tile.
4. After 90 s idle the stage drops to 30 fps and stops volumetric fog updates; after 5 min it dims to 40 % exposure. Battery matters on a phone.

### 3.7 Acceptance

1. A still of the menu next to a Stradale menu still: the bot's metal shows at least two clean strip reflections and a lit rim on every top edge; no plate reads as a flat colour.
2. Grey sphere check: lit to shadow side 3:1 to 4:1.
3. No stroke, bar, skewed line or outline on any tile, button or panel.
4. 60 fps held on the phone for 60 s in the menu and 60 s of garage use, measured on device.
5. Every string in the UI: plain sentences, no em dashes.
