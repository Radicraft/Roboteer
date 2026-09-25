extends SceneTree
## Headless test for the ANIMATED menu/workshop stage (agent S, 2026-09-14).
##
##   Godot --headless --path Arena --script tests/stage_animation_test.gd
##
## Exit code 0 = PASS. It covers the three things that cannot be seen without a window:
## that both stage shaders actually PARSE (the headless ShaderLanguage pass is real, a
## broken one reports 0 uniforms), that the particle budget is what each GraphicsQuality
## tier is supposed to get, and that the light choreography moves and stays inside its
## bounds over 600 and 3600 stepped frames.
##
## The still frame rules from workshop_test.gd are deliberately re-asserted here for the
## emitters that did not exist when that test was written (the tendrils and the puff).

const GROUND_FOG_SHADER := "res://render/stage/ground_fog.gdshader"
const BEAM_SHADER := "res://render/stage/beam.gdshader"
const SOFT_SPRITE_SHADER := "res://render/stage/soft_sprite.gdshader"
const STAGE_SHADERS := [GROUND_FOG_SHADER, BEAM_SHADER, SOFT_SPRITE_SHADER]
## Things the Forward+ renderer has and gl_compatibility (the simulator, OpenGL ES 3) does
## not, or that cost a texture fetch the sprite shaders must not need. See the header of
## soft_sprite.gdshader: the beam dust drew as opaque tan rectangles in the simulator
## because its ONLY source of alpha was a runtime generated gradient texture.
## 2026-09-14, second simulator sighting: the tan rectangles were STILL there after the
## texture was removed, as whole quads with no falloff at all. The shader was billboarding
## itself by writing MODELVIEW_MATRIX, which the compatibility renderer does not apply to
## particles, and its per particle data came from INSTANCE_CUSTOM. Both are banned here and
## the billboard is done engine side by GPUParticles3D.transform_align instead.
const RENDERER_TRAPS := ["SCREEN_TEXTURE", "DEPTH_TEXTURE", "NORMAL_ROUGHNESS_TEXTURE",
	"hint_screen_texture", "hint_depth_texture", "hint_normal_roughness_texture",
	"fwidth(", "dFdx(", "dFdy(", "texture(",
	"MODELVIEW_MATRIX", "INV_VIEW_MATRIX", "INSTANCE_CUSTOM"]
const DT := 1.0 / 60.0

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	_test_shaders()
	await _test_particles()
	await _test_choreography()
	_finish()


# ---------------------------------------------------------------- shaders

func _test_shaders() -> void:
	# A shader whose GLSL does not compile comes back with an EMPTY uniform list here, so
	# a non empty list is proof the whole file parsed, not just that it loaded as a file.
	var fog: Shader = load(GROUND_FOG_SHADER) as Shader
	_check(fog != null, "ground_fog.gdshader loads")
	if fog != null:
		_check(fog.get_mode() == Shader.MODE_SPATIAL, "ground_fog is a spatial shader")
		var names := _uniform_names(fog)
		_check(names.size() > 0, "ground_fog parses (%d uniforms)" % names.size())
		for wanted in ["base_colour", "alpha_scale", "strength", "softness", "stretch",
				"bite", "noise_scale", "scroll", "floor_lift", "use_particle_alpha"]:
			_check(names.has(wanted), "ground_fog declares uniform %s" % wanted)
		_check(fog.code.contains("TIME"), "ground_fog's alpha is driven by TIME, so the layer moves")

	var beam: Shader = load(BEAM_SHADER) as Shader
	_check(beam != null, "beam.gdshader loads")
	if beam != null:
		_check(beam.get_mode() == Shader.MODE_SPATIAL, "beam is a spatial shader")
		var names := _uniform_names(beam)
		_check(names.size() > 0, "beam parses (%d uniforms)" % names.size())
		for wanted in ["tint", "strength", "half_length", "shimmer", "seed"]:
			_check(names.has(wanted), "beam declares uniform %s" % wanted)
		_check(beam.code.contains("TIME"), "the beam shimmer is driven by TIME")

	var sprite: Shader = load(SOFT_SPRITE_SHADER) as Shader
	_check(sprite != null, "soft_sprite.gdshader loads")
	if sprite != null:
		_check(_uniform_names(sprite).size() > 0,
			"soft_sprite parses (%d uniforms)" % _uniform_names(sprite).size())

	# The compatibility renderer bug, asserted so it cannot come back: every sprite the
	# stage draws must write ALPHA itself, blend additively by render_mode, and never reach
	# for a texture or a Forward+ only built in.
	for path_variant in STAGE_SHADERS:
		var path: String = str(path_variant)
		var shader: Shader = load(path) as Shader
		if shader == null:
			continue
		# Comment lines are stripped first: these headers NAME the banned built ins.
		var code := _without_comments(shader.code)
		var short: String = str(path).get_file()
		# THE rule: the emitted colour is multiplied by the falloff, so a renderer that
		# ignores ALPHA under blend_add still cannot draw a hard edged solid quad.
		var albedo := _assignment(code, "ALBEDO")
		var alpha := _assignment(code, "ALPHA")
		_check(albedo.contains("fall"),
			"%s multiplies its emitted colour by the falloff (ALBEDO =%s)" % [short, albedo])
		_check(alpha.contains("fall"),
			"%s writes the falloff into ALPHA as well (ALPHA =%s)" % [short, alpha])
		_check(albedo.contains("strength") or albedo.contains("amount"),
			"%s also scales its emitted colour by the authored alpha" % short)
		_check(code.contains("ALPHA ="), "%s writes ALPHA itself, never leaving it at 1.0" % short)
		_check(code.contains("blend_add"), "%s sets its blend mode in render_mode" % short)
		_check(code.contains("unshaded"), "%s is unshaded, so no light path can differ" % short)
		var trap := ""
		for candidate in RENDERER_TRAPS:
			if code.contains(candidate):
				trap = candidate
		_check(trap == "",
			"%s uses nothing gl_compatibility lacks and fetches no texture (%s)"
			% [short, "clean" if trap == "" else trap])


## A shader's code with every `//` comment line removed, so a scan for a banned built in
## cannot trip over a comment that warns about it.
func _without_comments(code: String) -> String:
	var out: Array = []
	for raw in code.split("\n"):
		var line: String = str(raw)
		if line.strip_edges().begins_with("//"):
			continue
		out.append(line)
	return "\n".join(out)


## The right hand side of the last `NAME =` assignment in a shader, so a check can read
## what the fragment actually emits rather than trusting a comment.
func _assignment(code: String, name: String) -> String:
	var out := ""
	for raw in code.split("\n"):
		var line: String = str(raw).strip_edges()
		if line.begins_with(name + " ="):
			out = line.substr(name.length() + 1)
	return out


func _uniform_names(shader: Shader) -> Array:
	var out: Array = []
	for entry_variant in shader.get_shader_uniform_list():
		var entry: Dictionary = entry_variant
		out.append(str(entry.get("name", "")))
	return out


# ---------------------------------------------------------------- particles per tier

func _test_particles() -> void:
	# The high tier is the budget that matters: a few hundred billboards, no more.
	var expected := {"high": 280, "medium": 167, "low": 91}
	var ring_names := ["DryIce0", "DryIce1", "DryIce2", "DryIce3", "DryIce4"]
	var extra_names := ["DryIceTendril0", "DryIceTendril1", "DryIcePuff", "Dust"]
	for tier in ["high", "medium", "low"]:
		var stage := WorkshopStage.new()
		stage.name = "Stage_" + tier
		stage.force_quality_tier(tier)
		root.add_child(stage)
		await _frames(2)
		_check(stage.quality_tier() == tier, "a stage can be built as the %s tier (got %s)"
			% [tier, stage.quality_tier()])

		for wanted in ring_names + extra_names:
			_check(stage.get_node_or_null(wanted) != null, "%s: %s exists" % [tier, wanted])

		var budget := stage.particle_budget()
		_check(budget == int(expected[tier]),
			"%s tier emits %d billboards (expected %d)" % [tier, budget, int(expected[tier])])
		if tier == "high":
			_check(budget <= 320, "the high tier stays inside a few hundred particles (%d)" % budget)

		# Every dry ice emitter still obeys the calibration the owner accepted, including
		# the two tendril emitters and the puff, which workshop_test.gd predates.
		var low := true
		var off_centre := true
		var small := true
		var dim := true
		var curls := true
		var stable_seed := true
		var animated := true
		var counted := 0
		for child in stage.get_children():
			var emitter := child as GPUParticles3D
			if emitter == null or not String(emitter.name).begins_with("DryIce"):
				continue
			counted += 1
			if emitter.position.y > 0.2:
				low = false
			if Vector2(emitter.position.x, emitter.position.z).length() < 1.2:
				off_centre = false
			var proc := emitter.process_material as ParticleProcessMaterial
			if proc == null:
				continue
			if proc.scale_max > 1.2:
				small = false
			if proc.color.a > 0.08:
				dim = false
			if not proc.turbulence_enabled:
				curls = false
			if absf(proc.angular_velocity_min) > 0.001 or absf(proc.angular_velocity_max) > 0.001:
				stable_seed = false
			if (emitter.material_override as ShaderMaterial) == null:
				animated = false
		_check(counted == 8, "%s: 8 dry ice emitters, 5 ring + 2 tendril + 1 puff (got %d)"
			% [tier, counted])
		_check(low, "%s: every dry ice emitter hugs the floor below 0.2 m" % tier)
		_check(off_centre, "%s: no dry ice is emitted over the stage centre" % tier)
		_check(small, "%s: every dry ice quad is under 1.2 m" % tier)
		_check(dim, "%s: every dry ice alpha is 0.08 or lower" % tier)
		_check(curls, "%s: every dry ice emitter has turbulence on, so it curls" % tier)
		_check(stable_seed,
			"%s: no dry ice particle spins, so the shader's sprite seed is stable" % tier)
		_check(animated, "%s: every dry ice emitter draws with the animated fog shader" % tier)

		# Nothing the stage emits may depend on a runtime generated texture for its alpha,
		# and every emitter must be billboarded by the PARTICLE SYSTEM rather than by its
		# shader, which is the half of the fix the compatibility renderer actually needed.
		var flat := ""
		for child in stage.get_children():
			var billboard := child as GPUParticles3D
			if billboard != null and billboard.transform_align != GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD:
				flat = String(billboard.name)
		_check(flat == "", "%s: every emitter is billboarded engine side (%s)"
			% [tier, "clean" if flat == "" else flat])
		var textured := ""
		for child in stage.get_children():
			var emitter := child as GPUParticles3D
			if emitter == null:
				continue
			var standard := emitter.material_override as StandardMaterial3D
			if standard != null and standard.albedo_texture != null:
				textured = String(emitter.name)
			if (emitter.material_override as ShaderMaterial) == null:
				textured = String(emitter.name)
		_check(textured == "",
			"%s: every emitter, dust included, draws with a texture free shader (%s)"
			% [tier, "clean" if textured == "" else textured])

		var puff := stage.get_node_or_null("DryIcePuff") as GPUParticles3D
		_check(puff != null and puff.one_shot, "%s: the puff is a one shot burst" % tier)
		_check(puff != null and not puff.emitting, "%s: the puff is silent until it is fired" % tier)

		stage.queue_free()
		await _frames(1)


# ---------------------------------------------------------------- choreography

func _test_choreography() -> void:
	var stage := WorkshopStage.new()
	stage.name = "StageAnim"
	stage.force_quality_tier("high")
	root.add_child(stage)
	await _frames(2)

	# Nothing here is gated on a bot, a fight or a camera mode: the stage animates as the
	# bare menu backdrop, which is exactly how the main menu shows it before a build loads.
	_check(stage.bot() == null, "the stage animates with no bot on it (the menu backdrop)")
	_check(stage.is_active(), "the stage starts active and processing")

	var key := stage.get_node_or_null("KeyLight") as SpotLight3D
	var rim := stage.get_node_or_null("RimLight") as SpotLight3D
	var mover0 := stage.get_node_or_null("Movers/Mover0/Spot") as SpotLight3D
	_check(key != null and rim != null and mover0 != null, "the key, the rim and mover 0 are there")
	if key == null or rim == null or mover0 == null:
		stage.queue_free()
		return

	var key_before := key.light_energy
	var key_colour_before := key.light_color
	var rim_before := rim.global_position
	var mover_basis_before := mover0.global_transform.basis
	var turn_before := stage.turntable_angle_deg()

	# 600 frames, 10 seconds.
	var key_min := 99.0
	var key_max := 0.0
	var warm_sum_max := 0.0
	var two_warms := 0
	var offset_max := 0.0
	var rim_max := 0.0
	for i in 600:
		stage._process(DT)
		key_min = minf(key_min, key.light_energy)
		key_max = maxf(key_max, key.light_energy)
		offset_max = maxf(offset_max, absf(stage.sweep_offset()))
		rim_max = maxf(rim_max, absf(stage.rim_swing_deg()))
		var sum := 0.0
		var hot := 0
		for value in stage.mover_warmth():
			sum += float(value)
			if float(value) > 0.25:
				hot += 1
		warm_sum_max = maxf(warm_sum_max, sum)
		if hot > 1:
			two_warms += 1

	_check(stage.sweep_crossings() >= 1 and stage.sweep_crossings() <= 2,
		"a beam crosses the bot once every 6 to 10 s (%d crossings in 10 s)" % stage.sweep_crossings())
	_check(offset_max <= 1.0001, "the sweep never aims further than SWEEP_REACH off the bot (%.3f)"
		% offset_max)
	var aims: Array = stage.aim_offsets()
	var settled := true
	for value in aims:
		if absf(float(value)) > 1.0001:
			settled = false
	_check(settled, "no mover is ever aimed past SWEEP_REACH " + str(aims))
	_check(stage.aim_step_max() < 0.04,
		"no mover's aim ever jumps: the biggest single frame step is %.4f of the sweep"
		% stage.aim_step_max())
	_check(key_max > key_min, "the key light breathes (%.3f to %.3f)" % [key_min, key_max])
	_check(key_min >= WorkshopStage.KEY_ENERGY * 0.95 and key_max <= WorkshopStage.KEY_ENERGY * 1.05,
		"the key breathes by a few percent and no more (%.3f to %.3f around %.1f)"
		% [key_min, key_max, WorkshopStage.KEY_ENERGY])
	_check(key_min >= 5.0 and key_max <= 9.0,
		"the key stays inside the 5 to 9 band workshop_test.gd asserts")
	_check(not key.light_color.is_equal_approx(key_colour_before),
		"the key's colour temperature drifts " + str(key.light_color))
	# Wave A: the key is a 4300 K warm white now (docs/look/reference-study.md 3.1). It may
	# drift a little warmer or more neutral, but never towards the amber mover's
	# saturation: blue stays above 0.55 and green above 0.72.
	_check(key.light_color.b >= 0.55 and key.light_color.g >= 0.72,
		"the key stays a warm WHITE and never drifts to amber (g %.3f, b %.3f)"
		% [key.light_color.g, key.light_color.b])
	_check(rim_max > 5.0 and rim_max <= WorkshopStage.RIM_SWING_DEG + 0.01,
		"the rim rolls round the bot, inside its %.0f degree swing (reached %.1f)"
		% [WorkshopStage.RIM_SWING_DEG, rim_max])
	_check(rim.global_position.distance_to(rim_before) > 0.05,
		"the rim light actually moved (%.3f m)" % rim.global_position.distance_to(rim_before))
	_check(absf(rim.global_position.y - WorkshopStage.RIM_AT.y) < 0.001,
		"the rim stays at its mounted height")
	_check(rim.global_position.z < 0.0, "the rim stays BEHIND the bot and never flares the lens")
	_check(not mover0.global_transform.basis.is_equal_approx(mover_basis_before),
		"the movers are aiming somewhere new")
	_check(warm_sum_max <= 1.0001, "the three movers never hold more than one amber between them (%.3f)"
		% warm_sum_max)
	_check(two_warms == 0, "two movers are never warm at the same time (%d frames)" % two_warms)
	_check(absf(wrapf(stage.turntable_angle_deg() - turn_before, -180.0, 180.0)) > 1.0,
		"the turntable is still turning under all of it")

	# 3600 more frames, a minute, which is long enough for the amber to change hands and
	# for several puffs.
	var puffs_before := stage.puff_count()
	var warmth_start: Array = stage.mover_warmth()
	var handed_over := false
	for i in 3600:
		stage._process(DT)
		var now: Array = stage.mover_warmth()
		if float(now[0]) < 0.5:
			handed_over = true
		var sum := 0.0
		var hot := 0
		for value in now:
			sum += float(value)
			if float(value) > 0.25:
				hot += 1
		if sum > 1.0001 or hot > 1:
			two_warms += 1
	_check(float(warmth_start[0]) > 0.9, "mover 0, the upper left, starts with the amber")
	_check(handed_over, "the amber changes hands inside a minute")
	_check(two_warms == 0, "and it is still never in two places at once")
	_check(stage.puff_count() - puffs_before >= 4,
		"denser puffs keep firing (%d in a minute)" % (stage.puff_count() - puffs_before))
	_check(stage.sweep_crossings() >= 7 and stage.sweep_crossings() <= 10,
		"70 seconds of stage produced %d beam crossings" % stage.sweep_crossings())

	# Colour: the beam cone and the lamp head must agree with the light.
	var beam_tint: Variant = null
	var beam := stage.get_node_or_null("Movers/Mover0/Beam") as MeshInstance3D
	if beam != null:
		beam_tint = (beam.material_override as ShaderMaterial).get_shader_parameter("tint")
	_check(beam_tint is Color and (beam_tint as Color).is_equal_approx(mover0.light_color),
		"the beam cone is tinted with its mover's live colour")
	var head := stage.get_node_or_null("Movers/Mover0/Head") as MeshInstance3D
	var head_mat := head.material_override as StandardMaterial3D if head != null else null
	_check(head_mat != null and head_mat.emission.is_equal_approx(mover0.light_color),
		"the lamp head glows the same colour as its beam")

	# Frozen when the stage is switched off, moving again when it comes back.
	stage.set_active(false)
	var frozen_key := key.light_energy
	var frozen_crossings := stage.sweep_crossings()
	for i in 120:
		stage._process(DT)
	_check(is_equal_approx(key.light_energy, frozen_key) and stage.sweep_crossings() == frozen_crossings,
		"set_active(false) stops the choreography dead")
	stage.set_active(true)
	for i in 120:
		stage._process(DT)
	_check(not is_equal_approx(key.light_energy, frozen_key),
		"set_active(true) starts it again")
	stage.queue_free()


# ---------------------------------------------------------------- helpers

func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS  ", label)
	else:
		_failures += 1
		printerr("FAIL  ", label)
		print("FAIL  ", label)


func _finish() -> void:
	print("")
	if _failures == 0:
		print("PASS  stage animation: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  stage animation: %d checks, %d failures" % [_checks, _failures])
		quit(1)
