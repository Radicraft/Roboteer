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
##
## G4 (graphics bar pass, docs/graphics-fx-notes.md) changed only what a bolt LOOKS
## like. Every number above, the pool, the scatter, the magnet and the collect are
## untouched, and fx_test.gd still measures the same timings it always did. What is
## new: G3's 20 triangle hex nut mesh instead of a procedural one, gold metal with
## emission 3 so it blooms under G1's glow, a two axis tumble so the facets flash as
## it turns, a 120 ms additive streak so a shower reads as a STREAM rather than a
## cloud of dots, and a small gold flash where each bolt arrives.

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
const SPIN_RATE_MIN := 9.0          # rad/s
const SPIN_RATE_MAX := 20.0
## Second tumble axis. A single axis spin reads as a coin flipping in place; two
## axes at different rates make the hex facets catch the key light at irregular
## intervals, which is most of what sells a bolt as a machined metal object.
const SPIN2_RATE_MIN := 4.0
const SPIN2_RATE_MAX := 11.0
## The PHYSICAL size. It sets the height a bolt rests at on the floor and therefore
## feeds the ballistics, so it is frozen at the Stage 3 value: changing it would move
## the timings agent B measured and the test asserts.
const BOLT_SIZE := 0.05             # m across the flats of the hex head
## The DRAWN size, and nothing else. A real 50 mm nut is three pixels at the fight
## framing on a 6.9 inch phone, which is the whole of why the first desktop frames
## showed gold specks instead of a shower. 90 mm is not a real bolt and does not
## pretend to be; it is the size at which "bright gold, small and spinning" survives
## the camera distance the brief actually asks for.
const BOLT_VISUAL_SIZE := 0.09
const SHORT_POOL_SCALE := 1.6       # fewer, bigger bolts when the pool is short
const MAX_LIFE_S := 8.0             # safety net: force collect, never drop scrap

## G3's hex nut, 20 triangles. The procedural mesh below is the fallback if the
## import is missing, so a broken asset degrades to the Stage 3 look, not to nothing.
const BOLT_MESH_PATH := "res://assets/parts/fx/debris_bolt.glb"

## --- trail ------------------------------------------------------------------
## HARD CAP. One streak segment per pool slot and no more, so the trail can never
## cost more draw data than the bolts themselves.
const TRAIL_SEGMENTS := 120
## A segment reaches full brightness, or fades to nothing, in this long. Also the
## length of travel the streak represents.
const TRAIL_LIFE_S := 0.12
## How much travel the streak DRAWS, kept separate from the 120 ms fade so the
## streak could be doubled in length without touching the locked fade time.
const TRAIL_LENGTH_S := 0.24
const TRAIL_MIN_SPEED := 2.2        # m/s; below this a bolt draws no streak at all
const TRAIL_FULL_SPEED := 8.0       # m/s at which the streak is at full alpha
## Tuned on the second desktop pass: at 1.10 m and 65 mm the streaks read as TRACER
## FIRE rather than as a stream of nuts, which is the wrong genre entirely. Shorter
## and slimmer keeps the stream and gives the bolt itself back the eye.
const TRAIL_MAX_LEN := 0.75         # m, so a capped 12 m/s bolt does not draw a spear
const TRAIL_WIDTH := 0.050          # m

## --- collect flash ----------------------------------------------------------
const FLASH_POOL := 8
const FLASH_SIZE := 0.48            # m, before the pop; FxFlashPool grows it
const FLASH_LIFE_S := 0.14

## A parked bolt: zero basis, so it has no area and the renderer draws nothing.
var _hidden := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)

var _rng := RandomNumberGenerator.new()   # presentation RNG, deliberately unseeded (§7)

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _spin_axis := PackedVector3Array()
var _spin_angle := PackedFloat32Array()
var _spin_rate := PackedFloat32Array()
var _spin_axis2 := PackedVector3Array()
var _spin_angle2 := PackedFloat32Array()
var _spin_rate2 := PackedFloat32Array()
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

## Scale that takes G3's real-world 19 mm nut up to the readable BOLT_SIZE. Folded
## into the instance basis so `_scale[i]` keeps meaning exactly what it meant before.
var _mesh_scale: float = 1.0

var _trail: MultiMeshInstance3D = null
var _trail_count: int = 0
var _trail_alpha := PackedFloat32Array()
var _trail_live: int = 0

var _flash: FxFlashPool = null


func _ready() -> void:
	_rng.randomize()
	_build()
	set_process(false)   # FightFx steps us


func _build() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _load_bolt_mesh()
	mm.instance_count = FightTypes.BOLT_POOL
	multimesh = mm
	material_override = FxMaterials.bolt_metal()
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
	_spin_axis2.resize(n)
	_spin_angle2.resize(n)
	_spin_rate2.resize(n)
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

	_build_trail()
	_build_flash()


## The streak. Slot i belongs to bolt i, so the cap is structural rather than a
## budget somebody has to remember: there can never be more segments than bolts.
func _build_trail() -> void:
	_trail_count = mini(FightTypes.BOLT_POOL, TRAIL_SEGMENTS)
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)     # unit quad; the instance basis stretches it
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = _trail_count
	_trail = MultiMeshInstance3D.new()
	_trail.name = "BoltTrail"
	_trail.multimesh = mm
	_trail.material_override = FxMaterials.additive(
		FxMaterials.texture("trail_streak.png"),
		FxMaterials.TRAIL_GOLD, FxMaterials.TRAIL_ENERGY, false)
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_trail.custom_aabb = custom_aabb
	add_child(_trail)
	_trail_alpha.resize(_trail_count)
	for i in _trail_count:
		_trail_alpha[i] = 0.0
		mm.set_instance_transform(i, _hidden)
		mm.set_instance_color(i, Color(1.0, 1.0, 1.0, 0.0))


func _build_flash() -> void:
	_flash = FxFlashPool.new()
	_flash.name = "CollectFlash"
	add_child(_flash)
	_flash.configure(FLASH_POOL, FLASH_SIZE, FightTypes.BOLT_GOLD, FLASH_LIFE_S,
		FxMaterials.FLASH_ENERGY, custom_aabb)


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
	_spin_axis[i] = _random_axis()
	_spin_angle[i] = _rng.randf_range(0.0, TAU)
	_spin_rate[i] = _rng.randf_range(SPIN_RATE_MIN, SPIN_RATE_MAX)
	_spin_axis2[i] = _random_axis()
	_spin_angle2[i] = _rng.randf_range(0.0, TAU)
	_spin_rate2[i] = _rng.randf_range(SPIN2_RATE_MIN, SPIN2_RATE_MAX)
	# The arrival stagger is emergent from this jitter, never scheduled.
	var base := float(FightTypes.BOLT_SCATTER_DELAY_MS) / 1000.0
	_delay[i] = maxf(0.0, base * (1.0 + FightTypes.BOLT_SCATTER_JITTER * _rng.randf_range(-1.0, 1.0)))
	_life[i] = 0.0
	_scale[i] = scale
	_alive[i] = 1
	_bounced[i] = 0
	_bot_id[i] = bot_id
	_getter[i] = target_getter


func _random_axis() -> Vector3:
	var v := Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0))
	if v.length_squared() < 0.05:
		return Vector3.UP
	return v.normalized()


## Presentation step. delta is seconds; FightFx passes its own clock delta.
func step(delta: float) -> void:
	if delta <= 0.0:
		return
	if _live_count > 0:
		_step_bolts(delta)
	# The streak and the flash outlive the bolt that made them, so they are stepped
	# whether or not anything is in flight.
	_decay_trail(delta)
	if _flash != null:
		_flash.step(delta)


func _step_bolts(delta: float) -> void:
	_target_cache.clear()
	var mm := multimesh
	var cam := _camera_position()
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
			if _flash != null:
				_flash.flash(_pos[i], _scale[i])
			_retire(i, mm)
			continue
		_spin_angle[i] += _spin_rate[i] * delta
		_spin_angle2[i] += _spin_rate2[i] * delta
		var s: float = _scale[i] * _mesh_scale
		var basis := (Basis(_spin_axis[i], _spin_angle[i]) * Basis(_spin_axis2[i], _spin_angle2[i])).scaled(Vector3.ONE * s)
		mm.set_instance_transform(i, Transform3D(basis, _pos[i]))
		_written[i] = 1
		_write_trail(i, delta, cam)
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
	# The streak is deliberately NOT parked here: it keeps its last transform and
	# fades out over TRAIL_LIFE_S, which is what leaves a 120 ms wake behind an
	# arriving bolt instead of a hole where it used to be.


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


## --- the streak -------------------------------------------------------------

## Where the fight camera is, so a streak can be turned to face it. A velocity
## aligned quad cannot use BILLBOARD_FIXED_Y: Godot pins that to WORLD +Y, not to
## the instance's own Y, so a horizontal streak would be edge on. One camera lookup
## per frame and a cross product per bolt is cheaper than a custom shader and exact.
func _camera_position() -> Vector3:
	if not is_inside_tree():
		return Vector3.ZERO
	var vp := get_viewport()
	if vp == null:
		return Vector3.ZERO
	var cam := vp.get_camera_3d()
	if cam == null:
		return Vector3.ZERO
	return cam.global_position


func _write_trail(i: int, delta: float, cam: Vector3) -> void:
	if _trail == null or i >= _trail_count:
		return
	var v := _vel[i]
	var speed := v.length()
	var target := clampf((speed - TRAIL_MIN_SPEED) / (TRAIL_FULL_SPEED - TRAIL_MIN_SPEED), 0.0, 1.0)
	var was: float = _trail_alpha[i]
	# Both directions take at most TRAIL_LIFE_S, so a streak fades in and out over
	# 120 ms and never pops.
	var a := move_toward(was, target, delta / TRAIL_LIFE_S)
	_trail_alpha[i] = a
	if was <= 0.0 and a > 0.0:
		_trail_live += 1
	if a <= 0.0:
		if was > 0.0:
			_trail_live -= 1
			_park_trail(i)
		return
	var dir := v / maxf(speed, 0.0001)
	var length := minf(speed * TRAIL_LENGTH_S, TRAIL_MAX_LEN)
	var head := _pos[i]
	var to_cam := (cam - head)
	var side := dir.cross(to_cam)
	if side.length_squared() < 0.000001:
		side = dir.cross(Vector3.UP)
		if side.length_squared() < 0.000001:
			side = Vector3.RIGHT
	side = side.normalized()
	var face := side.cross(dir).normalized()
	var width: float = TRAIL_WIDTH * _scale[i]
	# QuadMesh spans -0.5..0.5 with v = 0 at +Y, and trail_streak.png is brightest at
	# v = 0, so +Y must be the HEAD. Origin therefore sits half a length behind it.
	var basis := Basis(side * width, dir * length, face)
	_trail.multimesh.set_instance_transform(i, Transform3D(basis, head - dir * (length * 0.5)))
	_trail.multimesh.set_instance_color(i, Color(1.0, 1.0, 1.0, a))


## Fade out every streak whose bolt is gone. Only runs while something is fading.
func _decay_trail(delta: float) -> void:
	if _trail == null or _trail_live <= 0:
		return
	var drop := delta / TRAIL_LIFE_S
	for i in _trail_count:
		if _trail_alpha[i] <= 0.0 or _alive[i] == 1:
			continue
		var a: float = _trail_alpha[i] - drop
		if a <= 0.0:
			_trail_alpha[i] = 0.0
			_trail_live -= 1
			_park_trail(i)
			continue
		_trail_alpha[i] = a
		_trail.multimesh.set_instance_color(i, Color(1.0, 1.0, 1.0, a))


func _park_trail(i: int) -> void:
	_trail.multimesh.set_instance_transform(i, _hidden)
	_trail.multimesh.set_instance_color(i, Color(1.0, 1.0, 1.0, 0.0))


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


## The hard cap on streak segments. fx_test.gd asserts this never grows past 120.
func trail_capacity() -> int:
	return _trail_count


func trail_live_count() -> int:
	return _trail_live


func flash_pool() -> FxFlashPool:
	return _flash


func mesh_scale() -> float:
	return _mesh_scale


## --- mesh ------------------------------------------------------------------

## G3's hex nut (Arena/assets/parts/manifest.json, 20 triangles, 19 mm across the
## flats: a real M12 nut). The game needs it at BOLT_VISUAL_SIZE to be readable at the
## fight camera distance, so the scale is derived from the mesh AABB rather than
## hard coded, and survives G3 re-exporting the part at a different size.
func _load_bolt_mesh() -> Mesh:
	var mesh := _mesh_from_glb(BOLT_MESH_PATH)
	if mesh == null:
		push_warning("BoltShower: %s missing, falling back to the procedural nut" % BOLT_MESH_PATH)
		_mesh_scale = 1.0
		return _build_bolt_mesh()
	var size := mesh.get_aabb().size
	# A hex seen down its axis is widest across the CORNERS; BOLT_SIZE is across the
	# flats, and across_corners = across_flats / cos(30 degrees).
	var across_corners := maxf(size.x, size.z)
	_mesh_scale = 1.0
	if across_corners > 0.0001:
		_mesh_scale = (BOLT_VISUAL_SIZE / cos(PI / 6.0)) / across_corners
	return mesh


## First mesh in a glTF scene. The part glbs are a single `body` MeshInstance3D
## under a Node3D root, so this is the whole of the contract.
static func _mesh_from_glb(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return null
	var root: Node = packed.instantiate()
	var found: Mesh = null
	var queue: Array[Node] = [root]
	while not queue.is_empty():
		var n: Node = queue.pop_front()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			found = (n as MeshInstance3D).mesh
			break
		for c in n.get_children():
			queue.append(c)
	root.free()
	return found


## Fallback hex nut, kept from Stage 3 so a missing import degrades rather than
## disappears. The art direction note on arena-mid-fight.png says the gold
## particles must carry a faceted hex head silhouette to sell what they are.
static func _build_bolt_mesh() -> ArrayMesh:
	var circum := BOLT_VISUAL_SIZE * 0.5 / cos(PI / 6.0)   # across the flats -> circumradius
	var half_h := BOLT_VISUAL_SIZE * 0.34 * 0.5
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
