class_name WorkshopStage extends Node3D
## The AAA menu and workshop stage: the player's own bot, centre stage, on a dark
## floor under three moving stage lights with visible haze and dry ice.
##
## Spec: docs/stage4-spec.md section 5, docs/stage2-art-direction.md "Owner decision
## 2026-09-13: menus are AAA cinematic". This is the live backdrop behind every
## SwiftUI menu screen as well as the builder turntable, so it has to be cheap: four
## lights, one shadow caster, three particle emitters, and no volumetrics (the mobile
## renderer has no FogVolume, so the beams are additive cone meshes).
##
## Presentation only. Nothing here is read by the fight simulation and the bot on the
## stage is frozen static so physics can never roll it off the disc.
##
## Everything below the root is built in code, so `WorkshopStage.new()` works as well
## as instancing `stage.tscn` and the headless test needs no display server.
##
## ANIMATION (agent S, 2026-09-14, owner: "I want this to be animated with the smoke
## swirling at the base and changing the light on the featured robot"). Everything that
## moves is driven from _process off this node's own clock, so it keeps running behind the
## SwiftUI menus and in both camera modes; nothing is gated on fight state. What moves and
## at what period is written down in docs/stage-animation.md, and tests/stage_animation_test.gd
## asserts every bound below. The calibrations above this line are unchanged: the fog ring
## still sits outside the 1.5 m rim, still hugs the floor under 0.2 m, and the per quad
## alpha is LOWER than before because there are more quads.

## Emitted after every show_bot(), carrying bot_summary().
signal ready_for_host(summary: Dictionary)

const BOT_SCENE := "res://bot/bot.tscn"
## Rendering (agent G1): the environment resource and the quality autoload.
const ENV_RESOURCE := "res://render/stage_env.tres"
const QUALITY_SCRIPT := "res://render/graphics_quality.gd"
## Agent S 2026-09-14: the two stage shaders. Both have an inline fallback below, so a
## checkout without res://render/stage/ still builds a stage, just a stiller one.
const BEAM_SHADER := "res://render/stage/beam.gdshader"
const GROUND_FOG_SHADER := "res://render/stage/ground_fog.gdshader"
const SOFT_SPRITE_SHADER := "res://render/stage/soft_sprite.gdshader"
const DEFAULT_CONFIG := "res://fight/fixtures/stage3_config.json"
const ARG_WORKSHOP := "--roboteer-workshop"

## Bridge contract (docs/stage4-spec.md section 5).
const MSG_WORKSHOP_CONFIG := "workshop_config"
const MSG_WORKSHOP_READY := "workshop_ready"
## Wave A: the stage also answers the shell's forwarded gestures while its own director
## has the picture (docs/bridge-spec.md). fight.gd still routes them to the rig as well,
## which is harmless: the rig's camera is not current then.
const MSG_STAGE_CAMERA := "stage_camera"
const DIRECTOR_SCRIPT := "res://workshop/stage_director.gd"
const FLOOR_SHADER := "res://render/stage/stage_floor.gdshader"
const POST_SHADER := "res://render/stage/stage_post.gdshader"
## Desktop QA: `--roboteer-shot=faceoff|showroom|garage|part:weapon`.
const ARG_SHOT := "--roboteer-shot="

## Geometry, metres.
const STAGE_RADIUS := 1.5          # a 3 m disc
const STAGE_HEIGHT := 0.12         # the raised lip the bot stands on
const FLOOR_SIZE := 16.0
const BACKDROP_DISTANCE := 7.0
const BACKDROP_HEIGHT := 6.0

## Idle turntable rotation, degrees per second (spec section 5).
const AUTO_ROTATE_DEG_PER_S := 8.0

## Colours, calibrated against Art/direction/menu-stage.png: the key art is mostly
## BLACK. The floor, the disc and the backdrop are all near zero and every visible
## value on screen is put there by a light, not by an albedo or by ambient.
const COL_FLOOR := Color(0.028, 0.030, 0.035)
## The plate floor shader's base: a touch lighter, rougher and less metal than the flat
## fallback so lit pools and seams read, and still under workshop_test's 0.04 black-frame
## guard (a brighter 0.09 plate was tried: no visible gain, the floor needs light, not albedo).
const COL_PLATE := Color(0.034, 0.036, 0.040)
const PLATE_ROUGHNESS := 0.3
const PLATE_METALLIC := 0.45
const COL_STAGE := Color(0.042, 0.044, 0.050)    # dark charcoal, as in the key art
const COL_RING := Color(0.11, 0.115, 0.13)
## The thin light edge. COOL white, not gold: gold is reserved for scrap and the bolt
## shower (docs/stage2-art-direction.md, the palette section), and a gold ring on the
## stage puts a second saturated warm in a frame whose only warm should be the amber
## mover. Changed by agent G1 2026-09-13.
const COL_EDGE := Color(0.76, 0.87, 1.0)
const COL_BACKDROP := Color(0.006, 0.009, 0.016) # effectively black
const COL_AMBER := Color(1.0, 0.66, 0.28)
const COL_BLUE := Color(0.38, 0.66, 1.0)
## Wave A: the key is 4300 K and the rims are cold (they were the other way round).
const COL_KEY := Color(1.0, 0.84, 0.70)          # warm key on the bot
const COL_RIM := Color(0.86, 0.90, 1.0)          # cold rims from behind

## Light budget: 3 movers + a key and a rim on the bot. Only the key casts a shadow.
const MOVER_ENERGY := 3.4
## HALF angle. The key art's shafts are narrow; 16 degrees filled the whole frame.
const MOVER_ANGLE_DEG := 8.0
## Peak alpha of a beam cone at the lens, falling to zero at the floor. Additive, so
## two crossing beams must still read as translucent. G1 2026-09-13: 0.06 with a 2.2
## fade left the shafts invisible below the lamp head in the shot frames, so the alpha
## is up and the fade is much flatter, which is what carries the beam down to the floor.
## It stays under 0.10 because two crossing beams must not clip to white.
const BEAM_ALPHA := 0.095
const BEAM_FADE_POWER := 1.25
## Volumetric shafts (high tier only): how much fog each mover lights. The key and the
## rim are pulled down instead, because a 3.6 energy key in real fog is a white wall.
## 4.5, was 2.2: the first high tier frames had no visible shaft at all.
const MOVER_FOG_ENERGY := 4.5
const KEY_FOG_ENERGY := 0.25
## When real fog IS drawing, the additive cones and the billboards stay on underneath it
## at this fraction of their alpha. They are three cones and 150 quads that never write
## depth, they cost almost nothing, and they are the reason the high tier can never come
## out WORSE than the low tier, which is the frame the owner has already accepted.
const FAKE_HAZE_GAIN_WITH_FOG := 0.5
## A beam cone is a solid additive shell, so a camera INSIDE one is looking through the
## shell at point blank range and the whole half of the frame washes over in that beam's
## colour (the workshop camera sits 2.4 m out and the near amber mover swept across it).
## The cone fades out as the camera crosses into it: 1.0 well outside, 0 inside.
## Measured in cone radii at the camera's own depth along the axis.
const BEAM_CAMERA_FADE_OUT := 1.75   # fully lit beyond 1.75 cone radii from the axis
const BEAM_CAMERA_FADE_IN := 1.0     # gone by the cone surface itself
## The key on the bot. 7.0, was 3.6: in the menu frame the bot read as a dark silhouette
## against the beams, where the key art has it clearly lit. The cone is narrower with it
## (18 degrees, was 22) and aimed at the hull rather than the floor, so the extra energy
## lands on the bot and not on the disc. Target: the hull's lit faces at 120 to 170 of
## 255 in the menu frame, with the floor unchanged.
##
## WAVE A (lighting lead, 2026-09-24, docs/look/reference-study.md section 3.1). The rig is
## now a studio one: a WARM key (4300 K) front left, 35 degrees up, 2.6 m out, a neutral
## fill at 4:1 under it, TWO cold rims (8500 K) behind at 1.2x the key because they graze,
## a top softbox and two strip lights that exist to be REFLECTED, and a reflection probe
## that carries those shapes into the metal. The key stays the one shadow caster.
const KEY_ENERGY := 7.0
const KEY_AT := Vector3(-1.52, 1.62, 1.56)       # front left, 35 deg up, 2.6 m out
const KEY_ANGLE_DEG := 24.0
## 4300 K. Warm, not amber: the amber mover is still the one SATURATED warm in the room.
const COL_KEY_WARM := Color(1.0, 0.84, 0.70)
## Fill: front right and low, 6500 K, key to fill 4:1. No shadow.
const FILL_ENERGY := 1.75
const FILL_AT := Vector3(1.75, 0.62, 1.70)
const FILL_ANGLE_DEG := 34.0
const COL_FILL := Color(1.0, 0.98, 0.98)
const KEY_SPECULAR := 0.3
const FILL_SPECULAR := 0.08
## Rims: behind left and behind right, 27 deg up, 8500 K, 1.2x the key.
const RIM_ENERGY := 5.0
const RIM_AT := Vector3(-1.45, 0.95, -1.95)      # behind left; swings (see RIM_SWING_DEG)
const RIM2_AT := Vector3(1.55, 0.95, -1.85)      # behind right; fixed
const RIM_ANGLE_DEG := 20.0
## Where a rim is cut off: just past the machine, so the cone never pools on the disc.
const RIM_RANGE := 2.95
## A full specular rim on bare steel seen against the light was a bloomed white blob the
## size of a wheel (face-off, showroom, garage). The rim still draws the edge through
## diffuse; the specular only has to glint.
const RIM_SPECULAR := 0.3
const COL_RIM_COLD := Color(0.86, 0.90, 1.0)

## The room the metal reflects (reference-study 3.1 items 5 to 8).
const SOFTBOX_SIZE := Vector2(1.6, 0.6)
const SOFTBOX_HEIGHT := 2.2
const SOFTBOX_EMISSION := 3.0
const SOFTBOX_OMNI_ENERGY := 1.2
const COL_SOFTBOX := Color(1.0, 0.97, 0.93)      # 5600 K
const STRIP_SIZE := Vector3(2.4, 0.08, 0.08)
const STRIP_EMISSION := 4.0
const STRIP_AT := [Vector3(-2.3, 1.55, -2.3), Vector3(2.3, 1.55, -2.3)]
const COL_STRIP := Color(1.0, 0.98, 0.98)        # 6500 K
## ReflectionProbe: centred over the stage and reaching the opponent's slot, captured
## ONCE (the room never moves). Renders the room layer only, never the machines, so a bot
## is never reflected in itself.
const PROBE_AT := Vector3(0.0, 2.0, -1.8)
const PROBE_SIZE := Vector3(12.0, 4.6, 14.0)
## VisualInstance3D layer 12 (bit 11): the room, which is what the probe captures.
const ROOM_LAYER := 1 << 11
## Layer 20 (bit 19): the full screen vignette quad, which no probe may ever see.
const POST_LAYER := 1 << 19

## The opponent's slot for the M2 face-off (docs/look/img2/menu-b-faceoff.webp): across
## the floor, back and to the right of the hero from the front of the room, under its own
## COLD top light. Hidden until an opponent is shown.
const OPPONENT_AT := Vector3(2.5, 0.0, -1.9)
const OPP_TOP_AT := Vector3(0.35, 3.1, 0.55)     # relative to the slot
const OPP_TOP_ENERGY := 10.0
const OPP_TOP_ANGLE_DEG := 17.0
const OPP_RIM_AT := Vector3(-1.2, 1.1, -1.4)     # relative to the slot
const OPP_RIM_ENERGY := 5.0
const COL_OPP_COLD := Color(0.55, 0.72, 1.0)     # well past 10000 K: the cold corner
const OPP_BEAM_ALPHA := 0.085
## How far the hero's nose turns back towards the room from dead on the opponent, so the
## face-off shows its front three quarters rather than its flank.
const FACEOFF_NOSE_TO_ROOM_DEG := 85.0

## Practicals: a low back truss of PAR cans, IN frame on the low face-off lens, which is
## what tells the eye this is a venue and not a void. Emissive only (no light): they light
## nothing, the haze cones under them do the work.
const TRUSS_Z := -6.45
const TRUSS_Y := 1.85
const PRACTICAL_CLUSTERS := [Vector2(1.1, 0.0), Vector2(4.7, 0.18)]
const PRACTICAL_EMISSION := 6.0
const COL_PRACTICAL := Color(1.0, 0.93, 0.82)

## The test-fire spark (attract cue).
const SPARK_AMOUNT := 40
const SPARK_FLASH_ENERGY := 2.6
const SPARK_FLASH_S := 0.22
const COL_SPARK := Color(1.0, 0.62, 0.22)

## Part pull-out (G2): every body of the focused category slides this far out from the
## machine's centre, and lifts a little, over the director's move.
const PULL_OUT_M := 0.11
const PULL_OUT_LIFT_M := 0.025
const PULL_OUT_TAU := 0.18
## The face-off floor wash.
const FLOOR_WASH_AT := Vector3(-1.9, 2.2, 2.6)
const FLOOR_WASH_AIM := Vector3(-0.35, 0.0, 1.1)
const FLOOR_WASH_ENERGY := 4.0
## The platform retract / raise, seconds (the director's move length).
const PLATFORM_S := 0.75

## One entry per mover: its COOL colour, mount position, and the sine path it wanders
## (yaw and pitch amplitude in degrees, period in seconds, phase in turns). Independent
## periods so the three never lock up. Each beam cone is cut to the distance from its
## mount to the stage, so no shaft ever passes through the floor and out the far side.
##
## The amber is not a property of a mover any more: exactly ONE mover holds it at a time
## and hands it on (see _animate_warmth), because two saturated warms in this frame breaks
## the palette rule in docs/stage2-art-direction.md. Mover 0, upper left, is the amber's
## home, which is where the accepted still has it.
const MOVERS := [
	{"cool": Color(0.62, 0.78, 1.0), "at": Vector3(-2.4, 3.5, 2.0),
		"yaw_amp": 10.0, "pitch_amp": 4.0, "period": 17.0, "phase": 0.0, "energy": 1.0},
	{"cool": COL_BLUE, "at": Vector3(1.9, 3.6, 1.1),
		"yaw_amp": 8.0, "pitch_amp": 5.0, "period": 23.0, "phase": 0.37, "energy": 0.9},
	{"cool": Color(0.46, 0.70, 1.0), "at": Vector3(0.3, 3.8, -2.6),
		"yaw_amp": 13.0, "pitch_amp": 6.0, "period": 29.0, "phase": 0.61, "energy": 0.75},
]

## ---------------------------------------------------------------- choreography
##
## THE SWEEP. Every SWEEP_PERIOD seconds exactly one mover walks its aim SWEEP_REACH
## metres from one side of the bot, through it, and out the other side, taking
## SWEEP_TRAVEL seconds over the walk and resting for what is left. So a beam crosses the
## bot once every 8 s, which is the middle of the 6 to 10 s the owner asked for, and only
## ever one beam at a time, so the frame never turns into a light show. The mover taking
## the sweep changes each period and the direction alternates.
const SWEEP_PERIOD := 8.0
const SWEEP_TRAVEL := 4.4
const SWEEP_REACH := 1.25
## Every mover eases towards its own aim with this time constant, in seconds, instead of
## being placed on it. It exists for ONE reason: at the moment the sweep is handed to the
## next mover, the outgoing one's aim would otherwise snap 1.25 m back to the centre in a
## single frame, which reads as a fault. Eased, it glides back over about a second, which
## is what a real moving head does. 0.5 s also keeps the fastest aim change on the stage
## under 0.04 of the sweep's range per frame, which stage_animation_test.gd asserts.
const AIM_EASE_TAU := 0.5

## THE AMBER HAND OFF. One mover holds the amber for WARM_HOLD seconds; the hand over is
## SEQUENTIAL (the holder fades to its cool colour over WARM_FADE, and only then does the
## next one warm up over WARM_FADE), which is what guarantees two movers are never warm at
## the same time. The order returns to mover 0 every other time.
const WARM_HOLD := 14.0
const WARM_FADE := 1.6
const WARM_ORDER := [1, 0, 2, 0]

## THE KEY BREATHES. Energy by KEY_BREATH_AMOUNT either side of KEY_ENERGY, and the colour
## drifts between a colder and a more neutral white. Both are small and slow: the point is
## that the bot is never lit by a dead constant, not that anyone sees a change happen.
## KEY_DRIFT_TO is a NEUTRAL white, not an amber: the frame's only saturated warm is the
## mover holding the amber (docs/stage2-art-direction.md).
const KEY_BREATH_PERIOD := 11.0
const KEY_BREATH_AMOUNT := 0.035
const KEY_DRIFT_PERIOD := 17.0
## Wave A: the drift runs between the 4300 K key and a slightly warmer and a slightly more
## neutral white. Small: 0.2 of the way either side.
const KEY_DRIFT_AMOUNT := 0.2
const COL_KEY_COOL := Color(1.0, 0.93, 0.86)
const COL_KEY_DRIFT_TO := Color(1.0, 0.80, 0.64)

## THE RIM ROLLS. The rim light swings RIM_SWING_DEG either side of its mounted angle with
## period RIM_SWING_PERIOD while the turntable turns under it, so the lit edge travels
## round the bot instead of sitting on one corner. It is a SWING and not an orbit on
## purpose: a rim light that comes round to the camera side flares into the lens and stops
## being a rim.
const RIM_SWING_DEG := 48.0
const RIM_SWING_PERIOD := 26.0

## Each mover's own energy breathes a few percent on its own long period, which is the
## "gobo flicker" at the only strength that stays tasteful. Nothing here strobes: the
## fastest thing on the stage is a 11 s sine.
const MOVER_BREATH := 0.05
const MOVER_BREATH_PERIODS := [13.0, 16.0, 19.0]

## Dry ice. In the key art the bank is a low billow at the disc rim and below it, in
## the bottom quarter of the frame, and it never touches the bot. So: a ring just
## outside the 1.5 m rim, nothing over the stage centre, small quads (the workshop
## camera sits 2.4 m away, where a 1 m billboard covers the whole screen height), and
## everything under 0.2 m. Measured against the menu camera (4.8 m, pitch 18, aimed at
## 0.28 m): fog at radius 1.5 to 1.9 lands 87 to 100 % down the frame, and anything
## behind the bot is depth tested against it rather than veiling it.
##
## G1 2026-09-13: in the shot frames this read as a handful of separate grey blobs, not
## as fog. Dry ice is continuous or it is nothing, and the fix is more, larger, fainter
## quads that overlap rather than fewer solid ones: 5 emitters and 150 billboards at
## roughly a third of the old per quad alpha. Every quad still obeys the rules the first
## calibration pass found and workshop_test.gd asserts (under 1.2 m, alpha at or under
## 0.08, below 0.2 m, never over the stage centre). On the high tier these are switched
## off entirely and real volumetric fog does the job.
##
## Agent S 2026-09-14 (the owner wants it MOVING). Three things were added and nothing was
## moved: `swirl`, a tangential speed that walks the bank anticlockwise around the rim so
## the whole ring turns; `wind`, a very small constant acceleration that drifts the bank
## towards the camera (the two emitters behind the bot get none, so nothing ever drifts
## across the bot's silhouette from behind); and GPU turbulence, which is what curls a
## straight drift into tendrils. The per quad alpha came DOWN because there are now more
## quads, and the ground_fog shader thins them again with scrolling noise, so the bank is
## no brighter in the bottom of the frame than the still the owner accepted.
const DRY_ICE = [
	{"at": Vector3(0.95, 0.035, 1.62), "extents": Vector3(1.35, 0.02, 0.62),
		"variant": 0, "amount": 40, "scale": 0.86, "alpha": 0.013, "swirl": 0.075,
		"wind": Vector3(0.004, -0.003, 0.010)},
	{"at": Vector3(-1.80, 0.035, 0.65), "extents": Vector3(0.62, 0.02, 1.35),
		"variant": 1, "amount": 36, "scale": 0.84, "alpha": 0.013, "swirl": 0.075,
		"wind": Vector3(-0.003, -0.003, 0.009)},
	{"at": Vector3(0.60, 0.035, -1.82), "extents": Vector3(1.35, 0.02, 0.62),
		"variant": 2, "amount": 34, "scale": 0.84, "alpha": 0.012, "swirl": 0.070,
		"wind": Vector3(0.002, -0.003, -0.004)},
	{"at": Vector3(-1.55, 0.035, -1.45), "extents": Vector3(0.70, 0.02, 0.70),
		"variant": 0, "amount": 32, "scale": 0.80, "alpha": 0.012, "swirl": 0.070,
		"wind": Vector3(-0.004, -0.003, -0.004)},
	{"at": Vector3(1.85, 0.035, -0.55), "extents": Vector3(0.62, 0.02, 1.10),
		"variant": 1, "amount": 36, "scale": 0.84, "alpha": 0.013, "swirl": 0.075,
		"wind": Vector3(0.006, -0.003, 0.006)},
]

## Tendrils: two emitters on the camera side of the rim that throw a few fast, small,
## heavily turbulent wisps OUTWARD over the stage lip, where they sink and dissolve. This
## is the only part of the dry ice that is meant to be read as individual shapes, which is
## why there are so few of them and why they die young (TENDRIL_LIFETIME).
const TENDRIL_LIFETIME := 5.5
const TENDRILS = [
	{"at": Vector3(1.55, 0.05, 1.32), "extents": Vector3(0.30, 0.015, 0.22),
		"amount": 22, "scale": 0.52, "alpha": 0.012, "out": Vector3(0.72, 0.05, 0.69)},
	{"at": Vector3(-1.62, 0.05, -0.92), "extents": Vector3(0.22, 0.015, 0.30),
		"amount": 22, "scale": 0.50, "alpha": 0.011, "out": Vector3(-0.86, 0.05, -0.49)},
]

## The occasional denser puff: ONE one-shot emitter that is walked round the rim by the
## golden angle and fired every PUFF_MIN to PUFF_MAX seconds, so a thicker billow appears
## somewhere new each time rather than the bank pulsing as a whole. Seeded, so two runs of
## the test see the same schedule.
const PUFF_MIN := 6.0
const PUFF_MAX := 11.0
const PUFF_RADIUS := 1.72
const PUFF_AMOUNT := 34
const PUFF_ALPHA := 0.018
const PUFF_SCALE := 1.05
const PUFF_LIFETIME := 7.0
const PUFF_SEED := 20260914

## Particle budget per tier. The numbers in the tables above are the HIGH tier; the other
## tiers are a fraction of them, and the per quad alpha is raised by ALPHA_TIER_GAIN by the
## same rough factor so a thinner bank is not also a fainter one. High tier total:
## 178 ring + 44 tendril + 34 puff + 24 dust = 280 billboards, which is the whole particle
## budget of the menu (the fight has its own). See docs/stage-animation.md.
const PARTICLE_SCALE := {"high": 1.0, "medium": 0.6, "low": 0.32}
const ALPHA_TIER_GAIN := {"high": 1.0, "medium": 1.5, "low": 2.2}
const DUST_AMOUNT := 24

## The three dry ice sprite variants, as `[softness, stretch, bite]`. They used to be picked
## per PARTICLE inside the shader from INSTANCE_CUSTOM; they are per EMITTER now because
## nothing outside the core shader built ins survived the compatibility renderer (see the
## header of res://render/stage/ground_fog.gdshader). Ring emitter i takes variant i % 3.
const FOG_VARIANTS := [
	[1.20, 1.00, 0.45],   # round and soft
	[1.50, 1.60, 0.60],   # a stretched wisp
	[1.00, 1.15, 0.75],   # lumpier, the noise bites harder
]
## The real thing, high tier only: two FogVolume boxes. One low bank rolling across the
## whole floor and one denser ring at the stage lip, which is what makes the platform
## read as raised (Art/direction/menu-stage.png: the fog pours over the edge).
const FOG_VOLUMES = [
	# Wave A: 0.36 m deep, was 0.75 centred at 0.22. The face-off and part lenses sit 0.25 to
	# 0.6 m off the floor, and a bank that reached 0.6 m put the camera INSIDE it: the whole
	# frame went milky. It hugs the floor now, which is also what the targets show.
	# The camera must never be INSIDE a bank: fog between the lens and the machine
	# absorbs (0.9 /m over 2 m kept 13 % of the light) and the frame goes black and milky
	# at once. So the floor bank tops out at 0.18 m, under the lowest lens (0.26 m).
	{"name": "FogFloor", "at": Vector3(0.0, 0.07, -1.5), "size": Vector3(13.0, 0.22, 15.0),
		"density": 0.8, "height_falloff": 5.0, "edge_fade": 0.35},
	{"name": "FogRim", "at": Vector3(0.0, 0.09, 0.0), "size": Vector3(4.4, 0.26, 4.4),
		"density": 1.6, "height_falloff": 4.0, "edge_fade": 0.5},
]
## Beam dust: only inside the cones, where they cross above the stage. Nothing else
## floats in the air (the key art has none).
const DUST_AT := Vector3(0.0, 1.05, 0.0)
const DUST_EXTENTS := Vector3(0.55, 0.55, 0.55)

var _turntable: Node3D = null
var _bot: Node3D = null
var _summary: Dictionary = {}
var _world_env: WorldEnvironment = null
var _environment: Environment = null
var _movers: Array[Node3D] = []
var _beam_materials: Array[ShaderMaterial] = []
var _beam_strength: Array[float] = []
var _emitters: Array[GPUParticles3D] = []
## Agent G1: the additive cones and the billboard dry ice. They draw on EVERY tier; on
## the high tier they are turned down (FAKE_HAZE_GAIN_WITH_FOG) and real FogVolumes are
## layered over them.
var _fakes: Array[Node3D] = []
var _volumetric := false
var _quality: Node = null
var _forced_tier := ""
var _bridge: Node = null
var _active := true
var _auto_rotate := true
var _t := 0.0
var _built := false

## Choreography state (agent S 2026-09-14). All of it is plain numbers off `_t` so the
## headless test can step it by hand and read it back.
var _spots: Array[SpotLight3D] = []
var _head_materials: Array[StandardMaterial3D] = []
var _key: SpotLight3D = null
var _fill: SpotLight3D = null
var _rim: SpotLight3D = null
var _rim_radius := 0.0
var _rim_base_angle := 0.0
## Which mover is sweeping, where its aim is (-1 to 1, 0 = straight through the bot),
## which way it is walking, and how many times a beam has crossed the bot.
var _sweep_index := 0
var _sweep_timer := 0.0
var _sweep_dir := 1.0
var _sweep_offset := 0.0
var _sweep_crossings := 0
## Where each mover's aim actually IS, easing towards _sweep_offset for the sweeping one
## and towards 0 for the rest.
var _aim_offset: Array[float] = [0.0, 0.0, 0.0]
var _aim_step_max := 0.0
## How amber each mover is, 0 cool to 1 amber. The hand off keeps the sum at or under 1.
var _warm: Array[float] = [1.0, 0.0, 0.0]
var _warm_owner := 0
var _warm_next := 1
var _warm_phase := 0        # 0 holding, 1 the holder fading out, 2 the next fading in
var _warm_timer := 0.0
var _warm_step := 0
## The puff.
var _puff: GPUParticles3D = null
var _puff_timer := 3.0
var _puff_angle := 0.0
var _puff_fired := 0
var _puff_rng := RandomNumberGenerator.new()

## Wave A: the second rim, the room, the director, the opponent and the attract spark.
var _rim2: SpotLight3D = null
var _probe: ReflectionProbe = null
var _post: MeshInstance3D = null
var _director: StageDirector = null
var _opponent: Node3D = null
var _opponent_key := ""
var _opp_slot: Node3D = null
var _opp_beam: ShaderMaterial = null
var _opp_bank: GPUParticles3D = null
var _hero_bounds: Dictionary = {}
## Turntable override from the director: a speed, or an angle to park at (NAN = none).
var _turn_override := false
var _turn_speed := AUTO_ROTATE_DEG_PER_S
var _turn_park := NAN
var _spark: GPUParticles3D = null
var _flash: OmniLight3D = null
var _flash_t := -1.0
## Part pull-out: body -> its resting local transform, and the eased share (0 to 1).
var _pulled: Dictionary = {}
var _pull_focus := ""
var _pull_k := 0.0
var _pull_base: Dictionary = {}
## The turntable platform: 1 raised, 0 retracted into the floor (the face-off stands the
## hero on the arena floor, as in the target), eased towards _platform_want.
var _platform_k := 1.0
var _platform_want := 1.0


func _ready() -> void:
	_build()
	_connect_bridge()
	_read_qa_arguments()
	_read_qa_shot()
	set_process(true)


# ---------------------------------------------------------------- public API

## Free whatever is on the turntable, assemble `config` (a FightConfig bot entry),
## stand it on the stage centre and freeze it. Emits ready_for_host afterwards.
func show_bot(config: Dictionary) -> void:
	_build()
	_clear_bot()
	if config.is_empty():
		_summary = {}
		emit_signal("ready_for_host", _summary)
		return

	var scene: PackedScene = load(BOT_SCENE)
	if scene == null:
		push_error("WorkshopStage: cannot load " + BOT_SCENE)
		_summary = {}
		emit_signal("ready_for_host", _summary)
		return

	var bot := scene.instantiate() as Node3D
	if bot == null:
		push_error("WorkshopStage: " + BOT_SCENE + " root is not a Node3D")
		_summary = {}
		emit_signal("ready_for_host", _summary)
		return

	bot.name = "ShowBot"
	_turntable.add_child(bot)
	_bot = bot
	if bot.has_method("setup"):
		# --- wave P: paint jobs (agent G, docs/paint-jobs.md). The turntable is where the
		# player picks one, so the builder has to show it the moment it is tapped.
		Livery.begin(config)
		bot.call("setup", config, 0, RandomNumberGenerator.new())
		Livery.clear()
	if bot.has_method("place_at"):
		bot.call("place_at", _turntable.global_position, Vector3.RIGHT)
	# Bot.freeze() kills the motors as well, which stops a flipper twitching on the
	# stand. The explicit sweep afterwards is the guarantee the spec asks for: every
	# rigid body under the bot is static, whatever the assembly built.
	if bot.has_method("freeze"):
		bot.call("freeze")
	_freeze_bodies(bot)
	# Owner bug 2026-09-24, "the wheels always go through the floor": Bot.place_at puts
	# the root at max(origin.y, drive radius), which is right on the arena floor (origin
	# y 0) and wrong on anything raised: on the 0.12 m turntable the root landed AT the
	# platform top and every wheel sank by its own radius. Seat by geometry instead.
	set_meta("last_seat_lift", seat_on_ground(bot, _turntable))

	_summary = bot_summary()
	_hero_bounds = {}
	_pulled.clear()
	_pull_base.clear()
	_pull_k = 0.0
	emit_signal("ready_for_host", _summary)


## Visibility and processing. Off also stops the particles and releases the
## environment, so the fight's own WorldEnvironment is never fought over.
func set_active(on: bool) -> void:
	_build()
	_active = on
	visible = on
	set_process(on)
	for emitter in _emitters:
		if is_instance_valid(emitter):
			emitter.emitting = on
	for node in _fakes:
		if is_instance_valid(node):
			node.visible = on
	if _world_env != null:
		_world_env.environment = _environment if on else null
	# Wave A: going dark for a fight hands the picture back to the rig's camera.
	if not on and _director != null and is_instance_valid(_director):
		_director.release()
	if _spark != null and is_instance_valid(_spark):
		_spark.emitting = false
	if _opp_bank != null and is_instance_valid(_opp_bank):
		_opp_bank.emitting = on


func is_active() -> bool:
	return _active


## The build numbers for the host, from the Bot itself. Empty until P2's
## build_summary() lands, which is exactly what the Swift side must tolerate.
func bot_summary() -> Dictionary:
	if _bot != null and is_instance_valid(_bot) and _bot.has_method("build_summary"):
		var out: Variant = _bot.call("build_summary")
		if out is Dictionary:
			return out as Dictionary
	return {}


func set_auto_rotate(on: bool) -> void:
	_auto_rotate = on


func auto_rotate() -> bool:
	return _auto_rotate


## Where the camera should look. The stage top, not the floor.
func stage_centre() -> Vector3:
	return global_position + Vector3(0.0, STAGE_HEIGHT, 0.0)


func turntable() -> Node3D:
	_build()
	return _turntable


func turntable_angle_deg() -> float:
	_build()
	return rad_to_deg(_turntable.rotation.y)


func bot() -> Node3D:
	return _bot if (_bot != null and is_instance_valid(_bot)) else null


func last_summary() -> Dictionary:
	return _summary


## QA and tests only: build as if this were a `high`/`medium`/`low` device. Must be called
## BEFORE the stage enters the tree, because _build reads the tier once. A forced tier
## always uses a PRIVATE GraphicsQuality instance, so a test can never retune the autoload
## for the rest of the process.
func force_quality_tier(value: String) -> void:
	_forced_tier = value


## How many particles one emitter gets on this tier. Public so the test can assert the
## budget without duplicating the arithmetic.
func tier_amount(base: int) -> int:
	var scale: float = float(PARTICLE_SCALE.get(quality_tier(), 0.32))
	return int(maxi(4, int(round(float(base) * scale))))


## Every billboard the stage is emitting on this tier, dust included.
func particle_budget() -> int:
	_build()
	var total := 0
	for emitter in _emitters:
		if is_instance_valid(emitter):
			total += emitter.amount
	return total


# --------------------------------------------------- choreography read outs (tests, QA)

## Where the sweeping beam's aim is: -1 and 1 are SWEEP_REACH metres either side of the
## bot, 0 is straight through it.
func sweep_offset() -> float:
	return _sweep_offset


func sweep_index() -> int:
	return _sweep_index


## How many times a beam has walked across the bot since the stage started.
func sweep_crossings() -> int:
	return _sweep_crossings


## Where each mover's aim actually sits, and the largest single frame step any of them has
## taken. Nothing on this stage may jump: the step is the pop detector.
func aim_offsets() -> Array[float]:
	return _aim_offset.duplicate()


func aim_step_max() -> float:
	return _aim_step_max


## How amber each mover is right now, 0 to 1. The sum is never above 1.
func mover_warmth() -> Array[float]:
	return _warm.duplicate()


func key_energy() -> float:
	return _key.light_energy if _key != null and is_instance_valid(_key) else 0.0


func key_colour() -> Color:
	return _key.light_color if _key != null and is_instance_valid(_key) else Color.BLACK


## The rim light's swing away from its mounted angle, in degrees.
func rim_swing_deg() -> float:
	return RIM_SWING_DEG * sin(TAU * _t / RIM_SWING_PERIOD)


func puff_count() -> int:
	return _puff_fired


# ---------------------------------------------------------------- frame

## The whole stage is animated from here, off this node's own clock. It is deliberately
## free of any fight, menu or bridge state: the menus are SwiftUI drawn OVER this scene, so
## the moment this stops being driven the backdrop freezes and the owner is looking at a
## still again. The only switch is set_active().
func _process(delta: float) -> void:
	if not _active:
		return
	_t += delta
	if _turntable != null:
		if _turn_override:
			if not is_nan(_turn_park):
				# Park by the shortest way round, eased (about 0.4 s to settle).
				var gap := wrapf(deg_to_rad(_turn_park) - _turntable.rotation.y, -PI, PI)
				_turntable.rotation.y += gap * (1.0 - exp(-delta / 0.14))
			elif _turn_speed != 0.0:
				_turntable.rotation.y = wrapf(
					_turntable.rotation.y + deg_to_rad(_turn_speed) * delta, -TAU, TAU)
		elif _auto_rotate:
			_turntable.rotation.y = wrapf(
				_turntable.rotation.y + deg_to_rad(AUTO_ROTATE_DEG_PER_S) * delta, -TAU, TAU)
	_animate_pull(delta)
	_animate_flash(delta)
	_animate_platform(delta)
	_advance_sweep(delta)
	_animate_warmth(delta)
	_sweep_movers()
	_animate_lights()
	_animate_dry_ice(delta)
	_fade_beams_near_camera()


## Pick the sweeping mover and walk its aim across the bot. One crossing per SWEEP_PERIOD,
## which lands in the middle of the 6 to 10 s the owner asked for.
func _advance_sweep(delta: float) -> void:
	if _movers.is_empty():
		return
	_sweep_timer += delta
	while _sweep_timer >= SWEEP_PERIOD:
		_sweep_timer -= SWEEP_PERIOD
		_sweep_index = (_sweep_index + 1) % _movers.size()
		_sweep_dir = -_sweep_dir
	var walked: float = clampf(_sweep_timer / SWEEP_TRAVEL, 0.0, 1.0)
	var was := _sweep_offset
	# +1 through 0 to -1 with a smooth start and stop: the beam accelerates off one side,
	# runs through the bot, and settles on the other.
	_sweep_offset = _sweep_dir * (1.0 - 2.0 * smoothstep(0.0, 1.0, walked))
	if was != 0.0 and signf(was) != signf(_sweep_offset):
		_sweep_crossings += 1
	# Ease every mover towards its own aim. The sweeping one follows the walk; the other
	# two return to centre, which is what stops the hand over from snapping.
	var k: float = 1.0 - exp(-delta / maxf(AIM_EASE_TAU, 0.001))
	for i in _aim_offset.size():
		var target: float = _sweep_offset if i == _sweep_index else 0.0
		var moved: float = (target - _aim_offset[i]) * k
		_aim_offset[i] += moved
		_aim_step_max = maxf(_aim_step_max, absf(moved))


## The amber hand off. Sequential by construction: the holder is all the way cool before
## the next one starts to warm, so two movers are never warm at the same time.
func _animate_warmth(delta: float) -> void:
	if _warm.size() < MOVERS.size():
		return
	_warm_timer += delta
	match _warm_phase:
		0:
			if _warm_timer >= WARM_HOLD:
				_warm_timer = 0.0
				_warm_phase = 1
				_warm_next = int(WARM_ORDER[_warm_step % WARM_ORDER.size()]) % MOVERS.size()
				_warm_step += 1
				if _warm_next == _warm_owner:
					_warm_next = (_warm_owner + 1) % MOVERS.size()
		1:
			var out_t: float = clampf(_warm_timer / WARM_FADE, 0.0, 1.0)
			_warm[_warm_owner] = 1.0 - smoothstep(0.0, 1.0, out_t)
			if out_t >= 1.0:
				_warm[_warm_owner] = 0.0
				_warm_timer = 0.0
				_warm_phase = 2
		2:
			var in_t: float = clampf(_warm_timer / WARM_FADE, 0.0, 1.0)
			_warm[_warm_next] = smoothstep(0.0, 1.0, in_t)
			if in_t >= 1.0:
				_warm[_warm_next] = 1.0
				_warm_owner = _warm_next
				_warm_timer = 0.0
				_warm_phase = 0


## Push the choreography onto the actual lights and onto the additive cones and lamp heads
## that have to agree with them. Colour: each mover is its own cool colour crossfaded
## towards the one amber. Energy: a few percent of slow breathing each, on its own period.
func _animate_lights() -> void:
	for i in _spots.size():
		var spot := _spots[i]
		if not is_instance_valid(spot) or i >= MOVERS.size():
			continue
		var spec: Dictionary = MOVERS[i]
		var colour: Color = (spec["cool"] as Color).lerp(COL_AMBER, _warm[i])
		var breath_period: float = float(MOVER_BREATH_PERIODS[i % MOVER_BREATH_PERIODS.size()])
		var breath: float = 1.0 + MOVER_BREATH * sin(TAU * _t / breath_period + float(i))
		spot.light_color = colour
		spot.light_energy = MOVER_ENERGY * float(spec["energy"]) * breath
		if i < _beam_materials.size() and _beam_materials[i] != null:
			_beam_materials[i].set_shader_parameter("tint", colour)
		if i < _head_materials.size() and _head_materials[i] != null:
			_head_materials[i].albedo_color = colour
			_head_materials[i].emission = colour

	if _key != null and is_instance_valid(_key):
		_key.light_energy = KEY_ENERGY * (1.0 + KEY_BREATH_AMOUNT * sin(TAU * _t / KEY_BREATH_PERIOD))
		# Colour temperature drift around the calibrated key: colder one way, neutral the
		# other, never into amber.
		var drift: float = sin(TAU * _t / KEY_DRIFT_PERIOD)
		var towards: Color = COL_KEY_DRIFT_TO if drift >= 0.0 else COL_KEY_COOL
		_key.light_color = COL_KEY.lerp(towards, absf(drift) * KEY_DRIFT_AMOUNT)

	# The rim swings round the bot while the turntable turns under it, so the lit edge
	# travels instead of sitting on one corner.
	if _rim != null and is_instance_valid(_rim) and _rim_radius > 0.0:
		var angle: float = _rim_base_angle + deg_to_rad(rim_swing_deg())
		var at := Vector3(_rim_radius * sin(angle), RIM_AT.y, _rim_radius * cos(angle))
		_rim.look_at_from_position(at, Vector3(0.0, STAGE_HEIGHT + 0.26, 0.0), Vector3.UP)


## The occasional denser puff, walked round the rim by the golden angle so it never fires
## twice in the same place. One shot: the emitter is silent between bursts.
func _animate_dry_ice(delta: float) -> void:
	if _puff == null or not is_instance_valid(_puff):
		return
	_puff_timer -= delta
	if _puff_timer > 0.0:
		return
	_puff_timer = _puff_rng.randf_range(PUFF_MIN, PUFF_MAX)
	_puff_angle = wrapf(_puff_angle + 2.39996, 0.0, TAU)
	_puff.position = Vector3(
		PUFF_RADIUS * sin(_puff_angle), 0.045, PUFF_RADIUS * cos(_puff_angle))
	_puff.restart()
	_puff_fired += 1


## Each mover aims at the stage centre plus a slow independent sine wander, which is
## what sells "moving heads" without any animation data. One of them, in turn, is also
## WALKING its aim across the bot (_advance_sweep): its aim point is pushed sideways, at
## right angles to its own line to the stage, so the beam crosses the bot rather than
## running up and down it.
func _sweep_movers() -> void:
	for i in _movers.size():
		var node := _movers[i]
		if not is_instance_valid(node):
			continue
		var spec: Dictionary = MOVERS[i]
		var period: float = maxf(float(spec["period"]), 0.001)
		var phase: float = TAU * (_t / period + float(spec["phase"]))
		var yaw_off: float = sin(phase) * float(spec["yaw_amp"])
		var pitch_off: float = sin(phase * 0.63 + 1.1) * float(spec["pitch_amp"])
		var from := global_position + (spec["at"] as Vector3)
		var aim := stage_centre() + Vector3(0.0, 0.22, 0.0)
		var offset: float = _aim_offset[i] if i < _aim_offset.size() else 0.0
		if absf(offset) > 0.0005:
			var to_stage := aim - from
			var side := Vector3(-to_stage.z, 0.0, to_stage.x)
			if side.length() > 0.001:
				aim += side.normalized() * SWEEP_REACH * offset
		node.look_at_from_position(from, aim, Vector3.UP)
		node.rotate_object_local(Vector3.UP, deg_to_rad(yaw_off))
		node.rotate_object_local(Vector3.RIGHT, deg_to_rad(pitch_off))


## Fade each additive cone out as the camera enters it. The test is geometric and exact:
## project the camera onto the cone's axis, compare its distance from that axis with the
## cone's radius at that depth, and fade between BEAM_CAMERA_FADE_OUT and _FADE_IN radii.
## Three movers, three dot products, once a frame.
func _fade_beams_near_camera() -> void:
	if _beam_materials.is_empty() or not is_inside_tree():
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var camera := viewport.get_camera_3d()
	if camera == null:
		return
	var eye := camera.global_position
	var tan_angle := tan(deg_to_rad(MOVER_ANGLE_DEG))
	for i in _beam_materials.size():
		var material: ShaderMaterial = _beam_materials[i]
		if material == null or i >= _movers.size() or not is_instance_valid(_movers[i]):
			continue
		var mount: Node3D = _movers[i]
		var origin := mount.global_position
		# The mount is aimed with look_at, so the shaft runs down its own -Z.
		var axis := -mount.global_transform.basis.z.normalized()
		var to_eye := eye - origin
		var along := to_eye.dot(axis)
		var gain := 1.0
		if along > 0.0:
			var radius: float = maxf(tan_angle * along, 0.001)
			var perpendicular := (to_eye - axis * along).length()
			gain = smoothstep(BEAM_CAMERA_FADE_IN, BEAM_CAMERA_FADE_OUT, perpendicular / radius)
		material.set_shader_parameter("strength", float(_beam_strength[i]) * gain)


# ---------------------------------------------------------------- bridge and QA

## The autoload is reached by node rather than by its `Bridge` global identifier. A
## `--script` test run compiles this file as a dependency of the test script, which is
## before the autoload globals are registered, and the global would not resolve.
func _connect_bridge() -> void:
	if not is_inside_tree():
		return
	_bridge = get_tree().root.get_node_or_null("Bridge")
	if _bridge != null and not _bridge.is_connected("message_received", _on_bridge_message):
		_bridge.connect("message_received", _on_bridge_message)


func _on_bridge_message(type: String, payload: Dictionary) -> void:
	if type == MSG_STAGE_CAMERA:
		_on_stage_camera(payload)
		return
	if type != MSG_WORKSHOP_CONFIG:
		return
	var bot_config: Dictionary = payload.get("bot", {}) as Dictionary
	show_bot(bot_config)
	apply_presentation(payload)
	if _bridge != null and is_instance_valid(_bridge):
		_bridge.call("send", MSG_WORKSHOP_READY, _summary)


## `--roboteer-workshop` or `--roboteer-workshop=/abs/path.json`. Desktop only, so a
## device build can never be posed by an argument. The file may be a whole FightConfig
## (bots[0] is used) or a bare bot config.
func _read_qa_arguments() -> void:
	if not OS.has_feature("pc"):
		return
	for raw in OS.get_cmdline_user_args():
		var arg := str(raw)
		if arg != ARG_WORKSHOP and not arg.begins_with(ARG_WORKSHOP + "="):
			continue
		var path := DEFAULT_CONFIG
		if arg.length() > ARG_WORKSHOP.length() + 1:
			path = arg.substr(ARG_WORKSHOP.length() + 1)
		var config := load_bot_config(path)
		if config.is_empty():
			push_warning("WorkshopStage: no bot config in " + path)
			return
		show_bot(config)
		return


## Reads a bot config from a res:// or absolute path. Accepts a FightConfig (first bot)
## or a bare bot entry. Returns {} when there is nothing usable.
static func load_bot_config(path: String) -> Dictionary:
	var text := ""
	if path.begins_with("res://"):
		if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
			return {}
		var res := FileAccess.open(path, FileAccess.READ)
		if res == null:
			return {}
		text = res.get_as_text()
	else:
		if not FileAccess.file_exists(path):
			return {}
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return {}
		text = file.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	var dict: Dictionary = parsed as Dictionary
	if dict.has("chassis"):
		return dict
	var bots: Array = dict.get("bots", []) as Array
	if bots.size() > 0 and bots[0] is Dictionary:
		return bots[0] as Dictionary
	return {}


# ---------------------------------------------------------------- construction

func _clear_bot() -> void:
	if _bot != null and is_instance_valid(_bot):
		_turntable.remove_child(_bot)
		_bot.queue_free()
	_bot = null
	_summary = {}


## Every RigidBody3D under the bot goes static. A frozen static body still follows its
## parent transform, which is what lets the turntable carry the whole assembly round.
func _freeze_bodies(node: Node) -> void:
	var body := node as RigidBody3D
	if body != null:
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		body.freeze = true
	for child in node.get_children():
		_freeze_bodies(child)


## GraphicsQuality (agent G1), by node when the autoload is up and as a private instance
## when it is not. Exactly the Bridge pattern above, and for the same reason: a `--script`
## test run has no autoloads.
func _resolve_quality() -> Node:
	var script: GDScript = load(QUALITY_SCRIPT) as GDScript
	if script == null:
		return null
	if _forced_tier != "":
		# A PRIVATE instance, never the autoload: forcing a tier is a QA and test lever and
		# it must not retune the rest of the process.
		var private: Node = script.new()
		private.call("detect")
		private.call("set_tier", _forced_tier)
		return private
	return script.call("resolve", self)


func _allows(feature: String) -> bool:
	if _quality == null or not _quality.has_method("allows"):
		return false
	return bool(_quality.call("allows", feature))


## True when the additive cones and the billboards are doing ALL the work, which is every
## tier below high. They draw on the high tier too, at FAKE_HAZE_GAIN_WITH_FOG.
func fake_haze() -> bool:
	_build()
	return not _volumetric


## True when real volumetric fog and the FogVolumes are drawing.
func volumetric_haze() -> bool:
	_build()
	return _volumetric


func _haze_gain() -> float:
	return FAKE_HAZE_GAIN_WITH_FOG if _volumetric else 1.0


func quality_tier() -> String:
	_build()
	if _quality == null or not _quality.has_method("tier"):
		return ""
	return str(_quality.call("tier"))


func _build() -> void:
	if _built:
		return
	_built = true
	_build_environment()
	_build_floor()
	_build_stage()
	_build_backdrop()
	_build_lights()
	_build_haze()
	_build_room()
	_build_opponent_slot()
	_build_attract()
	_build_post()
	_build_director()


## The environment is agent G1's `res://render/stage_env.tres` (ACES, glow tuned to the
## beams and the lamp heads, volumetric fog on the high tier). It is DUPLICATED on load
## because GraphicsQuality switches features off per tier and the resource is shared.
func _build_environment() -> void:
	_world_env = get_node_or_null("Environment") as WorldEnvironment
	if _world_env == null:
		_world_env = WorldEnvironment.new()
		_world_env.name = "Environment"
		add_child(_world_env)

	_environment = null
	if ResourceLoader.exists(ENV_RESOURCE):
		var loaded: Environment = load(ENV_RESOURCE) as Environment
		if loaded != null:
			_environment = loaded.duplicate() as Environment
	if _environment == null:
		# A checkout without res://render/ still gets the calibrated stage look.
		_environment = Environment.new()
		_environment.background_mode = Environment.BG_COLOR
		_environment.background_color = Color(0.0, 0.0, 0.0)
		_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_environment.ambient_light_color = Color(0.30, 0.40, 0.60)
		_environment.ambient_light_energy = 0.05
		_environment.glow_enabled = true
		_environment.glow_intensity = 0.35
		_environment.glow_bloom = 0.05
		_environment.glow_hdr_threshold = 1.1

	# Black, not "dark blue", and ambient 0.05, not 0.35: in the key art the background
	# and the top third of the frame are zero, and everything visible is put there by a
	# light. Re-asserted here so a bad resource cannot silently milk the frame.
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Color(0.0, 0.0, 0.0)
	_environment.ambient_light_energy = minf(_environment.ambient_light_energy, 0.05)

	_quality = _resolve_quality()
	_volumetric = _allows("volumetric_fog")
	if _quality != null and _quality.has_method("apply"):
		_quality.call("apply", _environment, [])
	_world_env.environment = _environment


func _build_floor() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(FLOOR_SIZE, FLOOR_SIZE)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COL_FLOOR
	# Low roughness plus a little metal is what gives the wet stage sheen under the
	# beams without any screen space reflection, which mobile does not have.
	mat.roughness = 0.22
	mat.metallic = 0.55
	mat.metallic_specular = 0.6
	# Wave A: the steel plate floor (res://render/stage/stage_floor.gdshader): staggered
	# plates, dark seams, rivet rows, per plate tone, roughness breakup and wet patches, so
	# SSR and the probe have something to break up. Same base colour, roughness and metal
	# as the flat material above, which stays as the fallback.
	var floor_material: Material = mat
	if ResourceLoader.exists(FLOOR_SHADER):
		var shader := load(FLOOR_SHADER) as Shader
		if shader != null:
			var sm := ShaderMaterial.new()
			sm.shader = shader
			sm.set_shader_parameter("base_colour", COL_PLATE)
			sm.set_shader_parameter("roughness_base", PLATE_ROUGHNESS)
			sm.set_shader_parameter("metallic_base", PLATE_METALLIC)
			floor_material = sm
	var floor_node := MeshInstance3D.new()
	floor_node.name = "Floor"
	floor_node.mesh = plane
	floor_node.material_override = floor_material
	floor_node.position = Vector3.ZERO
	floor_node.layers = 1 | ROOM_LAYER
	add_child(floor_node)


func _build_stage() -> void:
	var root := Node3D.new()
	root.name = "Stage"
	add_child(root)

	var disc := CylinderMesh.new()
	disc.top_radius = STAGE_RADIUS
	disc.bottom_radius = STAGE_RADIUS * 1.02
	disc.height = STAGE_HEIGHT
	disc.radial_segments = 48
	var disc_mat := StandardMaterial3D.new()
	disc_mat.albedo_color = COL_STAGE
	# Matte, as in the key art: the disc is a dark charcoal plate, not a mirror. The
	# sheen belongs to the floor around it.
	disc_mat.roughness = 0.6
	disc_mat.metallic = 0.15
	# Wave A: a black GLOSS top, as in the G1 target (garage-a-assembly.webp). A matte disc
	# under a 7.0 key was a bright grey pool round the machine; a glossy one reflects the
	# machine and the softbox instead and stays dark everywhere else.
	disc_mat.albedo_color = Color(0.018, 0.019, 0.022)
	disc_mat.roughness = 0.34
	disc_mat.metallic = 0.55
	var disc_node := MeshInstance3D.new()
	disc_node.name = "Disc"
	disc_node.mesh = disc
	disc_node.material_override = disc_mat
	disc_node.position = Vector3(0.0, STAGE_HEIGHT * 0.5, 0.0)
	root.add_child(disc_node)

	# The turntable ring: a raised rim the bot sits inside, as in bot-in-workshop.png.
	var ring := TorusMesh.new()
	ring.inner_radius = STAGE_RADIUS * 0.90
	ring.outer_radius = STAGE_RADIUS * 0.97
	ring.rings = 32
	ring.ring_segments = 12
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = COL_RING
	ring_mat.roughness = 0.4
	ring_mat.metallic = 0.7
	var ring_node := MeshInstance3D.new()
	ring_node.name = "Ring"
	ring_node.mesh = ring
	ring_node.material_override = ring_mat
	ring_node.position = Vector3(0.0, STAGE_HEIGHT, 0.0)
	root.add_child(ring_node)

	# The thin light edge. Unshaded and above 1.0 so the glow catches it.
	var edge := TorusMesh.new()
	# Wave A: a thin line of light (about 8 mm), not a band.
	edge.inner_radius = STAGE_RADIUS * 1.004
	edge.outer_radius = STAGE_RADIUS * 1.0095
	edge.rings = 48
	edge.ring_segments = 8
	var edge_mat := StandardMaterial3D.new()
	edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge_mat.albedo_color = COL_EDGE
	edge_mat.emission_enabled = true
	edge_mat.emission = COL_EDGE
	edge_mat.emission_energy_multiplier = 2.2
	var edge_node := MeshInstance3D.new()
	edge_node.name = "EdgeLight"
	edge_node.mesh = edge
	edge_node.material_override = edge_mat
	edge_node.position = Vector3(0.0, STAGE_HEIGHT * 0.55, 0.0)
	root.add_child(edge_node)

	_turntable = Node3D.new()
	_turntable.name = "Turntable"
	_turntable.position = Vector3(0.0, STAGE_HEIGHT, 0.0)
	root.add_child(_turntable)


func _build_backdrop() -> void:
	var wall := PlaneMesh.new()
	wall.size = Vector2(FLOOR_SIZE * 1.4, BACKDROP_HEIGHT)
	wall.orientation = PlaneMesh.FACE_Z
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COL_BACKDROP
	mat.roughness = 1.0
	mat.metallic = 0.0
	var node := MeshInstance3D.new()
	node.name = "Backdrop"
	node.mesh = wall
	node.material_override = mat
	node.position = Vector3(0.0, BACKDROP_HEIGHT * 0.5 - 0.4, -BACKDROP_DISTANCE)
	add_child(node)
	# Wave A: black flags on the other three sides. The garage and face-off lenses look
	# along the room, and past the backdrop's edge the lit haze read as a pale sheet with a
	# black rectangle cut out of it. Same black, same height.
	for side in [
			{"name": "FlagLeft", "at": Vector3(-FLOOR_SIZE * 0.55, BACKDROP_HEIGHT * 0.5 - 0.4, 0.0), "yaw": PI * 0.5},
			{"name": "FlagRight", "at": Vector3(FLOOR_SIZE * 0.55, BACKDROP_HEIGHT * 0.5 - 0.4, 0.0), "yaw": -PI * 0.5},
			{"name": "FlagFront", "at": Vector3(0.0, BACKDROP_HEIGHT * 0.5 - 0.4, FLOOR_SIZE * 0.55), "yaw": PI}]:
		var flag := MeshInstance3D.new()
		flag.name = str(side["name"])
		flag.mesh = wall
		flag.material_override = mat
		flag.position = side["at"]
		flag.rotation = Vector3(0.0, float(side["yaw"]), 0.0)
		flag.layers = 1 | ROOM_LAYER
		add_child(flag)


func _build_lights() -> void:
	var movers := Node3D.new()
	movers.name = "Movers"
	add_child(movers)
	_movers.clear()
	_spots.clear()
	_head_materials.clear()
	var aim := Vector3(0.0, STAGE_HEIGHT + 0.22, 0.0)
	for i in MOVERS.size():
		var spec: Dictionary = MOVERS[i]
		# The starting colour is the cool one crossfaded by however amber this mover is at
		# t = 0, so the very first frame already matches the accepted still (mover 0 amber).
		var colour: Color = (spec["cool"] as Color).lerp(COL_AMBER, _warm[i] if i < _warm.size() else 0.0)
		var at: Vector3 = spec["at"]
		# The shaft stops at the stage. A fixed 9 m cone shot through the floor and
		# out the far side of the frame, which is what read as a solid wedge.
		var length: float = at.distance_to(aim)
		var mount := Node3D.new()
		mount.name = "Mover%d" % i
		movers.add_child(mount)

		var spot := SpotLight3D.new()
		spot.name = "Spot"
		spot.light_color = colour
		spot.light_energy = MOVER_ENERGY * float(spec["energy"])
		spot.spot_range = length + 1.2
		spot.spot_angle = MOVER_ANGLE_DEG
		spot.spot_angle_attenuation = 0.9
		spot.spot_attenuation = 1.2
		# No shadows on the movers: three moving shadow casters is the whole phone
		# budget and the key light already grounds the bot.
		spot.shadow_enabled = false
		# On the high tier THIS is what makes the shaft: a real spot lighting real
		# volumetric fog. On the other tiers it costs nothing and the additive cone below
		# does the job instead.
		spot.light_volumetric_fog_energy = MOVER_FOG_ENERGY if _volumetric else 1.0
		mount.add_child(spot)

		var cone := MeshInstance3D.new()
		cone.name = "Beam"
		cone.mesh = _beam_mesh(length, MOVER_ANGLE_DEG)
		var strength: float = BEAM_ALPHA * float(spec["energy"]) * _haze_gain()
		var beam_material := _beam_material(colour, strength, length, float(i) * 3.7 + 0.5)
		cone.material_override = beam_material
		_beam_materials.append(beam_material)
		_beam_strength.append(strength)
		cone.rotate_x(deg_to_rad(-90.0))
		cone.position = Vector3(0.0, 0.0, -length * 0.5)
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_fakes.append(cone)
		mount.add_child(cone)

		# The lamp head itself, as in the key art: a small bright disc at the top of
		# the frame that tells the eye where each shaft comes from.
		var head := MeshInstance3D.new()
		head.name = "Head"
		var head_mesh := CylinderMesh.new()
		head_mesh.top_radius = 0.085
		head_mesh.bottom_radius = 0.105
		head_mesh.height = 0.09
		head_mesh.radial_segments = 12
		head.mesh = head_mesh
		var head_mat := StandardMaterial3D.new()
		head_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		head_mat.albedo_color = colour
		head_mat.emission_enabled = true
		head_mat.emission = colour
		head_mat.emission_energy_multiplier = 2.4
		head.material_override = head_mat
		head.rotate_x(deg_to_rad(-90.0))
		head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mount.add_child(head)

		_movers.append(mount)
		_spots.append(spot)
		_head_materials.append(head_mat)

	# The key: a cold white spot from the front left of the workshop camera. This is
	# what makes the bot's plates read instead of sitting in the haze as a silhouette,
	# and it is the one shadow caster on the stage.
	var key := SpotLight3D.new()
	key.name = "KeyLight"
	key.light_color = COL_KEY
	key.light_energy = KEY_ENERGY
	key.spot_range = 7.0
	key.spot_angle = KEY_ANGLE_DEG
	key.spot_angle_attenuation = 1.0
	key.spot_attenuation = 1.0
	key.shadow_enabled = true
	key.shadow_bias = 0.03
	# A 3.6 energy key pumped into real fog is a white wall in front of the bot, so in
	# volumetric fog the key lights the BOT and almost nothing else.
	key.light_volumetric_fog_energy = KEY_FOG_ENERGY if _volumetric else 1.0
	add_child(key)
	# Aimed at the hull, not at the floor in front of it.
	key.look_at_from_position(KEY_AT, Vector3(0.0, STAGE_HEIGHT + 0.28, 0.0), Vector3.UP)
	_key = key

	# The camera side fill.
	var fill := SpotLight3D.new()
	fill.name = "FillLight"
	fill.light_color = COL_FILL
	fill.light_energy = FILL_ENERGY
	fill.spot_range = 6.0
	fill.spot_angle = FILL_ANGLE_DEG
	fill.spot_angle_attenuation = 1.2
	fill.spot_attenuation = 1.0
	fill.shadow_enabled = false
	fill.light_specular = FILL_SPECULAR
	fill.light_volumetric_fog_energy = KEY_FOG_ENERGY if _volumetric else 1.0
	add_child(fill)
	fill.look_at_from_position(FILL_AT, Vector3(0.0, STAGE_HEIGHT + 0.26, 0.0), Vector3.UP)
	_fill = fill

	# Wave A: the key is 4300 K, soft edged (light_size) with a blurred shadow, and wide
	# enough to cover a machine the size of the apex hull.
	key.light_size = 0.15
	key.shadow_blur = 1.5
	# A point light's specular on the glossy disc is a hot blob, not a studio reflection.
	# The shapes in the metal come from the softbox, the strips and the probe; the key and
	# the fill keep a reduced specular so they model form without spotting the floor.
	key.light_specular = KEY_SPECULAR
	key.spot_range = 5.5

	# The second cold rim, behind right. Fixed: the first one swings.
	var rim2 := SpotLight3D.new()
	rim2.name = "RimLight2"
	rim2.light_color = COL_RIM
	rim2.light_energy = RIM_ENERGY
	rim2.spot_range = RIM_RANGE
	rim2.spot_attenuation = 1.6
	rim2.spot_angle = RIM_ANGLE_DEG
	rim2.spot_angle_attenuation = 1.1
	rim2.shadow_enabled = false
	rim2.light_specular = RIM_SPECULAR
	rim2.light_volumetric_fog_energy = KEY_FOG_ENERGY if _volumetric else 1.0
	add_child(rim2)
	rim2.look_at_from_position(RIM2_AT, Vector3(0.0, STAGE_HEIGHT + 0.26, 0.0), Vector3.UP)
	_rim2 = rim2

	# The first cold rim from behind, which separates the bot from the black backdrop.
	var rim := SpotLight3D.new()
	rim.name = "RimLight"
	rim.light_color = COL_RIM
	rim.light_energy = RIM_ENERGY
	# Just past the bot: a grazing rim that carried on would pool on the floor in front.
	rim.spot_range = RIM_RANGE
	rim.spot_attenuation = 1.6
	rim.spot_angle = RIM_ANGLE_DEG
	rim.spot_angle_attenuation = 1.1
	rim.shadow_enabled = false
	rim.light_specular = RIM_SPECULAR
	rim.light_volumetric_fog_energy = KEY_FOG_ENERGY if _volumetric else 1.0
	add_child(rim)
	rim.look_at_from_position(RIM_AT, Vector3(0.0, STAGE_HEIGHT + 0.26, 0.0), Vector3.UP)
	_rim = rim
	# The swing is around the stage at the radius and height it was mounted at, so the
	# calibrated pose IS the middle of the swing.
	_rim_radius = Vector2(RIM_AT.x, RIM_AT.z).length()
	_rim_base_angle = atan2(RIM_AT.x, RIM_AT.z)


## A hollow cone along +Y, narrow at the lens and wide at the far end, sized to the
## spot's own angle so the mesh and the light agree.
func _beam_mesh(length: float, angle_deg: float) -> Mesh:
	var mesh := CylinderMesh.new()
	mesh.height = length
	mesh.bottom_radius = 0.035                                  # at the lens
	mesh.top_radius = maxf(tan(deg_to_rad(angle_deg)) * length, 0.1)
	mesh.radial_segments = 20
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	return mesh


## The fake haze. The mobile renderer has no volumetric fog and no FogVolume, so a
## beam is an additive unshaded cone that fades along its length and brightens at the
## silhouette, which is what a real shaft does to the eye.
func _beam_material(tint: Color, strength: float, length: float, seed: float) -> ShaderMaterial:
	var shader: Shader = null
	if ResourceLoader.exists(BEAM_SHADER):
		shader = load(BEAM_SHADER) as Shader
	if shader == null:
		shader = Shader.new()
		shader.code = _beam_shader_fallback()
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("strength", strength)
	mat.set_shader_parameter("half_length", length * 0.5)
	mat.set_shader_parameter("fade_power", BEAM_FADE_POWER)
	mat.set_shader_parameter("near_fade_begin", 0.25)
	mat.set_shader_parameter("near_fade_end", 1.30)
	mat.set_shader_parameter("seed", seed)
	return mat


## The beam shader as it was before it moved into res://render/stage/beam.gdshader, kept
## as a fallback so a checkout without that file still gets beams (without the shimmer).
func _beam_shader_fallback() -> String:
	return """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0);
uniform float strength = 0.1;
uniform float half_length = 4.0;
uniform float fade_power = 2.2;
uniform float near_fade_begin = 0.25;
uniform float near_fade_end = 1.30;

varying float along;

void vertex() {
	// 0 at the lens, 1 at the far end, whatever the mesh UV convention is.
	along = clamp((VERTEX.y + half_length) / max(half_length * 2.0, 0.0001), 0.0, 1.0);
}

void fragment() {
	float fade = pow(1.0 - along, fade_power);
	float edge = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	// Distance from the camera, in view space. A shell right against the lens is a wash
	// over the frame, never a beam: the CPU side fades a cone the camera has entered,
	// and this catches every other way a surface can end up too close.
	float near = smoothstep(near_fade_begin, near_fade_end, length(VERTEX));
	ALBEDO = tint.rgb;
	ALPHA = strength * fade * near * (0.35 + 0.65 * edge);
}
"""


## Both hazes are BUILT on every tier so the scene tree, and therefore the test, is the
## same everywhere. The cones and the billboards draw on every tier; on the high tier they
## are turned down and the FogVolumes are layered over them.
func _build_haze() -> void:
	_emitters.clear()
	for i in DRY_ICE.size():
		var spec: Dictionary = DRY_ICE[i]
		var node := _dry_ice_emitter("DryIce%d" % i, spec)
		_fakes.append(node)
		add_child(node)
		_emitters.append(node)
	for i in TENDRILS.size():
		var spec: Dictionary = TENDRILS[i]
		var node := _tendril_emitter("DryIceTendril%d" % i, spec)
		_fakes.append(node)
		add_child(node)
		_emitters.append(node)
	_puff = _puff_emitter()
	_puff_rng.seed = PUFF_SEED
	_fakes.append(_puff)
	add_child(_puff)
	_emitters.append(_puff)
	var dust := _dust_emitter()
	# The beam dust stays on every tier: real fog has no specks in it, and the specks are
	# what sell a shaft as air rather than glass.
	add_child(dust)
	_emitters.append(dust)
	_build_fog_volumes()


## Real dry ice: a low bank across the whole floor plus a denser ring at the stage lip.
## FogVolume needs the Forward+ volumetric fog buffer, so on medium and low these are
## built but hidden, and the billboards above carry the look instead.
func _build_fog_volumes() -> void:
	for spec_variant in FOG_VOLUMES:
		var spec: Dictionary = spec_variant
		var material := FogMaterial.new()
		material.density = float(spec["density"])
		material.albedo = Color(0.88, 0.92, 1.0)
		material.emission = Color(0.0, 0.0, 0.0)
		# Falloff is what keeps it a BANK: dense at the floor, gone by knee height, so it
		# never veils the bot the way the first build's billboards did.
		material.height_falloff = float(spec["height_falloff"])
		material.edge_fade = float(spec["edge_fade"])
		var volume := FogVolume.new()
		volume.name = str(spec["name"])
		volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
		volume.size = spec["size"]
		volume.position = spec["at"]
		volume.material = material
		volume.visible = _volumetric
		add_child(volume)


## Dry ice: a low billow at the disc rim and below it, drifting outward and away. The
## quads are SMALL on purpose: the workshop camera sits 2.4 m from the stage, where a
## 1 m billboard already covers the whole screen height, so metre scale blobs are what
## turned the first build into a milky wash. Cheap: 36 quads that never write depth.
func _dry_ice_emitter(node_name: String, spec: Dictionary) -> GPUParticles3D:
	var at: Vector3 = spec["at"]
	# Anticlockwise around the stage, with a little outward lean so the ring also creeps
	# off the lip instead of running round a groove for ever.
	var radial := Vector3(at.x, 0.0, at.z).normalized()
	var tangent := Vector3(-radial.z, 0.0, radial.x)
	var swirl: float = float(spec.get("swirl", 0.07))

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = spec["extents"]
	process.direction = (tangent * 0.85 + radial * 0.32 + Vector3(0.0, 0.04, 0.0)).normalized()
	# 55, was 88: a coherent flow reads as a moving bank, a hemisphere of directions reads
	# as static fizz. The turbulence below puts the wander back, curled.
	process.spread = 55.0
	process.initial_velocity_min = swirl * 0.8
	process.initial_velocity_max = swirl * 2.0
	# Almost no damping, or the swirl dies in the first second and the ring is a still again.
	process.damping_min = 0.02
	process.damping_max = 0.08
	# `wind`: a very small constant acceleration. Sinking, plus a drift towards the camera
	# on the near emitters. No lift at all: dry ice sinks and spreads, it does not rise
	# into the bot.
	process.gravity = spec.get("wind", Vector3(0.0, -0.004, 0.0))
	# Curl. GPU turbulence is a noise field the particle shader samples, so it costs
	# nothing on the CPU and behaves the same on both renderers. The strength is chosen so
	# that a curl cannot lift a quad above the stage lip line: 0.13 against a 0.22 influence
	# ceiling is a few centimetres of wander over a 9 s life.
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.13
	process.turbulence_noise_scale = 2.6
	process.turbulence_noise_speed = Vector3(0.05, 0.0, 0.035)
	process.turbulence_noise_speed_random = 0.25
	process.turbulence_influence_min = 0.05
	process.turbulence_influence_max = 0.22
	process.scale_min = float(spec["scale"]) * 0.7
	process.scale_max = float(spec["scale"]) * 1.3
	process.angle_min = -180.0
	process.angle_max = 180.0
	# The angle must stay CONSTANT over a particle's life: ground_fog.gdshader uses it as
	# the seed that picks which of its three sprites this quad is.
	process.angular_velocity_min = 0.0
	process.angular_velocity_max = 0.0
	process.color = Color(0.80, 0.86, 1.0, float(spec["alpha"]) * _alpha_tier_gain())
	process.color_ramp = _fade_ramp()

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)

	var node := GPUParticles3D.new()
	node.name = node_name
	node.amount = tier_amount(int(spec["amount"]))
	node.lifetime = 9.0
	node.randomness = 0.7
	node.preprocess = 5.0
	node.process_material = process
	node.draw_pass_1 = quad
	var variant: Array = FOG_VARIANTS[int(spec.get("variant", 0)) % FOG_VARIANTS.size()]
	node.material_override = _ground_fog_material(
		Color(0.82, 0.88, 1.0), process.color.a, Vector2(0.013, 0.021), 1.35,
		float(variant[0]), float(variant[1]), float(variant[2]))
	# The billboard is done by the PARTICLE SYSTEM, not by the shader: transform_align is
	# computed engine side into the instance transform, so it works on Forward+ and on
	# gl_compatibility alike. A shader that billboards itself by writing MODELVIEW_MATRIX
	# does NOT: that is what left the dust as world space rectangles in the simulator.
	node.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	node.position = at
	# Wide enough that the blobs are not culled as they drift off the stage edge.
	node.visibility_aabb = AABB(Vector3(-4.0, -0.4, -4.0), Vector3(8.0, 1.0, 8.0))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## A tendril: a few small wisps thrown OUT over the stage lip, where they sink and
## dissolve. Short lived and heavily turbulent, which is what makes them curl; there are
## only ~22 of them per emitter because these are the one part of the dry ice meant to be
## read as separate shapes.
func _tendril_emitter(node_name: String, spec: Dictionary) -> GPUParticles3D:
	var out: Vector3 = (spec["out"] as Vector3).normalized()
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = spec["extents"]
	process.direction = out
	process.spread = 35.0
	process.initial_velocity_min = 0.16
	process.initial_velocity_max = 0.30
	# Over the lip and DOWN: the tendril falls as it leaves, which is what dry ice does.
	process.gravity = Vector3(out.x * 0.01, -0.022, out.z * 0.01)
	process.damping_min = 0.10
	process.damping_max = 0.30
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.30
	process.turbulence_noise_scale = 4.2
	process.turbulence_noise_speed = Vector3(0.09, 0.0, 0.07)
	process.turbulence_noise_speed_random = 0.4
	process.turbulence_influence_min = 0.15
	process.turbulence_influence_max = 0.55
	process.scale_min = float(spec["scale"]) * 0.55
	process.scale_max = float(spec["scale"]) * 1.15
	# Growing as it goes is what turns a blob into a wisp that thins out and vanishes.
	process.scale_curve = _grow_curve()
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.angular_velocity_min = 0.0
	process.angular_velocity_max = 0.0
	process.color = Color(0.82, 0.88, 1.0, float(spec["alpha"]) * _alpha_tier_gain())
	process.color_ramp = _fade_ramp()

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)

	var node := GPUParticles3D.new()
	node.name = node_name
	node.amount = tier_amount(int(spec["amount"]))
	node.lifetime = TENDRIL_LIFETIME
	node.randomness = 0.85
	node.preprocess = 3.0
	node.process_material = process
	node.draw_pass_1 = quad
	# A tighter noise field and a sharper falloff than the bank, so a tendril has an edge.
	node.material_override = _ground_fog_material(
		Color(0.84, 0.90, 1.0), process.color.a, Vector2(0.026, 0.034), 2.1, 1.6, 1.75, 0.70)
	node.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	node.position = spec["at"]
	node.visibility_aabb = AABB(Vector3(-3.0, -0.6, -3.0), Vector3(6.0, 1.2, 6.0))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## The denser puff. One shot, so it is silent between bursts; _animate_dry_ice walks it
## round the rim and fires it every 6 to 11 s.
func _puff_emitter() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.30, 0.015, 0.30)
	process.direction = Vector3(0.0, 0.06, 0.0)
	process.spread = 80.0
	process.initial_velocity_min = 0.06
	process.initial_velocity_max = 0.18
	process.gravity = Vector3(0.0, -0.010, 0.0)
	process.damping_min = 0.12
	process.damping_max = 0.34
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.18
	process.turbulence_noise_scale = 3.0
	process.turbulence_noise_speed = Vector3(0.06, 0.0, 0.05)
	process.turbulence_influence_min = 0.08
	process.turbulence_influence_max = 0.34
	process.scale_min = PUFF_SCALE * 0.55
	process.scale_max = PUFF_SCALE
	process.scale_curve = _grow_curve()
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.angular_velocity_min = 0.0
	process.angular_velocity_max = 0.0
	process.color = Color(0.82, 0.88, 1.0, PUFF_ALPHA * _alpha_tier_gain())
	process.color_ramp = _fade_ramp()

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)

	var node := GPUParticles3D.new()
	node.name = "DryIcePuff"
	node.amount = tier_amount(PUFF_AMOUNT)
	node.lifetime = PUFF_LIFETIME
	node.one_shot = true
	node.explosiveness = 0.85
	node.randomness = 0.8
	node.emitting = false
	node.process_material = process
	node.draw_pass_1 = quad
	node.material_override = _ground_fog_material(
		Color(0.84, 0.90, 1.0), process.color.a, Vector2(0.018, 0.028), 1.6, 1.15, 1.0, 0.55)
	node.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	node.position = Vector3(0.0, 0.045, PUFF_RADIUS)
	node.visibility_aabb = AABB(Vector3(-3.0, -0.4, -3.0), Vector3(6.0, 1.0, 6.0))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## The faint dust INSIDE the beams, where they cross above the stage: what makes the
## cones read as light in air rather than as glass. The key art has a few specks in the
## shafts and nothing else in the air, so this box is small and nothing floats outside
## it. Tiny, bright, and slow.
func _dust_emitter() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = DUST_EXTENTS
	process.direction = Vector3(0.0, -1.0, 0.0)
	process.spread = 30.0
	process.initial_velocity_min = 0.02
	process.initial_velocity_max = 0.06
	process.gravity = Vector3(0.0, -0.01, 0.0)
	process.scale_min = 0.008
	process.scale_max = 0.018
	# A fixed random angle per mote and no spin: soft_sprite.gdshader uses the angle as the
	# seed for its twinkle, and a spinning particle would make that seed a strobe.
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.angular_velocity_min = 0.0
	process.angular_velocity_max = 0.0
	process.color = Color(1.0, 0.94, 0.86, 0.35)
	process.color_ramp = _fade_ramp()

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)

	var node := GPUParticles3D.new()
	node.name = "Dust"
	node.amount = tier_amount(DUST_AMOUNT)
	node.lifetime = 9.0
	node.randomness = 0.9
	node.preprocess = 5.0
	node.process_material = process
	node.draw_pass_1 = quad
	node.material_override = _soft_quad_material(Color(1.0, 0.94, 0.85), process.color.a)
	node.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	node.position = DUST_AT
	node.visibility_aabb = AABB(Vector3(-1.5, -0.5, -1.5), Vector3(3.0, 3.0, 3.0))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## Alpha in and out over the particle's life, so nothing ever pops.
func _fade_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, Color(1, 1, 1, 0))
	gradient.set_offset(1, 1.0)
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.25, Color(1, 1, 1, 1))
	gradient.add_point(0.65, Color(1, 1, 1, 0.85))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


## Per quad alpha is raised on the tiers that get fewer quads, so a thinner bank is not
## also a fainter one and the bottom of the frame reads the same on every device.
func _alpha_tier_gain() -> float:
	return float(ALPHA_TIER_GAIN.get(quality_tier(), 2.2)) * _haze_gain()


## Scale over life: small at birth, full size by the time it dissolves.
func _grow_curve() -> CurveTexture:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.55))
	curve.add_point(Vector2(0.45, 0.92))
	curve.add_point(Vector2(1.0, 1.0))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


## The animated ground fog material (res://render/stage/ground_fog.gdshader): a soft
## additive billboard whose alpha is bitten into by two octaves of scrolling noise, with
## three procedural sprites picked per particle. Falls back to the old static gradient
## billboard if the shader file is missing, so the stage always builds.
func _ground_fog_material(tint: Color, alpha_scale: float, scroll: Vector2,
		noise_scale: float, softness: float, stretch: float, bite: float) -> Material:
	var shader: Shader = null
	if ResourceLoader.exists(GROUND_FOG_SHADER):
		shader = load(GROUND_FOG_SHADER) as Shader
	if shader == null:
		return _soft_quad_material(tint, alpha_scale)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("base_colour", tint)
	# The authored per quad alpha as a CONSTANT. It is the same number that went into the
	# particle colour, and it is what the quad falls back to if the particle colour is not
	# what the shader expects, which is why an opaque quad is impossible.
	mat.set_shader_parameter("alpha_scale", alpha_scale)
	mat.set_shader_parameter("use_particle_alpha", 1.0)
	# The one knob that turns the whole bank down.
	mat.set_shader_parameter("strength", 1.0)
	mat.set_shader_parameter("softness", softness)
	mat.set_shader_parameter("stretch", stretch)
	mat.set_shader_parameter("bite", bite)
	mat.set_shader_parameter("noise_scale", noise_scale)
	mat.set_shader_parameter("scroll", scroll)
	mat.set_shader_parameter("octave_mix", 0.35)
	mat.set_shader_parameter("floor_lift", 0.30)
	mat.set_shader_parameter("near_fade_begin", 0.22)
	mat.set_shader_parameter("near_fade_end", 1.05)
	return mat


## One soft additive billboard. Agent S 2026-09-14: this now goes through
## res://render/stage/soft_sprite.gdshader, which computes its falloff in GLSL and writes
## ALPHA explicitly, because the gradient-texture version below drew as OPAQUE TAN
## RECTANGLES on gl_compatibility in the simulator (see the shader's header comment). The
## texture version is kept only as the last resort fallback.
func _soft_quad_material(tint: Color, alpha_scale: float = 0.35) -> Material:
	var shader: Shader = null
	if ResourceLoader.exists(SOFT_SPRITE_SHADER):
		shader = load(SOFT_SPRITE_SHADER) as Shader
	if shader == null:
		return _gradient_quad_material(tint)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("base_colour", tint)
	mat.set_shader_parameter("alpha_scale", alpha_scale)
	mat.set_shader_parameter("use_particle_alpha", 1.0)
	mat.set_shader_parameter("strength", 1.0)
	mat.set_shader_parameter("softness", 1.6)
	mat.set_shader_parameter("twinkle", 0.25)
	mat.set_shader_parameter("twinkle_speed", 0.6)
	mat.set_shader_parameter("near_fade_begin", 0.10)
	mat.set_shader_parameter("near_fade_end", 0.45)
	return mat


## The pre-2026-09-14 billboard: a 64 px radial gradient as the only source of alpha. It is
## the material that failed in the compatibility renderer, so nothing reaches it unless
## res://render/stage/ is missing entirely.
func _gradient_quad_material(tint: Color) -> StandardMaterial3D:
	var gradient := Gradient.new()
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_offset(1, 1.0)
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.45, Color(1, 1, 1, 0.55))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 64
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.albedo_color = tint
	mat.albedo_texture = texture
	# The particle colour and the colour ramp arrive as vertex colour.
	mat.vertex_color_use_as_albedo = true
	mat.disable_receive_shadows = true
	return mat


# =============================================================== wave A: the showroom
#
# Lighting, camera and stage lead, 2026-09-24. Spec: docs/look/reference-study.md section 3,
# targets docs/look/img2/menu-b-faceoff.webp (M2) and garage-a-assembly.webp (G1), notes in
# docs/wave-a-stage-notes.md. Everything below is ADDED to the stage; the legacy camera
# modes, the movers, the dry ice and the bridge answers are unchanged, and a shell that
# never sends `shot` sees the new light and the old framing.

## `workshop_config` extras (docs/bridge-spec.md, "workshop_config.shot"):
##   shot:     "showroom" | "faceoff" | "garage" | "part"; absent = the legacy rig camera
##   opponent: a bot config for the far slot (faceoff only; absent falls back to showroom)
##   focus:    a part category for "part" (weapon, drive, armour, chassis, utility, paint)
##   frame:    the existing 0..1 horizontal placement, honoured by garage and part
func apply_presentation(payload: Dictionary) -> void:
	_build()
	var shot := str(payload.get("shot", ""))
	var opponent: Dictionary = {}
	if payload.get("opponent", null) is Dictionary:
		opponent = payload["opponent"] as Dictionary
	if shot == StageDirector.SHOT_FACEOFF and opponent.is_empty():
		# M1 covers every moment with no opponent (owner decision 2026-09-24).
		shot = StageDirector.SHOT_SHOWROOM
	if shot == StageDirector.SHOT_FACEOFF:
		show_opponent(opponent)
	else:
		show_opponent({})
	var options := {}
	if payload.has("focus"):
		options["focus"] = str(payload["focus"])
	if payload.has("frame"):
		options["frame"] = float(payload["frame"])
	if _director == null:
		return
	if shot == "":
		_director.release()
		_set_pull_focus("")
		return
	_director.set_shot(shot, options)
	_set_pull_focus(str(options.get("focus", "")) if shot == StageDirector.SHOT_PART else "")


func director() -> StageDirector:
	_build()
	return _director


func opponent_bot() -> Node3D:
	return _opponent if (_opponent != null and is_instance_valid(_opponent)) else null


## Stand `config` in the opponent's slot, facing the hero, frozen; {} clears the slot.
## Rebuilt only when the config actually changed, because the shell re-sends
## workshop_config on every builder edit.
func show_opponent(config: Dictionary) -> void:
	_build()
	var key := JSON.stringify(config) if not config.is_empty() else ""
	if key == _opponent_key and (key == "" or opponent_bot() != null):
		return
	_opponent_key = key
	if _opponent != null and is_instance_valid(_opponent):
		_opponent.get_parent().remove_child(_opponent)
		_opponent.queue_free()
	_opponent = null
	if _opp_slot != null:
		_opp_slot.visible = key != ""
	if key == "":
		return
	var scene: PackedScene = load(BOT_SCENE)
	if scene == null:
		return
	var bot := scene.instantiate() as Node3D
	if bot == null:
		return
	bot.name = "OpponentBot"
	_opp_slot.add_child(bot)
	if bot.has_method("setup"):
		Livery.begin(config)
		bot.call("setup", config, 1, RandomNumberGenerator.new())
		Livery.clear()
	if bot.has_method("place_at"):
		var towards := (global_position - _opp_slot.global_position)
		# Nose at the hero, turned a touch towards the room so its weapon reads.
		var facing := Vector3(towards.x, 0.0, towards.z).normalized().rotated(Vector3.UP, deg_to_rad(14.0))
		bot.call("place_at", _opp_slot.global_position, facing)
	if bot.has_method("freeze"):
		bot.call("freeze")
	_freeze_bodies(bot)
	seat_on_ground(bot, _opp_slot)
	_opponent = bot


## Where the opponent stands (its bounds' centre when there is one), in world space.
func opponent_point() -> Vector3:
	_build()
	var at := _opp_slot.global_position + Vector3(0.0, 0.3, 0.0)
	var opp := opponent_bot()
	if opp != null:
		var box := _world_aabb(opp)
		if box.size != Vector3.ZERO:
			return box.get_center()
	return at


## The turntable angle, in degrees, that points the hero's nose at the opponent and then
## FACEOFF_NOSE_TO_ROOM_DEG back towards the room.
func faceoff_hero_yaw_deg() -> float:
	_build()
	var to := _opp_slot.global_position - _turntable.global_position
	var yaw := atan2(-to.z, to.x)
	return rad_to_deg(yaw) - FACEOFF_NOSE_TO_ROOM_DEG


## The director's turntable control. `park` NAN means turn at `speed` deg/s.
func set_turn(speed: float, park: float) -> void:
	_turn_override = true
	_turn_speed = speed
	_turn_park = park


## The director has let go: the legacy auto rotate is back in charge.
func director_released() -> void:
	_turn_override = false
	_turn_park = NAN
	_set_pull_focus("")
	set_platform(true)


## Raise or retract the turntable platform. Retracting sinks the disc, its ring and its
## edge light under the floor and lowers the machine onto the floor over PLATFORM_S.
func set_platform(raised: bool) -> void:
	_platform_want = 1.0 if raised else 0.0


func platform_share() -> float:
	return _platform_k


func _animate_platform(delta: float) -> void:
	if is_equal_approx(_platform_k, _platform_want) and delta > 0.0:
		return
	_platform_k = move_toward(_platform_k, _platform_want, delta / PLATFORM_S) if delta > 0.0 else _platform_want
	var k := smoothstep(0.0, 1.0, _platform_k)
	var sink := -(STAGE_HEIGHT + 0.04) * (1.0 - k)
	for name_ in ["Stage/Disc", "Stage/Ring", "Stage/EdgeLight"]:
		var node := get_node_or_null(name_) as Node3D
		if node == null:
			continue
		if not node.has_meta("rest_y"):
			node.set_meta("rest_y", node.position.y)
		node.position.y = float(node.get_meta("rest_y")) + sink
		node.visible = _platform_k > 0.01
	if _turntable != null:
		_turntable.position.y = STAGE_HEIGHT * k
	# The rim bank is the fog pouring over the platform's lip: no platform, no bank.
	var wash := get_node_or_null("Room/FloorWash") as Light3D
	if wash != null:
		wash.visible = _platform_k < 0.5
	var rim_fog := get_node_or_null("FogRim") as FogVolume
	if rim_fog != null:
		rim_fog.visible = _volumetric and _platform_k > 0.5
	# The hero's cached bounds carry a world centre.
	_hero_bounds = {}


## The hero's bounds, rotation invariant, cached per show_bot. `centre` is world space;
## `radius` is the largest horizontal reach from that centre (so the turning machine never
## outgrows its framing); `length` runs along the machine's nose, `width` across it.
func hero_bounds() -> Dictionary:
	_build()
	if not _hero_bounds.is_empty():
		return _hero_bounds
	var fallback := {"centre": stage_centre() + Vector3(0.0, 0.18, 0.0), "radius": 0.45,
		"height": 0.3, "length": 0.75, "width": 0.55}
	var hero := bot()
	if hero == null:
		return fallback
	# In turntable space, so the answer does not change as the table turns.
	var inv := _turntable.global_transform.affine_inverse()
	var box := AABB()
	var first := true
	for mesh in _meshes_under(hero):
		var local_box: AABB = inv * mesh.global_transform * mesh.get_aabb()
		if first:
			box = local_box
			first = false
		else:
			box = box.merge(local_box)
	if first:
		return fallback
	var c := box.get_center()
	var reach := 0.0
	for i in 8:
		var corner := box.get_endpoint(i)
		reach = maxf(reach, Vector2(corner.x - c.x, corner.z - c.z).length())
	# The machine was placed facing turntable +X, so x is its length.
	_hero_bounds = {"centre": _turntable.global_transform * c, "radius": reach,
		"height": box.size.y, "length": box.size.x, "width": box.size.z,
		"local_centre": c}
	return _hero_bounds


## Stand `machine` so its lowest GROUND CONTACT point (wheels, track belts, feet, hover
## skirt: whatever its drive puts on the floor) is exactly on `surface`'s origin plane,
## the turntable top or the opponent slot's floor. Measured from the assembled RENDER
## meshes, never from a radius constant, so a rebuilt wheel or tread (wave A models lead)
## seats itself. Returns how far the machine moved, metres (positive is up).
##
## Why not the physics rest height: the stage never runs physics (every body is frozen),
## and what the owner sees is the render mesh, which is allowed to differ from the
## collider by a few millimetres of tread.
func seat_on_ground(machine: Node3D, surface: Node3D) -> float:
	if machine == null or surface == null:
		return 0.0
	var lowest := ground_contact_height(machine, surface)
	if is_inf(lowest):
		return 0.0
	# Move along the surface's own up, in the machine's parent's space.
	var lift := -lowest
	var world_up := surface.global_transform.basis.y.normalized() * lift
	machine.global_position += world_up
	return lift


## The lowest ground contact point of `machine`, in `surface`'s local Y (0 = on it). INF
## when the machine has no meshes at all.
func ground_contact_height(machine: Node3D, surface: Node3D) -> float:
	var inv := surface.global_transform.affine_inverse()
	var lowest := INF
	for mesh in ground_contact_meshes(machine):
		var box: AABB = inv * mesh.global_transform * mesh.get_aabb()
		lowest = minf(lowest, box.position.y)
	return lowest


## The meshes a machine stands on: everything under its wheel bodies, plus the drive
## visuals the bodiless drives hang off the hull (TrackSkin*, Leg*, HoverSkirt). A
## machine with none of those (a bare hull) stands on its lowest mesh of any kind.
func ground_contact_meshes(machine: Node3D) -> Array[MeshInstance3D]:
	var roots: Array[Node] = []
	if machine.has_method("attached_parts"):
		for part_variant in machine.call("attached_parts"):
			var part := part_variant as Node
			if part != null and "part_kind" in part and str(part.get("part_kind")) == "wheel":
				roots.append(part)
	var hull: Node = machine.get("chassis") if "chassis" in machine else null
	if hull != null:
		for child in hull.get_children():
			var n := String(child.name)
			if n.begins_with("TrackSkin") or n.begins_with("Leg") or n.begins_with("HoverSkirt"):
				roots.append(child)
	var out: Array[MeshInstance3D] = []
	for root_node in roots:
		out.append_array(_meshes_under(root_node))
	if out.is_empty():
		out = _meshes_under(machine)
	return out


## The weapon's mount in world space, for the test-fire spark.
func weapon_point() -> Vector3:
	var hero := bot()
	if hero != null and hero.has_method("weapon_socket_world"):
		return hero.call("weapon_socket_world")
	return stage_centre() + Vector3(0.3, 0.2, 0.0)


## G2: the focused category's centre, size and the direction it faces out of the machine,
## all world space, INCLUDING the pull-out.
func part_focus(category: String) -> Dictionary:
	var hb := hero_bounds()
	var hero_centre: Vector3 = hb["centre"]
	var bodies := _category_nodes(category)
	var box := AABB()
	var first := true
	for node in bodies:
		for mesh in _meshes_under(node):
			var b: AABB = mesh.global_transform * mesh.get_aabb()
			if first:
				box = b
				first = false
			else:
				box = box.merge(b)
	if first:
		# Paint, utility and anything with no bodies of its own: the whole machine.
		return {"centre": hero_centre, "radius": float(hb["radius"]) * 0.8,
			"outward": _hero_forward().lerp(Vector3(0, 0, 1), 0.5).normalized()}
	var centre := box.get_center()
	var outward := centre - hero_centre
	outward.y = 0.0
	if outward.length() < 0.05:
		outward = _hero_forward()
	return {"centre": centre, "radius": box.size.length() * 0.5, "outward": outward.normalized()}


func _hero_forward() -> Vector3:
	var fwd := _turntable.global_transform.basis * Vector3.RIGHT
	fwd.y = 0.0
	return fwd.normalized() if fwd.length() > 0.001 else Vector3(0, 0, 1)


## The bodies that make up a garage category on the hero.
func _category_nodes(category: String) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var hero := bot()
	if hero == null or not hero.has_method("attached_parts"):
		return out
	var kinds: Array = []
	match category:
		"weapon":
			kinds = ["weapon"]
		"drive", "wheels":
			kinds = ["wheel"]
		"armour":
			kinds = ["armour"]
		"chassis":
			kinds = ["chassis"]
		_:
			return out
	for part_variant in hero.call("attached_parts"):
		var part := part_variant as Node3D
		if part != null and "part_kind" in part and str(part.get("part_kind")) in kinds:
			out.append(part)
	return out


## Every MeshInstance3D under `node` that is drawing.
func _meshes_under(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var mi := n as MeshInstance3D
		# Its own flag, not is_visible_in_tree(): the stage may be dark (a fight is up)
		# when the shell re-sends the build, and the machine must still seat.
		if mi != null and mi.mesh != null and mi.visible:
			out.append(mi)
		for child in n.get_children():
			stack.append(child)
	return out


func _world_aabb(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for mesh in _meshes_under(node):
		var b: AABB = mesh.global_transform * mesh.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box


# ---------------------------------------------------------------- G2 pull-out

func _set_pull_focus(category: String) -> void:
	if category == _pull_focus:
		return
	_pull_focus = category
	_pull_k = 0.0
	# Put everything back first; the new category eases out from rest.
	for body_variant in _pull_base.keys():
		var body := body_variant as Node3D
		if body != null and is_instance_valid(body):
			body.transform = _pull_base[body_variant]
	_pull_base.clear()
	_pulled.clear()
	if category == "" or category == "chassis":
		return
	var hb := hero_bounds()
	var hero_centre: Vector3 = hb["centre"]
	for body in _category_nodes(category):
		_pull_base[body] = body.transform
		var out := body.global_position - hero_centre
		out.y = 0.0
		if out.length() < 0.02:
			out = _hero_forward()
		_pulled[body] = out.normalized() * PULL_OUT_M + Vector3(0.0, PULL_OUT_LIFT_M, 0.0)


func pull_share() -> float:
	return _pull_k


func _animate_pull(delta: float) -> void:
	if _pulled.is_empty():
		return
	if delta > 0.0:
		_pull_k += (1.0 - _pull_k) * (1.0 - exp(-delta / PULL_OUT_TAU))
	for body_variant in _pulled.keys():
		var body := body_variant as Node3D
		if body == null or not is_instance_valid(body) or not _pull_base.has(body_variant):
			continue
		var base: Transform3D = _pull_base[body_variant]
		var world_offset: Vector3 = _pulled[body_variant] * _pull_k
		var parent := body.get_parent() as Node3D
		var local_offset := world_offset
		if parent != null:
			local_offset = parent.global_transform.basis.inverse() * world_offset
		body.transform = Transform3D(base.basis, base.origin + local_offset)


# ---------------------------------------------------------------- attract

## The test-fire: a short shower of sparks off the weapon and a warm flash on the plates.
func fire_test_spark(at: Vector3 = Vector3.INF) -> void:
	_build()
	if _spark == null:
		return
	var where := weapon_point() if at == Vector3.INF else at
	_spark.global_position = where
	_spark.restart()
	_spark.emitting = true
	if _flash != null:
		_flash.global_position = where + Vector3(0.0, 0.12, 0.0)
		_flash.visible = true
		_flash_t = 0.0


func _animate_flash(delta: float) -> void:
	if _flash == null or _flash_t < 0.0:
		return
	_flash_t += delta
	var k := _flash_t / SPARK_FLASH_S
	if k >= 1.0:
		_flash.light_energy = 0.0
		_flash.visible = false
		_flash_t = -1.0
		return
	# Up fast, down slower: a strike, not a pulse.
	_flash.light_energy = SPARK_FLASH_ENERGY * (1.0 - k) * minf(k * 8.0, 1.0)


func _on_attract_cue(kind: String, at: Vector3) -> void:
	if kind == "test_fire":
		fire_test_spark(at)


func _on_stage_camera(payload: Dictionary) -> void:
	if _director == null or not _director.is_directing():
		return
	var raw_orbit: Variant = payload.get("orbit", null)
	if raw_orbit is Array and (raw_orbit as Array).size() >= 2:
		_director.orbit(Vector2(float(raw_orbit[0]), float(raw_orbit[1])))
	if payload.has("pinch"):
		_director.pinch(float(payload["pinch"]))


# ---------------------------------------------------------------- construction

func _stage_tier_allows(feature: String) -> bool:
	match feature:
		"probe":
			return _allows("reflection_probe")
		"dof":
			# DOF exists on Forward+ and Mobile, not on the compatibility renderer.
			return quality_tier() != "low"
		"practical_beams":
			return quality_tier() != "low"
	return true


func _build_room() -> void:
	# The room is what the probe captures.
	for name_ in ["Backdrop", "Stage/Disc", "Stage/Ring", "Stage/EdgeLight"]:
		var gi := get_node_or_null(name_) as GeometryInstance3D
		if gi != null:
			gi.layers = 1 | ROOM_LAYER

	var room := Node3D.new()
	room.name = "Room"
	add_child(room)

	# The top softbox. Faces down, sits above every framing, and exists to be reflected.
	var softbox := MeshInstance3D.new()
	softbox.name = "Softbox"
	var plane := PlaneMesh.new()
	plane.size = SOFTBOX_SIZE
	softbox.mesh = plane
	softbox.material_override = _emissive(COL_SOFTBOX, SOFTBOX_EMISSION)
	softbox.position = Vector3(0.0, SOFTBOX_HEIGHT, 0.0)
	softbox.rotation = Vector3(PI, 0.0, 0.0)            # face down
	softbox.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	softbox.layers = ROOM_LAYER
	room.add_child(softbox)
	var omni := OmniLight3D.new()
	omni.name = "SoftboxFill"
	omni.light_color = COL_SOFTBOX
	omni.light_energy = SOFTBOX_OMNI_ENERGY
	omni.omni_range = 3.0
	omni.omni_attenuation = 1.4
	omni.shadow_enabled = false
	omni.light_volumetric_fog_energy = 0.0
	omni.position = Vector3(0.0, SOFTBOX_HEIGHT - 0.1, 0.0)
	room.add_child(omni)

	# The two strips, 45 degrees either side behind the stage, facing it.
	for i in STRIP_AT.size():
		var at: Vector3 = STRIP_AT[i]
		var strip := MeshInstance3D.new()
		strip.name = "Strip%d" % i
		var box := BoxMesh.new()
		box.size = STRIP_SIZE
		strip.mesh = box
		strip.material_override = _emissive(COL_STRIP, STRIP_EMISSION)
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		strip.layers = ROOM_LAYER
		room.add_child(strip)
		# Long axis across the line to the stage, so the strip faces the machine. Local
		# maths, not look_at: the room may be built before the stage is in a tree.
		strip.transform = _local_look(at, Vector3(0.0, at.y, 0.0))
		strip.rotate_object_local(Vector3.UP, PI * 0.5)

	# Practicals: two clusters of four PAR cans on a low back truss.
	var truss := Node3D.new()
	truss.name = "Truss"
	truss.position = Vector3(0.0, TRUSS_Y, TRUSS_Z)
	room.add_child(truss)
	var bar := MeshInstance3D.new()
	bar.name = "Bar"
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(9.0, 0.06, 0.06)
	bar.mesh = bar_mesh
	var bar_mat := StandardMaterial3D.new()
	bar_mat.albedo_color = Color(0.03, 0.03, 0.035)
	bar_mat.metallic = 0.8
	bar_mat.roughness = 0.45
	bar.material_override = bar_mat
	bar.position = Vector3(0.0, 0.16, 0.0)
	bar.layers = ROOM_LAYER
	truss.add_child(bar)
	var lens := _emissive(COL_PRACTICAL, PRACTICAL_EMISSION)
	var can_body := StandardMaterial3D.new()
	can_body.albedo_color = Color(0.02, 0.02, 0.022)
	can_body.metallic = 0.6
	can_body.roughness = 0.5
	var cluster_index := 0
	for cluster_variant in PRACTICAL_CLUSTERS:
		var cluster: Vector2 = cluster_variant
		for j in 4:
			var can := Node3D.new()
			can.name = "Can%d_%d" % [cluster_index, j]
			can.position = Vector3(cluster.x + (float(j % 2) - 0.5) * 0.24,
				cluster.y - float(j >> 1) * 0.2, 0.0)
			truss.add_child(can)
			# Tilted down and towards the room, as a real rig would be focused: the lens faces
			# the audience, which is what puts a bright point in the face-off frame.
			can.rotation = Vector3(deg_to_rad(-62.0), PI, 0.0)
			var shell := MeshInstance3D.new()
			shell.name = "Shell"
			var shell_mesh := CylinderMesh.new()
			shell_mesh.top_radius = 0.1
			shell_mesh.bottom_radius = 0.1
			shell_mesh.height = 0.16
			shell_mesh.radial_segments = 12
			shell.mesh = shell_mesh
			shell.material_override = can_body
			shell.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
			shell.layers = ROOM_LAYER
			can.add_child(shell)
			var face := MeshInstance3D.new()
			face.name = "Lens"
			var face_mesh := CylinderMesh.new()
			face_mesh.top_radius = 0.05
			face_mesh.bottom_radius = 0.05
			face_mesh.height = 0.01
			face_mesh.radial_segments = 12
			face.mesh = face_mesh
			face.material_override = lens
			face.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
			face.position = Vector3(0.0, 0.0, -0.085)
			face.layers = ROOM_LAYER
			can.add_child(face)
			if _stage_tier_allows("practical_beams") and j < 2:
				var cone := MeshInstance3D.new()
				cone.name = "Beam"
				var length := 2.6
				cone.mesh = _beam_mesh(length, 7.0)
				var bm := _beam_material(COL_PRACTICAL, 0.07 * _haze_gain(), length, 11.0 + float(j))
				cone.material_override = bm
				cone.rotate_x(deg_to_rad(-90.0))
				cone.position = Vector3(0.0, 0.0, -length * 0.5 - 0.09)
				cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_fakes.append(cone)
				can.add_child(cone)
		cluster_index += 1

	# The face-off floor wash: a warm pool on the floor in front of the hero, which is what
	# the M2 target's foreground is (rivets and wet steel catching warm light). Only on
	# while the platform is retracted, i.e. only in the face-off.
	var wash := SpotLight3D.new()
	wash.name = "FloorWash"
	wash.light_color = COL_KEY
	wash.light_energy = FLOOR_WASH_ENERGY
	# A floor light: its specular on the wedge's bare steel bloomed into a white blob.
	wash.light_specular = 0.08
	wash.spot_angle = 40.0
	wash.spot_angle_attenuation = 2.4
	wash.spot_range = 5.0
	wash.shadow_enabled = false
	wash.light_volumetric_fog_energy = 0.0
	wash.visible = false
	room.add_child(wash)
	wash.transform = _local_look(FLOOR_WASH_AT, FLOOR_WASH_AIM)

	# The probe. Captured once; renders the room layer only.
	if _stage_tier_allows("probe"):
		var probe := ReflectionProbe.new()
		probe.name = "RoomProbe"
		probe.position = PROBE_AT
		probe.size = PROBE_SIZE
		probe.box_projection = true
		probe.interior = true
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		probe.intensity = 1.0
		probe.cull_mask = ROOM_LAYER
		probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
		probe.enable_shadows = false
		add_child(probe)
		_probe = probe


## A transform at `from` in the PARENT's space whose -Z points at `to`.
func _local_look(from: Vector3, to: Vector3) -> Transform3D:
	var dir := to - from
	var up := Vector3.UP if absf(dir.normalized().y) < 0.98 else Vector3.FORWARD
	return Transform3D(Basis.looking_at(dir, up), from)


## An emissive surface that reads as a light source: black albedo, all emission.
func _emissive(colour: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 0.0, 0.0)
	mat.roughness = 1.0
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = energy
	mat.disable_receive_shadows = true
	return mat


## The opponent's slot: cold top light with its haze cone and lamp head, a cold rim, and
## a small far dry ice bank. Hidden until show_opponent() puts a machine in it.
func _build_opponent_slot() -> void:
	var slot := Node3D.new()
	slot.name = "OpponentSlot"
	slot.position = OPPONENT_AT
	slot.visible = false
	add_child(slot)
	_opp_slot = slot

	var aim := Vector3(0.0, 0.25, 0.0)
	var mount := Node3D.new()
	mount.name = "TopMount"
	slot.add_child(mount)
	mount.transform = _local_look(OPP_TOP_AT, aim)
	var top := SpotLight3D.new()
	top.name = "OpponentTop"
	top.light_color = COL_OPP_COLD
	top.light_energy = OPP_TOP_ENERGY
	top.spot_angle = OPP_TOP_ANGLE_DEG
	top.spot_angle_attenuation = 0.9
	var length := OPP_TOP_AT.distance_to(aim)
	top.spot_range = length + 1.4
	top.shadow_enabled = false
	top.light_volumetric_fog_energy = MOVER_FOG_ENERGY if _volumetric else 1.0
	mount.add_child(top)
	var cone := MeshInstance3D.new()
	cone.name = "Beam"
	cone.mesh = _beam_mesh(length, OPP_TOP_ANGLE_DEG * 0.8)
	_opp_beam = _beam_material(COL_OPP_COLD, OPP_BEAM_ALPHA * _haze_gain(), length, 7.3)
	cone.material_override = _opp_beam
	cone.rotate_x(deg_to_rad(-90.0))
	cone.position = Vector3(0.0, 0.0, -length * 0.5)
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fakes.append(cone)
	mount.add_child(cone)
	var head := MeshInstance3D.new()
	head.name = "Head"
	var head_mesh := CylinderMesh.new()
	head_mesh.top_radius = 0.09
	head_mesh.bottom_radius = 0.11
	head_mesh.height = 0.09
	head_mesh.radial_segments = 12
	head.mesh = head_mesh
	head.material_override = _emissive(COL_OPP_COLD.lightened(0.3), 3.2)
	head.rotate_x(deg_to_rad(-90.0))
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mount.add_child(head)

	var rim := SpotLight3D.new()
	rim.name = "OpponentRim"
	rim.light_color = COL_OPP_COLD
	rim.light_energy = OPP_RIM_ENERGY
	rim.spot_angle = 26.0
	rim.spot_range = 3.0
	rim.shadow_enabled = false
	rim.light_volumetric_fog_energy = KEY_FOG_ENERGY if _volumetric else 1.0
	slot.add_child(rim)
	rim.transform = _local_look(OPP_RIM_AT, Vector3(0.0, 0.2, 0.0))

	# A low bank rolling round the opponent's feet, as in the target.
	var bank := _dry_ice_emitter("OpponentDryIce", {"at": Vector3.ZERO,
		"extents": Vector3(1.1, 0.02, 0.5), "variant": 1, "amount": 26, "scale": 0.95,
		"alpha": 0.014, "swirl": 0.06, "wind": Vector3(0.003, -0.003, 0.004)})
	bank.position = Vector3(0.0, 0.035, 0.55)
	slot.add_child(bank)
	_opp_bank = bank


func _build_attract() -> void:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.02
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 70.0
	process.initial_velocity_min = 1.2
	process.initial_velocity_max = 3.2
	process.gravity = Vector3(0.0, -7.0, 0.0)
	process.damping_min = 0.4
	process.damping_max = 1.2
	process.scale_min = 0.6
	process.scale_max = 1.2
	process.color = COL_SPARK
	process.color_ramp = _spark_ramp()
	var streak := QuadMesh.new()
	streak.size = Vector2(0.008, 0.07)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(4.0, 2.4, 1.0)   # above the glow threshold: sparks bloom
	mat.disable_receive_shadows = true
	var spark := GPUParticles3D.new()
	spark.name = "TestFireSpark"
	spark.amount = SPARK_AMOUNT
	spark.lifetime = 0.8
	spark.one_shot = true
	spark.explosiveness = 0.9
	spark.randomness = 0.6
	spark.emitting = false
	spark.process_material = process
	spark.draw_pass_1 = streak
	spark.material_override = mat
	spark.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	spark.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 3, 4))
	spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spark.local_coords = false
	# Under its own node: the stage's direct GPUParticles3D children are the haze, which
	# the tests hold to the compatibility renderer's billboard and shader rules. A spark is
	# a velocity aligned streak with a texture free unshaded material, fine on every tier.
	var attract := Node3D.new()
	attract.name = "Attract"
	add_child(attract)
	attract.add_child(spark)
	_spark = spark
	var flash := OmniLight3D.new()
	flash.name = "TestFireFlash"
	flash.light_color = COL_SPARK
	flash.light_energy = 0.0
	flash.omni_range = 1.4
	flash.shadow_enabled = false
	flash.light_volumetric_fog_energy = 0.0
	flash.visible = false
	attract.add_child(flash)
	_flash = flash


func _spark_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.95, 0.8, 1.0))
	gradient.set_color(1, Color(0.8, 0.2, 0.05, 0.0))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


## The vignette and film grain: one full screen multiply quad drawn after everything else
## in the stage's own pass (res://render/stage/stage_post.gdshader). It lives on its own
## layer so the probe never captures it, and it goes dark with the stage.
func _build_post() -> void:
	if not ResourceLoader.exists(POST_SHADER):
		return
	var shader := load(POST_SHADER) as Shader
	if shader == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.render_priority = Material.RENDER_PRIORITY_MAX
	var tier := quality_tier()
	mat.set_shader_parameter("vignette_amount", 0.22)
	mat.set_shader_parameter("vignette_start", 0.60)
	# Grain on the Forward+ tier only; the others keep the vignette, which is free.
	mat.set_shader_parameter("grain_amount", 0.015 if tier == "high" else 0.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var node := MeshInstance3D.new()
	node.name = "PostVignette"
	node.mesh = quad
	node.material_override = mat
	node.layers = POST_LAYER | 1
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The vertex shader puts it on the screen whatever the camera does, so it must never be
	# frustum culled.
	node.custom_aabb = AABB(Vector3(-1e4, -1e4, -1e4), Vector3(2e4, 2e4, 2e4))
	node.extra_cull_margin = 16384.0
	add_child(node)
	_post = node


func _build_director() -> void:
	var script := load(DIRECTOR_SCRIPT) as GDScript
	if script == null:
		return
	_director = script.new() as StageDirector
	if _director == null:
		return
	add_child(_director)
	_director.bind_stage(self)
	_director.set_dof_enabled(_stage_tier_allows("dof"))
	_director.attract_cue.connect(_on_attract_cue)


## Desktop QA: `--roboteer-shot=NAME[:focus]`, with the fixture's second bot (or the QA
## slice opponent) standing in for the next career opponent.
func _read_qa_shot() -> void:
	if not OS.has_feature("pc"):
		return
	for raw in OS.get_cmdline_user_args():
		var arg := str(raw)
		if not arg.begins_with(ARG_SHOT):
			continue
		var spec := arg.substr(ARG_SHOT.length()).split(":")
		var payload := {"shot": spec[0]}
		if spec.size() > 1:
			payload["focus"] = spec[1]
		if spec[0] == StageDirector.SHOT_FACEOFF:
			payload["opponent"] = qa_opponent_config()
		apply_presentation(payload)
		return


static func qa_opponent_config() -> Dictionary:
	var path := "res://qa/stage_slice_bots.json"
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary and (parsed as Dictionary).get("opponent", null) is Dictionary:
			return (parsed as Dictionary)["opponent"]
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string(DEFAULT_CONFIG))
	if fixture is Dictionary:
		var bots: Array = (fixture as Dictionary).get("bots", []) as Array
		if bots.size() > 1:
			return bots[1] as Dictionary
	return {}
