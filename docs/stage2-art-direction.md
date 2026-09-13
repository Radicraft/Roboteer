# Stage 2: art direction validation

Three renders, no code. The purpose is to prove the locked direction in §13 of `brief-v3.md` survives contact with a real image: stylised low poly 3D, chunky readable silhouettes, flat or lightly shaded materials, tabletop miniature rather than photoreal or cartoon, with the GBC homage confined to the SwiftUI chrome.

Final files:

- `Art/direction/bot-in-workshop.png` (4096 x 3018, 4:3)
- `Art/direction/arena-mid-fight.png` (4096 x 2048, 2:1)
- `Art/direction/bracket-screen.png` (4096 x 2048, 2:1)

Rejected and shortlisted candidates are kept in `Art/direction/candidates/`, three per render.

Total Recraft spend: **32 credits** (29 on generation, 3 on upscales). Budget was 90.

---

## Render 1: bot-in-workshop.png

**Model:** `recraftv4_1_raster`. **Style id:** none. Recraft V4.1 rejects the `digital_illustration` style parameter outright (`invalid_image_type`), so the low poly look has to be carried entirely by the prompt. That is worth recording for every later Recraft call in this project.

**Aspect:** 4:3. **Credits:** 6 for three variants, 1 for the upscale.

**Final prompt**

> Stylised low-poly 3D render of a single original combat robot standing on a circular metal workshop turntable, viewed from a near-orthographic isometric game camera at about 45 degrees yaw and 50 degrees pitch looking down. The robot is a low wedge-shaped chassis with a sharp sloping front ramp, four chunky black rubber wheels, a pneumatic flipper plate hinged at the front of the wedge, and a small hinged self-righting arm folded on top. Armour panels are visibly different materials on different faces: a brushed bare steel front wedge, flat matte orange plastic side panels, a smoky translucent polycarbonate rear panel, with visible hex bolt heads at the panel corners. Light battle wear on the front wedge only: a few pale scratch scuffs and one small scorch smudge. Faceted low-polygon geometry, flat or very lightly shaded materials, no gloss, no reflections, chunky readable silhouette, like a well-made painted tabletop miniature, not photorealistic and not cartoon. Behind it a wooden workbench with a perforated pegboard wall holding simple spanners and pliers, a small vice, a coil of wire. Warm tungsten workshop key light from the upper left, soft cool fill, gentle shadow on the turntable. Muted industrial colour palette. No text, no letters, no numbers, no logos, no signage, no people.

**Why the pick won (candidate `01-bot-a`)**

It is the only variant that reads correctly on all four of the things the brief actually asks a builder screenshot to prove. The camera sits at the game's angle, so the turntable ring and the floor plane establish the same isometric read the arena will use. The per face armour story is legible without a caption: bare scratched steel on the front wedge, flat orange plastic down the side, a darker smoked panel across the rear quarter, and hex bolt heads marking every panel seam so the eye can see the machine is assembled from separable parts. The srimech arm is a distinct jointed shape standing proud of the top plate, which is the silhouette element that says self righting rather than decoration. The battle wear is restricted to the front wedge, three pale scuffs and one scorch smudge, which is exactly the "damage carries the visual load" idea at its quietest end, before a fight rather than after.

**What the rejected ones got wrong**

- `01-bot-b` is the prettiest miniature of the three and has the best material separation on the rear polycarbonate panel, but the srimech reads as an unattached wedge of scrap sitting on the roof, the flipper reads as a loose grey slab rather than a hinged plate, and the front wheels are hidden by the body so the drive count is not readable. A builder render that cannot show you your own wheel count fails its job.
- `01-bot-c` put six wheels on a bot specified as 4WD, and painted the front wedge as rust brown rather than steel, which collapses the steel versus plastic contrast the armour system depends on. It is kept only as a reference for how good the wheel geometry looks at this scale.

**Carry over note:** the wedge plus flipper plus srimech silhouette is a genre standard rather than a copy of any single machine, but the colourway matters for §3. Keep this bot orange and steel. A white and black wedge with a full width front flipper would start to read as a specific famous competitor, and that read is a silhouette and livery problem, not a name problem.

---

## Render 2: arena-mid-fight.png

**Model:** `recraftv4_1_raster`. **Style id:** none. **Aspect:** 2:1. **Credits:** 6 for the first three variants, 4 for a tuned pair, 1 for the upscale. 11 total.

**Final prompt**

> Stylised low-poly 3D video game render, wide landscape, of two original wheeled combat robots fighting inside a small enclosed steel arena, near-orthographic isometric camera at about 45 degrees yaw and 50 degrees pitch, whole square arena floor plan visible. Scuffed steel floor with yellow and black hazard chevrons at the edges, low scratched steel perimeter walls, and two floor-mounted spinning angle grinder discs set into the floor on the left and right flanks, the left one throwing a bright orange spark fan. Centre left: a dark blue four wheeled wedge robot with a broad steel flipper plate hinged at its nose, the plate swung fully up and open. Centre right: a yellow boxy four wheeled robot flung into the air above it, tumbling on its side, wheels spinning. One detached black wheel rolls free on the right, and one large dull grey bent armour panel lies flat on the floor nearby. At the point of impact only, a tight compact burst of about thirty tiny bright gold spinning bolts and nuts, clearly much smaller and far brighter than the dull grey debris, not scattered across the whole floor. Faceted low polygon geometry, flat lightly shaded materials, no gloss, chunky readable silhouettes like painted tabletop miniatures, strong contrast between dark chassis and bare steel weapons, scorch marks and scratch decals on the floor. No user interface, no HUD, no text, no letters, no numbers, no logos, no crowd.

**Why the pick won (candidate `02-arena-d`)**

This is the only frame that carries every piece of information the fight screen has to carry at once and still reads at phone size. The Grinder is unmistakably itself: an enclosed square floor plan, low walls, and a floor mounted grinder disc on each flank, the left one throwing a spark fan. The flip is unambiguous because the yellow bot is airborne, rotated off its axis, with spin arcs on two wheels, and it is large in frame, so at 400 points wide you still see a robot in the air rather than a smear. Critically it passes the §6 readability rule on the first glance: the bolts are a tight bright gold cluster at the point of contact, small and clumped, while the structural debris is a separate visual class, two dull grey bent panels and two loose dark wheels, each larger, matte, and lying still on the floor. Nobody would drive across the arena to collect one of those panels. The fourth thing it proves is that the 45 degree yaw and 50 degree pitch framing fits the whole floor plan into a 2:1 phone landscape without losing the walls, which was the camera claim in §11.

**What the rejected ones got wrong**

- `02-arena-a` turned the aggressor into a legged mech with a hammer arm. Wrong genre, and a walking robot is outside the part library in §5 entirely.
- `02-arena-c` mixed small dark specks into the gold bolt spray, which is precisely the confusion the readability rule forbids. Kept as a candidate because its twin ram flipper assembly is a good modelling reference.
- `02-arena-b` is the flattest and most miniature like shading in the set and has the clearest single detached wheel, but its bolt shower is scattered as a confetti field across a third of the floor. That is both a wrong count and a wrong behaviour: bolts converge on the attacker, they do not carpet the arena. Kept as the shading reference.
- `02-arena-e` has the best flipper read in the whole batch, a genuine broad plate hinged at the nose and swung fully up, and the cleanest flat materials, but it is underlit, only one grinder is doing anything, and the camera is zoomed in far enough that the floor plan is lost.

**Known weakness of the pick, to correct in 3D:** the chosen frame is the most texture heavy image in the set. Its walls carry grunge and its grinder discs carry specular highlights, which drifts toward photoreal and away from the locked flat material target. Treat `02-arena-b` and `02-arena-e` as the material reference and `02-arena-d` as the composition and content reference. The gold bolts also render as spheres here rather than bolt heads, so the real particle needs a faceted hex head silhouette to sell what it is.

---

## Render 3: bracket-screen.png

**Model:** `recraftv4_1_raster`. **Style id:** none. **Aspect:** 2:1. **Credits:** 3 wasted on a rejected `recraftv3` batch, 6 for three V4.1 variants, 4 for a tuned pair, 1 for the upscale. 14 total.

**Method note:** this MCP surface exposes no `list_basic_styles` tool, so there is no pixel art basic style to select and the look has to be prompted. The first attempt used `recraftv3` with `digital_illustration` as suggested by `suggest_model`, and all three variants ignored the interface instruction and drew a green forest landscape with the bracket floating over it. `recraftv4_1_raster` with an explicit negative list (no landscape, no trees, no sky, no scenery, no console bezel) fixed it completely on the first try. For UI chrome, prompt adherence beats style compatibility.

**Final prompt**

> A flat pixel art user interface screen for a mobile game, wide landscape, filling the whole frame. Strictly four shades of green from the classic Game Boy palette: darkest green #0f380f as the background, dark green #306230, mid green #8bac0f, pale yellow green #9bbc0f. No other colours, no white, no black, no brown. Layout: a heading bar across the top reads REGIONAL CIRCUIT in chunky bitmap pixel capitals. Below it a single elimination tournament bracket with exactly four columns. The first column is a vertical stack of EIGHT small name plates, evenly spaced, each plate holding a tiny sixteen by sixteen pixel art portrait of a blocky wheeled combat robot at its left and a short name in chunky bitmap pixel capitals: SKIDMARK, HALF NELSON, BRIQUETTE, COG ROT, TIN VICAR, DUSTPAN, MEATLOAF, PIGEON, from top to bottom. The second column has exactly four empty plates, the third column exactly two, the fourth column one final plate, joined by chunky right angled pixel connector lines. The plate for COG ROT in the first column is highlighted as a solid pale green block with dark text and a small arrow marker pointing at it. A faint dot matrix grid and horizontal scanline texture over everything. Crisp hard pixel edges, no antialiasing, no gradients. A designed app screen, a flat graphic diagram. No landscape, no trees, no sky, no scenery, no console bezel, no hands.

**Why the pick won (candidate `03-bracket-e`)**

It is the only variant that is both a correct eight entrant bracket and a screen rather than a picture. Eight named plates stack down the left, the rounds narrow to the right, and the empty later plates are honest: a bracket you have not played yet has empty slots, and that is a real state the SwiftUI view will need. The portraits sit inside the slots as specified, each a small wheeled bot with a readable weapon bump, and they hold up at portrait size rather than turning to mush. The player highlight works as a value swap rather than an accent colour, a mid green plate against pale ones with a pale arrow beside it, which is the only kind of emphasis a four tone palette allows and is therefore the right pattern to copy into SwiftUI. The type is a genuine chunky bitmap face with square terminals, all capitals, and it is legible at the size a phone will actually show it.

**What the rejected ones got wrong**

- The three `recraftv3` variants drew a landscape illustration with a bracket in it. Deleted.
- `03-bracket-a` and `03-bracket-b` both built four entrant brackets padded out with extra rounds, and their portraits are humanoid mechs with faces rather than wheeled combat robots. Deleted.
- `03-bracket-c` is the most attractive image of the whole batch, with every slot filled, a proper heading, and a strong highlight, but it is structurally a four entrant bracket and it repeats an entrant name in two rounds. Kept as the type and texture reference because its heading and its plate rhythm are better than the pick's.
- `03-bracket-d` has the best drawn bot portraits but parks them in a column outside the plates, which breaks the slot as a single tappable unit, and its highlight is ambiguous between two adjacent rows.

**Known weakness of the pick:** the second column should hold four slots and holds three, and the connector lines pair the first three entrants into one match. It is a look reference, not a layout spec. The SwiftUI view builds the tree from data and will be correct by construction.

**IP position:** all eight names are invented and none matches a known competitor robot, house robot, or show mark, and the bracket furniture is generic tournament geometry with no show typeface. The names still need a clearance search before any of them ship in a build, since this was a judgement call and not a trademark check.

---

## Palette

### The four greens, sampled from `bracket-screen.png`

| Role | Hex | Where it appears |
|---|---|---|
| Deepest | `#00531e` | Glyph interiors, plate text, portrait outlines |
| Dark | `#056327` | Page ground behind the bracket |
| Mid | `#7ebd63` | Heading bar, connector lines, the player highlight plate |
| Light | `#f0fda9` | Name plate fill, heading glyphs, arrow marker |

These four are what the render actually uses, and the relationships are right: one ground, one fill, one structural mid, one deepest for type. The hues are not right. Recraft pulled toward a saturated emerald and a cream rather than the yellow green of a DMG screen, so the render is a proof of the structure and not a colour spec.

**Locked for the SwiftUI chrome, use these instead:** `#0f380f` deepest, `#306230` dark, `#8bac0f` mid, `#9bbc0f` light. Four tones and no fifth, ever, including for disabled states, alerts and focus rings.

### Dominant colours of `arena-mid-fight.png`

| Hex | Role |
|---|---|
| `#c5d9d5` | Arena floor steel, lit |
| `#84a6b2` | Arena floor steel, mid tone |
| `#516e78` | Chassis blue, lit faces |
| `#32474e` | Chassis blue, shadowed faces |
| `#0f1b23` | Tyres, joint shadows, the darkest structural line |
| `#e6b53f` | Gold bolts and the yellow bot, the one saturated warm in the frame |
| `#c3b98c` | Hazard chevron yellow, dusted down |
| `#e7f7fc` | Spark cores and specular edges |

The useful finding is the ratio. Roughly four fifths of the frame is a cold grey blue range and the only strong warm is gold, which is what makes the bolt shower read instantly against the floor. Protect that. If a bot livery, a hazard marking or a UI overlay introduces a second saturated warm into the arena, the bolts stop being the brightest thing on screen and the §6 readability rule breaks without anyone changing the bolt art.

---

## Guidance for the 3D modelling stage

Model every part so its function is legible from the silhouette alone at the default camera, because at 45 degrees yaw and 50 degrees pitch on a phone the player reads outline before surface: a wedge must have a visibly sharp ground edge, a flipper must be a broad plate hinged at the nose rather than a thin arm, a srimech must stand proud of the top plate as its own jointed shape, and the wheel count must never be occluded by bodywork. Keep materials flat and separated by value rather than by texture, one shared atlas, bare steel as the brightest structural value, plastics as flat unlit colour, and tyres and joints as the darkest value in the scene, so that a chassis and the weapon bolted to it never merge into one mass. Build the damage language as three additive layers on top of that flat base, scratch decals that accumulate, scorch smudges that darken a panel without changing its hue, and bent or missing panels that expose a deliberately uglier interior, and keep detached structural debris matte, grey and large so it can never be mistaken for the small bright gold bolts.

## Guidance for the SwiftUI chrome

Use one chunky bitmap face at a small set of fixed pixel sizes, all capitals for headings and labels, and let it alias hard rather than smoothing, because the moment the type antialiases against the four tone ground the homage collapses into a green tinted modern app. Build the whole chrome from the locked four greens with emphasis expressed as a value swap, a plate that inverts from light fill to mid fill, never as a fifth colour or an opacity fade, and treat that constraint as the design language rather than a limitation to work around. Apply the dot matrix and scanline texture as one consistent overlay at a fixed pixel scale across every chrome screen so menus, bracket, loading and stat cards feel like one device, and keep it entirely out of the arena, which stays full colour full 3D with no green cast and no scanlines at all.
