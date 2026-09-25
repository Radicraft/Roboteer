class_name FightParticles extends Node3D
## Pooled one-shot GPUParticles3D for impacts, plus the continuous spike emitter,
## the shrapnel chips and the flash pool.
##
## Presentation only; built in code so there is no scene to keep in sync.
##
## Budget (docs/graphics-bar.md, mobile at 60 fps): 8 spark emitters of 24 particles
## and 4 dust emitters of 14, all one-shot and mostly idle, one 12 particle
## continuous emitter for risen spikes, 32 chip instances in one MultiMesh and 6
## flash quads in another. Worst case on screen is a few hundred additive quads (or
## ribbon trails) for a quarter of a second, 32 lit 8 triangle chips for 1.2 s, and
## two extra draw calls that are usually empty.
##
## G4 (docs/graphics-fx-notes.md) upgraded the LOOK: Godot 4 particle trails so a
## spark is a streak of light rather than a dash, a hot white core flash when a part
## detaches, the dust on a soft authored billboard instead of a hard quad, and grey
## shrapnel chips using G3's spark_chip mesh. The API FightFx calls is unchanged
## except for two additions, burst_detach() and step().

const SPARK_EMITTERS := 8
## Doubled after the first desktop frames: 24 particles spread over a 75 degree fan
## is a handful of dashes at the fight framing, not a burst.
const SPARK_AMOUNT := 48
## 0.25 s (docs/graphics-bar.md). Sparks are an event, not a fire; the art direction
## rule is that the only persistent saturated warm in the frame is the gold of the
## bolts, and a spark that lingers breaks it.
const SPARK_LIFETIME := 0.25
## How much of that lifetime the streak behind a spark is worth. Long enough to read
## as a moving light, short enough that eight emitters of ribbon do not cost more
## than the bots.
const SPARK_TRAIL_S := 0.12
const DUST_EMITTERS := 4
const DUST_AMOUNT := 20
const DUST_LIFETIME := 0.85
const SPIKE_AMOUNT := 12

## White-out pass (gauntlet 2026-09-25, docs/qa/weapons-gauntlet.md): the detach core was
## 0.55 m x up to 1.7 x a 2.4 grow = 2.2 m of energy 7 white over a 0.8 m machine, and every
## hit-tier blow (feel sparks 0.55) popped a 4.2 energy light of 1.6 m reach that lit both
## hulls' specular white. Now: a core that starts at 0.3 m and is never drawn past 0.6 m,
## and light only for heavy blows, shorter and dimmer, so the contact stays readable.
const FLASH_POOL := 6
const FLASH_SIZE := 0.30
const FLASH_MAX_SIZE := 0.60
const FLASH_LIFE_S := 0.16
## Above this severity a hit also throws real light (FxLightPool). Below it, the
## flash quad alone is enough and a light would just be noise. 0.8: the feel tiers pass
## their `sparks` (hit 0.55, heavy 0.85, smash 1.0), so only heavy and smash blows light up.
const LIGHT_POP_SEVERITY := 0.8
const LIGHT_POP_ENERGY := 2.4
const LIGHT_POP_RANGE := 0.9
## Spark size at full severity: was 1.6 + 1.4 x severity (3.0 x the streak at a smash).
const SPARK_SCALE_MIN := Vector2(0.8, 0.3)    # base + per severity
const SPARK_SCALE_MAX := Vector2(1.2, 0.6)
## Chips per detach, before severity. Deliberately few: the brief wants detached
## PARTS to carry the structural story, and a blizzard of chips would dilute it.
const CHIP_MIN := 3
const CHIP_MAX := 9

var _sparks: Array[GPUParticles3D] = []
var _dust: Array[GPUParticles3D] = []
var _spike: GPUParticles3D = null
var _chips: DebrisChips = null
var _flash: FxFlashPool = null
var _lights: FxLightPool = null
var _next_spark: int = 0
var _next_dust: int = 0
var _trails_supported: bool = false


func _ready() -> void:
	# Particle trails need a RenderingDevice. The GL Compatibility tier (the
	# Simulator, and the fallback on older phones) has none, and silently draws
	# nothing for a RibbonTrailMesh draw pass, so that tier gets streak quads.
	_trails_supported = FxMaterials.hdr_available()
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

	_chips = DebrisChips.new()
	_chips.name = "Chips"
	add_child(_chips)

	_flash = FxFlashPool.new()
	_flash.name = "CoreFlash"
	add_child(_flash)
	_flash.configure(FLASH_POOL, FLASH_SIZE, Color(1.0, 0.98, 0.94), FLASH_LIFE_S,
		FxMaterials.CORE_ENERGY, AABB(Vector3(-8.0, -2.0, -8.0), Vector3(16.0, 10.0, 16.0)),
		FLASH_MAX_SIZE)

	_lights = FxLightPool.new()
	_lights.name = "ImpactLights"
	add_child(_lights)

	set_process(false)   # FightFx steps us, like every other node in Arena/fx


## True when there is a real renderer behind us. Headless builds construct the nodes
## but never simulate a particle, so the tests must not assert on particle output.
static func gpu_available() -> bool:
	return DisplayServer.get_name() != "headless"


## Presentation step for the parts of this tree that are not GPU particles: the
## chips and the flash quads run on the CPU, on FightFx's clock, so a headless test
## can advance them at a fixed delta.
func step(delta: float) -> void:
	if _chips != null:
		_chips.step(delta)
	if _flash != null:
		_flash.step(delta)
	if _lights != null:
		_lights.step(delta)


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
		m.scale_min = SPARK_SCALE_MIN.x + s * SPARK_SCALE_MIN.y
		m.scale_max = SPARK_SCALE_MAX.x + s * SPARK_SCALE_MAX.y
	p.restart()
	p.emitting = true
	# A severe hit throws light. One frame of the floor and both bots lighting up is
	# what separates an impact that reads as an event from one that reads as a decal.
	if _lights != null and s >= LIGHT_POP_SEVERITY:
		_lights.pop(at, LIGHT_POP_ENERGY * (0.6 + 0.4 * s), LIGHT_POP_RANGE)


## A part came off. The moment needs to be bigger than a hit: a hot white core at
## the tear, grey dust so the eye reads structural loss rather than scrap, and a few
## torn chips. The chips are grey and unlit-by-emission on purpose (brief §6).
func burst_detach(at: Vector3, severity: float) -> void:
	var s := clampf(severity, 0.0, 1.0)
	puff_dust(at)
	if _flash != null:
		_flash.flash(at, 0.8 + s * 0.9)
	if _chips != null:
		_chips.burst(at, CHIP_MIN + int(round(s * float(CHIP_MAX - CHIP_MIN))), s)
	if _lights != null:
		_lights.pop(at, LIGHT_POP_ENERGY * 1.3, LIGHT_POP_RANGE * 1.25)


## A part came off: grey dust, so the eye reads structural loss, not scrap.
func puff_dust(at: Vector3) -> void:
	var p := _dust[_next_dust]
	_next_dust = (_next_dust + 1) % DUST_EMITTERS
	p.global_position = at
	p.restart()
	p.emitting = true


## The spike patch is up: a small continuous fizz so the hazard reads as live, and
## on the RISE a single warm flash at the tips so the hazard announces itself. The
## flash is the frame the player needs to see; the fizz is what keeps it live after.
func set_spike_sparks(on: bool, at: Vector3) -> void:
	if _spike == null:
		return
	if on:
		_spike.global_position = at
		if _flash != null:
			# Slightly above the emitter so it reads as the tips, not the floor.
			# Tint is a RATIO of the pool's own energy, not of the nominal: on the
			# Compatibility tier both are tamed to the same value, and dividing the
			# tamed spike energy by the untamed core energy would make the hazard
			# flash four times too dim exactly where it is hardest to see.
			var ratio := FxMaterials.energy(FxMaterials.SPIKE_ENERGY) / maxf(FxMaterials.energy(FxMaterials.CORE_ENERGY), 0.0001)
			_flash.flash(at + Vector3(0.0, 0.08, 0.0), 2.2, Color(1.0, 0.72, 0.34) * minf(ratio, 1.0))
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
	m.scale_min = 0.9
	m.scale_max = 2.1
	m.color_ramp = _spark_ramp()
	# Sparks never collide: the collision pass costs a depth prepass read per
	# particle and a spark that bounces off a wall looks like a bug, not like metal.
	m.collision_mode = ParticleProcessMaterial.COLLISION_DISABLED
	p.process_material = m

	if _trails_supported:
		p.trail_enabled = true
		p.trail_lifetime = minf(SPARK_TRAIL_S, lifetime * 0.5)
		p.draw_pass_1 = _trail_ribbon()
		p.material_override = _spark_trail_material()
	else:
		var quad := QuadMesh.new()
		quad.size = Vector2(0.026, 0.11)   # a streak, not a dot
		p.draw_pass_1 = quad
		p.material_override = _particle_material(true)
	return p


## The trail geometry. SHAPE_CROSS rather than SHAPE_FLAT because a flat ribbon is
## invisible edge on, and the fight camera sits at a fixed 45/50 where half the
## sparks would be exactly that. A cross reads from every angle for 8 more triangles.
static func _trail_ribbon() -> RibbonTrailMesh:
	var r := RibbonTrailMesh.new()
	r.shape = RibbonTrailMesh.SHAPE_CROSS
	r.size = 0.034
	r.sections = 6
	r.section_length = 0.05
	r.section_segments = 2
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))     # full width at the spark
	curve.add_point(Vector2(1.0, 0.0))     # tapered to nothing at the tail
	r.curve = curve
	return r


## Additive, unshaded, HDR: the spark core must be over 1.0 for G1's glow to find it
## (energy 4), and FxMaterials tames that on the tier with no HDR buffer.
## use_particle_trails is what makes the ribbon follow the particle's transform
## history; setting it on a material NOT used by a trail mesh breaks the draw, so it
## lives here and nowhere else.
static func _spark_trail_material() -> StandardMaterial3D:
	var m := FxMaterials.additive(null, Color.WHITE, FxMaterials.SPARK_ENERGY, false)
	m.use_particle_trails = true
	return m


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
	# A little tumble so two overlapping puffs are not the same sprite twice.
	m.angle_min = -180.0
	m.angle_max = 180.0
	m.angular_velocity_min = -40.0
	m.angular_velocity_max = 40.0
	m.collision_mode = ParticleProcessMaterial.COLLISION_DISABLED
	m.color_ramp = _dust_ramp()
	p.process_material = m

	var quad := QuadMesh.new()
	quad.size = Vector2(0.30, 0.30)
	p.draw_pass_1 = quad
	# A soft authored billboard, not a hard edged quad: a square of grey is the most
	# obvious "particle system" tell there is.
	p.material_override = FxMaterials.soft_smoke(FxMaterials.texture("dust_soft.png"))
	return p


static func _particle_material(additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	if additive:
		m.albedo_color = FxMaterials.hdr(Color.WHITE, FxMaterials.SPARK_ENERGY)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return m


## --- introspection, used by Arena/tests/fx_test.gd -------------------------

func chips() -> DebrisChips:
	return _chips


func flash_pool() -> FxFlashPool:
	return _flash


func light_pool() -> FxLightPool:
	return _lights


func trails_enabled() -> bool:
	return _trails_supported


## White hot core, orange body, gone. Sparks are warm but they last 0.25 s, so they
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
	g.add_point(0.15, Color(0.66, 0.68, 0.71, 0.8))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t
