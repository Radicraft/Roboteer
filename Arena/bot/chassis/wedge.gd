extends ChassisBase
## The Wedge: Stage 3's chassis, unchanged. Its geometry is signed off and the whole
## flipper tuning sits on top of it, so every number here is the Stage 3 number
## (docs/stage3-physics-notes.md section 5, "Getting under").
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
const SIDE_SIZE := Vector2(0.10, 0.30)
const SIDE_ANCHOR := Vector3(-0.03, 0.0, 0.30)
const REAR_SIZE := Vector2(0.12, 0.52)
const TOP_SIZE := Vector2(0.46, 0.50)
const TOP_ANCHOR := Vector3(-0.18, 0.07, 0.0)
## Stage 3's flipper hinge, in bot space.
const WEAPON_PIVOT := Vector3(0.1115, 0.0977, 0.0)


func hull_points() -> PackedVector3Array:
	return BotMeshes.wedge_points()


func procedural_meshes() -> Array[Dictionary]:
	return [{"mesh": BotMeshes.wedge_mesh(), "transform": Transform3D.IDENTITY,
		"slot": "livery"}]


func floor_y() -> float:
	return BotMeshes.BODY_BOTTOM


func top_y() -> float:
	return BotMeshes.BODY_TOP


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
			return [{"point": Vector3(-BotMeshes.HALF_LEN, 0.0, 0.0),
				"basis": Basis(Vector3.UP, PI)}]
		_:
			return [{"point": TOP_ANCHOR, "basis": Basis(Vector3.BACK, PI * 0.5)}]
