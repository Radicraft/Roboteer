class_name ArcBolt extends MultiMeshInstance3D
## The tesla arc's bolt: a jagged emissive line from the coil to whatever it just
## hit, for a handful of frames (wave P, agent F).
##
## The arc weapon landed with no bolt at all (docs/wave-p-d1-notes.md: "the arc has
## no visible bolt yet"), which made it the one weapon in the game whose whole effect
## on screen was the other machine stopping. This is the effect.
##
## ONE MULTIMESH, N BOLTS OF `SEGMENTS` BOXES. A bolt is a polyline from the coil's
## electrode to the target, with every interior vertex pushed off the straight line;
## each span between two vertices is one box instance, stretched along its own
## direction and thin across it. A box rather than a billboard quad because the fight
## camera is fixed at 45 degrees and half the bolts would be edge on to a quad, and
## because 12 triangles at this instance count is nothing (4 x 7 x 12 = 336 worst
## case, against the scrap shower's 4 964).
##
## DETERMINISTIC. The jag comes from an integer hash of (strike number, segment), not
## from `randf()`: two runs of one seed draw the same bolt in the same place, and
## nothing here can move the fight's rng. Presentation only, stepped by its owner on
## `FightFx`'s clock like everything else in Arena/fx.
##
##     var arcs := ArcBolt.new()
##     add_child(arcs)
##     arcs.configure(4, AABB(...))
##     arcs.strike(coil_world, target_world, 1.0)
##     arcs.step(delta)

## Bolts alive at once. Two machines can both carry a coil and a coil discharges
## every `reset_s` (2.2 s), so two is the realistic worst case and four is the cap.
const BOLTS := 4
## Spans per bolt. Six interior kinks reads as lightning; three reads as a dogleg and
## twelve reads as a fuzzy line at phone size.
const SEGMENTS := 7
## How long a bolt is on screen. Real enough to see, short enough that the eye reads
## it as a discharge rather than as a beam.
const LIFE_S := 0.11
## How far a kink may leave the straight line, as a fraction of the bolt's length.
## Falls off toward both ends, because a bolt is pinned at the electrode and at the
## thing it struck.
const JAG := 0.17
## Cross section of a span, in metres, and how much thinner the far end is: a bolt is
## fattest at the electrode.
const THICK_M := 0.022
const THICK_TAPER := 0.55
## The flicker rate. A real discharge is a burst of restrikes, so the bolt blinks
## rather than fading smoothly; this is the same fact the sound is built out of.
const FLICKER_HZ := 90.0
const FLICKER_DEEP := 0.45

## Pale electric blue, pulled most of the way to white: a saturated blue at this
## energy reads as a dull violet smear once the glow has been through it, and the
## channel of a real arc is white hot at the core.
const ARC_COLOUR := Color(0.78, 0.88, 1.0)
const ARC_ENERGY := 7.0

var _hidden := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)

var _count: int = 0
var _bolts: int = 0
## Per bolt: the polyline, its age and whether it is alive.
var _points: Array = []                    ## Array of PackedVector3Array
var _age := PackedFloat32Array()
var _scale := PackedFloat32Array()
var _alive := PackedByteArray()
var _next: int = 0
var _live: int = 0
var _strikes: int = 0


func _ready() -> void:
	set_process(false)


## Build the pool. Call once, before the first strike().
func configure(bolts: int = BOLTS, aabb: AABB = AABB(
		Vector3(-14.0, -3.0, -14.0), Vector3(28.0, 12.0, 28.0))) -> void:
	_bolts = maxi(1, bolts)
	_count = _bolts * SEGMENTS

	var box := BoxMesh.new()
	box.size = Vector3(1.0, 1.0, 1.0)       # unit box; the instance basis sizes it

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = box
	mm.instance_count = _count
	multimesh = mm
	material_override = FxMaterials.additive(null, ARC_COLOUR, ARC_ENERGY, false)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	custom_aabb = aabb

	_points.clear()
	_age.resize(_bolts)
	_scale.resize(_bolts)
	_alive.resize(_bolts)
	for b in _bolts:
		_points.append(PackedVector3Array())
		_alive[b] = 0
		_scale[b] = 1.0
	for i in _count:
		mm.set_instance_transform(i, _hidden)
		mm.set_instance_color(i, Color(1.0, 1.0, 1.0, 0.0))


## Throw one bolt from `from` to `to`. `scale` thickens it (a bigger discharge is a
## fatter channel, not a longer one). The oldest bolt is recycled when the pool is
## full: a bolt is 110 ms, so stealing one is always less wrong than dropping the
## discharge that just happened.
func strike(from: Vector3, to: Vector3, scale: float = 1.0) -> void:
	if _count <= 0 or multimesh == null:
		return
	var b := _next
	_next = (_next + 1) % _bolts
	if _alive[b] == 0:
		_live += 1
	_strikes += 1
	_points[b] = _polyline(from, to, _strikes)
	_age[b] = 0.0
	_scale[b] = maxf(scale, 0.05)
	_alive[b] = 1


func step(delta: float) -> void:
	if _live <= 0 or delta <= 0.0 or multimesh == null:
		return
	var mm := multimesh
	for b in _bolts:
		if _alive[b] == 0:
			continue
		_age[b] += delta
		var t: float = _age[b] / LIFE_S
		if t >= 1.0:
			_alive[b] = 0
			_live -= 1
			_park(mm, b)
			continue
		# The blink. `int(age * rate)` alternates, so the bolt is at full for one
		# flicker period and at FLICKER_DEEP for the next, over an envelope that
		# falls to nothing. It never smoothly dissolves, because a discharge does not.
		var blink := 1.0 if int(_age[b] * FLICKER_HZ) % 2 == 0 else FLICKER_DEEP
		var alpha := (1.0 - t * t) * blink
		_draw(mm, b, alpha)


## --- introspection, used by Arena/tests/fx_test.gd -------------------------

func pool_size() -> int:
	return _bolts


func live_count() -> int:
	return _live


func segments_per_bolt() -> int:
	return SEGMENTS


func strike_count() -> int:
	return _strikes


func instance_count() -> int:
	return _count


## The polyline of one bolt, in world space. The test asserts on THIS rather than on
## the MultiMesh: `get_instance_transform` does not return what was written under the
## dummy renderer a headless run uses, so reading the instances back would be a test
## of the renderer and not of the jag.
func points_of(bolt: int) -> PackedVector3Array:
	if bolt < 0 or bolt >= _bolts:
		return PackedVector3Array()
	return (_points[bolt] as PackedVector3Array).duplicate()


## The bolt thrown most recently, whether or not it is still alive.
func last_points() -> PackedVector3Array:
	if _bolts <= 0 or _strikes <= 0:
		return PackedVector3Array()
	return points_of((_next - 1 + _bolts) % _bolts)


## --- internals --------------------------------------------------------------

## The polyline. Every interior vertex is pushed off the straight line in the two
## directions perpendicular to it, by a deterministic hash of (strike, vertex).
func _polyline(from: Vector3, to: Vector3, strike_id: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(SEGMENTS + 1)
	var span := to - from
	var length := span.length()
	if length < 0.0001:
		for i in SEGMENTS + 1:
			out[i] = from
		return out
	var dir := span / length
	# Two axes across the bolt. `Vector3.UP` unless the bolt is vertical, which a
	# coil's discharge across the floor never is, but a guard costs one branch.
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(dir).normalized()
	out[0] = from
	out[SEGMENTS] = to
	for i in range(1, SEGMENTS):
		var f := float(i) / float(SEGMENTS)
		# Pinned at both ends: the widest kinks are in the middle of the run.
		var taper := sin(f * PI)
		var a := _signed(strike_id, i, 0) * JAG * length * taper
		var c := _signed(strike_id, i, 1) * JAG * length * taper
		out[i] = from + dir * (length * f) + side * a + up * c
	return out


## Write one bolt's spans into the MultiMesh at `alpha`.
func _draw(mm: MultiMesh, b: int, alpha: float) -> void:
	var pts: PackedVector3Array = _points[b]
	if pts.size() < 2:
		return
	var base := b * SEGMENTS
	var width: float = THICK_M * _scale[b]
	for s in SEGMENTS:
		var a := pts[s]
		var c := pts[s + 1]
		var span := c - a
		var length := span.length()
		var i := base + s
		if length < 0.0001:
			mm.set_instance_transform(i, _hidden)
			mm.set_instance_color(i, Color(1.0, 1.0, 1.0, 0.0))
			continue
		var dir := span / length
		var side := dir.cross(Vector3.UP)
		if side.length_squared() < 1e-6:
			side = dir.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := side.cross(dir).normalized()
		# Thinner as it goes: the channel is fattest where it left the electrode.
		var w: float = width * lerpf(1.0, THICK_TAPER, float(s) / float(SEGMENTS))
		var basis := Basis(side * w, dir * length, up * w)
		mm.set_instance_transform(i, Transform3D(basis, a + span * 0.5))
		mm.set_instance_color(i, Color(1.0, 1.0, 1.0, alpha))


func _park(mm: MultiMesh, b: int) -> void:
	var base := b * SEGMENTS
	for s in SEGMENTS:
		mm.set_instance_transform(base + s, _hidden)
		mm.set_instance_color(base + s, Color(1.0, 1.0, 1.0, 0.0))


## A repeatable value in [-1, 1] from three integers. An integer avalanche mix
## (the xorshift-multiply family), because the jag has to be the SAME in a replay
## and `randf()` is the one thing a presentation node may never call.
static func _signed(a: int, b: int, c: int) -> float:
	var h: int = (a * 0x27d4eb2d) ^ (b * 0x165667b1) ^ (c * 0x9e3779b1)
	h = h & 0x7fffffff
	h ^= (h >> 15)
	h = (h * 0x2545f491) & 0x7fffffff
	h ^= (h >> 13)
	return float(h % 20001) / 10000.0 - 1.0
