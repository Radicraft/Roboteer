extends Yard
class_name TestArena
## The Workshop Test Arena (docs/stage4-spec.md §6, brief §10): The Yard with the spike
## hazard taken out and a wall mounted target pad to drive a weapon into.
##
## It subclasses the Yard rather than copying it so the floor, the walls, the chevrons,
## the out of arena sensor and the spawn markers stay exactly the ones the fight uses:
## a build that behaves a certain way in here must behave the same way in a real fight,
## and that is the whole point of a test arena. Only the hazard is missing, because the
## player is here to read their own machine, not to be interrupted by the floor.
##
## The file lives in `Arena/fight/` because agent R2 owns that directory and
## `Arena/arena/test_arena.tscn`, but not `Arena/arena/yard.gd`.

## Where the pad sits: centred on the north wall (-Z), face pointing into the arena.
const PAD_SIZE := Vector3(1.8, 0.55, 0.12)
const PAD_COL := Color(0.78, 0.62, 0.16)        # the arena chevron yellow, not bolt gold
const PAD_STRIPE := Color(0.14, 0.14, 0.16)
const PAD_STRIPES := 5

var _pad: StaticBody3D = null


func build() -> void:
	if _built_already():
		return
	super()
	_remove_spikes()
	_build_target_pad()


## The target pad body, so the overlay or a test can find what was hit.
func target_pad() -> StaticBody3D:
	return _pad


# --- the hazard is not here ----------------------------------------------------------

## Nothing rises, so nothing to dodge: the AI's spike avoidance is a no-op in here and
## the judges' "seconds on the spike patch" can never be scored.
func spikes_risen() -> bool:
	return false


func seconds_to_spike_rise() -> float:
	return 999.0


## The Yard ticks the spike timer and the hazard damage in _physics_process. There is no
## hazard here, so the tick is dropped entirely rather than left running on hidden bodies.
func _physics_process(_delta: float) -> void:
	pass


func _remove_spikes() -> void:
	for spike in _spikes:
		if is_instance_valid(spike):
			spike.queue_free()
	_spikes.clear()
	if _spike_area != null and is_instance_valid(_spike_area):
		_spike_area.queue_free()
	_spike_area = null
	# The patch's bezel (bored holes, lamp dashes) is render only and stays behind once the
	# spikes are gone: a dead hazard in the middle of the test floor. Hidden, not freed, so
	# the tree the physics sees is exactly the one it was. The venue paints pivot rings there.
	var patch := get_node_or_null("SpikePatch") as Node3D
	if patch != null:
		patch.visible = false


# --- the target pad ------------------------------------------------------------------

## A chunky striped plate bolted to the north wall at weapon height, for driving into.
## Static and indestructible on purpose: it is a reference surface, so an impulse read off
## it is the build's, not a shared guess about how much the target gave way.
func _build_target_pad() -> void:
	var wall_inner := HALF - FightTypes.WALL_THICKNESS * 0.5
	var centre := Vector3(0.0, PAD_SIZE.y * 0.5, -wall_inner + PAD_SIZE.z * 0.5)

	_pad = StaticBody3D.new()
	_pad.name = "TargetPad"
	_pad.position = centre
	_pad.collision_layer = FightTypes.LAYER_ARENA
	_pad.collision_mask = FightTypes.MASK_BOT
	add_child(_pad)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = PAD_SIZE
	shape.shape = box
	_pad.add_child(shape)

	var plate := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = PAD_SIZE
	plate.mesh = mesh
	plate.material_override = _flat_colour(PAD_COL)
	_pad.add_child(plate)

	# Diagonal stripes, the same read as the wall chevrons, so it is obviously a target.
	var stripe_w := PAD_SIZE.x / float(PAD_STRIPES * 2)
	for i in PAD_STRIPES:
		var stripe := MeshInstance3D.new()
		var stripe_mesh := BoxMesh.new()
		stripe_mesh.size = Vector3(stripe_w, PAD_SIZE.y * 0.92, 0.01)
		stripe.mesh = stripe_mesh
		stripe.position = Vector3(
			-PAD_SIZE.x * 0.5 + stripe_w * (2.0 * float(i) + 1.0), 0.0, PAD_SIZE.z * 0.5 + 0.006)
		stripe.material_override = _flat_colour(PAD_STRIPE)
		_pad.add_child(stripe)


func _flat_colour(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.85
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material


## `_built` is the Yard's private guard. Reading it here keeps build() idempotent the way
## the Yard's own is, without reaching into it for anything else.
func _built_already() -> bool:
	return _built
