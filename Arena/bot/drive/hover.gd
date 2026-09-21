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
## MESHES (agent E). A skirt and four thruster pods: see docs/wave-p-d2-notes.md.
## Until then the skirt is drawn as a plain ring.

## How fast the cushion closes on its height, and how much of a g it has to do it.
const LIFT_RESPONSE_S := 0.1
const LIFT_MAX_G := 2.2
const LIFT_CLOSE_MS := 2.0
## The ring drawn in place of E's skirt.
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


## The cushion. A damped spring onto `hover_height` above the arena floor, faded
## by how upright the machine is and never allowed to pull downward: an upended
## hover has no lift at all and a thrown one comes down under gravity.
func support(chassis: RigidBody3D, dt: float) -> void:
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
