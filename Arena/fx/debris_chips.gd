class_name DebrisChips extends MultiMeshInstance3D
## Shrapnel. When something is struck hard enough to shed a part, a handful of torn
## metal chips fly off with the sparks, tumble, bounce once and settle.
##
## brief-v3.md §6, the readability rule, is the whole reason this class is separate
## from BoltShower rather than a flag on it: "collectible bolts are bright gold,
## small and spinning. Structural debris is dull grey, larger, and stays where it
## lands." So a chip is LIT and never emissive, it is grey, it does not magnetise to
## anybody, and nothing about it ever says pick me up. A player who chases a chip has
## been misled by the game's own art.
##
## Presentation only. Stepped by FightParticles, never by _physics_process, and the
## ballistics are the same closed form bounce the bolts use so a chip lands in the
## same place at 30 fps as at 120.

const POOL := 32
const LIFETIME := 1.2
const FADE_S := 0.3              # the last third of a second shrinks it away
## Scaled for the same reason the bolts were (docs/graphics-fx-notes.md §10): G3's
## 16 mm sliver is invisible at the fight framing. Still comfortably bigger than a
## bolt, which is the side of the readability rule that matters.
const CHIP_LENGTH := 0.085       # m, the long axis after scaling G3's 16 mm sliver
const GRAVITY := 9.8
const RESTITUTION := 0.34
const GROUND_FRICTION := 0.62
const REST_DRAG := 4.0
const SPIN_MIN := 9.0
const SPIN_MAX := 26.0
const LAUNCH_SPEED_MIN := 1.6
const LAUNCH_SPEED_MAX := 4.4
const LAUNCH_CONE_DEG := 70.0
const CHIP_MESH_PATH := "res://assets/parts/fx/spark_chip.glb"

var _hidden := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
var _rng := RandomNumberGenerator.new()

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _axis := PackedVector3Array()
var _angle := PackedFloat32Array()
var _rate := PackedFloat32Array()
var _age := PackedFloat32Array()
var _scale := PackedFloat32Array()
var _alive := PackedByteArray()
var _bounced := PackedByteArray()
var _next: int = 0
var _live: int = 0
var _mesh_scale: float = 1.0
var _rest_y: float = 0.004


func _ready() -> void:
	_rng.randomize()
	_build()
	set_process(false)


func _build() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _load_mesh()
	mm.instance_count = POOL
	multimesh = mm
	material_override = FxMaterials.debris_metal()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	custom_aabb = AABB(Vector3(-8.0, -2.0, -8.0), Vector3(16.0, 10.0, 16.0))

	_pos.resize(POOL)
	_vel.resize(POOL)
	_axis.resize(POOL)
	_angle.resize(POOL)
	_rate.resize(POOL)
	_age.resize(POOL)
	_scale.resize(POOL)
	_alive.resize(POOL)
	_bounced.resize(POOL)
	for i in POOL:
		_alive[i] = 0
		_scale[i] = 1.0
		mm.set_instance_transform(i, _hidden)
		mm.set_instance_color(i, Color(1.0, 1.0, 1.0, 1.0))


## Throw `count` chips out of a hit. severity 0..1 makes them fly further.
## The pool recycles its oldest slot rather than dropping the newest event: a chip
## is scenery, and a missing chip at the moment of a big hit is the worse failure.
func burst(at: Vector3, count: int, severity: float) -> int:
	if multimesh == null or count <= 0:
		return 0
	var s := clampf(severity, 0.0, 1.0)
	var n := mini(count, POOL)
	for _k in n:
		var i := _next
		_next = (_next + 1) % POOL
		if _alive[i] == 0:
			_live += 1
		_spawn_one(i, at, s)
	return n


func _spawn_one(i: int, at: Vector3, severity: float) -> void:
	_pos[i] = at + Vector3(
		_rng.randf_range(-0.04, 0.04),
		_rng.randf_range(-0.02, 0.05),
		_rng.randf_range(-0.04, 0.04))
	var az := _rng.randf_range(0.0, TAU)
	var y := _rng.randf_range(cos(deg_to_rad(LAUNCH_CONE_DEG)), 1.0)
	var r := sqrt(maxf(0.0, 1.0 - y * y))
	var dir := Vector3(r * cos(az), y, r * sin(az))
	var speed := _rng.randf_range(LAUNCH_SPEED_MIN, LAUNCH_SPEED_MAX) * (0.7 + 0.6 * severity)
	_vel[i] = dir * speed
	var ax := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0))
	_axis[i] = Vector3.UP if ax.length_squared() < 0.05 else ax.normalized()
	_angle[i] = _rng.randf_range(0.0, TAU)
	_rate[i] = _rng.randf_range(SPIN_MIN, SPIN_MAX)
	_age[i] = 0.0
	_scale[i] = _rng.randf_range(0.75, 1.35)
	_alive[i] = 1
	_bounced[i] = 0


func step(delta: float) -> void:
	if _live <= 0 or delta <= 0.0 or multimesh == null:
		return
	var mm := multimesh
	for i in POOL:
		if _alive[i] == 0:
			continue
		_age[i] += delta
		if _age[i] >= LIFETIME:
			_alive[i] = 0
			_live -= 1
			mm.set_instance_transform(i, _hidden)
			continue
		_ballistic(i, delta)
		_angle[i] += _rate[i] * delta
		# A settled chip stops tumbling; a chip spinning on the floor reads as a bug.
		if _bounced[i] == 1 and _vel[i].length_squared() < 0.04:
			_rate[i] = lerpf(_rate[i], 0.0, minf(1.0, delta * 8.0))
		var shrink := 1.0
		var left: float = LIFETIME - _age[i]
		if left < FADE_S:
			shrink = clampf(left / FADE_S, 0.0, 1.0)
		var s: float = _scale[i] * _mesh_scale * shrink
		mm.set_instance_transform(i, Transform3D(Basis(_axis[i], _angle[i]).scaled(Vector3.ONE * s), _pos[i]))


## The bolts' closed form single bounce, same reasoning: solved for the real
## crossing time inside the frame so the frame rate cannot move where it lands.
func _ballistic(i: int, dt: float) -> void:
	var p := _pos[i]
	var v := _vel[i]
	if _bounced[i] == 0 and v.y < 0.0 and p.y > _rest_y:
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


func _load_mesh() -> Mesh:
	var mesh := BoltShower._mesh_from_glb(CHIP_MESH_PATH)
	if mesh == null:
		push_warning("DebrisChips: %s missing, using a box" % CHIP_MESH_PATH)
		var box := BoxMesh.new()
		box.size = Vector3(CHIP_LENGTH, CHIP_LENGTH * 0.16, CHIP_LENGTH * 0.22)
		_mesh_scale = 1.0
		return box
	var longest := mesh.get_aabb().size.max_axis_index()
	var extent: float = mesh.get_aabb().size[longest]
	_mesh_scale = 1.0 if extent <= 0.0001 else CHIP_LENGTH / extent
	return mesh


## --- introspection, used by Arena/tests/fx_test.gd -------------------------

func pool_size() -> int:
	return POOL


func live_count() -> int:
	return _live
