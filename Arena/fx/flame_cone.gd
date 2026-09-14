class_name FlameCone extends Node3D
## The flamethrower's fire, for the weapon landing in W2 (brief-v3.md §5.3, and
## GRUDGE in §8). Built now so the weapon is a gameplay job when it arrives and not
## a gameplay job plus an art job.
##
## Presentation only. It never reports where the fire is; the weapon's damage volume
## is the physics code's business, and this node is what the player sees.
##
##     var flame := FlameCone.new()
##     weapon_muzzle.add_child(flame)     # a socket on the bot
##     flame.set_length(1.6)              # metres of reach
##     flame.set_active(true)             # hold to burn
##
## AXIS: fire goes along local +X, the bot convention from docs/graphics-bar.md
## (+X forward, +Y up, +Z right), NOT Godot's default -Z. Parent it to a socket that
## already faces the way the weapon points and it is correct with no rotation.
##
## Three layers, because one particle system on its own reads as sparks:
##   1. the cone itself, additive particles on a soft authored billboard
##   2. a broad faint additive glow standing in for heat haze. A screen space
##      distortion needs a screen texture read per pixel, which is exactly the kind
##      of full screen bandwidth a phone does not have going spare, so the haze is
##      a wobbling glow rather than a refraction. It is the cheapest lie in the file.
##   3. an OmniLight3D that flickers, so the fire lights the arena and the victim
##      rather than sitting in front of them like a decal

const PARTICLE_COUNT := 48
const LIFETIME := 0.45
const SPREAD_DEG := 13.0
const DEFAULT_LENGTH := 1.6
const MIN_LENGTH := 0.2
const MAX_LENGTH := 6.0

## Flicker: two incommensurate sines, so the light never visibly repeats.
const FLICKER_HZ_A := 11.0
const FLICKER_HZ_B := 4.3
const FLICKER_DEPTH := 0.28
const LIGHT_ENERGY := 2.6
const HAZE_ALPHA := 0.16

var _particles: GPUParticles3D = null
var _haze: MeshInstance3D = null
var _haze_material: StandardMaterial3D = null
var _light: OmniLight3D = null
var _length: float = DEFAULT_LENGTH
var _active: bool = false
var _t: float = 0.0
var _phase: float = 0.0

## Set true by an owner that drives step() itself (the headless test does), so the
## flicker is deterministic instead of riding the real frame clock.
var external_clock: bool = false


func _ready() -> void:
	_phase = randf() * TAU
	_build()
	set_length(_length)
	set_active(false)


func _process(delta: float) -> void:
	if external_clock:
		return
	step(delta)


## --- public API --------------------------------------------------------------

## Hold to burn. Turning off stops emission but lets the particles already in the
## air finish their 0.45 s, so releasing the trigger does not delete the fire.
func set_active(on: bool) -> void:
	_active = on
	if _particles != null:
		_particles.emitting = on
	if _light != null:
		_light.visible = on
	if _haze != null:
		_haze.visible = on


func is_active() -> bool:
	return _active


## Reach in metres. Everything scales off this one number: particle speed (so a
## particle just reaches the tip inside its lifetime), the width of the cone, where
## the haze sits and how far the light throws.
func set_length(metres: float) -> void:
	_length = clampf(metres, MIN_LENGTH, MAX_LENGTH)
	if _particles != null:
		var m := _particles.process_material as ParticleProcessMaterial
		if m != null:
			var speed := _length / LIFETIME
			m.initial_velocity_min = speed * 0.72
			m.initial_velocity_max = speed * 1.12
			m.scale_min = _length * 0.13
			m.scale_max = _length * 0.30
			m.emission_sphere_radius = maxf(0.02, _length * 0.035)
	if _haze != null:
		var quad := _haze.mesh as QuadMesh
		if quad != null:
			quad.size = Vector2(_length * 1.15, _length * 0.72)
		_haze.position = Vector3(_length * 0.5, 0.0, 0.0)
	if _light != null:
		_light.position = Vector3(_length * 0.35, 0.0, 0.0)
		_light.omni_range = _length * 1.5


func length() -> float:
	return _length


## Advance the flicker. Called by _process unless `external_clock` is set.
func step(delta: float) -> void:
	if delta <= 0.0:
		return
	_t += delta
	if not _active:
		return
	var f := 0.5 * (sin((_t * FLICKER_HZ_A + _phase) * TAU) + sin((_t * FLICKER_HZ_B - _phase) * TAU) * 0.7)
	var k := 1.0 + FLICKER_DEPTH * f
	if _light != null:
		_light.light_energy = FxMaterials.energy(LIGHT_ENERGY) * k
	if _haze_material != null:
		_haze_material.albedo_color.a = HAZE_ALPHA * (0.75 + 0.45 * f)
	if _haze != null:
		# A slow breathe on the glow, so the haze is never the same shape twice.
		var s := 1.0 + 0.06 * f
		_haze.scale = Vector3(s, s * 1.04, 1.0)


## --- build -------------------------------------------------------------------

func _build() -> void:
	_particles = GPUParticles3D.new()
	_particles.name = "Cone"
	_particles.amount = PARTICLE_COUNT
	_particles.lifetime = LIFETIME
	_particles.one_shot = false
	_particles.explosiveness = 0.0
	_particles.emitting = false
	_particles.local_coords = false     # fire is left behind when the bot turns
	_particles.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	_particles.process_material = _cone_process()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)       # the process material's scale sizes it
	_particles.draw_pass_1 = quad
	_particles.material_override = FxMaterials.additive(
		FxMaterials.texture("flame_soft.png"), Color.WHITE, FxMaterials.FLAME_ENERGY, false)
	var pm := _particles.material_override as StandardMaterial3D
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.billboard_keep_scale = true
	add_child(_particles)

	_haze_material = FxMaterials.additive(
		FxMaterials.texture("flame_soft.png"), FxMaterials.FLAME_BODY, 1.0, true)
	_haze_material.albedo_color.a = HAZE_ALPHA
	var hq := QuadMesh.new()
	hq.size = Vector2(1.0, 1.0)
	_haze = MeshInstance3D.new()
	_haze.name = "Haze"
	_haze.mesh = hq
	_haze.material_override = _haze_material
	_haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_haze.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_haze)

	_light = OmniLight3D.new()
	_light.name = "Flicker"
	_light.light_color = FxMaterials.FLAME_BODY
	_light.light_energy = FxMaterials.energy(LIGHT_ENERGY)
	_light.light_specular = 0.4
	# No shadow map: a flamethrower that costs a shadow pass every frame is the
	# single most expensive thing this file could do, and the fire is a fill light.
	_light.shadow_enabled = false
	add_child(_light)


static func _cone_process() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.06
	m.direction = Vector3(1.0, 0.0, 0.0)     # bot +X forward, see the class note
	m.spread = SPREAD_DEG
	m.flatness = 0.0
	m.initial_velocity_min = 2.4
	m.initial_velocity_max = 3.8
	# Hot gas rises and slows: the tip of a real flame curls up and dies.
	m.gravity = Vector3(0.0, 1.1, 0.0)
	m.damping_min = 0.8
	m.damping_max = 2.2
	m.angle_min = -180.0
	m.angle_max = 180.0
	m.angular_velocity_min = -90.0
	m.angular_velocity_max = 90.0
	m.scale_min = 0.2
	m.scale_max = 0.45
	m.scale_curve = _scale_curve()
	m.color_ramp = _flame_ramp()
	m.alpha_curve = _alpha_curve()
	# Turbulence is what stops the cone being a smooth spray: it curls the body of
	# the flame and is most of why this reads as fire rather than as a cone of dots.
	#
	# It is switched OFF headless. Not for looks (headless renders nothing) but
	# because the turbulence variant of the particle shader is a separate shader,
	# and Godot's DUMMY renderer does not release it at shutdown: a headless run
	# that also builds any other additive billboard material ends with
	# "1 RID allocations of type DummyShader were leaked at exit". Harmless, and
	# invisible on a real renderer, but a red ERROR line at the end of the test
	# suite is a thing future agents would waste an afternoon on.
	var live := FightParticles.gpu_available()
	m.turbulence_enabled = live
	m.turbulence_noise_strength = 0.24
	m.turbulence_noise_scale = 2.4
	m.turbulence_noise_speed = Vector3(1.4, 0.5, 0.0)
	m.collision_mode = ParticleProcessMaterial.COLLISION_DISABLED
	return m


## Small and tight at the muzzle, broad at the tip: this curve IS the cone shape.
static func _scale_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.35))
	c.add_point(Vector2(0.35, 1.0))
	c.add_point(Vector2(1.0, 1.35))
	var t := CurveTexture.new()
	t.curve = c
	return t


## White hot at the muzzle through orange to a dull red that gives up. Alpha is
## driven separately so the colour can stay saturated while the particle dies.
static func _flame_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, FxMaterials.FLAME_CORE)
	g.set_offset(1, 1.0)
	g.set_color(1, Color(0.35, 0.07, 0.02, 1.0))
	g.add_point(0.3, FxMaterials.FLAME_BODY)
	g.add_point(0.65, Color(0.85, 0.22, 0.05, 1.0))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func _alpha_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.0))     # fades in over the first few centimetres
	c.add_point(Vector2(0.12, 1.0))
	c.add_point(Vector2(0.55, 0.8))
	c.add_point(Vector2(1.0, 0.0))
	var t := CurveTexture.new()
	t.curve = c
	return t


## --- introspection, used by Arena/tests/fx_test.gd -------------------------

func particles() -> GPUParticles3D:
	return _particles


func light() -> OmniLight3D:
	return _light


func haze() -> MeshInstance3D:
	return _haze
