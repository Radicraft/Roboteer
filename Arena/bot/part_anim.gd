class_name PartAnim extends Node
## Presentation-only movement for the imported .glb parts (wave P, agent E).
##
## Three of wave P's parts are things that MOVE and are not on a joint. The saws,
## the drill and the two spinners are bodies on hinge motors, so the physics
## already turns them and nothing here is involved. These three are not:
##
##   * the walker's legs are four collision boxes welded to the hull, because a
##     leg does not roll and there is no wheel speed to command (legs.gd says so
##     at length). Four rigid boxes sliding across the floor read as a machine
##     being dragged, not walked.
##   * the hover's skirt and pods are one visual on the hull. A cushion that
##     never moves reads as a box resting on the floor.
##   * the adaptive belt's sprockets and road wheels are geometry inside one
##     skin node. A track whose wheels do not turn reads as a sledge.
##
## WHAT THIS IS ALLOWED TO TOUCH, and it is a short list: the `transform` of
## MeshInstance3D nodes under an imported model, and a DUPLICATED emissive
## material on the model's own `glow` node. It never writes to a RigidBody3D, it
## never adds a force, it never reads or writes anything the result depends on,
## and it takes its timing from `_process`, not `_physics_process`. Determinism
## is a hard rule in this repo (docs/wave-p-contracts.md) and the way to keep it
## while still animating something is to keep the animation strictly downstream
## of the simulation: the phase below is integrated from the chassis's own
## measured speed, so it FOLLOWS the fight and cannot feed back into it.
##
## The one thing to be careful of is the material. `PartVisuals._core_material`
## is cached and shared by every part in the fight, so pulsing it in place would
## pulse every core on both machines. `_glow_material` duplicates first.

enum Mode {
	## Turn every `spin_*` child about its own local Z at the road speed.
	ROLL,
	## Swing the whole model about its hip, with a per-leg phase.
	STRIDE,
	## Ride the cushion: a slow bob, a slight tilt into the turn, a lit skirt.
	HOVER,
}

## How far the machine travels per full stride cycle. A walker's top speed is
## 2.0 m/s, so at full tilt this is about 3.3 strides a second, which is a brisk
## walk and not a scuttle. Raise it for longer, lazier steps.
const STRIDE_LENGTH := 0.60
## How far the leg swings either side of straight down, in degrees.
const STRIDE_SWING := 15.0
## How far the foot lifts at the top of its swing, as a fraction of leg height.
const STRIDE_LIFT := 0.22
## Below this speed the legs stand still rather than marking time on the spot.
const STRIDE_MIN_SPEED := 0.08

## The hover's bob: amplitude in metres and cycles per second.
const HOVER_BOB := 0.012
const HOVER_BOB_HZ := 1.7
## A second, slower beat, so the bob does not read as a metronome.
const HOVER_BEAT_HZ := 0.63
## How far the skirt leans, in degrees, at the machine's top speed.
const HOVER_LEAN := 3.5
## The skirt glow, as a multiplier on the core material's own energy.
const HOVER_GLOW_MIN := 0.35
const HOVER_GLOW_MAX := 1.25

## A rolling part smaller than this is not a wheel and is left alone.
const MIN_ROLL_RADIUS := 0.01

var mode: int = Mode.ROLL
## STRIDE only: 0..1, where in the cycle this leg starts. legs.gd hands out
## 0, 0.5, 0.5, 0 across the four feet, which is a trot: the diagonal pairs
## move together, which is the gait a four legged machine with a rigid body
## actually uses and the only one that does not look like it is falling over.
var phase: float = 0.0

var _model: Node3D = null
var _body: RigidBody3D = null
var _spinners: Array[Node3D] = []
## The spinners' own rest transforms, indexed alongside `_spinners`. Kept apart
## from `_rest` (which is the MODEL's rest, and only STRIDE and HOVER have one)
## because sharing one array is exactly how the first cut indexed off the end.
var _spin_rest: Array[Transform3D] = []
var _rest: Array[Transform3D] = []
var _glow: MeshInstance3D = null
var _glow_material: StandardMaterial3D = null
var _glow_energy := 1.0
var _t := 0.0
var _travel := 0.0


## `model` is the instantiated .glb root. Call this before adding the node.
func configure(model: Node3D, of_mode: int, at_phase: float = 0.0) -> void:
	_model = model
	mode = of_mode
	phase = at_phase


func _ready() -> void:
	if _model == null:
		_model = get_parent() as Node3D
	if _model == null:
		set_process(false)
		return
	_body = _find_body(_model)
	match mode:
		Mode.ROLL:
			_collect_spinners(_model)
			_keep_spinners_round()
			set_process(not _spinners.is_empty())
		Mode.STRIDE:
			_rest = [_model.transform]
			set_process(true)
		Mode.HOVER:
			_rest = [_model.transform]
			_find_glow(_model)
			set_process(true)


## A ROUND THING MUST NOT BE SCALED UNEVENLY, and the belt is.
##
## `tracks.gd` fits one 0.70 m belt model to whatever wheelbase the hull has by
## scaling it along X alone, typically by about 1.17. That was harmless while the
## sprockets were baked into a skin that never moved: a slightly oval sprocket
## standing still is a slightly oval sprocket. Turn it and the ovalness turns with
## it, and a wheel that visibly swells and shrinks once per revolution is the kind
## of thing that reads as a bug the moment anybody notices it.
##
## Each spinner therefore cancels its parent's scale on its own axes. Its POSITION
## still scales, which is right: the sprockets should move apart as the wheelbase
## grows. Only its shape is protected.
func _keep_spinners_round() -> void:
	var parent_scale := _model.scale
	if is_equal_approx(parent_scale.x, parent_scale.y) \
			and is_equal_approx(parent_scale.y, parent_scale.z):
		return
	for i in range(_spinners.size()):
		var fix := Vector3(
			1.0 / maxf(absf(parent_scale.x), 0.0001),
			1.0 / maxf(absf(parent_scale.y), 0.0001),
			1.0 / maxf(absf(parent_scale.z), 0.0001))
		# Uniform, at the smallest of the three, so the part never grows past the
		# envelope the drive laid out for it.
		var uniform: float = minf(minf(fix.x, fix.y), fix.z)
		_spinners[i].scale = Vector3.ONE * uniform
		_spin_rest[i] = _spinners[i].transform


func _find_body(from: Node) -> RigidBody3D:
	var walk := from.get_parent()
	while walk != null:
		if walk is RigidBody3D:
			return walk as RigidBody3D
		walk = walk.get_parent()
	return null


func _collect_spinners(node: Node) -> void:
	var as_3d := node as Node3D
	if as_3d != null and String(node.name).begins_with("spin_"):
		_spinners.append(as_3d)
		_spin_rest.append(as_3d.transform)
	for child in node.get_children():
		_collect_spinners(child)


func _find_glow(node: Node) -> void:
	if node is MeshInstance3D and String(node.name).begins_with("glow"):
		_glow = node as MeshInstance3D
		var existing := _glow.get_surface_override_material(0)
		if existing is StandardMaterial3D:
			# Duplicate: `PartVisuals._core_material` is one shared object and
			# both machines in the fight are holding it.
			_glow_material = (existing as StandardMaterial3D).duplicate() as StandardMaterial3D
			_glow_energy = _glow_material.emission_energy_multiplier
			_glow.set_surface_override_material(0, _glow_material)
		return
	for child in node.get_children():
		_find_glow(child)


## Road speed along the machine's own nose, in metres a second. Zero when the
## part is not under a body yet, which is every frame of a workshop turntable.
func _road_speed() -> float:
	if _body == null or not _body.is_inside_tree():
		return 0.0
	return _body.linear_velocity.dot(_body.global_transform.basis.x)


func _process(delta: float) -> void:
	if _model == null or not _model.is_inside_tree():
		return
	_t += delta
	var speed := _road_speed()
	_travel += speed * delta
	match mode:
		Mode.ROLL:
			_tick_roll()
		Mode.STRIDE:
			_tick_stride(speed)
		Mode.HOVER:
			_tick_hover(speed)


## Every `spin_*` child turns about its own local Z, which in bot space is the
## machine's left-right axis, so a positive road speed rolls the top of the
## wheel forward. The radius comes from the node's own mesh, so a sprocket and a
## road wheel of different sizes stay in step with the ground rather than with
## each other.
func _tick_roll() -> void:
	for i in range(_spinners.size()):
		var node := _spinners[i]
		var radius := _radius_of(node)
		if radius < MIN_ROLL_RADIUS:
			continue
		var angle := -_travel / radius
		var rest: Transform3D = _spin_rest[i]
		node.transform = Transform3D(rest.basis * Basis(Vector3.BACK, angle),
			rest.origin)


func _radius_of(node: Node3D) -> float:
	var mesh_instance := node as MeshInstance3D
	if mesh_instance == null or mesh_instance.mesh == null:
		return 0.0
	var box := mesh_instance.mesh.get_aabb()
	# The rolling radius is across the axis, never along it: a sprocket is wide
	# and shallow or narrow and deep depending on the part, and taking the
	# largest extent would use the width on half of them.
	return maxf(box.size.x, box.size.y) * 0.5


## A trot. The leg swings fore and aft about its hip and lifts at the top of the
## forward swing, with the phase integrated from distance travelled rather than
## from the clock, so the feet keep pace with the floor whatever the speed and
## stop dead when the machine does.
func _tick_stride(speed: float) -> void:
	if _rest.is_empty():
		return
	var rest: Transform3D = _rest[0]
	if absf(speed) < STRIDE_MIN_SPEED:
		_model.transform = rest
		return
	var cycle := (_travel / STRIDE_LENGTH + phase) * TAU
	var swing := sin(cycle) * deg_to_rad(STRIDE_SWING)
	# The lift is only on the half of the cycle where the foot is coming
	# forward; on the other half it is planted and taking the weight.
	var lift := maxf(cos(cycle), 0.0) * STRIDE_LIFT * _leg_height()
	_model.transform = Transform3D(rest.basis * Basis(Vector3.BACK, swing),
		rest.origin + Vector3(0.0, lift, 0.0))


func _leg_height() -> float:
	if _model == null:
		return 0.09
	return maxf(_model.scale.y * 0.09, 0.02)


## The cushion: a bob on two beats so it does not tick, a lean that follows the
## speed, and a skirt glow that brightens with the lift the fans are making.
func _tick_hover(speed: float) -> void:
	if _rest.is_empty():
		return
	var rest: Transform3D = _rest[0]
	var bob := sin(_t * TAU * HOVER_BOB_HZ) * 0.7 + sin(_t * TAU * HOVER_BEAT_HZ) * 0.3
	var lean := clampf(speed / 5.2, -1.0, 1.0) * deg_to_rad(HOVER_LEAN)
	_model.transform = Transform3D(rest.basis * Basis(Vector3.BACK, -lean),
		rest.origin + Vector3(0.0, bob * HOVER_BOB, 0.0))
	if _glow_material != null:
		var work := clampf(absf(speed) / 5.2, 0.0, 1.0)
		var beat := 0.5 + 0.5 * sin(_t * TAU * HOVER_BOB_HZ * 1.6)
		var amount := lerpf(HOVER_GLOW_MIN, HOVER_GLOW_MAX,
			clampf(work * 0.6 + beat * 0.4, 0.0, 1.0))
		_glow_material.emission_energy_multiplier = _glow_energy * amount
