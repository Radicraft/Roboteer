extends Node
## Autoload `GraphicsQuality`: one place that decides how expensive this run is allowed
## to be, and the only place that turns a renderer feature on or off.
##
## docs/graphics-bar.md: the device is Forward+ on Metal, the simulator is OpenGL ES 3
## (gl_compatibility), and the same scenes have to look right on both. Every scalable
## setting in the project goes through here so that dropping the frame rate back into
## budget is a one line change with a documented order (docs/graphics-render-notes.md).
##
## Three tiers:
##
## | tier | when | SSAO | SSR | glow | volumetric fog | decals | shadows |
## |---|---|---|---|---|---|---|---|
## | high | forward_plus (iPhone with A15 or newer, and the Mac) | yes | yes | yes | yes | yes | 2 cascades, soft |
## | medium | mobile renderer (older iPhones) | no | no | yes | no | yes | 1 cascade |
## | low | gl_compatibility (the iOS simulator) and headless | no | no | no | no | NO (unsupported) | 1 cascade |
##
## This script has no `class_name` on purpose: an autoload and a global class may not
## share a name. Anything that is not itself an autoload reaches it with
## `GraphicsQuality.resolve(self)`, which returns the autoload when there is one and a
## private instance when there is not (a `--script` test run has no autoloads at all).

const TIER_HIGH := "high"
const TIER_MEDIUM := "medium"
const TIER_LOW := "low"
const TIERS := [TIER_HIGH, TIER_MEDIUM, TIER_LOW]

## `--roboteer-tier=high|medium|low` forces a tier on the desktop, so one Mac run can
## shoot the simulator's look. Never read on a device build.
const ARG_TIER := "--roboteer-tier="

## What each tier is allowed to switch on. `allows()` is the only reader.
const FEATURES := {
	TIER_HIGH: {
		"ssao": true, "ssr": true, "ssil": false, "sdfgi": false,
		"glow": true, "fog": true, "volumetric_fog": true,
		"decals": true, "reflection_probe": true,
		"soft_shadows": true, "shadows": true, "msaa": true, "debanding": true,
	},
	TIER_MEDIUM: {
		"ssao": false, "ssr": false, "ssil": false, "sdfgi": false,
		"glow": true, "fog": true, "volumetric_fog": false,
		"decals": true, "reflection_probe": true,
		"soft_shadows": false, "shadows": true, "msaa": false, "debanding": false,
	},
	# MARKED SIMULATOR FIX (docs/simulator-rendering.md): `shadows` and `fog` are off on the
	# low tier. Both are pure fragment cost, and the low tier only ever runs on the software
	# rasterizer in the simulator (or headless, where nothing draws at all). Shadow lookups
	# are the most expensive thing left in the scene shader once the resolution is down.
	TIER_LOW: {
		"ssao": false, "ssr": false, "ssil": false, "sdfgi": false,
		"glow": false, "fog": false, "volumetric_fog": false,
		"decals": false, "reflection_probe": false,
		"soft_shadows": false, "shadows": false, "msaa": false, "debanding": false,
	},
}

## MARKED SIMULATOR FIX (docs/simulator-rendering.md). `scaling_3d_scale` shrinks only the
## 3D buffer; the tonemap/adjustment post pass and the viewport texture still run at the
## full window size, and on the software rasterizer THAT became the bottleneck
## (`GLES3::PostEffects::post_copy`, 1.7 s in one full screen draw). `stretch_shrink` on the
## SubViewportContainer shrinks the whole SubViewport instead, so the 3D pass, the post pass
## and the render target are all a sixteenth of the pixels, and only the final upscale blit
## is full screen. Aspect ratio and input mapping are preserved by the container.
const STAGE_SHRINK := {TIER_HIGH: 1, TIER_MEDIUM: 1, TIER_LOW: 4}

## Directional shadow atlas, per tier. The project setting is the high value; the lower
## tiers are re-applied at runtime through RenderingServer.
const SHADOW_ATLAS := {TIER_HIGH: 4096, TIER_MEDIUM: 2048, TIER_LOW: 2048}
## Positional (spot and omni) shadow atlas on a SubViewport. The stage has one shadow
## casting spot, the yard none, so this never needs to be large.
const POSITIONAL_ATLAS := {TIER_HIGH: 2048, TIER_MEDIUM: 1024, TIER_LOW: 1024}

## Directional shadow distance in metres. The yard is 10 m across and the camera sits
## about 9 m back, so 28 m covers it with room for a flipped bot in the air.
const SHADOW_MAX_DISTANCE := 28.0
## Soft shadows come from the light's angular size (Forward+ only). Half a degree is
## about the sun; 0.6 is a slightly softer studio key, which is what the art direction
## asks for without smearing the bolt heads' contact shadows.
const KEY_ANGULAR_DISTANCE := 0.6

## The first iPhone generation that gets Forward+ (docs/graphics-bar.md): A15, which is
## `iPhone14,*`. Anything older is asked to run the mobile renderer.
const MIN_IPHONE_MAJOR_FOR_HIGH := 14

var _tier := TIER_LOW
var _method := ""
var _driver := ""
var _model := ""
var _adapter := ""
var _forced := ""
var _auto_viewports := true


func _ready() -> void:
	detect()
	apply_simulation_rate()
	apply_viewport(get_viewport())
	# Every fight builds its own SubViewport with its own World3D (fight.gd), and a
	# SubViewport does not inherit the project's anti aliasing settings. Rather than
	# reach into another agent's scene, catch them as they enter the tree.
	if _auto_viewports and is_inside_tree():
		get_tree().node_added.connect(_on_node_added)
		# Anything already in the tree when this autoload starts (nothing, in the shipping
		# app; the whole scene, in a test that loads it first).
		_sweep(get_tree().root)


func _sweep(node: Node) -> void:
	if node == null:
		return
	_on_node_added(node)
	for child in node.get_children():
		_sweep(child)


# ---------------------------------------------------------------- detection

## Work out the tier from the renderer actually in use, the OS and the device model.
## Safe to call again; QA calls it after forcing a tier.
func detect() -> String:
	_method = _current_rendering_method()
	_driver = _current_rendering_driver()
	_model = _safe_model_name()
	_adapter = _safe_adapter_name()
	_forced = _cmdline_tier()

	if _forced != "":
		_tier = _forced
		return _tier

	# A headless run keeps the project's rendering method name ("forward_plus") while the
	# actual driver is the dummy one, which implements nothing. Tested before the method,
	# because every headless test would otherwise claim the high tier and build volumetric
	# fog, reflection probes and decals that can never draw.
	if _driver == "dummy" or DisplayServer.get_name() == "headless":
		_tier = TIER_LOW
		return _tier

	match _method:
		"forward_plus":
			_tier = TIER_HIGH
		"mobile":
			_tier = TIER_MEDIUM
		_:
			# gl_compatibility and anything unknown.
			_tier = TIER_LOW

	# An old iPhone that somehow started Forward+ is stepped down rather than trusted.
	if _tier == TIER_HIGH and OS.get_name() == "iOS" and not _iphone_is_modern(_model):
		_tier = TIER_MEDIUM
	return _tier


func tier() -> String:
	return _tier


## QA and the tests. Anything not in TIERS is ignored.
func set_tier(value: String) -> void:
	if value in TIERS:
		_tier = value


func allows(feature: String) -> bool:
	var table: Dictionary = FEATURES.get(_tier, FEATURES[TIER_LOW]) as Dictionary
	return bool(table.get(feature, false))


## Everything the notes and the QA overlay want to print in one line.
func describe() -> Dictionary:
	return {
		"tier": _tier,
		"rendering_method": _method,
		"rendering_driver": _driver,
		"model": _model,
		"adapter": _adapter,
		"forced": _forced != "",
		"os": OS.get_name(),
		# 1.0 means the 3D is drawn at one pixel per device pixel. Anything above it is a
		# resolution LOSS, and this is the only place it can be read off a phone. See
		# viewport_oversample() and docs/wave-v-v4-notes.md.
		"oversample": "%.4f" % viewport_oversample(get_viewport() if is_inside_tree() else null),
	}


## How many DEVICE pixels one of this viewport's own pixels is blown up to on the way to
## the screen. 1.0 is native. Wave V, agent V4 (docs/wave-v-v4-notes.md).
##
## `window/stretch/mode = "canvas_items"` makes the root window report a `size` in real
## device pixels and a `get_visible_rect()` in the stretched canvas units every Control is
## laid out in. On the owner's iPhone 17 those are 2622 x 1206 and 2417 x 1112: a ratio of
## 1.0846. That matters because the FIGHT is not drawn into the root viewport at all. It is
## drawn into the SubViewport under `fight.tscn`'s `Stage` SubViewportContainer, and a
## SubViewportContainer sizes its child from its own Control size, which is in CANVAS
## units. So the whole 3D image is rendered at 2417 x 1112, 85 % of the device's pixels,
## and bilinearly blown back up to 2622 x 1206 by a non integer factor. Every measurement
## in this file and every texture in the pack is downstream of that.
##
## Nothing here fixes it, because the fix is one key in the `[display]` section
## (`window/stretch/mode = "disabled"`) and that changes the coordinate space `hud.gd` and
## `controls.gd` lay themselves out in. Both of them derive their whole scale from
## `get_visible_rect()` (`_pt = min(s.x / 1206, s.y / 556)`), so both would come out at the
## same physical size, and the safe area — which arrives from Swift in DEVICE pixels and is
## consumed here as canvas units — would stop being 8.5 % too generous and become exact.
## That is a two line change for whoever owns those two files, and this function is how to
## confirm it worked: it reads 1.0000 when the fight is drawing natively.
static func viewport_oversample(vp: Viewport) -> float:
	if vp == null or not is_instance_valid(vp):
		return 1.0
	var visible := vp.get_visible_rect().size
	var real := Vector2.ZERO
	var window := vp as Window
	if window != null:
		real = Vector2(window.size)
	else:
		var sub := vp as SubViewport
		if sub != null:
			real = Vector2(sub.size)
	if real.x <= 1.0 or real.y <= 1.0 or visible.x <= 1.0 or visible.y <= 1.0:
		return 1.0
	return maxf(minf(real.x / visible.x, real.y / visible.y), 1.0)


func rendering_method() -> String:
	return _method


# ---------------------------------------------------------------- applying

## MARKED SIMULATOR FIX (docs/simulator-rendering.md). Godot runs at most
## `max_physics_steps_per_frame` fixed steps per drawn frame, so on the software rasterizer
## (1 to 3 frames a second) the simulation crawls at a fraction of real time and a fight
## that works headless never reaches its result. The low tier lets the simulation run ahead
## of the renderer. This changes nothing about determinism: the step size is still fixed and
## the same number of steps happen, they are just not rationed to the frame rate.
func apply_simulation_rate() -> void:
	if _tier == TIER_LOW:
		Engine.max_physics_steps_per_frame = 64

## Push the tier onto one Environment and any lights that came with it. The resources in
## `res://render/` are authored for the high tier; this only ever turns things DOWN, so a
## scene can load its environment and call this without knowing which phone it is on.
func apply(env: Environment, lights: Array = []) -> void:
	if env != null:
		_apply_environment(env)
	for light_variant in lights:
		var light := light_variant as Light3D
		if light != null and is_instance_valid(light):
			apply_light(light)
	RenderingServer.directional_shadow_atlas_set_size(
		int(SHADOW_ATLAS.get(_tier, 2048)), _tier == TIER_HIGH)


func _apply_environment(env: Environment) -> void:
	env.ssao_enabled = env.ssao_enabled and allows("ssao")
	env.ssr_enabled = env.ssr_enabled and allows("ssr")
	env.ssil_enabled = env.ssil_enabled and allows("ssil")
	env.sdfgi_enabled = env.sdfgi_enabled and allows("sdfgi")
	env.glow_enabled = env.glow_enabled and allows("glow")
	env.fog_enabled = env.fog_enabled and allows("fog")
	env.volumetric_fog_enabled = env.volumetric_fog_enabled and allows("volumetric_fog")
	if _tier == TIER_LOW:
		# The compatibility renderer has no HDR buffer worth the name. Pull the exposure
		# back to neutral so the simulator is a readable proxy rather than a blown out one.
		env.tonemap_exposure = minf(env.tonemap_exposure, 1.0)
		# MARKED SIMULATOR FIX (docs/simulator-rendering.md): brightness/contrast/saturation
		# is a branch in the same full screen post fragment program that the software
		# rasterizer interprets per pixel. Off, it is a straight tonemap and copy.
		env.adjustment_enabled = false


## Shadow quality per light. Directional lights get the cascade count and the soft
## shadow; spots and omnis only get the blur, because their cost is the atlas.
func apply_light(light: Light3D) -> void:
	if not allows("volumetric_fog"):
		# Free on every tier that has no volumetric fog, but a stale value would light
		# real fog the moment a high tier run loaded the same scene. Done BEFORE the
		# shadow branch so it still holds on the low tier, which returns early.
		light.light_volumetric_fog_energy = 0.0
	if not allows("shadows"):
		light.shadow_enabled = false
		return
	var directional := light as DirectionalLight3D
	if directional != null:
		if _tier == TIER_HIGH:
			# ONE cascade, not two. Two split a 10 m arena across a seam that showed in
			# the shot frames as a straight edged lighter rectangle over most of the
			# floor, and a 10 m room does not need the range two cascades buy. The soft
			# shadow stays: that is the angular distance, not the split count.
			directional.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			directional.directional_shadow_blend_splits = false
			directional.light_angular_distance = KEY_ANGULAR_DISTANCE
			directional.shadow_blur = 1.2
		else:
			directional.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			directional.directional_shadow_blend_splits = false
			directional.light_angular_distance = 0.0
			directional.shadow_blur = 1.0
		directional.directional_shadow_max_distance = SHADOW_MAX_DISTANCE
		directional.directional_shadow_fade_start = 0.9
	else:
		light.shadow_blur = 1.0 if _tier == TIER_HIGH else 0.7


## Anti aliasing and the shadow atlas for one viewport. The root viewport is done in
## _ready; every SubViewport is caught by _on_node_added.
func apply_viewport(vp: Viewport) -> void:
	if vp == null or not is_instance_valid(vp):
		return
	if allows("msaa"):
		vp.msaa_3d = Viewport.MSAA_4X
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	else:
		vp.msaa_3d = Viewport.MSAA_DISABLED
		# FXAA on medium: one cheap pass, and the bots' bevelled edges are the whole
		# silhouette read at phone size.
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if _tier == TIER_MEDIUM \
			else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_debanding = allows("debanding")
	vp.use_taa = false
	var sub := vp as SubViewport
	if sub != null:
		sub.positional_shadow_atlas_size = int(POSITIONAL_ATLAS.get(_tier, 1024))


func _on_node_added(node: Node) -> void:
	var sub := node as SubViewport
	if sub != null:
		apply_viewport(sub)
		return
	# MARKED SIMULATOR FIX (docs/simulator-rendering.md).
	var container := node as SubViewportContainer
	if container != null:
		apply_subviewport_container(container)


## Shrink the whole SubViewport on the low tier. `stretch_shrink` is a Control feature, not
## a renderer one, so it works on every backend and needs nothing from the scene's owner.
func apply_subviewport_container(container: SubViewportContainer) -> void:
	if container == null or not is_instance_valid(container):
		return
	if not container.stretch:
		return
	container.stretch_shrink = int(STAGE_SHRINK.get(_tier, 1))


# ---------------------------------------------------------------- helpers

## The autoload when there is one, otherwise a private instance. A `--script` test run
## and a tool script have no autoloads, and neither does a scene opened on its own in the
## editor, so nothing may assume the global exists.
static func resolve(context: Node) -> Node:
	if context != null and context.is_inside_tree():
		var found := context.get_tree().root.get_node_or_null("GraphicsQuality")
		if found != null:
			return found
	var fallback: Node = (load("res://render/graphics_quality.gd") as GDScript).new()
	fallback.call("detect")
	return fallback


func _current_rendering_method() -> String:
	# OS.get_current_rendering_method() is the one that reflects a --rendering-method
	# override; the project setting still reads whatever was saved (see
	# docs/simulator-rendering.md, where exactly that trap cost a day).
	var value := ""
	if OS.has_method("get_current_rendering_method"):
		value = str(OS.call("get_current_rendering_method"))
	if value == "":
		value = str(ProjectSettings.get_setting("rendering/renderer/rendering_method", ""))
	return value


## "metal", "vulkan", "opengl3" or "dummy". This is the one that tells a headless run
## apart from a real one, because the METHOD name survives into a headless process.
func _current_rendering_driver() -> String:
	if OS.has_method("get_current_rendering_driver_name"):
		return str(OS.call("get_current_rendering_driver_name"))
	return ""


func _safe_model_name() -> String:
	var value := ""
	if OS.has_method("get_model_name"):
		value = str(OS.call("get_model_name"))
	return value


func _safe_adapter_name() -> String:
	# Dummy and headless drivers answer this with an error rather than a string.
	if not ClassDB.class_exists("RenderingServer"):
		return ""
	var adapter := ""
	if RenderingServer.has_method("get_video_adapter_name"):
		adapter = str(RenderingServer.get_video_adapter_name())
	return adapter


## "iPhone14,2" and up is A15 and up. A name that is not an iPhone (the simulator answers
## "GenericDevice", the Mac answers its own model) is treated as modern: the tier has
## already been decided by the rendering method by the time this is asked.
func _iphone_is_modern(model: String) -> bool:
	if not model.begins_with("iPhone"):
		return true
	var digits := ""
	for i in range(6, model.length()):
		var c := model[i]
		if c >= "0" and c <= "9":
			digits += c
		else:
			break
	if digits == "":
		return true
	return int(digits) >= MIN_IPHONE_MAJOR_FOR_HIGH


func _cmdline_tier() -> String:
	if not OS.has_feature("pc"):
		return ""
	for raw in OS.get_cmdline_user_args():
		var arg := str(raw)
		if arg.begins_with(ARG_TIER):
			var value := arg.substr(ARG_TIER.length())
			if value in TIERS:
				return value
	return ""
