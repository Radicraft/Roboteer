class_name ChassisBase extends RefCounted
## One chassis module per catalogue id (docs/stage4-spec.md section 3). A module
## owns three things and nothing else:
##
## 1. the COLLISION: convex shapes built from hand-written points, in bot space;
## 2. the VISUAL: agent G3's .glb when it exists, the Stage 3 procedural mesh when
##    it does not, with G2's materials bound by slot name;
## 3. the SOCKETS: where the weapon, the wheels, the plates and the utility parts
##    go. Read from the .glb node tree when present, computed from the catalogue
##    footprint when not, so the bot assembles with no art at all.
##
## BOT SPACE (the one convention): +X forward, +Y up, +Z the bot's right. The origin
## is the chassis centre on the AXLE PLANE, which rides `RIDE_HEIGHT` above the
## floor. So the floor is at y = -0.11 and a catalogue `clearance_front` of 0.05
## puts the hull's underside at y = -0.06.
##
## Nothing here touches physics behaviour beyond mass and shape. Drive, weapon and
## damage all live elsewhere.

const RIDE_HEIGHT := 0.11

## Plate thickness in metres for catalogue thickness 1 to 4. Unit 1 is Stage 3's
## 0.020 m plate and each further unit adds 10 mm.
##
## A thicker plate grows INWARD. Its outer face stays `PLATE_PROUD` above the hull
## surface whatever the thickness, so armour changes mass and protection and never
## changes the silhouette or the ground game. This is not a detail: on a wedge, a
## 50 mm plate that grew outward would lift the ramp surface above an opponent's
## underside and the weapon could no longer get under anything (measured trap,
## docs/stage3-physics-notes.md section 5). The plates already overlap the hull and
## are collision excluded from it, so growing inward costs nothing.
const PLATE_BASE_THICKNESS := 0.020
const PLATE_THICKNESS_STEP := 0.010
const PLATE_PROUD := 0.022
## The .glb plates are authored at one thickness unit = 12 mm along X.
const PLATE_MODEL_UNIT := 0.012

var bot: Node = null
var id := ""
var spec: Dictionary = {}
var config: Dictionary = {}
var body: RigidBody3D = null
var model: Node3D = null
var sockets: Dictionary = {}
## Lowered by the skirts utility, reported by build_summary().
var clearance_drop := 0.0


func setup(owner: Node, chassis_id: String, chassis_spec: Dictionary,
		bot_config: Dictionary) -> void:
	bot = owner
	id = chassis_id
	spec = chassis_spec
	config = bot_config


# ---------------------------------------------------------------------------
# Catalogue readings
# ---------------------------------------------------------------------------
func footprint() -> Vector2:
	var raw: Array = spec.get("footprint", [0.9, 0.6]) as Array
	if raw.size() < 2:
		return Vector2(0.9, 0.6)
	return Vector2(float(raw[0]), float(raw[1]))


func half_len() -> float:
	return footprint().x * 0.5


func half_wid() -> float:
	return footprint().y * 0.5


func height() -> float:
	return float(spec.get("height", 0.2))


func clearance() -> float:
	return maxf(float(spec.get("clearance_front", 0.04)) - clearance_drop, 0.005)


## Underside and top of the hull in bot space.
func floor_y() -> float:
	return -RIDE_HEIGHT + float(spec.get("clearance_front", 0.04))


func top_y() -> float:
	return floor_y() + height()


func mass_kg() -> float:
	return float(spec.get("weight", 30.0))


func invertible() -> bool:
	return bool(spec.get("invertible", false))


func flip_resistance() -> float:
	return float(spec.get("flip_resistance", 1.0))


func tip_resistance() -> float:
	return float(spec.get("tip_resistance", 1.0))


func drive_fragility() -> float:
	return float(spec.get("drive_fragility", 1.0))


func turn_rate_factor() -> float:
	return float(spec.get("turn_rate_factor", 1.0))


func mount_weapon() -> String:
	return str(spec.get("mount_weapon", "front"))


## Centre of mass in bot space. `com_height` is measured from the FLOOR, so it
## comes down by the ride height to land in the body's own frame. `com_x` is the
## fore and aft bias: Stage 3's wedge sat 0.08 m behind the axle plane centre and
## that is what keeps a wedge's nose down under power.
func com_local() -> Vector3:
	return Vector3(com_x(), float(spec.get("com_height", 0.08)) - RIDE_HEIGHT, 0.0)


func com_x() -> float:
	return -0.08


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
func build(chassis_body: RigidBody3D, livery: Color) -> void:
	body = chassis_body
	for entry in shapes():
		var holder := CollisionShape3D.new()
		holder.shape = entry["shape"]
		holder.transform = entry.get("transform", Transform3D.IDENTITY)
		body.add_child(holder)
	_build_visual(livery)


## Extra collision, for the skirts and the rear wedge. They ride on the chassis
## body rather than being bodies of their own: brief section 12 caps the body
## count at chassis + six wheels + weapon + four panels, and a skirt that can be
## knocked off is not worth two more rigid bodies per bot.
func add_shape(shape: Shape3D, at: Transform3D) -> void:
	if body == null:
		return
	var holder := CollisionShape3D.new()
	holder.shape = shape
	holder.transform = at
	body.add_child(holder)


## Default: one convex hull from `hull_points()`. Chassis that are genuinely two
## solids (the tall tank) or round (the shell) override this.
func shapes() -> Array[Dictionary]:
	var shape := ConvexPolygonShape3D.new()
	shape.points = hull_points()
	return [{"shape": shape, "transform": Transform3D.IDENTITY}]


## The hand-built profile: a stack of rectangular rings, bottom to top. Two levels
## is a box; the sloped hulls add levels. `BotMeshes.loft_points` turns it into the
## convex hull's points and `BotMeshes.loft_mesh` into the fallback mesh, so the
## collider and the silhouette are the same list of numbers.
func levels() -> Array:
	return [
		{"y": floor_y(), "hx": half_len(), "hz": half_wid()},
		{"y": top_y(), "hx": half_len(), "hz": half_wid()},
	]


func hull_points() -> PackedVector3Array:
	return BotMeshes.loft_points(levels())


## The Stage 3 style fallback visual, used only when the .glb is missing.
func procedural_meshes() -> Array[Dictionary]:
	return [{"mesh": BotMeshes.loft_mesh(levels()),
		"transform": Transform3D.IDENTITY, "slot": "livery"}]


func _build_visual(livery: Color) -> void:
	model = PartVisuals.instantiate(id)
	if model != null:
		body.add_child(model)
		sockets = PartVisuals.read_sockets(model)
		PartVisuals.bind(model, livery)
		_on_model_bound()
		return
	# No art: the Stage 3 procedural hull, plus the emissive core block so the
	# build still reads the same way on screen.
	for entry in procedural_meshes():
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "Hull"
		mesh_instance.mesh = entry["mesh"]
		mesh_instance.transform = entry.get("transform", Transform3D.IDENTITY)
		mesh_instance.material_override = PartVisuals.slot_material(
			str(entry.get("slot", "livery")), livery)
		body.add_child(mesh_instance)
	var core := MeshInstance3D.new()
	core.name = "Core"
	core.mesh = BotMeshes.flat_box_mesh(Vector3(0.16, 0.07, 0.20))
	core.position = Vector3(com_x() - 0.10, minf(top_y() - 0.03, 0.04), 0.0)
	core.material_override = PartVisuals.slot_material("core_glow", livery)
	body.add_child(core)


## Hook for chassis with model parts to hide or hand over (the shell's ring).
func _on_model_bound() -> void:
	pass


# ---------------------------------------------------------------------------
# Sockets. Read from the model when it has them, computed when it does not.
# ---------------------------------------------------------------------------
func socket_point(socket_name: String, fallback: Vector3) -> Vector3:
	if sockets.has(socket_name):
		return sockets[socket_name]
	return fallback


## "front", "top" or "shell". Falls back to the chassis' catalogue `mount_weapon`
## when the asked for socket does not exist on this hull.
func weapon_socket(kind: String) -> Transform3D:
	var want := kind
	if want == "":
		want = preferred_weapon_mount()
	var name := "socket_weapon_" + want
	if not sockets.has(name):
		var mount := preferred_weapon_mount()
		if mount != want:
			return weapon_socket(mount)
	var origin := socket_point(name, _weapon_fallback(want))
	if want == "front":
		# THE WEDGE RULING (docs/graphics-models-notes.md section 8): on a hull with
		# a front ramp the armour plate bolts to the ramp FIRST and the weapon rides
		# on top of it, so the mount lifts along the ramp normal by the whole plate
		# stack. Miss this and the weapon hinges inside its own armour.
		var lift := front_armour_stack()
		if lift > 0.0:
			var a := weapon_rest_angle()
			origin += Vector3(-sin(a), cos(a), 0.0) * lift
	return Transform3D(Basis.IDENTITY, origin)


## Plate thickness plus the plate's raised step plus a few mm of air, which is what
## a front weapon has to clear on a ramped hull. Zero on a flat nose.
func front_armour_stack() -> float:
	if absf(weapon_rest_angle()) < 0.01:
		return 0.0
	var units := BuildRules.thickness_of(BuildRules.face_entry(config, "front"))
	return units * PLATE_MODEL_UNIT + 0.013 + 0.004


func preferred_weapon_mount() -> String:
	var mount := mount_weapon()
	if mount == "front_or_top":
		return "front"
	return mount


func _weapon_fallback(kind: String) -> Vector3:
	match kind:
		"top":
			return Vector3(half_len() * 0.1, top_y(), 0.0)
		"shell":
			return Vector3.ZERO
		_:
			return Vector3(half_len() * 0.85, floor_y() + height() * 0.3, 0.0)


## Wheel positions for a drive id, in bot space, on the axle plane.
func wheel_slots(drive_id: String) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var names := _wheel_socket_names(drive_id)
	var have_all := true
	for socket_name in names:
		if not sockets.has(socket_name):
			have_all = false
			break
	if have_all and not names.is_empty():
		for socket_name in names:
			var p: Vector3 = sockets[socket_name]
			out.append(Vector3(p.x, 0.0, p.z))
		return out
	# The catalogue is the fallback, and its rows are [x, z] pairs in this frame.
	var table: Dictionary = spec.get("wheel_slots", {}) as Dictionary
	var key := drive_id
	if not table.has(key):
		key = "4wd" if table.has("4wd") else str(table.keys()[0] if not table.is_empty() else "")
	var rows: Array = table.get(key, []) as Array
	for row_variant in rows:
		var row: Array = row_variant
		if row.size() >= 2:
			out.append(Vector3(float(row[0]), 0.0, float(row[1])))
	if out.is_empty():
		out.append(Vector3(half_len() * 0.6, 0.0, -half_wid()))
		out.append(Vector3(half_len() * 0.6, 0.0, half_wid()))
	return out


## Left before right, front before rear, which is the order the catalogue uses.
func _wheel_socket_names(drive_id: String) -> Array[String]:
	match drive_id:
		"2wd":
			return ["socket_wheel_2wd_rr", "socket_wheel_2wd_rl"]
		"6wd":
			return ["socket_wheel_fr", "socket_wheel_fl", "socket_wheel_mr",
				"socket_wheel_ml", "socket_wheel_rr", "socket_wheel_rl"]
		_:
			return ["socket_wheel_4wd_fr", "socket_wheel_4wd_fl",
				"socket_wheel_4wd_rr", "socket_wheel_4wd_rl"]


## Where an armour plate for a face sits, how big it is, and which way is out.
## `transforms` has two entries for the sides (one per flank) and one for
## everything else; `transform` is the first, for callers that only need one.
## The plate's local +X is OUTWARD, matching the .glb plates.
func armour_socket(face: String) -> Dictionary:
	var thickness := BuildRules.thickness_of(BuildRules.face_entry(config, face))
	var t := plate_thickness(thickness)
	var size := plate_size(face, t)
	var transforms: Array[Transform3D] = []
	for entry in _armour_anchors(face):
		var anchor: Vector3 = entry["point"]
		var basis: Basis = entry["basis"]
		transforms.append(Transform3D(basis, anchor + basis.x * (PLATE_PROUD - t * 0.5)))
	return {
		"transform": transforms[0] if not transforms.is_empty() else Transform3D.IDENTITY,
		"transforms": transforms,
		"size": size,
		"thickness": thickness,
		"thickness_m": t,
	}


func plate_thickness(units: float) -> float:
	return PLATE_BASE_THICKNESS + PLATE_THICKNESS_STEP * (units - 1.0)


## Plate box size in the PLATE's frame: x is the thickness, y and z are in plane.
func plate_size(face: String, t: float) -> Vector3:
	var face_height := minf(height() * 0.8, 0.30)
	match face:
		"front", "rear":
			return Vector3(t, face_height, half_wid() * 1.8)
		"sides":
			return Vector3(t, face_height, half_len() * 1.5)
		_:
			# Top: the plate's local y runs along the bot's length.
			return Vector3(t, half_len() * 1.6, half_wid() * 1.7)


## Anchor points on the hull surface plus the outward basis (+X out).
func _armour_anchors(face: String) -> Array[Dictionary]:
	var mid_y := floor_y() + height() * 0.5
	match face:
		"front":
			return [{"point": socket_point("socket_armour_front",
				Vector3(half_len(), mid_y, 0.0)), "basis": Basis.IDENTITY}]
		"rear":
			return [{"point": socket_point("socket_armour_rear",
				Vector3(-half_len(), mid_y, 0.0)), "basis": Basis(Vector3.UP, PI)}]
		"sides":
			return [
				{"point": socket_point("socket_armour_sides_r",
					Vector3(0.0, mid_y, half_wid())), "basis": Basis(Vector3.UP, -PI * 0.5)},
				{"point": socket_point("socket_armour_sides_l",
					Vector3(0.0, mid_y, -half_wid())), "basis": Basis(Vector3.UP, PI * 0.5)},
			]
		_:
			return [{"point": socket_point("socket_armour_top",
				Vector3(0.0, top_y(), 0.0)), "basis": Basis(Vector3.BACK, PI * 0.5)}]


## The angle the front mounted weapon rests at: along the hull's front ramp when it
## has one, flat when it does not. The flipper's whole geometry hangs off this.
func weapon_rest_angle() -> float:
	return 0.0


func utility_socket(index: int) -> Transform3D:
	var name := "socket_utility_%d" % index
	var fallback := Vector3(-half_len() * 0.6, top_y(), 0.0) if index == 0 \
		else Vector3(half_len() * 0.55, floor_y(), 0.0)
	return Transform3D(Basis.IDENTITY, socket_point(name, fallback))


func srimech_socket() -> Transform3D:
	return Transform3D(Basis.IDENTITY, socket_point("socket_srimech",
		Vector3(-half_len() * 0.84, top_y() - 0.01, 0.0)))


## The point the HUD's "front lip height" reads, and the AI's wedge test: the
## lowest, furthest forward point of the hull.
func front_lip_point() -> Vector3:
	return Vector3(half_len(), floor_y(), 0.0)


## True when the hull drives the same either way up (catalogue `invertible`).
func drives_inverted() -> bool:
	return invertible()


## Minimum wheel radius this hull needs. An invertible chassis has to have wheels
## that protrude BOTH ways (spec section 3), so a symmetric hull asks for a wheel
## larger than its half height. Everything else runs the standard 0.11 m wheel.
func wheel_radius_min() -> float:
	return FightTypes.WHEEL_RADIUS


## Multiplies the wheel motors' impulse limit. A hull with a bigger wheel scales it by
## the radius so the force at the tread stays the same (the wedge, hero hull pass).
func wheel_torque_scale() -> float:
	return 1.0


## The back face of the hull, in bot space (the rear wedge utility bolts here).
func rear_x() -> float:
	return -half_len()
