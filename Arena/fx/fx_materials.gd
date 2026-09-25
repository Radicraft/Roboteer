class_name FxMaterials extends RefCounted
## Every FX material and emission value in one place, so the glow budget is a list
## and not an archaeology exercise. docs/graphics-fx-notes.md records the numbers.
##
## The rule the whole file exists to hold (docs/graphics-bar.md): emissive FX must
## BLOOM when G1's glow is on, and still READ when it is not. Godot's glow only has
## anything to work with above 1.0, so the additive materials are given HDR albedo
## (values above 1). On the GL Compatibility tier there is no HDR buffer and no
## glow at all: everything above 1.0 clips flat, an orange spark clips to a white
## smear and the art direction's "gold is the one saturated warm" rule quietly
## breaks. So `energy()` tames the multiplier on that tier instead of clipping it.

## Nominal energies. G1's `Arena/render/arena_env.tres` does not set
## `glow_hdr_threshold`, so it is Godot's default **1.0**: a pixel only blooms once
## its HDR luminance passes 1.0, and `tonemap_exposure` (0.8 there) is applied
## first. Every value below is therefore chosen so `colour.get_luminance() x energy
## x 0.8` clears 1.0 with room to spare, and `fx_test.gd` asserts that against the
## live .tres so a future change to either side cannot silently un-bloom the bolts.
##
## Raised across the board after the first desktop frames (docs/graphics-fx-notes.md
## §10): at the fight framing a bolt is three pixels, and a three pixel source at
## `glow_intensity` 0.55 with the blur weighted onto the high mips contributes almost
## nothing. Size carries most of that fix; this carries the rest.
const BOLT_EMISSION := 5.0        # the gold hex nuts, lit metal + emission
const TRAIL_ENERGY := 5.0         # the additive streak behind a magnetised bolt
## FLASH, SPARK and CORE lowered 2026-09-25 (the contact white-out, gauntlet): at the closer
## fight camera the glow's big mips spread every over-threshold pixel into a machine-sized
## halo. Each still clears the glow threshold (lum x energy x 0.7 > 1) so it blooms, less.
const FLASH_ENERGY := 3.5         # the collect flash quad (was 6)
const SPARK_ENERGY := 3.5         # impact sparks (was 5)
const CORE_ENERGY := 4.0          # the hot white core of a detach (was 7)
const FLAME_ENERGY := 3.2         # flamethrower cone
const SPIKE_ENERGY := 4.5         # hazard tip flash

## What the Compatibility tier gets instead: enough over-brightness to still look
## hot, little enough that an orange spark is still orange after the clip.
const LDR_ENERGY := 1.45

const TEX_DIR := "res://fx/textures/"

const CHIP_GREY := Color(0.42, 0.44, 0.47)   # structural debris: never gold (brief §6)
const SPARK_WHITE := Color(1.0, 0.97, 0.88)
## The streak is gold pulled a third of the way to white: a pure BOLT_GOLD streak
## at this energy reads as a dull amber smear, and the head needs a hot core.
const TRAIL_GOLD := Color(0.966, 0.838, 0.537)
const SPARK_ORANGE := Color(0.82, 0.32, 0.10)
const FLAME_CORE := Color(1.0, 0.93, 0.72)
const FLAME_BODY := Color(1.0, 0.44, 0.10)


## True when the renderer has an HDR colour buffer and can therefore bloom.
## Forward+ and Mobile both have a RenderingDevice; GL Compatibility does not,
## and neither does --headless.
static func hdr_available() -> bool:
	return RenderingServer.get_rendering_device() != null


## An emissive multiplier that survives both tiers. See the note at the top.
static func energy(nominal: float) -> float:
	return nominal if hdr_available() else minf(nominal, LDR_ENERGY)


## An HDR colour for an UNSHADED material. Unshaded ignores `emission` entirely
## (the shader writes ALBEDO straight out), so brightness has to live in the
## albedo, and alpha has to stay at 1.0 or additive blending doubles it up.
static func hdr(colour: Color, nominal: float) -> Color:
	var e := energy(nominal)
	return Color(colour.r * e, colour.g * e, colour.b * e, 1.0)


static func texture(file_name: String) -> Texture2D:
	var path := TEX_DIR + file_name
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## The bolts themselves: gold metal that also glows. Lit, so the hex facets still
## catch the arena key light and the nut reads as a machined object rather than a
## sprite; emissive on top so it survives against the bright steel floor.
static func bolt_metal() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = FightTypes.BOLT_GOLD
	m.metallic = 1.0
	m.metallic_specular = 0.65
	m.roughness = 0.3
	m.emission_enabled = true
	m.emission = FightTypes.BOLT_GOLD
	m.emission_energy_multiplier = energy(BOLT_EMISSION)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.cull_mode = BaseMaterial3D.CULL_DISABLED   # 20 tris at 5 cm; two sided is free
	m.disable_receive_shadows = true
	return m


## Structural debris. Dull, grey, matte, LIT and never emissive: the brief's
## readability rule is that a player must never mistake a chip for scrap.
static func debris_metal() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = CHIP_GREY
	m.metallic = 0.35
	m.metallic_specular = 0.35
	m.roughness = 0.72
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.vertex_color_use_as_albedo = true          # MultiMesh instance colour = fade out
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return m


## A textured additive billboard: trails, flashes, flame, spark glow.
## `billboard` false leaves the instance basis alone, for quads this code orients
## itself (a velocity aligned streak cannot use BILLBOARD_FIXED_Y, which pins to
## world +Y, not to the instance's own Y).
static func additive(tex: Texture2D, colour: Color, nominal: float, billboard: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = hdr(colour, nominal)
	m.vertex_color_use_as_albedo = true
	if tex != null:
		m.albedo_texture = tex
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.no_depth_test = false
	return m


## Alpha blended, unshaded, billboarded. Dust: it must occlude, not glow.
static func soft_smoke(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.vertex_color_use_as_albedo = true
	if tex != null:
		m.albedo_texture = tex
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return m
