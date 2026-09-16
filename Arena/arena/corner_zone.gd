class_name CornerZone extends Node3D
## The house bot's corner (brief v4 §3): a painted 2.2 m no-go square in the corner the
## gate logic already uses, striped in the arena's warning colour.
##
## It is a MARKING and nothing else. No collision, no area, no physics: the rule that a
## bot inside it gets attacked is `fight.gd`'s, and it asks this node the one question it
## can answer, `contains()`. Keeping the geometry dumb is what lets the zone be added to
## any arena scene without that arena knowing anything about it.
##
## Renderer safety: plain MeshInstance3D boxes with StandardMaterial3D, no shader, no
## transparency and no decal, so it draws identically on `gl_compatibility` (the phone's
## fallback and the Simulator) and on Forward+. One material instance is shared by every
## bar, so `set_zone_state()` is a single albedo write rather than a rebuild.

## The square itself, brief v4 §3: 2.2 m on a side, held 0.3 m off the walls so a machine
## can still squeeze round the outside of it rather than being funnelled in.
const SIDE_M := 2.2
const WALL_INSET_M := 0.3

const STATE_IDLE := "idle"
const STATE_ALERT := "alert"
const STATE_RELEASED := "released"
const STATES := [STATE_IDLE, STATE_ALERT, STATE_RELEASED]

## Just over the arena's own floor markings (arena_base MARK_Y is 0.004) so the stripes
## never z-fight with the seam grid underneath them.
const MARK_Y := 0.008
const BAR_H := 0.006
const STRIPES := 6
const STRIPE_W := 0.17
const FRAME_W := 0.08
## How much of the arena's warning colour the three states carry. Idle is paint; alert is
## the same paint lit; released is red, and red means the thing in the corner is coming.
const COL_IDLE := Color(0.93, 0.76, 0.13)
const COL_ALERT := Color(1.0, 0.62, 0.12)
const COL_RELEASED := Color(0.93, 0.20, 0.16)
const GLOW_IDLE := 0.25
const GLOW_ALERT := 0.9
const GLOW_RELEASED := 1.3

## Floor rectangle in metres, XZ. `position` is the -X -Z corner of the square.
var _rect := Rect2(Vector2(-SIDE_M * 0.5, -SIDE_M * 0.5), Vector2(SIDE_M, SIDE_M))
var _warning_colour := COL_IDLE
var _state := STATE_IDLE
var _material: StandardMaterial3D = null
var _built := false


## The zone square for a corner of an arena of this half extent. `corner` only has to be
## in the right quadrant: the square is pinned to the walls of that quadrant, not to the
## point. Used with `fight.gd`'s existing `_gate_position()`.
static func rect_in_corner(corner: Vector3, half_extent: float) -> Rect2:
	var sx := 1.0 if corner.x >= 0.0 else -1.0
	var sz := 1.0 if corner.z >= 0.0 else -1.0
	var outer_x := (half_extent - WALL_INSET_M) * sx
	var outer_z := (half_extent - WALL_INSET_M) * sz
	var inner_x := outer_x - SIDE_M * sx
	var inner_z := outer_z - SIDE_M * sz
	return Rect2(
		Vector2(minf(outer_x, inner_x), minf(outer_z, inner_z)),
		Vector2(SIDE_M, SIDE_M))


## Set the square and the colour, before or after the node is in the tree.
func configure(rect: Rect2, warning_colour: Color = COL_IDLE) -> void:
	_rect = rect
	_warning_colour = warning_colour
	_rebuild()


func _ready() -> void:
	if not _built:
		_rebuild()


# ---------------------------------------------------------------- the contract

## The floor rectangle in metres, XZ: `position` is the corner nearest -X -Z.
func zone_rect() -> Rect2:
	return _rect


## Is this world position over the square? Height is ignored on purpose: a machine thrown
## over the corner is in the corner as far as the house bot is concerned.
func contains(position: Vector3) -> bool:
	return _rect.has_point(Vector2(position.x, position.z))


## The middle of the square: the house bot's mark.
func centre(y: float = 0.25) -> Vector3:
	var middle := _rect.get_center()
	return Vector3(middle.x, y, middle.y)


## "idle" | "alert" | "released". Anything else is ignored rather than fatal.
func set_zone_state(state: String) -> void:
	if not state in STATES or state == _state:
		return
	_state = state
	_apply_colour()


func zone_state() -> String:
	return _state


## The colour the stripes are painted right now. For the headless test, which has no
## renderer to look at.
func marking_colour() -> Color:
	match _state:
		STATE_ALERT:
			return _warning_colour.lerp(COL_ALERT, 0.5)
		STATE_RELEASED:
			return COL_RELEASED
		_:
			return _warning_colour


# ---------------------------------------------------------------- geometry

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_built = false
	_material = StandardMaterial3D.new()
	_material.roughness = 0.75
	_material.metallic = 0.0
	_material.emission_enabled = true
	_apply_colour()

	var middle := _rect.get_center()
	position = Vector3(middle.x, 0.0, middle.y)
	var half := _rect.size * 0.5

	# The frame: four bars right on the edge of the square, so the boundary the rule uses
	# is the boundary the player can see.
	_bar("FrameNorth", Vector3(0.0, MARK_Y, -half.y + FRAME_W * 0.5),
		Vector3(_rect.size.x, BAR_H, FRAME_W))
	_bar("FrameSouth", Vector3(0.0, MARK_Y, half.y - FRAME_W * 0.5),
		Vector3(_rect.size.x, BAR_H, FRAME_W))
	_bar("FrameWest", Vector3(-half.x + FRAME_W * 0.5, MARK_Y, 0.0),
		Vector3(FRAME_W, BAR_H, _rect.size.y))
	_bar("FrameEast", Vector3(half.x - FRAME_W * 0.5, MARK_Y, 0.0),
		Vector3(FRAME_W, BAR_H, _rect.size.y))

	# The stripes, evenly spaced inside the frame and a little shorter than it, so the
	# square reads as marked floor rather than as a solid plate.
	var span := _rect.size.y - FRAME_W * 2.0
	var length := _rect.size.x - FRAME_W * 2.0
	var step := span / float(STRIPES)
	for i in STRIPES:
		var z := -span * 0.5 + step * (float(i) + 0.5)
		_bar("Stripe%d" % i, Vector3(0.0, MARK_Y, z),
			Vector3(length, BAR_H, minf(STRIPE_W, step * 0.6)))
	_built = true


func _bar(bar_name: String, at: Vector3, size: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.name = bar_name
	mi.mesh = mesh
	mi.position = at
	mi.material_override = _material
	# Markings never cast: a 6 mm bar casting a shadow reads as a step on the floor.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _apply_colour() -> void:
	if _material == null:
		return
	var colour := marking_colour()
	var glow := GLOW_IDLE
	match _state:
		STATE_ALERT:
			glow = GLOW_ALERT
		STATE_RELEASED:
			glow = GLOW_RELEASED
	_material.albedo_color = colour
	_material.emission = colour
	_material.emission_energy_multiplier = glow


## True once the bars exist. For the test.
func is_built() -> bool:
	return _built
