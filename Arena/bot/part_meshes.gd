class_name BotMeshes
## Procedural part geometry for Stage 3. No imported meshes: every shape is a
## hand-built vertex list turned into an ArrayMesh with flat (per-face) normals,
## and the same points feed the ConvexPolygonShape3D so the collider and the
## silhouette can never drift apart.
##
## Winding: measured on Godot 4.6.3 (see docs/stage3-physics-notes.md), a front
## face has cross(b - a, c - a) pointing AGAINST its outward normal. `_face()`
## enforces that, so callers pass a polygon in any order plus a rough outward hint.

## Chassis wedge, local space, forward = +X, up = +Y, origin on the axle plane
## (which sits WHEEL_RADIUS above the floor). The bot is 0.9 long, 0.6 wide,
## 0.14 tall; the front 0.35 m slopes down to a lip 0.015 m above the floor.
const HALF_LEN := 0.45
const HALF_WID := 0.30
const BODY_TOP := 0.07
const BODY_BOTTOM := -0.07
const SLOPE_START_X := 0.10
## The lip is BELOW the body floor so the wedge can actually get under another
## bot: 0.015 m clearance at the lip against 0.04 m under the body.
const LIP_BOTTOM := -0.095
const LIP_TOP := -0.075

## Points shared by the mesh and the convex hull.
static func wedge_points() -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(-HALF_LEN, BODY_BOTTOM, -HALF_WID),   # 0 rear bottom left
		Vector3(-HALF_LEN, BODY_BOTTOM, HALF_WID),    # 1 rear bottom right
		Vector3(HALF_LEN, LIP_BOTTOM, -HALF_WID),     # 2 lip bottom left
		Vector3(HALF_LEN, LIP_BOTTOM, HALF_WID),      # 3 lip bottom right
		Vector3(-HALF_LEN, BODY_TOP, -HALF_WID),      # 4 rear top left
		Vector3(-HALF_LEN, BODY_TOP, HALF_WID),       # 5 rear top right
		Vector3(SLOPE_START_X, BODY_TOP, -HALF_WID),  # 6 slope start left
		Vector3(SLOPE_START_X, BODY_TOP, HALF_WID),   # 7 slope start right
		Vector3(HALF_LEN, LIP_TOP, -HALF_WID),        # 8 lip top left
		Vector3(HALF_LEN, LIP_TOP, HALF_WID),         # 9 lip top right
	])


## Where the slope meets the deck, and where it meets the lip: the flipper arm
## and the front armour plate both ride on this line.
static func slope_start() -> Vector2:
	return Vector2(SLOPE_START_X, BODY_TOP)


static func slope_end() -> Vector2:
	return Vector2(HALF_LEN, LIP_TOP)


static func slope_angle() -> float:
	var d := slope_end() - slope_start()
	return atan2(d.y, d.x)


static func slope_length() -> float:
	return (slope_end() - slope_start()).length()


## The world-space (chassis-local) point of the wedge lip, for front_edge_height().
static func wedge_lip_point() -> Vector3:
	return Vector3(HALF_LEN, LIP_BOTTOM, 0.0)


static func wedge_mesh() -> ArrayMesh:
	var p := wedge_points()
	var tris := PackedVector3Array()
	var norms := PackedVector3Array()
	# bottom
	_face(tris, norms, [p[0], p[2], p[3], p[1]], Vector3.DOWN)
	# rear
	_face(tris, norms, [p[0], p[1], p[5], p[4]], Vector3.LEFT)
	# top deck
	_face(tris, norms, [p[4], p[5], p[7], p[6]], Vector3.UP)
	# front slope
	_face(tris, norms, [p[6], p[7], p[9], p[8]], Vector3(0.5, 1.0, 0.0))
	# lip face
	_face(tris, norms, [p[2], p[8], p[9], p[3]], Vector3.RIGHT)
	# left flank (z = -HALF_WID)
	_face(tris, norms, [p[0], p[4], p[6], p[8], p[2]], Vector3.FORWARD)
	# right flank (z = +HALF_WID)
	_face(tris, norms, [p[1], p[3], p[9], p[7], p[5]], Vector3.BACK)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = tris
	arrays[Mesh.ARRAY_NORMAL] = norms
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func wedge_shape() -> ConvexPolygonShape3D:
	var shape := ConvexPolygonShape3D.new()
	shape.points = wedge_points()
	return shape


## A flat-shaded convex box built the same way, used for armour plates and the
## flipper arm so every part shades identically.
static func flat_box_mesh(size: Vector3) -> ArrayMesh:
	var h := size * 0.5
	var p := [
		Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z),
		Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z),
		Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z),
		Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z),
	]
	var tris := PackedVector3Array()
	var norms := PackedVector3Array()
	_face(tris, norms, [p[0], p[2], p[3], p[1]], Vector3.DOWN)
	_face(tris, norms, [p[4], p[5], p[7], p[6]], Vector3.UP)
	_face(tris, norms, [p[2], p[6], p[7], p[3]], Vector3.RIGHT)
	_face(tris, norms, [p[0], p[1], p[5], p[4]], Vector3.LEFT)
	_face(tris, norms, [p[0], p[4], p[6], p[2]], Vector3.FORWARD)
	_face(tris, norms, [p[1], p[3], p[7], p[5]], Vector3.BACK)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = tris
	arrays[Mesh.ARRAY_NORMAL] = norms
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Fan-triangulate a convex polygon with one flat normal. `hint` only picks
## which side is outward; the normal itself comes from the polygon, so tilted
## faces shade correctly.
static func _face(tris: PackedVector3Array, norms: PackedVector3Array,
		poly: Array, hint: Vector3) -> void:
	var a0: Vector3 = poly[0]
	var a1: Vector3 = poly[1]
	var a2: Vector3 = poly[2]
	var n := (a1 - a0).cross(a2 - a0).normalized()
	if n.dot(hint) < 0.0:
		n = -n
	for i in range(1, poly.size() - 1):
		var a: Vector3 = a0
		var b: Vector3 = poly[i]
		var c: Vector3 = poly[i + 1]
		if (b - a).cross(c - a).dot(n) > 0.0:
			var swap := b
			b = c
			c = swap
		tris.append(a)
		tris.append(b)
		tris.append(c)
		norms.append(n)
		norms.append(n)
		norms.append(n)
