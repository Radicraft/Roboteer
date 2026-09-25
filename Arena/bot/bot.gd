class_name Bot extends Node3D
## A fighting robot, assembled from the catalogue (docs/stage4-spec.md section 3).
## A chassis rigid body with wheels, a weapon and armour faces hung off it by
## joints. Damage is joint failure (brief section 6), so every part is a real body
## and "destroyed" means the joint goes away.
##
## API contract: docs/stage3-spec.md section 4, unchanged for R and C. `setup`,
## then `apply_input` once per physics tick BEFORE the step, then `condition()` and
## the signals. Stage 4 adds `register_part`, `weapon_status`, `weapon_readiness`,
## `opponent_damage_tick`, `disrupt` and `build_summary`.
##
## AXES (the one convention everyone needs). The bot's local frame is
##   +X forward (the nose), +Y up, +Z the bot's right-hand side.
## `heading` is a world XZ vector: Vector2(x, z), length 0..1. Desired world
## direction is Vector3(heading.x, 0, heading.y); the bot turns toward it.
##
## MODULES. bot.gd owns the body list, damage and the queries; everything else is
## a module it loads by catalogue id:
##   bot/chassis/<id>.gd   hull collision, hull visual, sockets      (ChassisBase)
##   bot/drive/<id>.gd     wheels, hinges, steering                  (DriveBase)
##   bot/weapons/<id>.gd   the weapon's bodies and its behaviour     (WeaponBase)
## A missing chassis or drive script falls back to its base class; a missing weapon
## script fits an inert plate and logs. Nothing about a config can stop a fight.
##
## API DEVIATION from the spec text, on instruction: `opponent_relative` is a plain
## Dictionary VAR that R writes each tick, not a method. Read it as
## `bot.opponent_relative["distance"]`. `opponent_relative_dict()` returns the same.

signal damage_event(info: Dictionary)
signal part_detached(part: String)
signal inverted_changed(is_inverted: bool)
signal weapon_fired()

# ---------------------------------------------------------------------------
# Layout and tuning. Chassis local space, origin on the wheel-axle plane, which
# rides `ride_height()` above the floor when the bot is level.
# ---------------------------------------------------------------------------
const RIDE_HEIGHT := 0.11                   # the standard wheel radius

## THE MASS SCALE, and why it exists.
##
## The catalogue's kilograms are the DESIGN budget: 100 kg buys a chassis, a drive,
## a weapon, two utility parts and four armour faces, and that is the number the
## player sees. The SIMULATION runs at 0.52 of those kilograms, because every
## impulse in the game was measured at that scale: Stage 3's signed off wedge
## weighed 42.8 kg simulated and prices at 81.5 kg in the catalogue, and its all
## steel opponent weighed 48.0 kg against 92.6 kg priced, so both ratios are 0.52
## to within a percent. Running the catalogue numbers raw would double every
## contact impulse (the BREAK_MIN / BREAK_MAX table is calibrated against the old
## masses) and would leave a 115 N s pneumatic throw lifting a 93 kg bot by 78 mm
## instead of 780 mm. The scale is UNIFORM, so heavy builds are still heavy
## relative to light ones, which is the property the game actually trades on.
const MASS_SCALE := 0.52

const CHASSIS_FRICTION := 0.35
const PANEL_FRICTION := 0.5

## Self righting. Scaled by the build's mass so a 90 kg bot is not righted by a
## flick, and by the hull's flip and tip resistance.
const SRIMECH_IMPULSE := 150.0
const SRIMECH_TORQUE := 60.0
const SRIMECH_REFERENCE_MASS := 42.8

## Armour break thresholds scale with plate thickness (spec section 3).
const THICKNESS_THRESHOLD_BASE := 0.7
const THICKNESS_THRESHOLD_STEP := 0.3

const CHASSIS_SCRIPTS := "res://bot/chassis/%s.gd"
const DRIVE_SCRIPTS := "res://bot/drive/%s.gd"
const WEAPON_SCRIPTS := "res://bot/weapons/%s.gd"
const INERT_WEAPON := "res://bot/weapons/inert_weapon.gd"

# ---------------------------------------------------------------------------
# Public state (spec section 4)
# ---------------------------------------------------------------------------
var bot_id: String = ""
var team: int = 0
var chassis: RigidBody3D = null
var gas_charges: int = FightTypes.FLIPPER_CHARGES
var livery: Color = FightTypes.LIVERY_PLAYER
## Filled by R every physics tick: {"position": Vector3, "distance": float}
var opponent_relative: Dictionary = {"position": Vector3.ZERO, "distance": 0.0}

## The modules. R and C may read them; only the Bot drives them.
var chassis_module: ChassisBase = null
var drive_module: DriveBase = null
var weapon: WeaponBase = null
## BuildRules' complaints about this config. The bot still assembles.
var build_errors: Array[String] = []

# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------
var damage: BotDamage = null
var _rng: RandomNumberGenerator = null
var _config: Dictionary = {}
var _materials: Dictionary = {}             # face -> material name
var _utility: Array[String] = []

var _parts: Array[BotPart] = []
var _panels: Dictionary = {}                # "armour_front" -> Array[BotPart]
var _panel_joints: Dictionary = {}          # body -> Generic6DOFJoint3D
var _visuals: Dictionary = {}               # condition key -> Array[Node3D]
var _joints_root: Node3D = null
var _srimech_mesh: Node3D = null

var _frozen := false
## Ticks this machine has simulated (see `_physics_process`). Never counts a held frame.
var _sim_ticks: int = 0
var _weapon_jammed := false
var _assembled := false
var _srimech_cooldown := 0.0
var _was_inverted := false
var _speed_window: PackedFloat32Array = PackedFloat32Array()
var _speed_head := 0
var _speed_filled := false
var _last_input: Dictionary = FightTypes.empty_input()
var _fire_was := false
var _dt := 1.0 / float(FightTypes.TICK_HZ)

## Utility effects, resolved once at build time.
var _has_srimech := false
var _rear_damage_factor := 1.0
var _speed_factor := 1.0
var _spin_up_factor := 1.0
var _downforce := 0.0
var _com_shift := 0.0
var _has_scoop := false
## Wave P, the overcharge core: what this machine's blows are multiplied by, and
## how much core condition per second it cooks off while its weapon is at full.
var _hit_factor := 1.0
var _cook_rate := 0.0
var _cook_owed := 0.0
## Wave P, reactive armour: impulses to hand out next `_physics_process`, queued
## from inside the physics step where nothing may be pushed.
var _knockbacks: Array[Dictionary] = []
## Which `utility_socket(i)` mounts are already taken, so two fitted parts never
## come out at the same point. See `_claim_utility_socket`.
var _utility_sockets_used: Dictionary = {}

## Flamethrower disruption timers (spec section 4).
var _disrupt_weapon := 0.0
var _disrupt_drive := 0.0

## Largest contact impulse this bot has seen, for tuning only. Never gameplay.
var debug_max_impulse := 0.0
var debug_contacts := false
## Tuning only: weapons print what they did with each press.
var debug_weapon := false


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
func setup(bot_config: Dictionary, team_index: int, rng: RandomNumberGenerator) -> void:
	_config = bot_config
	_rng = rng if rng != null else RandomNumberGenerator.new()
	team = team_index
	bot_id = str(bot_config.get("id", "bot-%d" % team_index))
	livery = _livery_colour(bot_config, team_index)

	build_errors = BuildRules.validate(bot_config)
	for problem in build_errors:
		_warn("%s: %s" % [bot_id, problem])

	for face in BotDamage.ARMOUR_FACES:
		var entry := BuildRules.face_entry(bot_config, face)
		_materials[face] = str(entry.get("material", "steel"))
	for id_variant in bot_config.get("utility", []):
		_utility.append(str(id_variant))

	var window := int(round(FightTypes.IMMOBILE_WINDOW_S * FightTypes.TICK_HZ))
	_speed_window = PackedFloat32Array()
	_speed_window.resize(maxi(window, 1))
	_speed_window.fill(99.0)

	_joints_root = Node3D.new()
	_joints_root.name = "Joints"

	_make_chassis_module()
	_resolve_utility()
	_build_chassis()
	add_child(_joints_root)
	_build_drive()
	_build_damage()
	_build_weapon()
	_build_armour()
	_build_utility()

	_assembled = true
	_exclude_internal_collisions()
	_apply_initial_damage()
	set_physics_process(true)


func _livery_colour(bot_config: Dictionary, team_index: int) -> Color:
	var hex := str(bot_config.get("livery", ""))
	if hex != "" and Color.html_is_valid(hex):
		return Color.html(hex)
	return FightTypes.LIVERY_PLAYER if team_index == 0 else FightTypes.LIVERY_OPPONENT


## Arena style warning: the same shape R's log messages use, so a bad build shows
## up in the same place as everything else that went wrong. ONCE per message per
## process: the workshop rebuilds a bot on every keystroke and the assembly test
## builds 232 of them, and a warning repeated two thousand times is not a log, it
## is a denial of service on whoever has to read it.
static var _warned: Dictionary = {}


func _warn(text: String) -> void:
	if _warned.has(text):
		return
	_warned[text] = true
	push_warning("[bot] " + text)
	print("[bot] ", text)


func _load_module(path_format: String, id: String) -> Script:
	var path := path_format % id
	if id == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Script


func _make_chassis_module() -> void:
	var id := str(_config.get("chassis", "wedge"))
	var spec := PartsCatalogue.chassis(id)
	if spec.is_empty():
		_warn("unknown chassis \"%s\", falling back to the wedge" % id)
		id = "wedge"
		spec = PartsCatalogue.chassis(id)
	var script := _load_module(CHASSIS_SCRIPTS, id)
	if script == null:
		_warn("no chassis module for \"%s\", using the plain hull" % id)
		chassis_module = ChassisBase.new()
	else:
		chassis_module = script.new()
	chassis_module.setup(self, id, spec, _config)


## Utility effects that change how the chassis is BUILT have to be resolved before
## it is built: the skirts lower the clearance and the counterweight moves the
## centre of mass.
func _resolve_utility() -> void:
	for id in _utility:
		var spec := PartsCatalogue.utility(id)
		if spec.is_empty():
			continue
		match str(spec.get("effect", "")):
			"self_right":
				_has_srimech = true
			"rear_damage_factor":
				_rear_damage_factor = float(spec.get("value", 0.6))
			"clearance":
				chassis_module.clearance_drop = absf(float(spec.get("value", -0.02)))
			"downforce":
				_downforce = float(spec.get("value", 1.5))
				_speed_factor *= float(spec.get("speed_factor", 0.8))
			"scoop":
				_has_scoop = true
			"battery":
				_spin_up_factor = float(spec.get("spin_up_factor", 0.7))
			"counterweight":
				_com_shift = float(spec.get("com_shift", -0.08))
			"overcharge":
				# Wave P, Level 90. Faster spin up and harder blows, and the core
				# runs hot the whole time the weapon is at full: see `_cook_core`.
				_spin_up_factor = minf(_spin_up_factor,
					float(spec.get("spin_up_factor", 0.55)))
				_hit_factor = float(spec.get("hit_factor", 1.25))
				_cook_rate = float(spec.get("cook_rate", 0.004))


func _build_chassis() -> void:
	chassis = BotPart.new()
	chassis.name = "Chassis"
	chassis.part_key = "chassis"
	chassis.part_kind = "chassis"
	chassis.material_name = str(_materials.get("top", "steel"))
	chassis.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	chassis.center_of_mass = chassis_module.com_local() + Vector3(_com_shift, 0.0, 0.0)
	chassis.continuous_cd = true
	chassis.physics_material_override = _make_material(CHASSIS_FRICTION)
	# The hull carries the utility parts' weight: they are visuals and extra
	# collision on this body, never bodies of their own, which is what keeps the
	# whole bot inside brief section 12's part budget.
	var mass_kg := chassis_module.mass_kg()
	for id in _utility:
		mass_kg += float(PartsCatalogue.utility(id).get("weight", 0.0))
	register_part(chassis, "chassis", "chassis", mass_kg)
	chassis_module.build(chassis, livery)


func _build_drive() -> void:
	var id := str(_config.get("drive", "4wd"))
	var spec := PartsCatalogue.drive(id)
	if spec.is_empty():
		_warn("unknown drive \"%s\", falling back to 4wd" % id)
		id = "4wd"
		spec = PartsCatalogue.drive(id)
	var script := _load_module(DRIVE_SCRIPTS, id)
	drive_module = script.new() if script != null else DriveBase.new()
	drive_module.setup(self, chassis_module, spec, id)
	drive_module.build()


func _build_damage() -> void:
	var keys := drive_module.condition_keys
	damage = BotDamage.new()
	damage.owner_bot = self
	damage.setup(_config.get("damage", {}) as Dictionary, keys.size(), keys)
	for face in BotDamage.ARMOUR_FACES:
		var thickness := BuildRules.thickness_of(BuildRules.face_entry(_config, face))
		damage.threshold_scale["armour_" + face] = THICKNESS_THRESHOLD_BASE \
			+ THICKNESS_THRESHOLD_STEP * thickness


func _build_weapon() -> void:
	var id := str(_config.get("weapon", ""))
	var spec := PartsCatalogue.weapon(id).duplicate()
	if spec.is_empty():
		_warn("unknown weapon \"%s\", fitting an inert plate" % id)
		spec = {"kind": "ram", "reach": 0.2, "weight": 8.0, "height_band": "floor"}
	spec["id"] = id
	var script := _load_module(WEAPON_SCRIPTS, id)
	if script == null:
		_warn("no weapon module for \"%s\" yet, fitting an inert plate" % id)
		script = load(INERT_WEAPON) as Script
	weapon = script.new()
	weapon.mass_kg = float(spec.get("weight", 8.0))
	# Only gas weapons carry charges. Everything else reads zero, which is what the
	# HUD's charge pip shows when there is nothing to count.
	gas_charges = int(spec.get("charges", 0))
	for id_variant in _utility:
		var utility_spec := PartsCatalogue.utility(str(id_variant))
		if str(utility_spec.get("effect", "")) == "battery":
			gas_charges += int(utility_spec.get("extra_charges", 0))
	var mount := str(spec.get("mount", ""))
	if mount == "":
		mount = _mount_for(spec)
	weapon.build(self, chassis_module.weapon_socket(mount), spec, _rng)


## Where a weapon mounts. The WEAPON decides first and the hull second: a flipper
## has to be at floor level to work at all, so it goes on the nose even on a Tall
## Tank whose catalogue line says "top". Overhead weapons take the deck wherever
## there is one, and the full body spinner takes the shell's spin axis.
func _mount_for(spec: Dictionary) -> String:
	var mount := chassis_module.mount_weapon()
	if mount == "shell" or str(spec.get("kind", "")) == "fbs":
		return "shell"
	var band := str(spec.get("height_band", "mid"))
	# ONLY a weapon that works DOWNWARD takes the deck: the axe, which swings over
	# its own nose, and the crusher, whose jaw hangs down in front of it.
	#
	# There used to be a third rule here, "a mid height weapon on a hull built for
	# overhead mounting uses the deck, that is the Tall Tank's whole character".
	# Measured 2026-09-16 and deleted: the Tall Tank's deck socket is 0.405 m up, so
	# a horizontal spinner bolted there spans 0.67 to 0.73 m above the arena floor,
	# a saw 0.57 to 0.88 and a flame nozzle 0.66 to 0.75 — and the TALLEST machine in
	# the catalogue only reaches 0.48 m. Those three could not touch anything in the
	# game. It is half of "the weapons are not all responding once built in the
	# workshop": they spin up, they read READY, and they sweep over the opponent's
	# roof all fight. A mid or floor band weapon goes on the nose on every hull.
	var wants_top := band == "high" or str(spec.get("kind", "")) == "crusher"
	if wants_top and chassis_module.sockets.has("socket_weapon_top"):
		return "top"
	return "front"


func _build_armour() -> void:
	for face in BotDamage.ARMOUR_FACES:
		var socket := chassis_module.armour_socket(face)
		var transforms: Array = socket["transforms"]
		if transforms.is_empty():
			continue
		var size: Vector3 = socket["size"]
		var face_mass := BuildRules.face_weight(_config, face)
		var per := face_mass / float(transforms.size())
		for at_variant in transforms:
			_add_panel("armour_" + face, face, size, at_variant as Transform3D, per)


func _add_panel(key: String, face: String, size: Vector3, at: Transform3D,
		mass_kg: float) -> void:
	var material_name := str(_materials.get(face, "steel"))
	var panel := BotPart.new()
	var node_name := "Panel" + key.substr(7).capitalize()
	if face == "sides":
		node_name += "R" if at.origin.z > 0.0 else "L"
	panel.name = node_name
	panel.part_key = key
	panel.part_kind = "armour"
	panel.material_name = material_name
	panel.physics_material_override = _make_material(PANEL_FRICTION)
	panel.transform = at

	var plate_size := size
	if face == "front" and _has_scoop:
		plate_size = Vector3(size.x, size.y, size.z * 1.15)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = plate_size
	shape.shape = box
	panel.add_child(shape)
	_add_panel_visual(panel, face, plate_size, material_name)

	register_part(panel, key, "armour", maxf(mass_kg, 0.2))
	if not _panels.has(key):
		_panels[key] = []
	(_panels[key] as Array).append(panel)
	weld(panel)


func _add_panel_visual(panel: BotPart, face: String, size: Vector3,
		material_name: String) -> void:
	# One plate model per material family: cut steel and moulded plastic do not look
	# alike at this distance (docs/graphics-models-notes.md section 3).
	var model_id := "plate_flat"
	if face == "front":
		model_id = "plate_sloped"
	elif material_name == "hdpe":
		model_id = "plate_flat_hdpe"
	elif material_name == "reactive":
		# Wave P (agent E). Reactive armour is a grid of separate cassettes on a
		# backing plate, not a sheet, and that IS the explanation of its
		# catalogue row: excellent against a spinner, poor against a saw. It
		# reads as the same swap the hdpe branch above makes, on the same rule
		# (the front face keeps the sloped plate on every material).
		model_id = "plate_flat_reactive"
	if face == "front" and _has_scoop:
		model_id = "scoop"
	# Wave A (models): a chassis-FITTED plate, when one exists, is authored at its
	# face's real size with its outer face on its own origin, so it goes on at scale 1
	# and its bevels and bolts stay round (the generic plate is scaled to every face,
	# 0.33 x 0.6 on a wedge flank). Visual only: the collision box above is unchanged,
	# and the outer face lands where the box's outer face is (thicker armour grows
	# inward, ChassisBase.PLATE_PROUD). docs/wave-a-models-notes.md section 4.
	var fitted := "" if model_id == "scoop" else _fitted_plate_id(face, material_name)
	if fitted != "":
		var fitted_model := PartVisuals.instantiate(fitted)
		if fitted_model != null:
			fitted_model.position = Vector3(size.x * 0.5, 0.0, 0.0)
			panel.add_child(fitted_model)
			PartVisuals.bind(fitted_model, livery, {
				"steel": PartVisuals.armour_material(material_name, livery)})
			return
	var model := PartVisuals.instantiate(model_id)
	if model != null:
		if model_id == "scoop":
			# The scoop is authored pointing forward from its own mount, not as a
			# plate, so it is turned to lie along the plate's outward axis.
			model.transform = Transform3D(Basis(Vector3.BACK, PI * 0.5),
				Vector3(-size.x * 0.5, 0.0, 0.0))
		else:
			model.scale = Vector3(size.x / ChassisBase.PLATE_MODEL_UNIT,
				size.y / 0.30, size.z / 0.50)
		panel.add_child(model)
		# plate_flat_hdpe already wears the hdpe slot; the others carry the face
		# material on their `steel` surface.
		PartVisuals.bind(model, livery, {
			"steel": PartVisuals.armour_material(material_name, livery)})
		return
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = BotMeshes.flat_box_mesh(size)
	mesh_instance.material_override = PartVisuals.armour_material(material_name, livery)
	panel.add_child(mesh_instance)


## `plate_<chassis>_<face>[_hdpe]` when that model exists, else "". Reactive armour
## keeps its cassette plate, which is a different object, not a different fit.
func _fitted_plate_id(face: String, material_name: String) -> String:
	if material_name == "reactive" or chassis_module == null:
		return ""
	var base := "plate_%s_%s" % [chassis_module.id, face]
	if material_name == "hdpe" and PartVisuals.has_model(base + "_hdpe"):
		return base + "_hdpe"
	if PartVisuals.has_model(base):
		return base
	return ""


## Utility parts are visuals plus extra collision on the hull, plus the effects
## resolved in `_resolve_utility`. See `_build_chassis` for why they are not bodies.
func _build_utility() -> void:
	for id in _utility:
		var spec := PartsCatalogue.utility(id)
		if spec.is_empty():
			continue
		match str(spec.get("effect", "")):
			"self_right":
				_fit_srimech()
			"rear_damage_factor":
				_fit_rear_wedge(id)
			"clearance":
				_fit_skirts(id)
			"scoop":
				pass                                  # fitted with the front plate
			_:
				# Downforce magnets belong low and forward (socket 1); everything
				# else rides the rear deck (socket 0). `_claim_utility_socket` is
				# what stops the second one landing inside the first.
				_fit_utility_visual(id, _claim_utility_socket(
					1 if str(spec.get("effect", "")) == "downforce" else 0))


## Hand out a utility mount, never the same one twice.
##
## Measured 2026-09-16, and it is the "building screen customisations are not all
## showing" report: the spare battery and the counterweight both took
## `utility_socket(0)` and came out at the identical point, (-0.27, 0.20, 0) on a
## wedge, one model wholly inside the other, so a player who fitted both saw one
## part. Skirts and magnets collided the same way on socket 1. The hulls carry two
## utility mounts, the builder has two utility slots, and now the two line up.
func _claim_utility_socket(preferred: int) -> Transform3D:
	var index := preferred
	if _utility_sockets_used.has(index):
		index = 1 - index
	if _utility_sockets_used.has(index):
		# Three visuals on a two-socket hull cannot happen while BuildRules caps the
		# slots at two, but a config is not obliged to be legal, so nudge rather
		# than stack.
		var at := chassis_module.utility_socket(preferred)
		var bumped: int = int(_utility_sockets_used.size())
		return Transform3D(at.basis, at.origin
			+ Vector3(0.0, 0.0, 0.10 * float(bumped)))
	_utility_sockets_used[index] = true
	return chassis_module.utility_socket(index)


func _fit_srimech() -> void:
	var at := chassis_module.srimech_socket()
	var model := PartVisuals.instantiate("srimech")
	if model == null:
		model = MeshInstance3D.new()
		(model as MeshInstance3D).mesh = BotMeshes.flat_box_mesh(Vector3(0.26, 0.025, 0.07))
		(model as MeshInstance3D).material_override = PartVisuals.slot_material(
			"steel", livery)
		model.transform = Transform3D(Basis(Vector3.BACK, deg_to_rad(-14.0)),
			at.origin + Vector3(0.0, 0.02, 0.0))
	else:
		model.transform = at
		PartVisuals.bind(model, livery)
	_srimech_mesh = model
	# It rides on the top plate when there is one, so it leaves with the plate.
	var tops: Array = _panels.get("armour_top", [])
	if not tops.is_empty():
		var plate: BotPart = tops[0]
		model.transform = plate.transform.affine_inverse() * model.transform
		plate.add_child(model)
	else:
		chassis.add_child(model)


func _fit_rear_wedge(id: String) -> void:
	var at := Transform3D(Basis.IDENTITY, Vector3(-chassis_module.half_len(),
		chassis_module.floor_y() + 0.03, 0.0))
	_fit_utility_visual(id, at)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.20, 0.06, chassis_module.half_wid() * 1.6)
	chassis_module.add_shape(shape, Transform3D(Basis.IDENTITY,
		at.origin + Vector3(-0.08, 0.0, 0.0)))


func _fit_skirts(id: String) -> void:
	var at := _claim_utility_socket(1)
	_fit_utility_visual(id, at)
	# A thin lip all the way round, 0.02 m below the hull, so nothing gets under.
	var shape := BoxShape3D.new()
	shape.size = Vector3(chassis_module.half_len() * 1.7, 0.02,
		chassis_module.half_wid() * 2.0)
	chassis_module.add_shape(shape, Transform3D(Basis.IDENTITY,
		Vector3(0.0, chassis_module.floor_y() - 0.01, 0.0)))


func _fit_utility_visual(id: String, at: Transform3D) -> Node3D:
	var model := PartVisuals.instantiate(id)
	if model == null:
		return null
	model.transform = at
	chassis.add_child(model)
	PartVisuals.bind(model, livery)
	return model


# ---------------------------------------------------------------------------
# The module facing API. Chassis, drive and weapon modules call these.
# ---------------------------------------------------------------------------
## Take ownership of a body: layers, contact reporting, mass and the damage key.
## `mass_kg` is in CATALOGUE kilograms; the simulation scale is applied here so
## every module can talk in the units the player sees. Weapons call this for every
## body they build, with part_kind "weapon".
func register_part(body: RigidBody3D, part_key: String, part_kind: String,
		mass_kg: float) -> void:
	var part := body as BotPart
	if part == null:
		_warn("register_part needs a BotPart, got %s" % body)
		return
	part.owner_bot = self
	part.part_key = part_key
	part.part_kind = part_kind
	part.mass = maxf(mass_kg * MASS_SCALE, 0.1)
	part.collision_layer = FightTypes.LAYER_BOT
	part.collision_mask = FightTypes.MASK_BOT
	part.contact_monitor = true
	# 24, not Stage 3's 6. The cap is not a budget: above it the engine reports an
	# ARBITRARY SUBSET of the contacts, and which ones depends on recycled RIDs, so
	# two identical fights can report different damage. A flat wedge landing on its
	# belly already produces four points and a spinner hit on a plate produces
	# more. `BotPart._integrate_forces` sums per collider, so a higher cap costs a
	# few additions and buys determinism (flagged by R2, 2026-09-13).
	part.max_contacts_reported = 24
	part.can_sleep = false
	if part.get_parent() == null:
		add_child(part)
	if not _parts.has(part):
		_parts.append(part)
	if _assembled:
		for other in _parts:
			if other != part:
				part.add_collision_exception_with(other)


## Joints live under one node so nothing has to walk the body list to find them.
func add_joint(joint: Joint3D) -> void:
	if _joints_root == null:
		return
	_joints_root.add_child(joint)


## Lock a body rigidly to the chassis: the armour plates and any fixed weapon
## (the ram, the inert fallback) hang off one of these, and it is the joint that
## fails when the part is destroyed.
func weld(body: RigidBody3D) -> Generic6DOFJoint3D:
	var joint := Generic6DOFJoint3D.new()
	joint.name = "Joint" + String(body.name)
	joint.transform = body.transform
	add_joint(joint)
	joint.node_a = joint.get_path_to(chassis)
	joint.node_b = joint.get_path_to(body)
	for axis in ["x", "y", "z"]:
		joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
		for p in [Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT,
				Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT,
				Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,
				Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT]:
			joint.call("set_param_" + axis, p, 0.0)
	joint.exclude_nodes_from_collision = true
	_panel_joints[body] = joint
	return joint


## A visual that belongs to a condition key and leaves when that key hits zero
## (the tracks' belts). Not a body, so it never takes a hit of its own.
func register_visual(key: String, node: Node3D) -> void:
	if not _visuals.has(key):
		_visuals[key] = []
	(_visuals[key] as Array).append(node)


func emit_weapon_fired() -> void:
	emit_signal("weapon_fired")


## Wave P: a drive with no wheel bodies (the walker, the hover) has nowhere to put
## its catalogue kilograms, so they go on the hull, exactly as a utility part's do.
## Called from the drive module's `build()`, which runs after the hull is
## registered. `kg` is CATALOGUE kilograms; the simulation scale is applied here.
func add_hull_mass(kg: float) -> void:
	if chassis == null or kg <= 0.0:
		return
	chassis.mass = maxf(chassis.mass + kg * MASS_SCALE, 0.1)


func spin_up_factor() -> float:
	return _spin_up_factor


func speed_factor() -> float:
	return _speed_factor


## What this machine's blows are multiplied by (the overcharge core, wave P). Read
## by the VICTIM when it works out what a contact took off, and by this bot when
## its own weapon chews at something, so it covers every weapon in the catalogue
## without a weapon module having to know the part exists.
func hit_factor() -> float:
	return _hit_factor


func flip_resistance() -> float:
	if chassis_module == null:
		return 1.0
	var drive_factor := drive_module.flip_factor() if drive_module != null else 1.0
	return chassis_module.flip_resistance() * drive_factor


func tip_resistance() -> float:
	if chassis_module == null:
		return 1.0
	var drive_factor := drive_module.flip_factor() if drive_module != null else 1.0
	return chassis_module.tip_resistance() * drive_factor


func ride_height() -> float:
	return drive_module.radius if drive_module != null else RIDE_HEIGHT


func total_mass() -> float:
	var total := 0.0
	for part in _parts:
		if is_instance_valid(part) and not part.detached:
			total += part.mass
	return total


# ---------------------------------------------------------------------------
# Input and drive
# ---------------------------------------------------------------------------
func apply_input(inp: Dictionary) -> void:
	_last_input = inp
	if _frozen:
		return
	var heading: Vector2 = inp.get("heading", Vector2.ZERO)
	var secondary := bool(inp.get("secondary", false))
	# `turn` is optional: the twin-stick scheme's pure pivot. Every other caller
	# leaves it out and nothing changes.
	var turn := clampf(float(inp.get("turn", 0.0)), -1.0, 1.0)
	if _disrupt_drive > 0.0:
		drive_module.stop()
	else:
		drive_module.drive(heading, secondary, _dt, turn)
	if weapon != null and _disrupt_weapon <= 0.0 and not _weapon_jammed:
		# `pressed` is the level, `fired` the rising edge. Stage 3's flipper read
		# the level and let its own cooldown gate repeats, so it still does; an axe
		# or a crusher wants the edge, which is why both are passed.
		var fire := bool(inp.get("fire", false))
		weapon.apply_input(fire, fire and not _fire_was, _dt)
		_fire_was = fire
	else:
		_fire_was = bool(inp.get("fire", false))
	if secondary:
		_try_secondary()


## Self righting. An invertible hull has no srimech fitted and does not need one to
## drive, but a shell that has been put on its back still has to get off it, so the
## righting impulse is available to an invertible chassis too.
func _try_secondary() -> void:
	if _srimech_cooldown > 0.0 or not is_inverted():
		return
	if not _has_srimech and not chassis_module.invertible():
		return
	_srimech_cooldown = FightTypes.SRIMECH_COOLDOWN_S
	var scale := clampf(total_mass() / SRIMECH_REFERENCE_MASS, 0.6, 2.5) \
		* chassis_module.tip_resistance() / chassis_module.flip_resistance()
	var right := chassis.global_basis.z
	var sign_roll := 1.0 if right.y > 0.0 else -1.0
	chassis.apply_impulse(Vector3.UP * SRIMECH_IMPULSE * scale, right * 0.28 * sign_roll)
	chassis.apply_torque_impulse(
		chassis.global_basis.x * SRIMECH_TORQUE * scale * sign_roll)


# ---------------------------------------------------------------------------
# Damage intake (called from BotPart._integrate_forces, inside the step)
# ---------------------------------------------------------------------------
func report_contact(part: BotPart, collider: Object, impulse: float,
		position: Vector3) -> void:
	if _frozen or damage == null or impulse <= 0.0:
		return
	debug_max_impulse = maxf(debug_max_impulse, impulse)
	if debug_contacts and impulse > 10.0:
		print("  [contact] tick=%d part=%s J=%.1f collider=%s" % [
			Engine.get_physics_frames(), part.part_key, impulse, collider])
	var attacker := "arena"
	var source := "impact"
	var attacker_bot: Bot = null
	if collider is BotPart:
		var other: BotPart = collider
		if other.owner_bot == self:
			return
		if other.owner_bot != null and not other.detached:
			attacker_bot = other.owner_bot as Bot
			attacker = str(attacker_bot.bot_id)
	elif collider is Node and (collider as Node).is_in_group("arena_hazard"):
		source = "hazard"

	# A blow landing on the chassis body actually landed on the armour face it came
	# through: thin plates let a fast, heavy hit reach the hull in one step, and
	# crediting the hull would silently lose the damage. Only once that face's plate
	# is gone does the blow reach the core.
	var key := part.part_key
	var kind := part.part_kind
	var material_name := part.material_name
	var core_exposed := false
	var face := ""
	if kind == "chassis":
		face = face_for_contact(position)
		var armour_key := "armour_" + face
		if damage.value_for(armour_key) > 0.0:
			key = armour_key
			kind = "armour"
			material_name = str(_materials.get(face, "steel"))
		else:
			core_exposed = true
	elif key.begins_with("armour_"):
		face = key.substr(7)

	var factor := 1.0
	if face == "rear":
		factor *= _rear_damage_factor
	if kind == "wheel":
		factor *= chassis_module.drive_fragility()
	# Wave P. A floor hazard passes under a hover and a walker steps over most of
	# one; an attacker carrying an overcharge core hits everything harder.
	if source == "hazard" and drive_module != null:
		factor *= drive_module.hazard_factor()
	if attacker_bot != null:
		factor *= attacker_bot.hit_factor()
	var applied := damage.apply_impulse_damage(key, kind, material_name,
		impulse, source, position, attacker, core_exposed, factor)
	if applied <= 0.0:
		return
	_bleed_drive_from_hull(kind, applied)
	if attacker_bot != null and kind == "armour" and source == "impact":
		_queue_knockback(attacker_bot, material_name, applied, position)


## Which armour face a world-space contact point came through.
func face_for_contact(world_position: Vector3) -> String:
	var l := chassis.global_transform.affine_inverse() * world_position
	var floor_y := chassis_module.floor_y()
	var height := maxf(chassis_module.top_y() - floor_y, 0.01)
	if l.y > floor_y + height * 0.79:
		return "top"
	if l.x > chassis_module.half_len() * 0.4:
		return "front"
	if l.x < -chassis_module.half_len() * 0.73:
		return "rear"
	return "sides"


## The yard's spike area calls this directly: an Area3D produces no contact
## impulse, so the hazard supplies its own (spec section 5).
func hazard_hit(part: BotPart, impulse: float, position: Vector3) -> void:
	if _frozen or damage == null:
		return
	# Wave P: the drive decides how much of a floor hazard reaches the machine. A
	# hover rides over one and takes nothing, a walker steps over most of one.
	var factor := drive_module.hazard_factor() if drive_module != null else 1.0
	if factor <= 0.0:
		return
	var applied := damage.apply_impulse_damage(part.part_key, part.part_kind,
		part.material_name, impulse, "hazard", position, "arena",
		_top_plate_gone(), factor)
	_bleed_drive_from_hull(part.part_kind, applied)


# ---------------------------------------------------------------------------
# Wave P: the two things a hit can do besides taking condition off
# ---------------------------------------------------------------------------
## A machine with no wheels (the walker, the hover) loses its drive through its
## hull, because it has no wheel to lose it through. `kind` is the part kind the
## blow landed on: only the hull and its plates carry the running gear.
func _bleed_drive_from_hull(kind: String, applied: float) -> void:
	if applied <= 0.0 or damage == null or drive_module == null:
		return
	if kind != "armour" and kind != "chassis":
		return
	var share := drive_module.hull_bleed()
	if share <= 0.0:
		return
	damage.bleed_drive(applied * share)


## Reactive armour. The plate's charge shoves whoever landed the blow away from
## it. Queued rather than applied: this runs inside the physics step, from a
## part's `_integrate_forces`, and nothing may be pushed from in there.
func _queue_knockback(attacker_bot: Bot, material_name: String, applied: float,
		position: Vector3) -> void:
	var charge := BotDamage.reactive_knockback(material_name, applied)
	if charge <= 0.0 or attacker_bot == null or attacker_bot.chassis == null:
		return
	var away := attacker_bot.chassis.global_position - position
	away.y = 0.0
	if away.length_squared() < 1e-6:
		away = chassis.global_basis.x if chassis != null else Vector3.RIGHT
		away.y = 0.0
	# Mostly a shove, a little lift: the charge fires along the plate's normal and
	# the attacker is usually nose down into it.
	var direction := (away.normalized() * 0.94 + Vector3.UP * 0.34).normalized()
	_knockbacks.append({"body": attacker_bot.chassis, "impulse": direction * charge})


func _flush_knockbacks() -> void:
	if _knockbacks.is_empty():
		return
	var queued := _knockbacks.duplicate()
	_knockbacks.clear()
	for entry_variant in queued:
		var entry: Dictionary = entry_variant
		var body := entry["body"] as RigidBody3D
		if body == null or not is_instance_valid(body) or body.freeze:
			continue
		body.apply_central_impulse(entry["impulse"] as Vector3)


## Continuous damage from ANOTHER bot's weapon: the saw's cut, the crusher's chew,
## the flame. `part` is one of the victim's bodies; the caller is the attacker's
## Bot, which is where the attacker id comes from (spec section 3).
func opponent_damage_tick(part: BotPart, amount: float, source: String = "cut") -> void:
	if part == null or not is_instance_valid(part) or part.detached:
		return
	var victim := part.owner_bot as Bot
	if victim == null or victim == self:
		return
	# Wave P: an overcharge core makes every weapon on this machine bite harder,
	# the continuous ones here and the ones that land blows in `report_contact`.
	victim.take_direct_damage(part, amount * _hit_factor, source, bot_id)


## The victim's half of `opponent_damage_tick`.
func take_direct_damage(part: BotPart, amount: float, source: String,
		attacker: String) -> void:
	if _frozen or damage == null or amount <= 0.0:
		return
	var key := part.part_key
	var material_name := part.material_name
	if part.part_kind == "chassis":
		if damage.value_for("armour_top") > 0.0:
			key = "armour_top"
			material_name = str(_materials.get("top", "steel"))
		else:
			key = FightTypes.PART_CORE
	var factor := 1.0
	if key.begins_with("armour_"):
		factor = PartsCatalogue.material_factor(material_name, source)
		# wave P (D1): the drill lance ignores half of whatever the plate is made
		# of, so it reads the "cut" row and then halves its distance from 1.0.
		if source == BotDamage.SOURCE_PIERCE:
			factor = BotDamage.pierce_factor(
				PartsCatalogue.material_factor(material_name, "cut"))
	var applied := damage.apply_direct_damage(key, amount, source,
		part.global_position, attacker, factor)
	_bleed_drive_from_hull(part.part_kind, applied)


## Cut this bot's weapon or drive for `seconds` (the flamethrower, spec section 4).
func disrupt(kind: String, seconds: float) -> void:
	if kind == "drive":
		_disrupt_drive = maxf(_disrupt_drive, seconds)
		if drive_module != null:
			drive_module.stop()
	else:
		_disrupt_weapon = maxf(_disrupt_weapon, seconds)


func is_disrupted(kind: String) -> bool:
	return _disrupt_drive > 0.0 if kind == "drive" else _disrupt_weapon > 0.0


func _top_plate_gone() -> bool:
	return damage.value_for("armour_top") <= 0.0


# ---------------------------------------------------------------------------
# Per-tick bookkeeping
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	# Combat feel wave: the machine's own count of simulation ticks. Engine.get_physics_frames()
	# also counts the frames a hit-stop HOLDS (the tree is paused, nothing moves), so any rule
	# timed off it would run on a different clock in a fight with hit-stop than in one without.
	_sim_ticks += 1
	_dt = delta
	_srimech_cooldown = maxf(_srimech_cooldown - delta, 0.0)
	_disrupt_weapon = maxf(_disrupt_weapon - delta, 0.0)
	_disrupt_drive = maxf(_disrupt_drive - delta, 0.0)
	if not _frozen:
		if weapon != null:
			weapon.physics_tick(delta)
		if _downforce > 0.0 and chassis != null:
			chassis.apply_central_force(Vector3.DOWN * total_mass() * 9.8 * _downforce)
		_flush_knockbacks()
		_cook_core(delta)
	_flush_damage()
	_update_speed_window()
	var inv := is_inverted()
	if inv != _was_inverted:
		_was_inverted = inv
		emit_signal("inverted_changed", inv)


## One second of the weapon at full costs the overcharge core `cook_rate` of the
## machine's own core condition (wave P, Level 90). Banked a whole second at a
## time so it arrives as one damage event a second rather than sixty, and credited
## to this machine itself, so the fight's ledger gives nobody else a bolt for it.
##
## It is the part's whole cost. A spinner held at full for three minutes cooks 0.72
## off a core that started at 1.0, which is the survivor bonus gone and a component
## kill in reach if anything else gets at the hull. Let the weapon idle and it stops.
const COOK_PULSE_S := 1.0


func _cook_core(delta: float) -> void:
	if _cook_rate <= 0.0 or damage == null or chassis == null:
		return
	if weapon_readiness() < 1.0:
		return
	_cook_owed += delta
	if _cook_owed < COOK_PULSE_S:
		return
	var seconds := _cook_owed
	_cook_owed = 0.0
	damage.apply_direct_damage(FightTypes.PART_CORE, _cook_rate * seconds,
		"heat", chassis.global_position, bot_id, 1.0)


func _flush_damage() -> void:
	if damage == null or damage.pending.is_empty():
		return
	var events := damage.pending.duplicate()
	damage.pending.clear()
	for ev_variant in events:
		var ev: Dictionary = ev_variant
		var part_key := str(ev["part"])
		var detached := false
		if bool(ev["zeroed"]):
			detached = _handle_zero(part_key)
		emit_signal("damage_event", {
			"attacker": ev["attacker"],
			"victim": bot_id,
			"part": part_key,
			"severity": ev["severity"],
			"position": ev["position"],
			"impulse": ev["impulse"],
			"detached": detached,
			"tick": ev["tick"],
			# B2 (combat feel): what KIND of damage it was ("impact", "cut", "burn", "heat",
			# ...), recorded by BotDamage all along and dropped here, so a burn was drawn as
			# a scratch unless the attacker's weapon happened to be a flamethrower.
			"source": str(ev.get("source", "")),
		})
		if detached:
			emit_signal("part_detached", part_key)


## Returns true when the part physically came off.
func _handle_zero(part_key: String) -> bool:
	if part_key == FightTypes.PART_WEAPON:
		if not _weapon_jammed:
			_weapon_jammed = true
			if weapon != null:
				weapon.set_jammed()
		return false
	if part_key == FightTypes.PART_CORE:
		return false
	var any := false
	# A track side loses its belt and free wheels; its road wheels stay bolted on.
	# Wave P: the adaptive belt is segmented and stays on the machine whatever its
	# condition, which is the drive's own `sheds_visual` answer.
	var sheds := drive_module == null or drive_module.sheds_visual(part_key)
	for node_variant in (_visuals.get(part_key, []) as Array):
		var node: Node3D = node_variant
		if sheds and is_instance_valid(node) and node.visible:
			node.visible = false
			any = true
	if drive_module != null and drive_module.condition_keys.has(part_key):
		drive_module.on_key_zero(part_key)
		for i in range(drive_module.wheels.size()):
			if drive_module.wheel_key[i] != part_key:
				continue
			if part_key.begins_with("wheel") and not drive_module.wheels[i].detached:
				_detach_part(drive_module.wheels[i], true)
				any = true
		return any
	if _panels.has(part_key):
		for panel_variant in (_panels[part_key] as Array):
			var panel: BotPart = panel_variant
			if not panel.detached:
				_detach_part(panel, true)
				any = true
	return any


func _detach_part(part: BotPart, tint: bool) -> void:
	if part.detached:
		return
	part.detached = true
	if _panel_joints.has(part):
		var joint: Node = _panel_joints[part]
		_panel_joints.erase(part)
		if joint != null and is_instance_valid(joint):
			joint.queue_free()
	if drive_module != null:
		var idx := drive_module.wheels.find(part)
		if idx >= 0 and idx < drive_module.joints.size() \
				and is_instance_valid(drive_module.joints[idx]):
			drive_module.joints[idx].queue_free()

	for other in _parts:
		if other != part:
			part.remove_collision_exception_with(other)
	part.collision_layer = FightTypes.LAYER_DEBRIS
	part.collision_mask = FightTypes.MASK_DEBRIS
	part.contact_monitor = false
	part.can_sleep = true

	var debris := _debris_root()
	if debris != null and part.is_inside_tree():
		part.reparent(debris, true)
	if tint:
		PartVisuals.tint_debris(part)


func _debris_root() -> Node:
	# Walk up for the nearest "Debris" sibling rather than hard coding
	# "/root/Fight/Debris": R rebuilds the fight's 3D world inside a fresh
	# SubViewport for every fight.
	var node: Node = self
	while node != null:
		var found := node.get_node_or_null("Debris")
		if found != null and found != self:
			return found
		node = node.get_parent()
	return get_parent()


## A part that arrives at zero condition was destroyed in an EARLIER fight (the
## shell carries `damage` between fights and only the workshop's Repair clears it).
## It is not on the machine any more, so it is RETIRED rather than detached: it must
## never be handed to the world as loose debris.
##
## Measured 2026-09-16, and it is exactly the "robot always loses armour when
## driving off at the start of the match" report. Detaching here spawned the dead
## plate as a free rigid body inside the hull, untinted (so it still wore the bot's
## own armour material), and the first tick dropped it on the spawn mark: the
## machine drove off and left a plate of its own armour lying on the floor, every
## fight, deterministically, for as long as the damage was carried.
func _apply_initial_damage() -> void:
	for i in range(drive_module.wheels.size()):
		var key := drive_module.wheel_key[i]
		if key.begins_with("wheel") and damage.value_for(key) <= 0.0:
			_retire_part(drive_module.wheels[i])
	for key in _panels.keys():
		if damage.value_for(key) <= 0.0:
			for panel_variant in (_panels[key] as Array):
				_retire_part(panel_variant)
	if damage.value_for(FightTypes.PART_WEAPON) <= 0.0:
		_weapon_jammed = true
		if weapon != null:
			weapon.set_jammed()


## Take a part off the machine before the fight starts: it is gone, not shed. The
## body object stays (the drive module indexes its wheels by position and a freed
## node would break every `wheels[i].detached` read), but it is out of the physics
## world, weightless to `total_mass()`, and invisible.
##
## Never reparented to Debris and never tinted: debris is what THIS fight knocked
## off, and a plate the player lost last week has no business on the floor of this
## one. `Bot.freeze()` and `place_at` both skip it because `detached` is already true
## for everything that matters.
func _retire_part(part: BotPart) -> void:
	if part == null or not is_instance_valid(part) or part.detached:
		return
	part.detached = true
	part.retired = true
	if _panel_joints.has(part):
		var joint: Node = _panel_joints[part]
		_panel_joints.erase(part)
		if joint != null and is_instance_valid(joint):
			joint.queue_free()
	if drive_module != null:
		var idx := drive_module.wheels.find(part)
		if idx >= 0 and idx < drive_module.joints.size() \
				and is_instance_valid(drive_module.joints[idx]):
			drive_module.joints[idx].queue_free()
	part.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	part.freeze = true
	part.collision_layer = 0
	part.collision_mask = 0
	part.contact_monitor = false
	part.can_sleep = true
	part.linear_velocity = Vector3.ZERO
	part.angular_velocity = Vector3.ZERO
	part.visible = false


## Parts of one bot never collide with each other: the plates, the arm and the
## wheels all overlap the hull by design and internal contacts would otherwise
## register as damage.
func _exclude_internal_collisions() -> void:
	for i in range(_parts.size()):
		for j in range(i + 1, _parts.size()):
			_parts[i].add_collision_exception_with(_parts[j])


func _make_material(friction: float) -> PhysicsMaterial:
	var material := PhysicsMaterial.new()
	material.friction = friction
	material.bounce = 0.05
	return material


func _update_speed_window() -> void:
	if chassis == null:
		return
	_speed_window[_speed_head] = chassis.linear_velocity.length()
	_speed_head = (_speed_head + 1) % _speed_window.size()
	if _speed_head == 0:
		_speed_filled = true


# ---------------------------------------------------------------------------
# Queries (spec section 4)
# ---------------------------------------------------------------------------
func is_inverted() -> bool:
	if chassis == null or not chassis.is_inside_tree():
		return false
	return chassis.global_basis.y.dot(Vector3.UP) < 0.0


func is_immobile() -> bool:
	if not _speed_filled:
		return false
	for v in _speed_window:
		if v > FightTypes.IMMOBILE_SPEED:
			return false
	return true


func condition() -> Dictionary:
	return damage.snapshot() if damage != null else {}


func weapon_height_band() -> String:
	if weapon != null:
		return weapon.height_band()
	return "floor"


func weapon_tip_height() -> float:
	if weapon != null and weapon.has_method("tip_height"):
		var h: float = weapon.call("tip_height")
		if h >= 0.0:
			return h
	return front_edge_height()


func weapon_status() -> String:
	return weapon.status_text() if weapon != null else ""


func weapon_readiness() -> float:
	if weapon == null or _weapon_jammed or _disrupt_weapon > 0.0:
		return 0.0
	return clampf(weapon.readiness(), 0.0, 1.0)


## Why the weapon is not answering the button, for the controls to say so: "jammed" when
## its condition reached zero (for the rest of the fight), "cooked" while a flame has its
## electronics down, "" when it is fine. The owner's "the weapon just stops working for no
## reason" was both of these happening silently (2026-09-16).
func weapon_fault() -> String:
	if weapon == null or _weapon_jammed:
		return "jammed"
	if _disrupt_weapon > 0.0:
		return "cooked"
	return ""


func weapon_reach() -> float:
	return weapon.reach() if weapon != null else 0.2


## The weapon's mount point in world space, for the test overlay's reach arc.
func weapon_socket_world() -> Vector3:
	if chassis == null:
		return global_position
	if weapon != null:
		return chassis.global_transform * weapon.socket_transform().origin
	return chassis.global_transform * chassis_module.front_lip_point()


func front_edge_height() -> float:
	if chassis == null:
		return 0.0
	return maxf((chassis.global_transform * chassis_module.front_lip_point()).y, 0.0)


## Where an armour face's plate sits in world space (the test drops weights here).
func armour_centre(face: String) -> Vector3:
	var panels: Array = _panels.get("armour_" + face, [])
	if not panels.is_empty() and is_instance_valid(panels[0]):
		return (panels[0] as Node3D).global_position
	return chassis.global_transform * Vector3(0.0, chassis_module.top_y(), 0.0)


func wheel_contacts() -> Array[bool]:
	return drive_module.wheel_contacts() if drive_module != null else []


## Same data as the `opponent_relative` var, for callers that prefer a call.
func opponent_relative_dict() -> Dictionary:
	return opponent_relative


func set_opponent_relative(position: Vector3, distance: float) -> void:
	opponent_relative["position"] = position
	opponent_relative["distance"] = distance


func weapon_jammed() -> bool:
	return _weapon_jammed


## Stage 3 AI hooks, forwarded to the weapon when it has them (the flipper does).
func opponent_on_wedge() -> bool:
	if weapon != null and weapon.has_method("opponent_on_wedge"):
		return bool(weapon.call("opponent_on_wedge"))
	return false


func flipper_ready() -> bool:
	if _weapon_jammed or _disrupt_weapon > 0.0:
		return false
	if weapon != null and weapon.has_method("ready"):
		return bool(weapon.call("ready"))
	return weapon_readiness() >= 1.0


## Everything that is still bolted on, for R's judges and for the FX layer.
## Is any attached part of this machine in physical contact with any part of `other` this
## tick? Read off the parts' own contact reports (every registered part has contact_monitor
## on), so it is a simulation fact and replays with the fight. For the knockout rule's
## "engaged" exception (Rules.is_engaged): a machine driving INTO its opponent is fighting.
func touching_bot(other: Node) -> bool:
	if other == null or not is_instance_valid(other):
		return false
	for p in _parts:
		if p.detached or not is_instance_valid(p) or not p.contact_monitor:
			continue
		for body in p.get_colliding_bodies():
			if body is BotPart and (body as BotPart).owner_bot == other:
				return true
	return false


func attached_parts() -> Array[BotPart]:
	var out: Array[BotPart] = []
	for p in _parts:
		if not p.detached:
			out.append(p)
	return out


## The workshop overlay's numbers (spec section 3). Catalogue kilograms, because
## these are the numbers the player is buying.
func build_summary() -> Dictionary:
	var weights := BuildRules.category_weights(_config)
	var wheel_count := drive_module.wheels.size() if drive_module != null else 0
	return {
		"name": str(_config.get("name", bot_id)),
		"chassis": str(_config.get("chassis", "")),
		"drive": str(_config.get("drive", "")),
		"weapon": str(_config.get("weapon", "")),
		"utility": _utility.duplicate(),
		"weights": weights,
		"total": BuildRules.total_weight(_config),
		"budget": PartsCatalogue.weight_budget(),
		"simulated_mass": total_mass(),
		"clearance": chassis_module.clearance(),
		"com_height": chassis_module.com_local().y + ride_height(),
		"wheels": wheel_count,
		"bodies": _parts.size(),
		"weapon_reach": weapon_reach(),
		"weapon_band": weapon_height_band(),
		"errors": build_errors.duplicate(),
		"valid": build_errors.is_empty(),
	}


## The body a decal for a hit on `part_key` should ride on (combat feel B4): the first
## attached part with that key, else the chassis. Presentation only; read, never written.
func body_for_part(part_key: String) -> Node3D:
	for part in _parts:
		if is_instance_valid(part) and not part.detached and part.part_key == part_key:
			return part
	return chassis


## Simulation ticks this machine has run. The clock every tick-timed rule reads instead of
## Engine.get_physics_frames(), which keeps counting through a hit-stop hold.
func sim_ticks() -> int:
	return _sim_ticks


## The RESULT: stop driving, stop the weapon, stop scoring (no damage lands on a machine
## that has stopped). The bodies are LEFT MOVING, so a machine thrown over the wall on the
## deciding tick carries on over it through the finish beat (combat feel B7). The result is
## already built before this is called, so nothing that happens after it can change it.
func stop_for_result() -> void:
	_frozen = true
	if weapon != null:
		weapon.freeze()
	if drive_module != null:
		drive_module.freeze()


## Stop everything, bodies included. The end of the finish beat, and the events' result.
func freeze() -> void:
	stop_for_result()
	for part in _parts:
		if is_instance_valid(part):
			part.linear_velocity = Vector3.ZERO
			part.angular_velocity = Vector3.ZERO
			part.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			part.freeze = true


## Stand the machine ON a surface whose top is at `floor_point.y` (a raised turntable, a
## ramp top, a plinth): the root goes to floor + ride height, so the wheels touch the surface
## instead of sinking into it. `place_at` keeps its old meaning (`origin.y` is a ROOT height
## floored at the ride height; the fight's spawns rely on it and drop from 0.25 m), so the
## determinism goldens do not move.
func place_on(floor_point: Vector3, facing: Vector3) -> void:
	place_at(Vector3(floor_point.x, floor_point.y + ride_height(), floor_point.z), facing)


## Place the bot at a spawn marker: the whole assembly moves with the root, so
## this must run before the first physics step. `origin.y` is the ROOT height, raised to at
## least the ride height; on a surface above y 0 use `place_on`, or the wheels are buried.
func place_at(origin: Vector3, facing: Vector3) -> void:
	var flat := Vector3(facing.x, 0.0, facing.z)
	if flat.length_squared() < 1e-6:
		flat = Vector3.RIGHT
	flat = flat.normalized()
	var yaw := atan2(-flat.z, flat.x)
	var at := Vector3(origin.x, maxf(origin.y, ride_height()), origin.z)
	global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	for part in _parts:
		if is_instance_valid(part) and part.is_inside_tree():
			part.force_update_transform()
			part.linear_velocity = Vector3.ZERO
			part.angular_velocity = Vector3.ZERO
	# Everything moved rigidly, so the joint frames are unchanged, but force a
	# reconfigure so a joint can never keep a stale world-space anchor.
	if _joints_root != null:
		for joint_variant in _joints_root.get_children():
			var joint := joint_variant as Joint3D
			if joint == null:
				continue
			var a := joint.node_a
			joint.node_a = NodePath()
			joint.node_a = a
