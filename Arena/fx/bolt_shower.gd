class_name BoltShower extends MultiMeshInstance3D
## The bolt shower: brief-v3.md §6 "Bolt showers, damage feedback and scrap, in one effect".
##
## Every bolt is a pure presentation particle. Nothing here is a physics body, nothing
## here runs in _physics_process, and nothing here can change the fight. Bolts visualise
## scrap that has ALREADY been awarded, so a bolt that never lands is a bug (the pool
## force collects any bolt that outlives MAX_LIFE_S so the scrap is never lost).
##
## Life of one bolt:
##   1. launch in an up-biased cone, 2 to 5 m/s, under gravity
##   2. exactly one analytic floor bounce at y = 0, restitution 0.4
##   3. wait out its scatter delay (250 ms +/- 90 %) -- this pause IS the effect
##   4. magnetise to the live attacker position, acceleration k / max(distance, 0.3)
##   5. arrive within 0.25 m, emit collected(bot_id), free its pool slot
##
## FightFx drives step(); this node keeps its own _process off so the headless test
## can advance it at a fixed delta.

## One bolt reached its target. The scrap it carries is FightFx's ledger, not ours.
signal collected(bot_id: String)

const GRAVITY := 9.8
const RESTITUTION := 0.4            # the single floor bounce
const GROUND_FRICTION := 0.72       # horizontal speed kept through that bounce
const REST_DRAG := 3.0              # per second, once a bolt is lying on the floor
const SPEED_CAP := 12.0             # m/s, magnet phase
const ARRIVE_DIST := 0.25           # m
const MAGNET_K := 45.0              # see docs/stage3-fx-notes.md for how this was tuned
const MAGNET_MIN_DIST := 0.3        # the max(distance, 0.3) clamp in the brief
## Per second rate at which the magnet also turns a bolt's existing velocity toward
## the target. Pure central attraction is a logarithmic potential: a bolt launched
## sideways at 5 m/s goes into a stable ORBIT and never arrives. Measured: at 0 it
## orbits from every distance, at 6 every launch lands in 0.08 to 1.05 s.
const MAGNET_ALIGN := 6.0
const LAUNCH_SPEED_MIN := 2.0
const LAUNCH_SPEED_MAX := 5.0
const LAUNCH_CONE_DEG := 55.0       # half angle around +Y, so the shower is up-biased
const SPIN_RATE_MIN := 7.0          # rad/s
const SPIN_RATE_MAX := 16.0
const BOLT_SIZE := 0.05             # m across the flats of the hex head
const SHORT_POOL_SCALE := 1.6       # fewer, bigger bolts when the pool is short
const MAX_LIFE_S := 8.0             # safety net: force collect, never drop scrap

## A parked bolt: zero basis, so it has no area and the renderer draws nothing.
var _hidden := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)

var _rng := RandomNumberGenerator.new()   # presentation RNG, deliberately unseeded (§7)

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _spin_axis := PackedVector3Array()
var _spin_angle := PackedFloat32Array()
var _spin_rate := PackedFloat32Array()
var _delay := PackedFloat32Array()       # seconds left before the magnet engages
var _life := PackedFloat32Array()
var _scale := PackedFloat32Array()
var _alive := PackedByteArray()
var _bounced := PackedByteArray()
## Mirror of what we last wrote into the MultiMesh: 1 = a real transform, 0 = parked.
var _written := PackedByteArray()
var _bot_id: Array[String] = []
var _getter: Array[Callable] = []

var _free: PackedInt32Array = PackedInt32Array()
var _live_count: int = 0
## Per frame cache of target positions so the getter is called once per bot, not once
## per bolt, while still being re-read every frame.
var _target_cache: Dictionary = {}
var _rest_y: float = BOLT_SIZE * 0.2


func _ready() -> void:
	_rng.randomize()
	_build()
	set_process(false)   # FightFx steps us


func _build() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _build_bolt_mesh()
	mm.instance_count = FightTypes.BOLT_POOL
	multimesh = mm
	material_override = _build_bolt_material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Every instance lives somewhere in the arena; a fixed AABB stops the parked
	# (zero scale, origin) instances from collapsing it and culling the live ones.
	custom_aabb = AABB(Vector3(-8.0, -2.0, -8.0), Vector3(16.0, 10.0, 16.0))

	var n := FightTypes.BOLT_POOL
	_pos.resize(n)
	_vel.resize(n)
	_spin_axis.resize(n)
	_spin_angle.resize(n)
	_spin_rate.resize(n)
	_delay.resize(n)
	_life.resize(n)
	_scale.resize(n)
	_alive.resize(n)
	_bounced.resize(n)
	_written.resize(n)
	_bot_id.resize(n)
	_getter.resize(n)
	_free.resize(n)
	for i in n:
		_alive[i] = 0
		_written[i] = 0
		_free[i] = n - 1 - i          # pop_back hands out 0, 1, 2 ... first
		mm.set_instance_transform(i, _hidden)


## Spawn up to count bolts at origin that magnetise to bot_id.
## target_getter takes a bot_id String and returns the live chassis Vector3.
## Returns how many were actually spawned: when the pool is short we spawn fewer,
## bigger bolts (brief §6 budget rule) and FightFx gives each one a larger share.
func spawn(origin: Vector3, count: int, bot_id: String, target_getter: Callable) -> int:
	if count <= 0:
		return 0
	var n: int = mini(count, _free.size())
	if n <= 0:
		return 0
	var scale: float = 1.0 if n >= count else SHORT_POOL_SCALE
	for _k in n:
		var i: int = _free[_free.size() - 1]
		_free.resize(_free.size() - 1)
		_spawn_one(i, origin, bot_id, target_getter, scale)
	_live_count += n
	return n


func _spawn_one(i: int, origin: Vector3, bot_id: String, target_getter: Callable, scale: float) -> void:
	_pos[i] = origin + Vector3(
		_rng.randf_range(-0.05, 0.05),
		_rng.randf_range(-0.02, 0.06),
		_rng.randf_range(-0.05, 0.05))
	# Uniform on a spherical cap around +Y: up-biased, never a flat spray.
	var az := _rng.randf_range(0.0, TAU)
	var y := _rng.randf_range(cos(deg_to_rad(LAUNCH_CONE_DEG)), 1.0)
	var r := sqrt(maxf(0.0, 1.0 - y * y))
	var dir := Vector3(r * cos(az), y, r * sin(az))
	_vel[i] = dir * _rng.randf_range(LAUNCH_SPEED_MIN, LAUNCH_SPEED_MAX)
	_spin_axis[i] = Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0)).normalized()
	if _spin_axis[i].length_squared() < 0.5:
		_spin_axis[i] = Vector3.UP
	_spin_angle[i] = _rng.randf_range(0.0, TAU)
	_spin_rate[i] = _rng.randf_range(SPIN_RATE_MIN, SPIN_RATE_MAX)
	# The arrival stagger is emergent from this jitter, never scheduled.
	var base := float(FightTypes.BOLT_SCATTER_DELAY_MS) / 1000.0
	_delay[i] = maxf(0.0, base * (1.0 + FightTypes.BOLT_SCATTER_JITTER * _rng.randf_range(-1.0, 1.0)))
	_life[i] = 0.0
	_scale[i] = scale
	_alive[i] = 1
	_bounced[i] = 0
	_bot_id[i] = bot_id
	_getter[i] = target_getter


## Presentation step. delta is seconds; FightFx passes its own clock delta.
func step(delta: float) -> void:
	if _live_count <= 0 or delta <= 0.0:
		return
	_target_cache.clear()
	var mm := multimesh
	var arrived: Array[String] = []
	for i in FightTypes.BOLT_POOL:
		if _alive[i] == 0:
			continue
		_life[i] += delta
		var done := false
		if _delay[i] > 0.0:
			_delay[i] -= delta
			_ballistic(i, delta)
		else:
			done = _magnet(i, delta)
		if not done and _life[i] >= MAX_LIFE_S:
			done = true   # never lose scrap to a lost bolt
		if done:
			arrived.append(_bot_id[i])
			_retire(i, mm)
			continue
		_spin_angle[i] += _spin_rate[i] * delta
		var basis := Basis(_spin_axis[i], _spin_angle[i]).scaled(Vector3.ONE * _scale[i])
		mm.set_instance_transform(i, Transform3D(basis, _pos[i]))
		_written[i] = 1
	for id in arrived:
		collected.emit(id)


func _retire(i: int, mm: MultiMesh) -> void:
	_alive[i] = 0
	_getter[i] = Callable()
	_bot_id[i] = ""
	_free.append(i)
	_live_count -= 1
	_written[i] = 0
	mm.set_instance_transform(i, _hidden)


## Gravity plus exactly one analytic floor bounce. The bounce is solved for the
## real crossing time inside the frame, so it lands in the same place at 30 fps
## as at 120 fps.
func _ballistic(i: int, dt: float) -> void:
	var p := _pos[i]
	var v := _vel[i]
	if _bounced[i] == 0 and v.y < 0.0 and p.y > _rest_y:
		# Solve p.y + v.y t - 0.5 g t^2 = rest_y for the first positive root.
		var disc := v.y * v.y + 2.0 * GRAVITY * (p.y - _rest_y)
		if disc >= 0.0:
			var t_hit := (v.y + sqrt(disc)) / GRAVITY
			if t_hit >= 0.0 and t_hit <= dt:
				p = p + v * t_hit + Vector3(0.0, -0.5 * GRAVITY * t_hit * t_hit, 0.0)
				p.y = _rest_y
				v.y = -(v.y - GRAVITY * t_hit) * RESTITUTION
				v.x *= GROUND_FRICTION
				v.z *= GROUND_FRICTION
				_bounced[i] = 1
				dt -= t_hit
	v.y -= GRAVITY * dt
	p += v * dt
	if p.y < _rest_y:
		p.y = _rest_y
		v.y = 0.0
		var drag := exp(-REST_DRAG * dt)
		v.x *= drag
		v.z *= drag
		_bounced[i] = 1
	_pos[i] = p
	_vel[i] = v


## Magnet phase. Acceleration scales inversely with distance so bolts speed up as
## they close (brief §6: constant velocity travel looks lifeless at any speed).
## Returns true when the bolt has arrived.
func _magnet(i: int, dt: float) -> bool:
	var target := _target_of(i)
	var p := _pos[i]
	var to := target - p
	var d := to.length()
	if d <= ARRIVE_DIST:
		return true
	var dir := to / d
	var v := _vel[i]
	# Steer the speed the bolt already has toward the target before adding the pull,
	# or a sideways launch orbits forever instead of streaming home.
	v = v.lerp(dir * v.length(), clampf(MAGNET_ALIGN * dt, 0.0, 1.0))
	v += dir * (MAGNET_K / maxf(d, MAGNET_MIN_DIST)) * dt
	var speed := v.length()
	if speed > SPEED_CAP:
		v = v * (SPEED_CAP / speed)
	var next := p + v * dt
	_pos[i] = next
	_vel[i] = v
	# A capped bolt covers 0.2 m per frame at 60 fps and can step straight over the
	# 0.25 m arrival ball on a slow frame, so test the whole segment, not the endpoint.
	return _segment_distance(p, next, target) <= ARRIVE_DIST


func _target_of(i: int) -> Vector3:
	var id := _bot_id[i]
	if _target_cache.has(id):
		return _target_cache[id]
	var pos := _pos[i]
	var cb := _getter[i]
	if cb.is_valid():
		var got: Variant = cb.call(id)
		if got is Vector3:
			pos = got
	_target_cache[id] = pos
	return pos


static func _segment_distance(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 <= 0.000001:
		return a.distance_to(p)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return (a + ab * t).distance_to(p)


## --- introspection, used by Arena/tests/fx_test.gd -------------------------

func live_count() -> int:
	return _live_count


func free_slots() -> int:
	return _free.size()


## Instances the renderer will actually draw: a parked bolt has a zero basis and
## covers no pixels.
##
## This counts the transforms we WROTE rather than reading the MultiMesh back,
## because the headless dummy renderer does not keep the instance buffer and
## multimesh.get_instance_transform() returns identity for every slot there. It
## still catches the bug that matters: a retired slot that was never parked, or a
## live bolt whose transform was never written.
func visible_instance_count() -> int:
	var n := 0
	for i in FightTypes.BOLT_POOL:
		if _written[i] == 1:
			n += 1
	return n


## --- mesh and material -----------------------------------------------------

## A hex nut, not a sphere: the art direction note on arena-mid-fight.png says the
## gold particles must carry a faceted hex head silhouette to sell what they are.
static func _build_bolt_mesh() -> ArrayMesh:
	var circum := BOLT_SIZE * 0.5 / cos(PI / 6.0)   # across the flats -> circumradius
	var half_h := BOLT_SIZE * 0.34 * 0.5
	var ring_top := PackedVector3Array()
	var ring_bot := PackedVector3Array()
	for k in 6:
		var a := float(k) * PI / 3.0
		var c := cos(a) * circum
		var s := sin(a) * circum
		ring_top.append(Vector3(c, half_h, s))
		ring_bot.append(Vector3(c, -half_h, s))

	# Triangle soup, no index buffer: every face carries its own flat normal so the
	# hex facets catch the light separately as the bolt spins.
	var tris := PackedVector3Array()
	var tri_norms := PackedVector3Array()
	var top_c := Vector3(0.0, half_h, 0.0)
	var bot_c := Vector3(0.0, -half_h, 0.0)
	for k in 6:
		var j := (k + 1) % 6
		var face_n := ((ring_top[k] + ring_top[j]) * 0.5).normalized()
		tris.append_array(PackedVector3Array([
			top_c, ring_top[k], ring_top[j],
			bot_c, ring_bot[j], ring_bot[k],
			ring_top[k], ring_bot[k], ring_bot[j],
			ring_top[k], ring_bot[j], ring_top[j],
		]))
		tri_norms.append_array(PackedVector3Array([
			Vector3.UP, Vector3.UP, Vector3.UP,
			Vector3.DOWN, Vector3.DOWN, Vector3.DOWN,
			face_n, face_n, face_n,
			face_n, face_n, face_n,
		]))
	var verts := tris
	var norms := tri_norms

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Gold, lightly shaded, emissive. docs/stage2-art-direction.md: gold is the one
## saturated warm in the frame and the bolts must be the brightest thing on screen.
static func _build_bolt_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = FightTypes.BOLT_GOLD
	m.metallic = 0.55
	m.metallic_specular = 0.6
	m.roughness = 0.32
	m.emission_enabled = true
	m.emission = FightTypes.BOLT_GOLD
	m.emission_energy_multiplier = 0.85
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	# 12 triangles at 5 cm: two sided costs nothing and removes any winding risk.
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	return m
