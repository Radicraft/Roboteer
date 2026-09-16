class_name ScrapSparks extends Node3D
## The moment of tearing, and where the scrap lands.
##
## Wave F, agent F3. Three small effects that belong to the scrap shower rather than to
## the impact (`FightParticles` still owns the impact fan, the detach core and the
## structural dust):
##
##   * `burst()`  -- sparks at the point the scrap was torn out of, fired with the shower
##   * `smoke()`  -- a short smoke puff, heavy hits only
##   * `ring()`   -- a tiny dust ring where a piece lands, kicked by its first bounce
##
## Presentation only, stepped by `BoltShower` on `FightFx`'s clock so a headless test can
## advance it at a fixed delta, and every pool is built in `_ready`/`configure` and
## recycled. Nothing here allocates during a fight.
##
## RENDERER GUARD. The sparks are `GPUParticles3D` where there is a RenderingDevice
## (Forward+ on the phone and on the Mac) and a CPU MultiMesh where there is not
## (gl_compatibility in the Simulator, and headless). That is the same test
## `FightParticles` uses for its ribbon trails and `FxMaterials` uses for HDR, kept in
## one place: `FxMaterials.hdr_available()`. The smoke and the landing rings are CPU on
## BOTH tiers on purpose -- they are at most a couple of dozen quads, a particle system
## for them would cost more in emitters than it saves, and one code path cannot silently
## rot on the tier nobody looks at.

# --- sparks ------------------------------------------------------------------
const SPARK_EMITTERS := 3          # GPU path: rotated, one shot
const SPARK_AMOUNT := 20
const SPARK_LIFE := 0.30
const CPU_SPARKS := 36             # fallback path: the whole pool, shared by every burst
const CPU_SPARK_PER_BURST := 10
const CPU_SPARK_SIZE := 0.055
const SPARK_SPEED_MIN := 2.2
const SPARK_SPEED_MAX := 6.0
const SPARK_GRAVITY := 11.0
const SPARK_DRAG := 2.2

# --- smoke -------------------------------------------------------------------
const SMOKE_POOL := 8
const SMOKE_LIFE := 0.55
const SMOKE_SIZE := 0.26
const SMOKE_GROW := 2.6
const SMOKE_RISE := 0.55           # m/s
const SMOKE_ALPHA := 0.42

# --- landing dust ring -------------------------------------------------------
const RING_POOL := 16
const RING_LIFE := 0.34
const RING_SIZE := 0.085
const RING_GROW := 2.2
const RING_ALPHA := 0.30
const RING_Y := 0.006              # sits just off the floor so it never z-fights it

const SPARK_COLOUR := Color(1.0, 0.86, 0.60)
const SMOKE_COLOUR := Color(0.56, 0.57, 0.60)
const RING_COLOUR := Color(0.62, 0.63, 0.66)

var _hidden := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
var _rng := RandomNumberGenerator.new()
var _aabb := AABB(Vector3(-8.0, -2.0, -8.0), Vector3(16.0, 10.0, 16.0))

var _gpu: bool = false
var _emitters: Array[GPUParticles3D] = []
var _next_emitter: int = 0

var _cpu_sparks: MultiMeshInstance3D = null
var _sp_pos := PackedVector3Array()
var _sp_vel := PackedVector3Array()
var _sp_age := PackedFloat32Array()
var _sp_alive := PackedByteArray()
var _sp_next: int = 0
var _sp_live: int = 0

var _smoke: MultiMeshInstance3D = null
var _sm_pos := PackedVector3Array()
var _sm_age := PackedFloat32Array()
var _sm_scale := PackedFloat32Array()
var _sm_alive := PackedByteArray()
var _sm_next: int = 0
var _sm_live: int = 0

var _rings: MultiMeshInstance3D = null
var _rg_pos := PackedVector3Array()
var _rg_age := PackedFloat32Array()
var _rg_scale := PackedFloat32Array()
var _rg_alive := PackedByteArray()
var _rg_next: int = 0
var _rg_live: int = 0


func _ready() -> void:
	set_process(false)


func configure(aabb: AABB) -> void:
	_rng.randomize()
	_aabb = aabb
	_gpu = FxMaterials.hdr_available()
	if _gpu:
		for i in SPARK_EMITTERS:
			var p := _make_emitter("ScrapSparks%d" % i)
			add_child(p)
			_emitters.append(p)
	else:
		_cpu_sparks = _make_bank("ScrapSparksCpu", CPU_SPARKS,
			_additive_material(), Vector2(CPU_SPARK_SIZE * 0.42, CPU_SPARK_SIZE))
		_sp_pos.resize(CPU_SPARKS)
		_sp_vel.resize(CPU_SPARKS)
		_sp_age.resize(CPU_SPARKS)
		_sp_alive.resize(CPU_SPARKS)

	_smoke = _make_bank("ScrapSmoke", SMOKE_POOL, _smoke_material(), Vector2.ONE)
	_sm_pos.resize(SMOKE_POOL)
	_sm_age.resize(SMOKE_POOL)
	_sm_scale.resize(SMOKE_POOL)
	_sm_alive.resize(SMOKE_POOL)

	_rings = _make_bank("ScrapDustRings", RING_POOL, _ring_material(), Vector2.ONE)
	_rg_pos.resize(RING_POOL)
	_rg_age.resize(RING_POOL)
	_rg_scale.resize(RING_POOL)
	_rg_alive.resize(RING_POOL)


# --------------------------------------------------------------------- firing

## Sparks where the scrap was torn out. `severity` 0 to 1 sizes the burst.
func burst(at: Vector3, severity: float) -> void:
	var s := clampf(severity, 0.0, 1.0)
	if _gpu:
		if _emitters.is_empty():
			return
		var p: GPUParticles3D = _emitters[_next_emitter]
		_next_emitter = (_next_emitter + 1) % _emitters.size()
		p.global_position = at
		p.amount_ratio = clampf(0.35 + s * 0.65, 0.35, 1.0)
		var m := p.process_material as ParticleProcessMaterial
		if m != null:
			m.initial_velocity_min = SPARK_SPEED_MIN * (0.7 + 0.5 * s)
			m.initial_velocity_max = SPARK_SPEED_MAX * (0.7 + 0.5 * s)
		p.restart()
		p.emitting = true
		return
	var n := int(round(float(CPU_SPARK_PER_BURST) * (0.4 + 0.6 * s)))
	for _k in maxi(1, n):
		var i := _sp_next
		_sp_next = (_sp_next + 1) % CPU_SPARKS
		if _sp_alive[i] == 0:
			_sp_live += 1
		_sp_pos[i] = at
		_sp_vel[i] = _cone(0.55) * _rng.randf_range(SPARK_SPEED_MIN, SPARK_SPEED_MAX) * (0.7 + 0.5 * s)
		_sp_age[i] = 0.0
		_sp_alive[i] = 1


## A short smoke puff. Heavy hits only: on a scrape it would read as a fire.
func smoke(at: Vector3, severity: float) -> void:
	if _smoke == null:
		return
	var i := _sm_next
	_sm_next = (_sm_next + 1) % SMOKE_POOL
	if _sm_alive[i] == 0:
		_sm_live += 1
	_sm_pos[i] = at
	_sm_age[i] = 0.0
	_sm_scale[i] = 0.8 + 0.7 * clampf(severity, 0.0, 1.0)
	_sm_alive[i] = 1


## A piece landed. A dust ring on the floor under it, which is the whole difference
## between scrap that arrives on the floor and scrap that arrives at a height of zero.
func ring(at: Vector3, scale: float) -> void:
	if _rings == null:
		return
	var i := _rg_next
	_rg_next = (_rg_next + 1) % RING_POOL
	if _rg_alive[i] == 0:
		_rg_live += 1
	_rg_pos[i] = Vector3(at.x, RING_Y, at.z)
	_rg_age[i] = 0.0
	_rg_scale[i] = clampf(scale, 0.4, 2.5)
	_rg_alive[i] = 1


# --------------------------------------------------------------------- stepping

func step(delta: float) -> void:
	if delta <= 0.0:
		return
	_step_cpu_sparks(delta)
	_step_smoke(delta)
	_step_rings(delta)


func _step_cpu_sparks(delta: float) -> void:
	if _cpu_sparks == null or _sp_live <= 0:
		return
	var mm := _cpu_sparks.multimesh
	for i in CPU_SPARKS:
		if _sp_alive[i] == 0:
			continue
		_sp_age[i] += delta
		var t: float = _sp_age[i] / SPARK_LIFE
		if t >= 1.0:
			_sp_alive[i] = 0
			_sp_live -= 1
			mm.set_instance_transform(i, _hidden)
			mm.set_instance_color(i, Color(1, 1, 1, 0))
			continue
		var v := _sp_vel[i]
		v.y -= SPARK_GRAVITY * delta
		v *= exp(-SPARK_DRAG * delta)
		_sp_vel[i] = v
		_sp_pos[i] += v * delta
		var s := 1.0 - t
		mm.set_instance_transform(i,
			Transform3D(Basis().scaled(Vector3(s, s, s)), _sp_pos[i]))
		mm.set_instance_color(i, Color(1.0, 1.0, 1.0, s))
	_cpu_sparks.visible = _sp_live > 0


func _step_smoke(delta: float) -> void:
	if _smoke == null or _sm_live <= 0:
		return
	var mm := _smoke.multimesh
	for i in SMOKE_POOL:
		if _sm_alive[i] == 0:
			continue
		_sm_age[i] += delta
		var t: float = _sm_age[i] / SMOKE_LIFE
		if t >= 1.0:
			_sm_alive[i] = 0
			_sm_live -= 1
			mm.set_instance_transform(i, _hidden)
			mm.set_instance_color(i, Color(1, 1, 1, 0))
			continue
		_sm_pos[i] += Vector3(0.0, SMOKE_RISE * delta, 0.0)
		var s: float = SMOKE_SIZE * _sm_scale[i] * lerpf(1.0, SMOKE_GROW, t)
		# Up fast, out slow: alpha peaks early then falls, so the puff never pops in.
		var a: float = SMOKE_ALPHA * clampf(t / 0.18, 0.0, 1.0) * pow(1.0 - t, 1.6)
		mm.set_instance_transform(i,
			Transform3D(Basis().scaled(Vector3(s, s, s)), _sm_pos[i]))
		mm.set_instance_color(i, Color(1.0, 1.0, 1.0, a))
	_smoke.visible = _sm_live > 0


func _step_rings(delta: float) -> void:
	if _rings == null or _rg_live <= 0:
		return
	var mm := _rings.multimesh
	# Flat on the floor: a quad faces +Z, so it is turned a quarter turn about X.
	var flat := Basis(Vector3.RIGHT, -PI * 0.5)
	for i in RING_POOL:
		if _rg_alive[i] == 0:
			continue
		_rg_age[i] += delta
		var t: float = _rg_age[i] / RING_LIFE
		if t >= 1.0:
			_rg_alive[i] = 0
			_rg_live -= 1
			mm.set_instance_transform(i, _hidden)
			mm.set_instance_color(i, Color(1, 1, 1, 0))
			continue
		var s: float = RING_SIZE * _rg_scale[i] * lerpf(0.6, RING_GROW, t)
		var a: float = RING_ALPHA * pow(1.0 - t, 1.4)
		mm.set_instance_transform(i,
			Transform3D(flat.scaled(Vector3(s, s, s)), _rg_pos[i]))
		mm.set_instance_color(i, Color(1.0, 1.0, 1.0, a))
	_rings.visible = _rg_live > 0


# --------------------------------------------------------------------- building

func _make_bank(node_name: String, count: int, mat: Material, size: Vector2) -> MultiMeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = count
	var node := MultiMeshInstance3D.new()
	node.name = node_name
	node.multimesh = mm
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	node.custom_aabb = _aabb
	node.visible = false
	add_child(node)
	for i in count:
		mm.set_instance_transform(i, _hidden)
		mm.set_instance_color(i, Color(1, 1, 1, 0))
	return node


func _make_emitter(node_name: String) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = node_name
	p.amount = SPARK_AMOUNT
	p.lifetime = SPARK_LIFE
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	p.local_coords = false
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH

	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.05
	m.direction = Vector3(0.0, 1.0, 0.0)
	m.spread = 68.0
	m.initial_velocity_min = SPARK_SPEED_MIN
	m.initial_velocity_max = SPARK_SPEED_MAX
	m.gravity = Vector3(0.0, -SPARK_GRAVITY, 0.0)
	m.damping_min = 1.6
	m.damping_max = 3.6
	m.scale_min = 0.7
	m.scale_max = 1.5
	m.color_ramp = _spark_ramp()
	# Sparks never collide: a spark that bounces off a wall looks like a bug, and the
	# collision pass costs a depth read per particle.
	m.collision_mode = ParticleProcessMaterial.COLLISION_DISABLED
	p.process_material = m

	var quad := QuadMesh.new()
	quad.size = Vector2(0.024, 0.10)   # a streak, not a dot
	p.draw_pass_1 = quad
	p.material_override = _additive_material()
	return p


static func _spark_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(1.0, 0.97, 0.88, 1.0))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(0.85, 0.34, 0.10, 0.0))
	g.add_point(0.3, Color(1.0, 0.72, 0.30, 1.0))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


## Additive, HDR where there is HDR, tamed where there is not: `FxMaterials` owns both
## halves of that, so the scrap sparks cannot drift away from the impact sparks.
static func _additive_material() -> StandardMaterial3D:
	var m := FxMaterials.additive(FxMaterials.texture("spark_glow.png"),
		SPARK_COLOUR, FxMaterials.SPARK_ENERGY, true)
	return m


## Smoke must OCCLUDE, never glow (docs/graphics-fx-notes.md §2), so it is alpha
## blended and unshaded, on the same authored soft billboard the structural dust uses.
static func _smoke_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.albedo_color = SMOKE_COLOUR
	m.vertex_color_use_as_albedo = true
	var tex := FxMaterials.texture("dust_soft.png")
	if tex != null:
		m.albedo_texture = tex
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return m


## The landing ring lies on the floor and must NOT billboard: a puff that turns to face
## the camera stops reading as dust on the ground and starts reading as a sprite.
static func _ring_material() -> StandardMaterial3D:
	var m := _smoke_material()
	m.albedo_color = RING_COLOUR
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	# It sits 6 mm above a floor it never needs to be depth tested against precisely;
	# no_depth_test stays OFF so a bot standing over it still hides it.
	return m


## A direction in an up biased cone. Uses this node's own presentation RNG, which is
## deliberately unseeded and must never be the fight's seeded generator.
func _cone(spread: float) -> Vector3:
	var az := _rng.randf_range(0.0, TAU)
	var y := _rng.randf_range(cos(spread * PI), 1.0)
	var r := sqrt(maxf(0.0, 1.0 - y * y))
	return Vector3(r * cos(az), y, r * sin(az))


# --------------------------------------------------------------------- introspection

func gpu_sparks() -> bool:
	return _gpu


func emitter_count() -> int:
	return _emitters.size()


func cpu_spark_pool() -> int:
	return CPU_SPARKS if _cpu_sparks != null else 0


func live_sparks() -> int:
	return _sp_live


func smoke_pool() -> int:
	return SMOKE_POOL


func live_smoke() -> int:
	return _sm_live


func ring_pool() -> int:
	return RING_POOL


func live_rings() -> int:
	return _rg_live
