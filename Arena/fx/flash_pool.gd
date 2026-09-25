class_name FxFlashPool extends MultiMeshInstance3D
## A pool of additive billboard quads that pop and fade. One frame of light where
## something happened: a bolt arriving at the attacker, the white core of a part
## tearing off, the tips of the floor spikes coming up.
##
## Presentation only, and stepped by its owner rather than by _process so the
## headless test can advance it at a fixed delta like everything else in Arena/fx.
##
## Cheap by construction: one MultiMesh, one quad mesh, one material, N instances.
## A parked flash has a zero basis so the renderer draws nothing for it.

const GROW := 2.4        # final size as a multiple of the start size
const EASE := 2.2        # alpha falls off faster than linear, so it snaps
## The white-out clamp (combat feel S6): with this many flashes younger than CROWD_WINDOW_S
## already up, a new one is drawn at CROWD_DIM alpha and CROWD_SHRINK size.
const CROWD := 2
const CROWD_WINDOW_S := 0.1
const CROWD_DIM := 0.25
const CROWD_SHRINK := 0.6
## White-out cap (gauntlet 2026-09-25): no flash is ever DRAWN larger than the pool's
## max_size, whatever scale a caller asks for and however far it has grown. A machine is
## 0.8 m long and 0.25 m tall; a flash wider than about half of it hides the contact.

var _hidden := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)

var _count: int = 0
var _size: float = 0.3
var _life: float = 0.14
var _colour := Color.WHITE
var _max_size: float = INF

var _pos := PackedVector3Array()
var _age := PackedFloat32Array()
var _scale := PackedFloat32Array()
var _tint: PackedColorArray = PackedColorArray()
var _alive := PackedByteArray()
var _next: int = 0
var _live: int = 0


func _ready() -> void:
	set_process(false)


## Build the pool. Call once, before the first flash().
## nominal is the emission energy band (FxMaterials); it is tamed automatically on
## the Compatibility tier so the flash does not clip to a white blob there.
func configure(count: int, size: float, colour: Color, life: float, nominal: float, aabb: AABB,
		max_size: float = 0.0) -> void:
	_count = maxi(1, count)
	_max_size = max_size if max_size > 0.0 else INF
	_size = size
	_life = maxf(0.01, life)
	_colour = colour

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)          # unit quad; the instance scale is the size

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = _count
	multimesh = mm
	material_override = FxMaterials.additive(
		FxMaterials.texture("spark_glow.png"), colour, nominal, true)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	custom_aabb = aabb

	_pos.resize(_count)
	_age.resize(_count)
	_scale.resize(_count)
	_tint.resize(_count)
	_alive.resize(_count)
	for i in _count:
		_alive[i] = 0
		_scale[i] = 1.0
		_tint[i] = Color.WHITE
		mm.set_instance_transform(i, _hidden)
		mm.set_instance_color(i, Color(1.0, 1.0, 1.0, 0.0))


## Pop one. Oldest slot is recycled when the pool is full: a flash is 140 ms, so
## stealing one is always less wrong than dropping the newest event.
## `tint` multiplies the pool colour, so one pool can serve a white detach core and
## a warm hazard flash without a second material.
func flash(at: Vector3, scale: float = 1.0, tint: Color = Color.WHITE) -> void:
	if _count <= 0 or multimesh == null:
		return
	# Combat feel (S6, "the biggest hits white out the screen"): additive flashes stack, and
	# a part coming off put a detach core, spark flashes and a dozen bolt arrivals on top of
	# each other over both machines. Past CROWD young flashes each new one is dimmer and
	# smaller, so a pile-up reads as a burst of light at the contact, not a white frame.
	var young := 0
	for j in _count:
		if _alive[j] != 0 and _age[j] < CROWD_WINDOW_S:
			young += 1
	var dim := 1.0
	if young >= CROWD:
		dim = CROWD_DIM
		scale *= CROWD_SHRINK
	var i := _next
	_next = (_next + 1) % _count
	if _alive[i] == 0:
		_live += 1
	_pos[i] = at
	_age[i] = 0.0
	_scale[i] = scale
	_tint[i] = Color(tint.r, tint.g, tint.b, tint.a * dim)
	_alive[i] = 1


func step(delta: float) -> void:
	if _live <= 0 or delta <= 0.0 or multimesh == null:
		return
	var mm := multimesh
	for i in _count:
		if _alive[i] == 0:
			continue
		_age[i] += delta
		var t: float = _age[i] / _life
		if t >= 1.0:
			_alive[i] = 0
			_live -= 1
			mm.set_instance_transform(i, _hidden)
			mm.set_instance_color(i, Color(1.0, 1.0, 1.0, 0.0))
			continue
		var s: float = drawn_size(_size * _scale[i], t)
		var a: float = pow(1.0 - t, EASE)
		var c: Color = _tint[i]
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s, s)), _pos[i]))
		mm.set_instance_color(i, Color(c.r, c.g, c.b, a * c.a))


## --- introspection, used by Arena/tests/fx_test.gd -------------------------

## The drawn size of a flash that started at `start` metres, `t` (0..1) through its life.
func drawn_size(start: float, t: float) -> float:
	return minf(start * lerpf(1.0, GROW, t), _max_size)


func max_size() -> float:
	return _max_size


func pool_size() -> int:
	return _count


func live_count() -> int:
	return _live
