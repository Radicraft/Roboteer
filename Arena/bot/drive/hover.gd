extends BodilessDrive
## Hover thrusters (brief v5 section 9.5, Level 55): the fastest thing in the
## arena, no pushing power, it floats over the floor hazards and it flips easily.
##
## The cushion. `support()` holds the hull at the catalogue's `hover_height` above
## the arena floor with a damped spring and never blows downward, so the machine
## rides at a steady height, sinks when it is knocked above it and drops like a
## brick the moment the drive stops answering (a flame cook or a dead drive calls
## `stop()`, which does not call `support()`).
##
## No push. Thrust is a force on the hull like the walker's, but while the machine
## is leaning on another machine it keeps only `contact_grip` of it: the fans blow
## past an opponent rather than driving through one. Together with a `traction` of
## 0.35, which is the lateral grip term, that is a machine that is quick in a
## straight line, slides through its corners and cannot shove anything.
##
## Flips easily. `flip_factor` 0.55 multiplies the hull's flip and tip resistance,
## so a spinner throws a hover further than anything else, and the lift fades with
## the hull's "up", so once it is over it is a dead weight until it rights itself.
##
## Floats over spikes. `hazard_factor` 0.0: a floor hazard passes under it. The
## spikes still STAND in the way and can still bump a low riding hull about, which
## is the visible difference between floating over one and being immune to it.
##
## MESHES (agent E, wave P). `hover.glb` is the skirt and four ducted thruster
## pods, authored around a wedge's footprint with the skirt's TOP at y = 0, so it
## hangs straight off `floor_y()` and is scaled in X and Z to whatever hull it is
## under. It carries a `glow` mesh node in the throat of each pod, which is the
## slot agent F lights, and a `PartAnim` in HOVER rides the cushion: a bob on two
## beats, a lean that follows the road speed, and a skirt that brightens with the
## work the fans are doing. The plain ring is kept as the no-art fallback.

## How fast the cushion closes on its height, and how much of a g it has to do it.
const LIFT_RESPONSE_S := 0.1
const LIFT_MAX_G := 2.2
const LIFT_CLOSE_MS := 2.0
## How deep E's skirt hangs below `floor_y()`. It matches SKIRT_DEPTH in
## `Tools/blender/parts_drive.py`, which is where the model is authored: a
## hover rides 0.20 m up, and a shallow band under a hull that high is a picture
## frame with daylight under it.
const SKIRT_DEPTH := 0.115
## The footprint `hover.glb` is authored around; the model is scaled to the hull.
const SKIRT_MODEL_HALF_LEN := 0.45
const SKIRT_MODEL_HALF_WID := 0.30
## The ring drawn in place of E's skirt when the model is missing.
const SKIRT_HEIGHT := 0.05
const SKIRT_SEGMENTS := 16


func setup(owner: Node, chassis_module: ChassisBase, drive_spec: Dictionary,
		drive_id: String) -> void:
	super.setup(owner, chassis_module, drive_spec, drive_id)
	# The cushion is the ride height, and it has to clear whatever the hull needs
	# underneath it (an invertible hull asks for a tall wheel, spec section 3).
	radius = maxf(hover_height(), hull.wheel_radius_min())


func hover_height() -> float:
	return maxf(float(spec.get("hover_height", 0.2)), 0.05)


func build_stance() -> void:
	super.build_stance()
	if _add_skirt_model():
		return
	var mesh := MeshInstance3D.new()
	mesh.name = "HoverSkirt"
	var ring := CylinderMesh.new()
	ring.top_radius = hull.half_wid() * 1.02
	ring.bottom_radius = hull.half_wid() * 1.08
	ring.height = SKIRT_HEIGHT
	ring.radial_segments = SKIRT_SEGMENTS
	mesh.mesh = ring
	mesh.position = Vector3(0.0, hull.floor_y() - SKIRT_HEIGHT * 0.5, 0.0)
	mesh.material_override = PartVisuals.slot_material("dark_metal", bot.livery)
	bot.chassis.add_child(mesh)


## E's skirt and pods, scaled to this hull and hung off its underside. False when
## the model is missing, which drops through to the plain ring above.
func _add_skirt_model() -> bool:
	var model := PartVisuals.instantiate("hover")
	if model == null:
		return false
	model.name = "HoverSkirt"
	model.position = Vector3(0.0, hull.floor_y(), 0.0)
	model.scale = Vector3(
		maxf(hull.half_len() / SKIRT_MODEL_HALF_LEN, 0.4), 1.0,
		maxf(hull.half_wid() / SKIRT_MODEL_HALF_WID, 0.4))
	bot.chassis.add_child(model)
	PartVisuals.bind(model, bot.livery)
	var anim := PartAnim.new()
	anim.name = "Cushion"
	anim.configure(model, PartAnim.Mode.HOVER)
	model.add_child(anim)
	return true


## AIR TRIM (systems gauntlet D5). A hover is the easiest machine to throw and has no
## wheels to land on, so a throw brought it down on its top plate: 0.9 of condition per
## upside-down landing from 1 m against a 4WD's 0.1 (the 4WD lands on its wheels), and
## three to five of those component-killed it inside 30 s without a weapon hit. Its fans
## still work in the air, so while it is clearly airborne they trim it back toward level,
## from any attitude short of fully upside down. It still flies further than anything
## else (flip_factor untouched); it just tends to come down the right way up.
const AIR_TRIM_CLEAR_M := 0.2
const AIR_TRIM_RATE := 9.0
const AIR_TRIM_RESPONSE_S := 0.12


func _air_trim(chassis: RigidBody3D, dt: float) -> void:
	if chassis.global_position.y < hover_height() + AIR_TRIM_CLEAR_M:
		return
	var tilt_axis := chassis.global_basis.y.cross(Vector3.UP)
	if tilt_axis.length() < 0.05:
		# Level (nothing to do) or exactly upside down (no preferred way round): roll
		# about the nose, which is how the flipper threw it.
		if upright_amount(chassis) > 0.0:
			return
		tilt_axis = flat_forward(chassis)
	var want := tilt_axis.normalized() * AIR_TRIM_RATE
	var blend := clampf(dt / AIR_TRIM_RESPONSE_S, 0.0, 1.0) * clampf(power_scale(), 0.0, 1.0)
	var av := chassis.angular_velocity
	chassis.angular_velocity = Vector3(
		lerpf(av.x, want.x, blend), av.y, lerpf(av.z, want.z, blend))


## The cushion. A damped spring onto `hover_height` above the arena floor, faded
## by how upright the machine is and never allowed to pull downward: an upended
## hover has no lift at all and a thrown one comes down under gravity.
func support(chassis: RigidBody3D, dt: float) -> void:
	_air_trim(chassis, dt)
	var up := clampf(upright_amount(chassis), 0.0, 1.0)
	if up <= 0.0:
		return
	var y := chassis.global_position.y
	var want_climb := clampf((hover_height() - y) / LIFT_RESPONSE_S,
		-LIFT_CLOSE_MS, LIFT_CLOSE_MS)
	var accel := clampf((want_climb - chassis.linear_velocity.y) / LIFT_RESPONSE_S,
		-LIFT_MAX_G * 9.8, LIFT_MAX_G * 9.8) + 9.8
	# A cushion stiff enough that the machine holds its height whatever it is
	# carrying. It has to be: the plates and the weapon are bodies of their own on
	# joints, and how much of their weight arrives at the hull is a solver
	# question, so a soft spring settles wherever the sag leaves it (measured
	# 2026-09-21: 0.139 m under a cushion asked to hold 0.20, then 0.246 m when the
	# force was worked out against the whole machine instead of the hull).
	if accel <= 0.0:
		return
	apply_at_com(chassis, Vector3.UP * accel * machine_mass() * up)
	level_body(chassis, dt, 1.0)
