class_name MenuPyro extends Node3D
## One pyro jet for the menus in the arena (docs/wave-c-menus-notes.md): a launcher on the
## floor you can see, and a flame JET out of its nozzle when fired. Never loops: it fires
## on arrival at a screen and on a win (MenuVenue decides when), and is dark otherwise.
##
## Why not the kit's flame column: in the A2 mockup that column (big soft quads rising
## slowly, round at the top) read as a glowing human figure standing in the gate. A jet is
## the opposite shape: pencil thin at the nozzle, fast, streaked along its travel, and only
## widening and breaking up at the top where the fire slows, with smoke rolling off after.
##
## Presentation only: GPU particles, one light, no simulation state.

const LAUNCHER := "res://arena/kit/models/pyro_launcher.glb"
## The nozzle sits this high above the launcher's base (pyro_launcher.glb is 0.62 m tall).
const NOZZLE_Y := 0.62
const JET_S := 0.85
const WIN_GAP_S := 0.7
## Flame particles per tier.
const FLAME := {"high": 150, "medium": 110, "low": 0}
const SMOKE := {"high": 18, "medium": 10, "low": 0}
const COL_FLASH := Color(1.0, 0.62, 0.3)

var tier := "high"
## False when the launcher is already standing there (the gate's own pedestals).
var with_launcher := true
## "flame" (a fire jet) or "co2" (a white CO2 cryo jet: vapour, no fire, no flash). The owner's
## call; MenuVenue.JET_STYLE picks it.
var style := "flame"
var _flame: GPUParticles3D = null
var _smoke: GPUParticles3D = null
var _sparks: GPUParticles3D = null
var _flash: OmniLight3D = null
var _t := -1.0
var _second_at := -1.0
var _fired := 0


func build() -> void:
	if with_launcher and ResourceLoader.exists(LAUNCHER):
		var scene := load(LAUNCHER) as PackedScene
		if scene != null:
			var l := scene.instantiate() as Node3D
			l.name = "Launcher"
			add_child(l)
	_flame = _flame_jet()
	_flame.position = Vector3(0.0, NOZZLE_Y, 0.0)
	add_child(_flame)
	_smoke = _smoke_cap()
	_smoke.position = Vector3(0.0, NOZZLE_Y + 2.6, 0.0)
	add_child(_smoke)
	_sparks = VenueFx.spark_fountain(tier, 3.2)
	_sparks.position = Vector3(0.0, NOZZLE_Y, 0.0)
	add_child(_sparks)
	_flash = OmniLight3D.new()
	_flash.name = "Flash"
	_flash.light_color = COL_FLASH
	_flash.light_energy = 0.0
	_flash.omni_range = 7.0
	_flash.shadow_enabled = false
	_flash.visible = false
	_flash.position = Vector3(0.0, NOZZLE_Y + 1.4, 0.0)
	add_child(_flash)
	set_process(true)


## Fire the jet now. `win` also throws the gerb and fires a second jet a beat later.
func fire(win: bool = false) -> void:
	if _flame == null:
		return
	_t = 0.0
	_fired += 1
	_burst()
	if win:
		_second_at = WIN_GAP_S
		_sparks.restart()
		_sparks.emitting = true
	else:
		_second_at = -1.0


func stop() -> void:
	_t = -1.0
	_second_at = -1.0
	if _flame != null:
		_flame.emitting = false
	if _flash != null:
		_flash.visible = false


func fired_count() -> int:
	return _fired


## True while the jet is burning (tests: it must never burn on its own).
func burning() -> bool:
	return _t >= 0.0 and _t < JET_S + 0.1


func _burst() -> void:
	_flame.restart()
	_flame.emitting = true
	if _smoke.amount > 0:
		_smoke.restart()
		_smoke.emitting = true
	_flash.visible = tier != "low" and style != "co2"


func _process(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	if _second_at > 0.0 and _t >= _second_at:
		_second_at = -1.0
		_t = 0.0
		_burst()
	if _t >= JET_S and _flame.emitting:
		_flame.emitting = false
	# The flash: up in 0.05 s, held while the jet burns, gone 0.5 s after.
	var k := 0.0
	if _t < 0.05:
		k = _t / 0.05
	elif _t < JET_S:
		k = 0.85 + 0.15 * sin(_t * 47.0)
	else:
		k = maxf(0.0, 1.0 - (_t - JET_S) / 0.5)
	_flash.light_energy = 5.0 * k
	if k <= 0.0 and _t > JET_S:
		_flash.visible = false
		_t = -1.0


## The jet: streaks leaving the nozzle at 13 m/s inside a 2 degree cone, dragged down so
## the top slows, widens and turns to smoke colour, a column about 3.5 m tall.
func _flame_jet() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Jet"
	p.amount = int(FLAME.get(tier, 0))
	p.lifetime = 0.5
	p.one_shot = false
	p.explosiveness = 0.0
	p.randomness = 0.3
	p.emitting = false
	p.local_coords = false
	p.fixed_fps = 0
	p.visibility_aabb = AABB(Vector3(-2, -0.5, -2), Vector3(4, 6, 4))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.035
	m.direction = Vector3(0, 1, 0)
	m.spread = 2.0
	m.initial_velocity_min = 15.0
	m.initial_velocity_max = 18.0
	m.gravity = Vector3(0, 2.0, 0)
	m.damping_min = 8.0
	m.damping_max = 11.0
	m.particle_flag_align_y = true
	m.scale_min = 0.8
	m.scale_max = 1.15
	# Thin at the nozzle, fat and breaking up at the top.
	m.scale_curve = _curve([Vector2(0.0, 0.22), Vector2(0.3, 0.45), Vector2(0.75, 0.9), Vector2(1.0, 1.25)])
	m.color_ramp = _ramp([
		[0.0, Color(1.0, 0.96, 0.82, 1.0)], [0.18, Color(1.0, 0.78, 0.35, 0.95)],
		[0.5, Color(1.0, 0.45, 0.1, 0.6)], [0.75, Color(0.45, 0.12, 0.03, 0.25)],
		[1.0, Color(0.1, 0.04, 0.02, 0.0)]])
	if style == "co2":
		# Vapour: dense white at the nozzle, billowing and thinning as it slows at the top.
		p.lifetime = 0.8
		m.damping_min = 10.0
		m.damping_max = 14.0
		m.gravity = Vector3(0, -0.6, 0)
		m.scale_curve = _curve([Vector2(0.0, 0.3), Vector2(0.3, 0.7), Vector2(0.7, 1.4), Vector2(1.0, 2.0)])
		m.color_ramp = _ramp([
			[0.0, Color(0.95, 0.97, 1.0, 0.85)], [0.35, Color(0.9, 0.93, 0.97, 0.6)],
			[0.75, Color(0.8, 0.84, 0.9, 0.25)], [1.0, Color(0.75, 0.8, 0.86, 0.0)]])
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 0.6
	m.turbulence_noise_scale = 3.0
	m.turbulence_influence_min = 0.02
	m.turbulence_influence_max = 0.12
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.36, 1.1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = load(VenueFx.FLAME_TEX)
	mat.albedo_color = Color(1.6, 1.6, 1.6, 1.0)
	if style == "co2":
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		mat.albedo_texture = load(VenueFx.DUST_TEX)
		mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	mat.vertex_color_use_as_albedo = true
	# Y along the particle's travel (align_y), turned about it to face the lens: streaks.
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	q.material = mat
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## The smoke the jet leaves at its top: a few dark puffs that roll up and thin out.
func _smoke_cap() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Smoke"
	p.amount = int(SMOKE.get(tier, 0))
	p.lifetime = 2.4
	p.one_shot = true
	p.explosiveness = 0.55
	p.emitting = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 6, 6))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.3
	m.direction = Vector3(0, 1, 0)
	m.spread = 25.0
	m.initial_velocity_min = 0.5
	m.initial_velocity_max = 1.1
	m.gravity = Vector3(0, 0.25, 0)
	m.damping_min = 0.4
	m.damping_max = 0.8
	m.scale_min = 1.0
	m.scale_max = 1.6
	m.scale_curve = _curve([Vector2(0.0, 0.5), Vector2(1.0, 1.8)])
	m.color_ramp = _ramp([[0.0, Color(0.2, 0.18, 0.17, 0.0)], [0.15, Color(0.16, 0.15, 0.15, 0.3)],
		[1.0, Color(0.08, 0.08, 0.09, 0.0)]])
	m.angle_min = -180.0
	m.angle_max = 180.0
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(1.1, 1.1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = load(VenueFx.DUST_TEX)
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	q.material = mat
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	c.max_value = 2.0
	for pt in points:
		c.add_point(pt)
	var t := CurveTexture.new()
	t.curve = c
	return t


static func _ramp(stops: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in stops:
		offs.append(float(s[0]))
		cols.append(s[1])
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	return t
