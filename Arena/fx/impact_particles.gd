class_name FightParticles extends Node3D
## Pooled one-shot GPUParticles3D for impacts, plus the continuous spike emitter.
## Presentation only; built in code so there is no scene to keep in sync.
##
## Budget (mobile renderer, docs/stage3-spec.md §11 "keep draw cost tiny"): 8 spark
## emitters of 24 particles and 4 dust emitters of 14, all one-shot and mostly idle,
## plus one 12 particle continuous emitter for risen spikes. Worst case on screen is
## a few hundred unlit additive quads for a third of a second.

const SPARK_EMITTERS := 8
const SPARK_AMOUNT := 24
const SPARK_LIFETIME := 0.3        # brief: sparks are a 0.3 s event, not a fire
const DUST_EMITTERS := 4
const DUST_AMOUNT := 14
const DUST_LIFETIME := 0.75
const SPIKE_AMOUNT := 12

var _sparks: Array[GPUParticles3D] = []
var _dust: Array[GPUParticles3D] = []
var _spike: GPUParticles3D = null
var _next_spark: int = 0
var _next_dust: int = 0


func _ready() -> void:
	for i in SPARK_EMITTERS:
		var p := _make_sparks("Sparks%d" % i, SPARK_AMOUNT, SPARK_LIFETIME, true)
		add_child(p)
		_sparks.append(p)
	for i in DUST_EMITTERS:
		var p := _make_dust("Dust%d" % i)
		add_child(p)
		_dust.append(p)
	_spike = _make_sparks("SpikeSparks", SPIKE_AMOUNT, 0.45, false)
	_spike.one_shot = false
	_spike.emitting = false
	_spike.explosiveness = 0.0
	add_child(_spike)


## True when there is a real renderer behind us. Headless builds construct the nodes
## but never simulate a particle, so the tests must not assert on particle output.
static func gpu_available() -> bool:
	return DisplayServer.get_name() != "headless"


## One impact. severity 0..1 scales both the count and the size of the fan.
func burst_sparks(at: Vector3, severity: float) -> void:
	var p := _sparks[_next_spark]
	_next_spark = (_next_spark + 1) % SPARK_EMITTERS
	var s := clampf(severity, 0.0, 1.0)
	p.global_position = at
	p.amount_ratio = clampf(0.3 + s * 0.7, 0.3, 1.0)
	# Size the fan through the emitter's own process material, not the node scale:
	# with local_coords off, a scaled node distorts where the particles are emitted.
	var m := p.process_material as ParticleProcessMaterial
	if m != null:
		m.initial_velocity_min = 1.4 + s * 1.6
		m.initial_velocity_max = 3.4 + s * 4.6
		m.scale_min = 0.45 + s * 0.35
		m.scale_max = 0.85 + s * 0.75
	p.restart()
	p.emitting = true


## A part came off: grey dust, so the eye reads structural loss, not scrap.
func puff_dust(at: Vector3) -> void:
	var p := _dust[_next_dust]
	_next_dust = (_next_dust + 1) % DUST_EMITTERS
	p.global_position = at
	p.restart()
	p.emitting = true


## The spike patch is up: a small continuous fizz so the hazard reads as live.
func set_spike_sparks(on: bool, at: Vector3) -> void:
	if _spike == null:
		return
	if on:
		_spike.global_position = at
	_spike.emitting = on


func _make_sparks(node_name: String, amount: int, lifetime: float, one_shot: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = node_name
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = one_shot
	p.explosiveness = 1.0
	p.emitting = false
	p.local_coords = false
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH

	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.04
	m.direction = Vector3(0.0, 1.0, 0.0)
	m.spread = 75.0
	m.flatness = 0.0
	m.initial_velocity_min = 2.0
	m.initial_velocity_max = 6.5
	m.gravity = Vector3(0.0, -11.0, 0.0)
	m.damping_min = 1.5
	m.damping_max = 4.0
	m.scale_min = 0.5
	m.scale_max = 1.2
	m.color_ramp = _spark_ramp()
	p.process_material = m

	var quad := QuadMesh.new()
	quad.size = Vector2(0.012, 0.05)   # a streak, not a dot
	p.draw_pass_1 = quad
	p.material_override = _particle_material(true)
	return p


func _make_dust(node_name: String) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = node_name
	p.amount = DUST_AMOUNT
	p.lifetime = DUST_LIFETIME
	p.one_shot = true
	p.explosiveness = 0.85
	p.emitting = false
	p.local_coords = false

	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.09
	m.direction = Vector3(0.0, 1.0, 0.0)
	m.spread = 90.0
	m.initial_velocity_min = 0.3
	m.initial_velocity_max = 1.3
	m.gravity = Vector3(0.0, -1.2, 0.0)
	m.damping_min = 1.0
	m.damping_max = 2.5
	m.scale_min = 0.8
	m.scale_max = 1.8
	m.scale_over_velocity_min = 0.0
	m.color_ramp = _dust_ramp()
	p.process_material = m

	var quad := QuadMesh.new()
	quad.size = Vector2(0.13, 0.13)
	p.draw_pass_1 = quad
	p.material_override = _particle_material(false)
	return p


static func _particle_material(additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return m


## White hot core, orange body, gone. Sparks are warm but they last 0.3 s, so they
## never compete with the gold bolts for "the one saturated warm in the frame".
static func _spark_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(1.0, 0.97, 0.88, 1.0))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(0.82, 0.32, 0.10, 0.0))
	g.add_point(0.28, Color(1.0, 0.70, 0.28, 1.0))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func _dust_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(0.58, 0.60, 0.63, 0.0))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(0.48, 0.49, 0.52, 0.0))
	g.add_point(0.15, Color(0.62, 0.64, 0.67, 0.5))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t
