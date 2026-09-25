extends SceneTree
## Headless test for the rendering layer (agent G1, docs/graphics-bar.md).
##
##   Godot --headless --path Arena --script tests/render_test.gd
##
## Exit code 0 = PASS. Everything here runs on the DUMMY driver, which reports itself as
## the low tier, so the test also proves the thing that matters most about this layer:
## nothing in it may require a GPU feature to exist in order to load.
##
## Deliberately duck typed. It never names `DamageDecals` or any other agent's
## `class_name`, because a test that names a global class fails to PARSE while that
## class's file is mid-edit, and a test that fails to parse exits 0 with zero checks run
## and the suite reports a pass (docs/stage4-stage-notes.md, known weakness 9).

const QUALITY_SCRIPT := "res://render/graphics_quality.gd"
const DECALS_SCRIPT := "res://render/damage_decals.gd"
const ARENA_ENV := "res://render/arena_env.tres"
const STAGE_ENV := "res://render/stage_env.tres"
const DEFAULT_ENV := "res://render/default_env.tres"
const YARD_SCENE := "res://arena/yard.tscn"
const STAGE_SCENE := "res://workshop/stage.tscn"
const STAGE_SCENE_SCRIPT := "res://workshop/stage.gd"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_quality()
	_test_environments()
	_test_anti_sparkle()
	_test_decals()
	await _test_scenes()
	_finish()


# ---------------------------------------------------------------- GraphicsQuality

func _test_quality() -> void:
	var script: GDScript = load(QUALITY_SCRIPT) as GDScript
	_check(script != null, "graphics_quality.gd loads")
	if script == null:
		return
	var quality: Node = script.new()
	root.add_child(quality)
	var tier := str(quality.call("detect"))
	_check(tier in script.TIERS, "the autoload picks a known tier (got '%s')" % tier)
	_check(str(quality.call("tier")) == tier, "tier() reads back what detect() chose")
	# The dummy driver is not Forward+ and is not the mobile renderer.
	_check(tier == script.TIER_LOW,
		"the headless dummy driver is the low tier (got '%s')" % tier)

	var described: Dictionary = quality.call("describe") as Dictionary
	_check(described.has("tier") and described.has("rendering_method") and described.has("os"),
		"describe() carries the tier, the rendering method and the OS")

	# Every tier answers every feature, and each one only ever allows less than the one
	# above it. That ordering IS the performance guard.
	var features := ["ssao", "ssr", "glow", "volumetric_fog", "decals", "reflection_probe",
		"soft_shadows", "msaa", "shadows", "fog"]
	var monotonic := true
	for feature in features:
		quality.call("set_tier", script.TIER_HIGH)
		var high := bool(quality.call("allows", feature))
		quality.call("set_tier", script.TIER_MEDIUM)
		var medium := bool(quality.call("allows", feature))
		quality.call("set_tier", script.TIER_LOW)
		var low := bool(quality.call("allows", feature))
		if (medium and not high) or (low and not medium):
			monotonic = false
	_check(monotonic, "no tier allows a feature the tier above it forbids")

	quality.call("set_tier", script.TIER_HIGH)
	_check(bool(quality.call("allows", "ssao")) and bool(quality.call("allows", "volumetric_fog"))
		and bool(quality.call("allows", "decals")),
		"high allows SSAO, volumetric fog and decals")
	quality.call("set_tier", script.TIER_MEDIUM)
	_check(bool(quality.call("allows", "glow")) and not bool(quality.call("allows", "ssao"))
		and not bool(quality.call("allows", "volumetric_fog")),
		"medium keeps glow and drops SSAO and volumetrics")
	quality.call("set_tier", script.TIER_LOW)
	_check(not bool(quality.call("allows", "glow")) and not bool(quality.call("allows", "decals")),
		"low drops glow, and decals are unsupported there")
	# The simulator fix (docs/simulator-rendering.md): the low tier draws on a CPU
	# rasterizer, so it buys neither shadows nor fog. It is chosen ONLY for
	# gl_compatibility and headless, so no device build can land on it.
	_check(not bool(quality.call("allows", "shadows")) and not bool(quality.call("allows", "fog")),
		"low drops shadows and fog too")
	quality.call("set_tier", script.TIER_MEDIUM)
	_check(bool(quality.call("allows", "shadows")) and bool(quality.call("allows", "fog")),
		"medium, the phone fallback, keeps both")
	quality.call("set_tier", script.TIER_LOW)

	# apply() on a full fat environment: every switch comes down, nothing errors.
	var env := Environment.new()
	env.ssao_enabled = true
	env.ssr_enabled = true
	env.glow_enabled = true
	env.volumetric_fog_enabled = true
	env.fog_enabled = true
	env.tonemap_exposure = 1.25
	var key := DirectionalLight3D.new()
	key.shadow_enabled = true
	var spot := SpotLight3D.new()
	spot.shadow_enabled = true
	spot.light_volumetric_fog_energy = 2.2
	quality.call("apply", env, [key, spot])
	_check(not env.ssao_enabled and not env.ssr_enabled and not env.glow_enabled
		and not env.volumetric_fog_enabled,
		"apply() on the low tier turns SSAO, SSR, glow and volumetrics off")
	# The low tier is the iOS Simulator's software rasterizer (or headless), where fog and
	# shadows are pure fragment cost on a CPU: docs/simulator-rendering.md. Medium is the
	# tier that keeps plain distance fog, and that is asserted below.
	_check(not env.fog_enabled, "apply() drops even plain distance fog on the low tier")
	_check(env.tonemap_exposure <= 1.0,
		"apply() pulls the exposure back to neutral on the low tier (%.2f)" % env.tonemap_exposure)
	_check(not key.shadow_enabled, "the low tier casts no shadows at all")
	_check(is_equal_approx(spot.light_volumetric_fog_energy, 0.0),
		"a light's volumetric energy is zeroed where there is no volumetric fog")

	# Medium is the phone fallback, not the simulator, so it keeps shadows and fog. This
	# is the assertion that stops a simulator fix leaking onto a device.
	quality.call("set_tier", script.TIER_MEDIUM)
	var medium_env := Environment.new()
	medium_env.fog_enabled = true
	medium_env.glow_enabled = true
	medium_env.volumetric_fog_enabled = true
	var medium_key := DirectionalLight3D.new()
	medium_key.shadow_enabled = true
	quality.call("apply", medium_env, [medium_key])
	_check(medium_env.fog_enabled and medium_env.glow_enabled,
		"the medium tier keeps distance fog and glow")
	_check(not medium_env.volumetric_fog_enabled,
		"and still has no volumetric fog")
	_check(medium_key.shadow_enabled
		and medium_key.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL,
		"the medium tier key light casts a one cascade shadow")
	_check(is_equal_approx(medium_key.light_angular_distance, 0.0),
		"with a hard edge: the soft shadow is the high tier's")
	quality.call("set_tier", script.TIER_LOW)

	quality.call("set_tier", script.TIER_HIGH)
	var high_env := Environment.new()
	high_env.ssao_enabled = true
	high_env.ssr_enabled = true
	high_env.glow_enabled = true
	high_env.volumetric_fog_enabled = true
	quality.call("apply", high_env, [key])
	_check(high_env.ssao_enabled and high_env.ssr_enabled and high_env.glow_enabled
		and high_env.volumetric_fog_enabled,
		"apply() on the high tier leaves an authored environment alone")
	# ONE cascade on the high tier as well: two put a visible seam across the Yard floor
	# in the shot frames, and a 10 m room does not need the range they buy. What high
	# still gets over the lower tiers is the SOFT shadow, asserted next.
	_check(key.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL,
		"the high tier key light is one cascade, so there is no split seam on the floor")
	_check(key.light_angular_distance > 0.0,
		"the high tier key light has a soft shadow (angular distance %.2f)"
			% key.light_angular_distance)
	_check(is_equal_approx(key.directional_shadow_max_distance, script.SHADOW_MAX_DISTANCE),
		"the shadow distance covers the whole arena")

	# apply() must never turn a feature ON that the environment did not ask for.
	var plain := Environment.new()
	quality.call("apply", plain, [])
	_check(not plain.ssao_enabled and not plain.glow_enabled,
		"apply() only ever turns features down, never up")

	# Viewports: MSAA on high, FXAA on medium, neither on low.
	var vp := SubViewport.new()
	root.add_child(vp)
	quality.call("set_tier", script.TIER_HIGH)
	quality.call("apply_viewport", vp)
	_check(vp.msaa_3d == Viewport.MSAA_4X, "the high tier viewport is 4x MSAA")
	quality.call("set_tier", script.TIER_MEDIUM)
	quality.call("apply_viewport", vp)
	_check(vp.msaa_3d == Viewport.MSAA_DISABLED
		and vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_FXAA,
		"the medium tier viewport swaps MSAA for FXAA")
	quality.call("set_tier", script.TIER_LOW)
	quality.call("apply_viewport", vp)
	_check(vp.msaa_3d == Viewport.MSAA_DISABLED
		and vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED,
		"the low tier viewport has no anti aliasing at all")
	vp.queue_free()

	# resolve() must answer with something usable whether or not the autoload exists.
	var resolved: Node = script.call("resolve", quality)
	_check(resolved != null and resolved.has_method("allows"),
		"resolve() answers with a usable instance when there is no autoload")
	quality.queue_free()


# ---------------------------------------------------------------- the resources

func _test_environments() -> void:
	var arena := _load_env(ARENA_ENV, "arena_env")
	if arena != null:
		_check(arena.tonemap_mode == Environment.TONE_MAPPER_ACES, "the arena tonemaps with ACES")
		_check(arena.background_mode == Environment.BG_COLOR, "the arena has no sky, just a colour")
		_check(arena.glow_enabled and arena.glow_hdr_threshold >= 0.9,
			"arena glow is on with an HDR threshold, so only emissives bloom (%.2f)"
				% arena.glow_hdr_threshold)
		_check(arena.ssao_enabled, "the arena has SSAO authored on")
		_check(arena.ssr_enabled, "the arena has SSR authored on for the floor")
		_check(arena.fog_enabled and arena.fog_density < 0.02,
			"the arena's distance fog is subtle (%.4f)" % arena.fog_density)
		_check(not arena.sdfgi_enabled and not arena.ssil_enabled,
			"the arena buys no SDFGI and no SSIL: neither is in the phone budget")

	var stage := _load_env(STAGE_ENV, "stage_env")
	if stage != null:
		# Wave A (docs/look/reference-study.md 3.4): AgX holds the livery's hue in the rim
		# highlights where ACES skewed orange to yellow (the GT7 lesson). Exposure is locked.
		_check(stage.tonemap_mode == Environment.TONE_MAPPER_AGX, "the stage tonemaps with AgX")
		_check(stage.background_color.r + stage.background_color.g + stage.background_color.b < 0.03,
			"the stage background is black " + str(stage.background_color))
		_check(stage.ambient_light_energy <= 0.0501,
			"the stage ambient is 0.05 or lower (%.3f)" % stage.ambient_light_energy)
		_check(stage.glow_enabled, "the stage blooms its beams and lamp heads")
		_check(stage.volumetric_fog_enabled,
			"the stage authors real volumetric fog for the high tier")
		_check(stage.volumetric_fog_anisotropy > 0.2,
			"the stage fog scatters forward, which is what makes a beam a shaft (%.2f)"
				% stage.volumetric_fog_anisotropy)
		# The first high tier shoot drew NO fog at all because this, the FogVolume
		# densities and the lights' volumetric energy were each far too low and three
		# small numbers multiplied to nothing. This is the floor under the first of them.
		# Wave A: 0.02 (the study's figure), down from 0.05: the new rig puts four times the
		# light into the room, and at 0.05 the low face-off lens looked through a milky wall.
		_check(stage.volumetric_fog_density >= 0.015,
			"the stage fog is dense enough to see (%.3f)" % stage.volumetric_fog_density)
		# Wave A reverses this: the floor is now steel plate with roughness breakup, and the
		# machine's reflection in it is half of the M2 target frame. GraphicsQuality still
		# strips SSR below the high tier, and it is first in the drop order.
		_check(stage.ssr_enabled and stage.ssr_max_steps <= 32,
			"the stage floor reflects the machine with SSR at 32 steps or fewer")
		_check(stage.glow_hdr_threshold >= 1.05,
			"only emissives and speculars bloom, never lit paint (%.2f)" % stage.glow_hdr_threshold)

	var fallback := _load_env(DEFAULT_ENV, "default_env")
	if fallback != null:
		_check(not fallback.glow_enabled and not fallback.ssao_enabled and not fallback.ssr_enabled,
			"the default environment is a cheap safety net, not a look")
	_check(str(ProjectSettings.get_setting("rendering/environment/defaults/default_environment", ""))
		== DEFAULT_ENV, "project.godot points default_environment at the resource")
	_check(str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")) == "forward_plus",
		"the project renders with Forward+")
	_check(str(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile", ""))
		== "forward_plus", "the phone renders with Forward+ too (one key to flip back)")
	# Specular aliasing: the parts' normal maps sparkle on metallic surfaces at a phone
	# screen footprint, and this is half the fix (the other half is roughness-from-normal
	# in the texture imports, asserted below).
	_check(bool(ProjectSettings.get_setting(
		"rendering/anti_aliasing/screen_space_roughness_limiter/enabled", false)),
		"the screen space roughness limiter is on")
	_test_sharpness()


## SHARPNESS (wave V, agent V4, docs/wave-v-v4-notes.md). The owner played on the phone:
## "not high res enough". Four project keys decide how much of a texture reaches a pixel,
## and every one of them has a silent default that is softer than what is wanted here.
func _test_sharpness() -> void:
	# MSAA 4x is the high tier's edge anti aliasing; GraphicsQuality re-applies it per
	# SubViewport because a SubViewport inherits none of this.
	_check(int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", 0)) == 2,
		"MSAA is 4x on the high tier")
	_check(int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/screen_space_aa", 1)) == 0,
		"and no screen space AA is stacked on top of it, which would only blur the result")
	# 0=1x, 1=2x, 2=4x, 3=8x, 4=16x. Raised from 4x on the measurement in the notes: the
	# arena floor is a 2048 plate tiled 4x under a 50 degree camera.
	_check(int(ProjectSettings.get_setting(
		"rendering/textures/default_filters/anisotropic_filtering_level", 0)) >= 3,
		"anisotropic filtering is at least 8x for the floor plate and the chevron strip")
	_check(not bool(ProjectSettings.get_setting(
		"rendering/textures/default_filters/use_nearest_mipmap_filter", false)),
		"mipmaps are sampled linearly, not nearest, so a mip change is not a visible step")
	var bias := float(ProjectSettings.get_setting(
		"rendering/textures/default_filters/texture_mipmap_bias", 0.0))
	_check(bias < 0.0 and bias >= -0.6,
		"the mipmap bias sharpens the minified case (%.2f), and not so far that it shimmers"
			% bias)
	# The 3D buffer is the viewport, one to one. FSR and any scale below 1.0 are a
	# resolution loss no texture work can win back, so both are pinned rather than left to
	# Godot's defaults where a stray editor click could change them.
	_check(int(ProjectSettings.get_setting("rendering/scaling_3d/mode", 0)) == 0,
		"3D scaling is plain bilinear, with no FSR pass in the way")
	_check(is_equal_approx(float(ProjectSettings.get_setting(
		"rendering/scaling_3d/scale", 1.0)), 1.0),
		"and it renders at native scale (scaling_3d/scale is 1.0)")
	_check(bool(ProjectSettings.get_setting(
		"rendering/textures/vram_compression/import_etc2_astc", false)),
		"import_etc2_astc is on: without it the iOS export ships every texture uncompressed")

	# The fight is drawn at the phone's own pixels. `window/stretch/mode` was
	# "canvas_items" with a 2412 x 1112 base, which laid every Control out in stretched
	# canvas units; the fight lives in a SubViewportContainer whose child is sized from its
	# CONTROL size, so the whole 3D image was rendered at 2417 x 1112 and bilinearly blown
	# up to 2622 x 1206, throwing away 15 % of the pixels on every frame (measured in
	# docs/wave-v-v4-notes.md section 1, fixed by wave P agent H). The key is asserted here
	# because it is a RENDERING setting, whatever else it moves.
	_check(String(ProjectSettings.get_setting("display/window/stretch/mode", "")) == "disabled",
		"the window stretch is disabled, so a Control's rect is the device pixel rect")
	var script: GDScript = load(QUALITY_SCRIPT) as GDScript
	var probe := SubViewport.new()
	probe.size = Vector2i(2622, 1206)
	root.add_child(probe)
	var native: float = script.viewport_oversample(probe)
	_check(is_equal_approx(native, 1.0),
		"and an iPhone 17's viewport, posed the way the phone poses it, reads %.4f: the "
			% native + "fight is drawn at every one of its pixels")
	# The probe still has to be able to SEE a blow up, or the 1.0000 above proves nothing.
	probe.size_2d_override = Vector2i(2417, 1112)
	probe.size_2d_override_stretch = true
	var measured: float = script.viewport_oversample(probe)
	_check(absf(measured - 1.0846) < 0.002,
		"and the probe still reads the old canvas_items stretch as a %.4f blow up"
			% measured)
	probe.queue_free()


## The anti sparkle settings live in G2's material and import files. They are asserted
## here because they are a RENDERING fix and this is the suite that would catch someone
## regenerating those files from a script that does not know about them.
func _test_anti_sparkle() -> void:
	for name in ["brushed_steel", "scratched_titanium", "arena_plate"]:
		var path := "res://assets/materials/%s.tres" % name
		if not ResourceLoader.exists(path):
			continue
		var mat: StandardMaterial3D = load(path) as StandardMaterial3D
		_check(mat != null, path + " loads")
		if mat == null:
			continue
		_check(mat.normal_scale <= 0.5,
			"%s pulls its normal map down to %.2f, so metal stops sparkling"
				% [name, mat.normal_scale])
		_check(mat.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC,
			"%s samples anisotropically with mipmaps" % name)
	var import_path := "res://assets/textures/brushed_steel/brushed_steel_roughness.png.import"
	var text := ""
	if FileAccess.file_exists(import_path):
		text = FileAccess.get_file_as_string(import_path)
	_check(text.find("roughness/mode=1") >= 0 and text.find("src_normal=\"res://") >= 0,
		"the roughness maps are imported with roughness-from-normal, so busy surfaces "
		+ "get rougher in the mips instead of sparkling")


func _load_env(path: String, expected_name: String) -> Environment:
	_check(ResourceLoader.exists(path), path + " exists")
	if not ResourceLoader.exists(path):
		return null
	var env: Environment = load(path) as Environment
	_check(env != null, path + " loads as an Environment")
	if env != null:
		_check(env.resource_name == expected_name,
			"%s is named '%s'" % [path, expected_name])
	return env


# ---------------------------------------------------------------- decals

func _test_decals() -> void:
	var script: GDScript = load(DECALS_SCRIPT) as GDScript
	_check(script != null, "damage_decals.gd loads")
	if script == null:
		return
	var decals: Node3D = script.new() as Node3D
	_check(decals != null, "DamageDecals is a Node3D")
	if decals == null:
		return
	root.add_child(decals)

	# The API exists on every tier, including the one where it cannot draw.
	_check(decals.has_method("add_scratch") and decals.has_method("add_scorch")
		and decals.has_method("clear"), "the decal API is add_scratch, add_scorch, clear")
	decals.call("set_enabled", false)
	_check(decals.call("add_scratch", Vector3.ZERO, Vector3.UP, 0.2) == null,
		"a disabled tier no-ops add_scratch instead of failing")
	_check(int(decals.call("active_count")) == 0, "a disabled tier places nothing")

	decals.call("set_enabled", true)
	var first: Object = decals.call("add_scratch", Vector3(1.0, 0.2, 0.0), Vector3.UP, 0.25)
	_check(first != null, "add_scratch places a Decal")
	_check(int(decals.call("active_count")) == 1, "one mark is one decal")
	var scorch: Object = decals.call("add_scorch", Vector3(0.0, 0.0, 1.0), 0.4)
	_check(scorch != null and scorch != first, "add_scorch places a second, different Decal")

	# A scratch on a wall projects into the wall, not down through it: the decal's own
	# +Y is the surface normal it was given.
	var wall: Node3D = decals.call("add_scratch", Vector3(0.0, 0.5, 0.0), Vector3.RIGHT, 0.2) as Node3D
	_check(wall != null and wall.transform.basis.y.dot(Vector3.RIGHT) > 0.95,
		"a scratch aims its projection down the surface normal")

	var capacity := int(decals.call("capacity"))
	_check(capacity == 48, "the pool is 48 decals (got %d)" % capacity)
	for i in capacity + 20:
		decals.call("add_scorch", Vector3(float(i) * 0.1, 0.0, 0.0), 0.3)
	_check(int(decals.call("active_count")) == capacity,
		"the pool caps at %d however many marks arrive (got %d)"
			% [capacity, int(decals.call("active_count"))])
	_check(decals.get_child_count() == capacity,
		"and it never makes more than %d Decal nodes (got %d)"
			% [capacity, decals.get_child_count()])
	var live: Array = decals.call("decals") as Array
	# Eviction RECYCLES the node: the first scratch's Decal is still in the pool, but it
	# is now carrying one of the scorches, which is what "the oldest is evicted" means
	# when nothing is ever allocated twice.
	_check(first is Decal and (first as Decal).albedo_mix > 0.9,
		"the oldest mark's node was recycled for a new one, not left holding the old mark")
	_check(live.size() > 0 and live[live.size() - 1] != first,
		"and the newest mark is not the one that was just evicted")
	var oldest: Object = live[0] if live.size() > 0 else null
	_check(oldest != null and (oldest as Decal).modulate.a < 0.2,
		"the oldest mark has already faded out before it is recycled")

	decals.call("clear")
	_check(int(decals.call("active_count")) == 0, "clear() takes every mark off the floor")
	decals.queue_free()


# ---------------------------------------------------------------- the scenes

func _test_scenes() -> void:
	var yard_scene: PackedScene = load(YARD_SCENE) as PackedScene
	_check(yard_scene != null, "yard.tscn loads")
	if yard_scene != null:
		var yard: Node3D = yard_scene.instantiate() as Node3D
		root.add_child(yard)
		await _frames(2)
		var world_env := yard.get_node_or_null("WorldEnvironment") as WorldEnvironment
		_check(world_env != null and world_env.environment != null,
			"the Yard carries a WorldEnvironment")
		if world_env != null and world_env.environment != null:
			_check(world_env.environment.resource_name == "arena_env",
				"the Yard is bound to arena_env (got '%s')" % world_env.environment.resource_name)
			_check(world_env.environment != load(ARENA_ENV),
				"and to a COPY of it, so a tier change cannot write back to the resource")
		var key := yard.get_node_or_null("KeyLight") as DirectionalLight3D
		# The key IS the shadow caster on medium and high. On the low tier, which is the
		# simulator's software rasterizer, GraphicsQuality has just switched its shadow
		# off, and this run is the low tier.
		_check(key != null, "the Yard has a key light")
		_check(key != null and not key.shadow_enabled,
			"and it casts no shadow on the low tier")
		_check(yard.get_node_or_null("FillLight") != null,
			"a cold fill keeps the shadowed faces off the tyres' value")
		var probe := yard.get_node_or_null("FloorProbe") as ReflectionProbe
		_check(probe != null, "a reflection probe sits over the arena floor")
		_check(probe == null or probe.update_mode == ReflectionProbe.UPDATE_ONCE,
			"the probe bakes once, so it costs one render and then nothing")
		_check(probe == null or not probe.visible,
			"and it is off on the low tier, where the renderer ignores probes anyway")
		yard.queue_free()

	var stage_scene: PackedScene = load(STAGE_SCENE) as PackedScene
	_check(stage_scene != null, "stage.tscn loads")
	if stage_scene != null:
		var stage: Node3D = stage_scene.instantiate() as Node3D
		root.add_child(stage)
		await _frames(2)
		var world_env := stage.get_node_or_null("Environment") as WorldEnvironment
		_check(world_env != null and world_env.environment != null,
			"the stage carries a WorldEnvironment")
		if world_env != null and world_env.environment != null:
			var env := world_env.environment
			_check(env.resource_name == "stage_env",
				"the stage is bound to stage_env (got '%s')" % env.resource_name)
			_check(env.ambient_light_energy <= 0.0501,
				"the stage's ambient stays at 0.05 (%.3f)" % env.ambient_light_energy)
			_check(not env.volumetric_fog_enabled,
				"volumetric fog is off on the low tier, where the renderer has none")
		_check(bool(stage.call("fake_haze")),
			"so the stage keeps the additive cones and the billboard dry ice")
		var fog_floor := stage.get_node_or_null("FogFloor") as FogVolume
		var fog_rim := stage.get_node_or_null("FogRim") as FogVolume
		_check(fog_floor != null and fog_rim != null,
			"the real fog volumes are built on every tier, so the tree never changes shape")
		_check(fog_floor == null or not fog_floor.visible,
			"and they are hidden while the fake haze is doing the work")
		var beam_visible := true
		for node_variant in _find_all(stage, "MeshInstance3D"):
			var mesh_node := node_variant as MeshInstance3D
			if mesh_node.material_override is ShaderMaterial and not mesh_node.visible:
				beam_visible = false
		_check(beam_visible, "the three beam cones are visible on the low tier")
		# The low tier frame is the one the owner has accepted, so the cones and the
		# billboards keep drawing UNDER the real fog on the high tier rather than being
		# swapped out for it. A zero gain here would be the high tier going backwards.
		var stage_script: GDScript = load(STAGE_SCENE_SCRIPT) as GDScript
		var constants: Dictionary = stage_script.get_script_constant_map() \
			if stage_script != null else {}
		_check(float(constants.get("FAKE_HAZE_GAIN_WITH_FOG", 0.0)) > 0.0,
			"the fake haze still draws under the real fog, so high can never be worse than low")
		stage.queue_free()


# ---------------------------------------------------------------- harness

func _find_all(node: Node, type_name: String) -> Array:
	var out: Array = []
	if node.is_class(type_name):
		out.append(node)
	for child in node.get_children():
		out.append_array(_find_all(child, type_name))
	return out


func _frames(count: int) -> void:
	for _i in count:
		await process_frame


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("PASS  ", label)
	else:
		_failures += 1
		print("FAIL  ", label)


func _finish() -> void:
	print("")
	print("render_test: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
