extends ChassisBase
## The Wedge: Stage 3's chassis. Its GROUND GAME is signed off and the whole flipper
## tuning sits on top of it, so every number here is the Stage 3 number measured from
## the FLOOR (docs/stage3-physics-notes.md section 5, "Getting under").
##
## HERO HULL (2026-09-25, docs/wave-a-hull-notes.md): the wedge rides its own 0.14 m
## wheel (catalogue `wheel_radius`), so the floor is BotMeshes.WEDGE_DROP (30 mm) lower
## in bot space and every ground-game point below comes down by the same amount. The
## tail is shorter (BotMeshes.REAR_X), and the shell over the deck is collision: a
## second convex shape plus the top plate on its crest.
##
## The three things that make the weapon possible at all, all preserved:
##   1. the lip bottom sits 0.015 m off the floor while the body floor sits at
##      0.033 to 0.04 m, so a wedge gets under a flank or a rear and under nothing
##      head on;
##   2. the front plate lies ON the slope near the lip, angled to match, never
##      below it;
##   3. the flipper pivot is at FLIPPER_PIVOT, not at the .glb's socket_weapon_front
##      (which G3 placed 40 mm lower and further back). The arm rests along the
##      slope from there, which is the measured position.

## Stage 3 armour geometry, in the plate frame (+X outward, y and z in plane).
const FRONT_SLOPE_S := 0.30
const FRONT_SIZE := Vector2(0.16, 0.56)
## The side plate fills the gap between the tyres (front slot 0.25, rear -0.23, 0.14 m
## tyres: -0.09 to 0.11).
const SIDE_SIZE := Vector2(0.10, 0.19)
const SIDE_ANCHOR := Vector3(0.01, 0.0, 0.30)
const REAR_SIZE := Vector2(0.12, 0.52)
## The top plate IS the shell's crest: its outer face at BotMeshes.CREST_Y, from the
## tail to the shell front, out over the tyres.
const TOP_SIZE := Vector2(0.42, 0.64)
const TOP_ANCHOR := Vector3(-0.15, BotMeshes.CREST_Y - ChassisBase.PLATE_PROUD, 0.0)
## Stage 3's flipper hinge, in bot space, moved down with the floor.
const WEAPON_PIVOT := Vector3(0.1115, 0.0977 - BotMeshes.WEDGE_DROP, 0.0)
## Where the srimech sits: in the channel between the pods, near the tail.
const SRIMECH_AT := Vector3(-0.30, BotMeshes.BODY_TOP + 0.01, 0.0)


func hull_points() -> PackedVector3Array:
	return BotMeshes.wedge_points()


## Two solids: the ground-game wedge and the shell over the deck.
func shapes() -> Array[Dictionary]:
	var lower := ConvexPolygonShape3D.new()
	lower.points = BotMeshes.wedge_points()
	var shell := ConvexPolygonShape3D.new()
	shell.points = BotMeshes.wedge_shell_points()
	return [{"shape": lower, "transform": Transform3D.IDENTITY},
		{"shape": shell, "transform": Transform3D.IDENTITY}]


## The wedge's own wheel. Every drive on it builds this radius (DriveBase.setup), and
## the model is scaled to it.
func wheel_radius_min() -> float:
	return float(spec.get("wheel_radius", BotMeshes.WEDGE_WHEEL_R))


## Measured (docs/wave-a-hull-notes.md): with Jolt's default contact settings a resting
## wedge wheel sits 5.2 mm inside the floor, which put the 15 mm lip on the floor (0.3 mm)
## and dragged it: the wedge stall. The collision wheel is that much bigger, so the machine
## rests at its drawn height and the lip at its signed-off 15 mm.
const WHEEL_SINK_ALLOWANCE := 0.005


func wheel_sink_allowance() -> float:
	return WHEEL_SINK_ALLOWANCE


func wheel_ballast_kg() -> float:
	return float(spec.get("wheel_ballast_kg", 0.0))


## Same force at the tread as a 0.11 m wheel: the motor limit scales with the radius.
func wheel_torque_scale() -> float:
	return wheel_radius_min() / FightTypes.WHEEL_RADIUS


## `com_height` is from the floor, and this floor is at -wheel radius.
func com_local() -> Vector3:
	return Vector3(com_x(), float(spec.get("com_height", 0.10)) - wheel_radius_min(), 0.0)


## The catalogue's slots, always: the physics never reads the model for the hero hull.
func wheel_slots(drive_id: String) -> Array[Vector3]:
	var table: Dictionary = spec.get("wheel_slots", {}) as Dictionary
	var key := drive_id if table.has(drive_id) else "4wd"
	var out: Array[Vector3] = []
	for row_variant in table.get(key, []) as Array:
		var row: Array = row_variant
		out.append(Vector3(float(row[0]), 0.0, float(row[1])))
	if out.is_empty():
		return super.wheel_slots(drive_id)
	return out


func rear_x() -> float:
	return BotMeshes.REAR_X


func srimech_socket() -> Transform3D:
	return Transform3D(Basis.IDENTITY, SRIMECH_AT)


func procedural_meshes() -> Array[Dictionary]:
	return [{"mesh": BotMeshes.wedge_mesh(), "transform": Transform3D.IDENTITY,
		"slot": "livery"}]


func floor_y() -> float:
	return BotMeshes.BODY_BOTTOM


## The top of the machine is the shell's crest (face_for_contact's "top" band).
func top_y() -> float:
	return BotMeshes.CREST_Y


func front_lip_point() -> Vector3:
	return BotMeshes.wedge_lip_point()


## PINNED, deliberately. The general rule in ChassisBase (the .glb socket lifted
## along the ramp normal by the armour stack) lands at (0.086, 0.096) for the
## signed off three unit steel front, against this measured (0.112, 0.098): the
## same height to two millimetres. It is pinned rather than computed because the
## rule moves with armour thickness, and a one unit front plate would drop the arm
## 22 mm, which is exactly the measured pogo trap (docs/stage3-physics-notes.md
## section 5: an arm that reaches the floor becomes a third ground contact, lifts
## the front wheels and the bot bounces around the arena). The whole flipper tuning
## is signed off against this point.
func weapon_socket(kind: String) -> Transform3D:
	if kind == "" or kind == "front":
		return Transform3D(Basis.IDENTITY, WEAPON_PIVOT)
	return super.weapon_socket(kind)


func weapon_rest_angle() -> float:
	return BotMeshes.slope_angle()


func plate_size(face: String, t: float) -> Vector3:
	match face:
		"front":
			return Vector3(t, FRONT_SIZE.x, FRONT_SIZE.y)
		"sides":
			return Vector3(t, SIDE_SIZE.x, SIDE_SIZE.y)
		"rear":
			return Vector3(t, REAR_SIZE.x, REAR_SIZE.y)
		_:
			return Vector3(t, TOP_SIZE.x, TOP_SIZE.y)


func _armour_anchors(face: String) -> Array[Dictionary]:
	match face:
		"front":
			# The plate lies along the slope. Its frame: +X is the slope's outward
			# normal, +Y runs up the slope, so the box's y is its length.
			var slope := Basis(Vector3.BACK, BotMeshes.slope_angle())
			var start := BotMeshes.slope_start()
			var basis := Basis(slope.y, slope.x, -slope.z)
			var anchor := Vector3(start.x, start.y, 0.0) + slope.x * FRONT_SLOPE_S
			return [{"point": anchor, "basis": basis}]
		"sides":
			return [
				{"point": SIDE_ANCHOR, "basis": Basis(Vector3.UP, -PI * 0.5)},
				{"point": Vector3(SIDE_ANCHOR.x, SIDE_ANCHOR.y, -SIDE_ANCHOR.z),
					"basis": Basis(Vector3.UP, PI * 0.5)},
			]
		"rear":
			return [{"point": Vector3(BotMeshes.REAR_X, 0.0, 0.0),
				"basis": Basis(Vector3.UP, PI)}]
		_:
			return [{"point": TOP_ANCHOR, "basis": Basis(Vector3.BACK, PI * 0.5)}]
