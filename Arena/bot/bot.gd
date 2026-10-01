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
## Wave B pacing: a boost began this tick. `direction` is +1 along the nose, -1 backing.
signal boost_started(direction: float)

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
## Ticks left of the srimech's controlled roll (QA D1): once the kick has the hull past
## upright, its roll is damped out so it stops the right way up instead of going round.
var _righting_ticks := 0
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
## Wave C: the catalogue's `part_toughness` for this machine's weapon (see `_build_damage`).
var _weapon_toughness := 1.0
## Wave C fitment: deck slots handed out so far (see `_deck_slot`).
var _deck_slots_used := 0
## Wave C fitment: bot-space boxes round every drive visual, for the armour plates to
## clear (see `_generic_plate_fit`). Presentation only.
var _drive_boxes: Array[AABB] = []
## Wave C fitment: bot-space boxes round thin weapon parts that pass through the nose.
var _blade_boxes: Array[AABB] = []
## Fitment pass 2: the nodes the drive drew (wheels, tracks, legs, fans) and the utility
## models by id, for the ring and scoop fits. Presentation only.
var _drive_roots: Array[Node] = []
## Fitment pass 2: bot-space boxes round static weapon parts that cross the front plate
## lower down (the crusher's bed): the plate is drawn with a notch under them.
var _notch_boxes: Array[AABB] = []
var _utility_models: Dictionary = {}

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
	_fit_ring()
	_add_axle_stubs()
	_add_weapon_supports()
	_fit_scoop_under_weapon()

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
	var before := chassis.get_children()
	drive_module.build()
	_collect_drive_boxes(before)
	# A hull can carry some of its own weight in its wheel bodies (the wedge's hub motors,
	# hero hull pass). The machine's total mass is unchanged; the chassis gives up exactly
	# what the wheels gained. See ChassisBase.wheel_ballast_kg.
	var ballast := chassis_module.wheel_ballast_kg() * float(drive_module.wheels.size())
	if ballast > 0.0:
		chassis.mass = maxf(chassis.mass - ballast * MASS_SCALE, 0.1)


func _build_damage() -> void:
	var keys := drive_module.condition_keys
	damage = BotDamage.new()
	damage.owner_bot = self
	damage.setup(_config.get("damage", {}) as Dictionary, keys.size(), keys)
	for face in BotDamage.ARMOUR_FACES:
		var thickness := BuildRules.thickness_of(BuildRules.face_entry(_config, face))
		damage.threshold_scale["armour_" + face] = THICKNESS_THRESHOLD_BASE \
			+ THICKNESS_THRESHOLD_STEP * thickness
	# Wave C: a weapon whose working part stands out in front of the armour (the saws,
	# since the fitment pass) takes the blows a hull used to. The catalogue row's
	# `part_toughness` scales its break thresholds and divides the direct damage (a ram's
	# blow, a cut) it takes; absent means 1.0, the old rule.
	var weapon_row := PartsCatalogue.weapon(str(_config.get("weapon", "")))
	if weapon_row.has("part_toughness"):
		_weapon_toughness = maxf(float(weapon_row["part_toughness"]), 0.1)
		damage.threshold_scale[FightTypes.PART_WEAPON] = _weapon_toughness


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
	_fit_weapon_visuals()


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
			if fitted_model.get_node_or_null("seg_u1") != null:
				_clear_plate_tiles(fitted_model, panel)
			else:
				_clear_fitted_plate(fitted, fitted_model, panel)
			panel.add_child(fitted_model)
			if face == "front":
				# Wave C: the wedge's front plate reads as part of the flipper's stack,
				# so it clears the front tyres the way the weapon does.
				_narrow_to_clear_drive(fitted_model)
			PartVisuals.bind(fitted_model, livery, {
				"steel": PartVisuals.armour_material(material_name, livery)})
			return
	var model := PartVisuals.instantiate(model_id)
	if model != null:
		if model_id == "scoop":
			# Wave C fitment: the scoop is authored pointing forward along the bot's
			# nose, its lip on the floor. It used to be turned to lie along the plate's
			# outward axis, which on every flat nosed hull stood it straight UP as a
			# 0.3 m blade in front of the machine, and on the wedge's ramp drove its
			# lip 105 mm into the floor. It now sits level in the BOT's frame, its lip
			# SCOOP_FLOOR_CLEAR off the floor and SCOOP_PROUD ahead of the front armour,
			# the rest of it behind the plate. Presentation only (the plate's box is
			# the collision, as before).
			model.transform = panel.transform.affine_inverse() * _scoop_at()
		else:
			var pieces := _generic_plate_fit(model_id, panel, size)
			model.transform = pieces[0]
			for i in range(1, pieces.size()):
				var extra := PartVisuals.instantiate(model_id)
				if extra != null:
					extra.name = "%s_%d" % [model.name, i]
					extra.transform = pieces[i]
					panel.add_child(extra)
					PartVisuals.bind(extra, livery, {
						"steel": PartVisuals.armour_material(material_name, livery)})
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


const SCOOP_PROUD := 0.07
const SCOOP_FLOOR_CLEAR := 0.005


func _scoop_at() -> Transform3D:
	var row := PartsCatalogue.model("scoop")
	var mn: Array = row.get("aabb_min", [-0.05, -0.078, -0.25]) as Array
	var mx: Array = row.get("aabb_max", [0.27, 0.15, 0.25]) as Array
	var nose := chassis_module.half_len() + ChassisBase.PLATE_PROUD
	return Transform3D(Basis.IDENTITY, Vector3(nose + SCOOP_PROUD - float(mx[0]),
		-ride_height() + SCOOP_FLOOR_CLEAR - float(mn[1]), 0.0))


## Wave C fitment (docs/wave-c-fitment-notes.md). Where a generic plate model sits on
## its collision box. PRESENTATION ONLY: the box, the body and the joint are untouched.
##
## 1. THICKNESS. The generic plates are authored as a 12 mm slab with a raised frame
##    and livery panel in front of it and ribs and gussets behind it, 59 mm deep in all.
##    Scaling the whole model by `size.x / PLATE_MODEL_UNIT` (the old rule) scaled that
##    depth too: a unit-1 plate drew 98 mm deep and a unit-4 plate 245 mm, a slab that
##    swallowed deck parts and stood off the hull like a door. Now the model grows by
##    PLATE_VISUAL_GROWTH per unit (1.0 at unit 1, 1.75 at unit 4: thicker armour still
##    reads thicker) and its OUTERMOST point sits PLATE_VISUAL_PROUD outside the box's
##    outer face, so the drawn plate is where the collider is and grows inward with it.
## 2. CLEARANCE. A side plate is as long as 1.5 hull half lengths and the wheels sit on
##    the hull flank, so the drawn plate went straight through every wheel (and through
##    tracks and road wheels). The drawn plate now takes the longest stretch of its face
##    that no drive visual crosses; when there is no such stretch (a track runs the full
##    length) it takes the band above the drive instead.
const PLATE_VISUAL_GROWTH := 0.25
const PLATE_VISUAL_PROUD := 0.004
## Air left between a trimmed plate and the wheel or track it clears.
const PLATE_CLEAR := 0.012
## A piece shorter than PLATE_MIN_PIECE, or a band lower than PLATE_MIN_BAND, is not
## a plate any more.
const PLATE_MIN_PIECE := 0.06
const PLATE_MIN_BAND := 0.035
## The authored in-plane size of the generic plate models (PLATE_H x PLATE_W in
## Tools/blender/parts_misc.py).
const PLATE_MODEL_H := 0.30
const PLATE_MODEL_W := 0.50


func _generic_plate_fit(model_id: String, panel: Node3D, size: Vector3) -> Array[Transform3D]:
	var units := 1.0 + (size.x - ChassisBase.PLATE_BASE_THICKNESS) \
		/ ChassisBase.PLATE_THICKNESS_STEP
	var sx := 1.0 + PLATE_VISUAL_GROWTH * maxf(units - 1.0, 0.0)
	var row := PartsCatalogue.model(model_id)
	var aabb_max: Array = row.get("aabb_max", [0.026, 0.15, 0.25]) as Array
	var aabb_min: Array = row.get("aabb_min", [-0.033, -0.15, -0.25]) as Array
	var out_x := float(aabb_max[0])
	var depth := (out_x - float(aabb_min[0])) * sx
	var outer := size.x * 0.5 + PLATE_VISUAL_PROUD
	# The in-plane rectangle this plate may occupy, in the panel's own frame.
	var y0 := -size.y * 0.5
	var y1 := size.y * 0.5
	var z0 := -size.z * 0.5
	var z1 := size.z * 0.5
	var clear := _plate_clearance(panel.transform, outer - depth, outer, y0, y1, z0, z1)
	y0 = clear[0]
	y1 = clear[1]
	# 3. SLOTS. A blade that passes through this plate splits it, so the disc runs in a
	#    slot instead of through a solid sheet.
	var spans: Array = clear[2]
	var to_panel := panel.transform.affine_inverse()
	for blade in _blade_boxes:
		var local := to_panel * blade
		if local.end.x <= outer - depth or local.position.x >= outer:
			continue
		if local.end.y <= y0 or local.position.y >= y1:
			continue
		var cut0 := local.position.z - BLADE_SLOT_CLEAR
		var cut1 := local.end.z + BLADE_SLOT_CLEAR
		var next: Array = []
		for span in spans:
			var a := float(span[0])
			var b := float(span[1])
			if cut1 <= a or cut0 >= b:
				next.append(span)
				continue
			if cut0 - a > 0.03:
				next.append([a, cut0])
			if b - cut1 > 0.03:
				next.append([cut1, b])
		spans = next
	# 4. NOTCHES (fitment pass 2). A static weapon part that crosses the plate (the
	#    crusher's bed) takes the plate out of its width above its underside: the
	#    plate runs on under it as a lower piece.
	var low: Array = []
	for notch in (_notch_boxes if String(panel.name) == "PanelFront" else []):
		var local := to_panel * notch
		if local.end.x <= outer - depth or local.position.x >= outer:
			continue
		if local.end.y <= y0 or local.position.y >= y1:
			continue
		var cut0 := local.position.z - BLADE_SLOT_CLEAR
		var cut1 := local.end.z + BLADE_SLOT_CLEAR
		var next: Array = []
		for span in spans:
			var a := float(span[0])
			var b := float(span[1])
			if cut1 <= a or cut0 >= b:
				next.append(span)
				continue
			if cut0 - a > 0.03:
				next.append([a, cut0])
			if b - cut1 > 0.03:
				next.append([cut1, b])
			var top := local.position.y - BLADE_SLOT_CLEAR
			if top - y0 >= PLATE_MIN_BAND:
				low.append([maxf(a, cut0), minf(b, cut1), y0, top])
		spans = next
	if spans.is_empty() and low.is_empty():
		spans = clear[2]
	var out: Array[Transform3D] = []
	for span in spans:
		var a := float(span[0])
		var b := float(span[1])
		var basis := Basis.from_scale(Vector3(sx, (y1 - y0) / PLATE_MODEL_H,
			(b - a) / PLATE_MODEL_W))
		out.append(Transform3D(basis, Vector3(outer - out_x * sx, (y0 + y1) * 0.5,
			(a + b) * 0.5)))
	for piece in low:
		var a := float(piece[0])
		var b := float(piece[1])
		var p0 := float(piece[2])
		var p1 := float(piece[3])
		out.append(Transform3D(Basis.from_scale(Vector3(sx, (p1 - p0) / PLATE_MODEL_H,
			(b - a) / PLATE_MODEL_W)), Vector3(outer - out_x * sx, (p0 + p1) * 0.5,
			(a + b) * 0.5)))
	return out


## A chassis-fitted plate is authored for the 4wd layout; the middle wheels of a 6wd
## (and the 2wd's wheel slots) go through it. It is squeezed onto the same clear
## rectangle a generic plate would take (`_plate_clearance`), about its own bounds.
func _clear_fitted_plate(model_id: String, model: Node3D, panel: Node3D) -> void:
	var row := PartsCatalogue.model(model_id)
	var mn: Array = row.get("aabb_min", []) as Array
	var mx: Array = row.get("aabb_max", []) as Array
	if mn.size() < 3 or mx.size() < 3:
		return
	var p := model.position
	var y0 := p.y + float(mn[1])
	var y1 := p.y + float(mx[1])
	var z0 := p.z + float(mn[2])
	var z1 := p.z + float(mx[2])
	var clear := _plate_clearance(panel.transform, p.x + float(mn[0]), p.x + float(mx[0]),
		y0, y1, z0, z1)
	# One fitted plate is one piece: the longest clear stretch.
	var best: Array = [z0, z1]
	var widest := -1.0
	for span in clear[2]:
		if float(span[1]) - float(span[0]) > widest:
			widest = float(span[1]) - float(span[0])
			best = span
	if is_equal_approx(clear[0], y0) and is_equal_approx(clear[1], y1) \
			and is_equal_approx(float(best[0]), z0) and is_equal_approx(float(best[1]), z1):
		return
	var sy := (float(clear[1]) - float(clear[0])) / maxf(y1 - y0, 0.001)
	var sz := (float(best[1]) - float(best[0])) / maxf(z1 - z0, 0.001)
	model.transform = Transform3D(Basis.from_scale(Vector3(1.0, sy, sz)), Vector3(p.x,
		float(clear[0]) - float(mn[1]) * sy, float(best[0]) - float(mn[2]) * sz))


## Fitment pass 2: a fitted plate authored as tiles (`seg_*` nodes, the pyramid's flank)
## leaves out every tile a drive visual stands over, by the same PLATE_CLEAR.
func _clear_plate_tiles(model: Node3D, panel: Node3D) -> void:
	# The left flank's plate is the right one MIRRORED (not turned round), so a tile and
	# its twin stand at the same station either side and leave out together.
	if String(panel.name).ends_with("L"):
		model.scale = Vector3(1.0, 1.0, -1.0)
	var at := panel.transform * model.transform
	for child in model.get_children():
		var tile := child as MeshInstance3D
		if tile == null or not String(tile.name).begins_with("seg_") or tile.mesh == null:
			continue
		var box := (at * tile.transform) * tile.get_aabb()
		box = box.grow(PLATE_CLEAR)
		for d in _drive_boxes:
			if box.intersects(d):
				tile.visible = false
				break


## [y0, y1, [[z0, z1], ...]]: the part of a plate's in-plane rectangle no drive visual
## crosses, as a band and the stretches of it between the wheels.
## `panel_at` is the panel's bot-space transform; x0..x1 is the drawn depth.
func _plate_clearance(panel_at: Transform3D, x0: float, x1: float, y0: float, y1: float,
		z0: float, z1: float) -> Array:
	var to_panel := panel_at.affine_inverse()
	var blocks: Array[AABB] = []
	for box in _drive_boxes:
		var local := to_panel * box
		if local.end.x <= x0 or local.position.x >= x1:
			continue
		if local.end.y <= y0 or local.position.y >= y1:
			continue
		if local.end.z <= z0 or local.position.z >= z1:
			continue
		blocks.append(local)
	if blocks.is_empty():
		return [y0, y1, [[z0, z1]]]
	# 1. every clear stretch along the plate's length, between the wheels
	var cuts: Array = []
	for b in blocks:
		cuts.append([b.position.z - PLATE_CLEAR, b.end.z + PLATE_CLEAR])
	cuts.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var spans: Array = []
	var cursor := z0
	for c in cuts:
		if float(c[0]) - cursor >= PLATE_MIN_PIECE:
			spans.append([cursor, float(c[0])])
		cursor = maxf(cursor, float(c[1]))
	if z1 - cursor >= PLATE_MIN_PIECE:
		spans.append([cursor, z1])
	var total := 0.0
	for span in spans:
		total += float(span[1]) - float(span[0])
	if total >= (z1 - z0) * 0.3:
		return [y0, y1, spans]
	# 2. the band above everything the drive draws
	var top := y0
	for b in blocks:
		top = maxf(top, b.end.y + PLATE_CLEAR)
	if y1 - top >= PLATE_MIN_BAND:
		return [top, y1, [[z0, z1]]]
	# 3. nothing clean: whatever pieces there are, else a thin band on the top edge
	if not spans.is_empty():
		return [y0, y1, spans]
	return [y1 - PLATE_MIN_BAND, y1, [[z0, z1]]]


## Bot-space boxes round everything the drive draws (wheels, tracks, legs, fans).
## Taken right after the drive is built, before any armour exists.
func _collect_drive_boxes(before: Array) -> void:
	_drive_boxes.clear()
	var roots: Array[Node] = []
	for wheel in drive_module.wheels:
		roots.append(wheel)
	for child in chassis.get_children():
		if not before.has(child):
			roots.append(child)
	_drive_roots = roots
	for root in roots:
		for mi in _mesh_instances_under(root):
			if mi.mesh == null:
				continue
			_drive_boxes.append(_relative_to_bot(mi) * mi.get_aabb())


static func _mesh_instances_under(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		out.append_array(_mesh_instances_under(c))
	return out


## A node's transform in this bot's frame, by walking parents: works before the bot is
## in the tree (the workshop builds it off tree).
func _relative_to_bot(node: Node3D) -> Transform3D:
	var t := node.transform
	var walk := node.get_parent()
	while walk != null and walk != self:
		if walk is Node3D:
			t = (walk as Node3D).transform * t
		walk = walk.get_parent()
	return t


## Wave C fitment: a weapon drawn wider than the gap between the front wheels went
## through them (the hero's flipper plate is 0.524 m wide, the wedge's front tyres start
## 0.259 m either side of the centre line: the owner's "the front tyre pokes up through
## the plate"). A centred weapon model that meets a drive visual is narrowed, about the
## centre line, to clear it by WEAPON_CLEAR. PRESENTATION ONLY: the weapon's collision
## shapes, mass and joints are untouched (they never collide with their own wheels).
## A weapon that encloses the drive (the full body spinners) is left alone: narrowing is
## only done when it keeps at least WEAPON_MIN_NARROW of the width.
const WEAPON_MIN_NARROW := 0.75
## Air between a narrowed weapon and the tyre beside it. Wider than a plate's: a tyre
## beside a flat plate reads as sitting ON it from a menu camera unless there is a
## visible strip of something else between them.
const WEAPON_CLEAR := 0.03


func _fit_weapon_visuals() -> void:
	_blade_boxes.clear()
	for part in _parts:
		if part.part_kind != "weapon":
			continue
		for child in part.get_children():
			var model := child as Node3D
			if model == null or not String(model.name).begins_with("Model_"):
				continue
			if not _drive_boxes.is_empty():
				_narrow_to_clear_drive(model)
			_note_blade(model)
	for mount_name in ["SawMount", "TwinSawMount"]:
		var mount := chassis.get_node_or_null(mount_name) as Node3D
		if mount != null:
			_note_blade(mount)
	_notch_boxes.clear()
	var bed := chassis.get_node_or_null("CrusherMount") as Node3D
	if bed != null:
		_notch_boxes.append(_weapon_box(bed))


## A thin weapon (a saw disc, its belt arm) that passes through the nose gets a slot
## cut in the front plate for it (`_generic_plate_segments`).
const BLADE_MAX_WIDTH := 0.10
const BLADE_SLOT_CLEAR := 0.010


func _note_blade(node: Node3D) -> void:
	var box := AABB()
	var first := true
	for mi in _mesh_instances_under(node):
		if mi.mesh == null:
			continue
		var b := _relative_to_bot(mi) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if not first and box.size.z <= BLADE_MAX_WIDTH:
		_blade_boxes.append(box)


func _narrow_to_clear_drive(model: Node3D) -> void:
	var at := _relative_to_bot(model)
	# Only a model whose own z runs along the bot's z (hinged about z, or fixed).
	if absf(at.basis.z.normalized().z) < 0.99:
		return
	var box := AABB()
	var first := true
	for mi in _mesh_instances_under(model):
		if mi.mesh == null:
			continue
		var b := _relative_to_bot(mi) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first or absf(box.get_center().z) > 0.02:
		return
	var half := box.size.z * 0.5
	var allowed := half
	for d in _drive_boxes:
		if d.end.x <= box.position.x or d.position.x >= box.end.x:
			continue
		if d.end.y <= box.position.y or d.position.y >= box.end.y:
			continue
		var inner := d.position.z if d.get_center().z > 0.0 else -d.end.z
		if inner < half:
			allowed = minf(allowed, inner - WEAPON_CLEAR)
	if allowed >= half or allowed < half * WEAPON_MIN_NARROW:
		return
	model.scale = Vector3(model.scale.x, model.scale.y, model.scale.z * allowed / half)


## Wave C fitment: a weapon the fitment harness found drawn in mid air gets something
## drawn to hold it. PRESENTATION ONLY: plain meshes on the chassis body, no shapes, no
## mass, and nothing here moves a body, a joint or a collider.
##   * a deck hinge (the axe, the crusher) whose pivot stands clear of the
##     deck under it gets two posts down to the deck (the wedge's top mount is 0.17 m
##     over its centre channel: the axe hung in the air);
##   * a spinning drum or disc on a cross axle gets fork arms from its socket out to
##     the axle ends, outside the disc (the saws carry their own mounts);
##   * a drill gets a boom from its socket to the back of the lance;
##   * a welded head that stands off the nose (the shock prod sits 80 mm out) gets two
##     stand-off bars back into the front plate.
const SUPPORT_BAR := 0.032
const SUPPORT_MIN_GAP := 0.03


func _add_weapon_supports() -> void:
	if weapon == null or chassis == null:
		return
	var hinged := {}
	for joint_variant in _joints_root.get_children():
		var hinge := joint_variant as HingeJoint3D
		if hinge == null or String(hinge.name).begins_with("JointWheel"):
			continue
		var body := hinge.get_node_or_null(hinge.node_b) as BotPart
		if body == null or body.part_kind != "weapon":
			continue
		hinged[body] = true
		_support_hinged(hinge, body)
	for part in _parts:
		if part.part_kind == "weapon" and not hinged.has(part):
			_support_welded(part)


func _weapon_box(body: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in _mesh_instances_under(body):
		if mi.mesh == null:
			continue
		var b := _relative_to_bot(mi) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _support_hinged(hinge: HingeJoint3D, body: BotPart) -> void:
	var at := _relative_to_bot(hinge)
	var axis := at.basis.z.normalized()
	var pivot := at.origin
	var box := _weapon_box(body)
	if box.size == Vector3.ZERO:
		return
	if hinge.get_flag(HingeJoint3D.FLAG_USE_LIMIT):
		# Posts from the deck up to the hinge, either side of the arm: the deck mounted
		# weapons only (a nose hinge sits in the hull).
		if not weapon.kind in ["axe", "crusher"]:
			return
		var z_off := box.size.z * 0.5 + 0.02
		# Fitment pass 2: the tower stands on the chassis now (AxeMount / CrusherMount),
		# so the posts only carry it down to the deck when its foot is clear of it.
		var top := pivot.y
		for mount_name in ["AxeMount", "CrusherMount"]:
			var mount := chassis.get_node_or_null(mount_name) as Node3D
			if mount == null:
				continue
			# A tower whose foot stands a little clear of the deck (under the posts'
			# SUPPORT_MIN_GAP) is stretched down onto it, its pin kept on the hinge.
			var foot := mount.transform.origin
			var deck := _surface_below(foot.x, 0.0, foot.y + 0.02)
			var lift := pivot.y - foot.y
			if foot.y - deck > 0.001 and foot.y - deck <= SUPPORT_MIN_GAP and lift > 0.05:
				var sy := (pivot.y - deck) / lift
				mount.transform = Transform3D(Basis.from_scale(Vector3(1.0, sy, 1.0)),
					Vector3(foot.x, pivot.y - lift * sy, foot.z))
			top = mount.transform.origin.y + 0.03
			# the posts overlap the tower's cheeks, so it is bolted to them
			z_off = _weapon_box(mount).size.z * 0.5 + SUPPORT_BAR * 0.5 - 0.006
		for side in [-1.0, 1.0]:
			var ground := _surface_below(pivot.x, side * z_off, top)
			if top - ground > SUPPORT_MIN_GAP:
				_support_bar(Vector3(pivot.x, ground - 0.01, side * z_off),
					Vector3(pivot.x, top, side * z_off))
		return
	if chassis.get_node_or_null("SawMount") != null \
			or chassis.get_node_or_null("TwinSawMount") != null:
		return
	var from := weapon.socket_transform().origin
	if absf(axis.y) > 0.9 and weapon.kind == "spinner":
		# Fitment pass 2: the bar spinner's forward mount. Two boom rails from the nose
		# out OVER the bar's hub, clear above the drawn bar (under it they would take the
		# floor a scoop needs), and the hub's drop post down to the bar.
		if pivot.x - from.x < SUPPORT_MIN_GAP:
			return
		var over := box.end.y + 0.006 + SUPPORT_BAR * 0.5
		for side in [-1.0, 1.0]:
			var z: float = side * 0.03
			# from the nose's face at the rail's height; where the hull does not reach
			# that high (a ramped nose), from the socket, on a post down to the ramp
			var face := _extent_along(chassis_module.model, Vector3(0.0, over, z),
				Vector3.RIGHT, over)
			var start := maxf(face, from.x) - 0.03
			_support_bar(Vector3(start, over, z), Vector3(pivot.x + 0.05, over, z))
			if face < from.x:
				var ground := _surface_below(start + 0.01, z, over)
				if over - ground > SUPPORT_MIN_GAP:
					_support_bar(Vector3(start + 0.01, ground - 0.01, z),
						Vector3(start + 0.01, over, z))
		_support_bar(Vector3(pivot.x, over, 0.0), Vector3(pivot.x, box.end.y - 0.004, 0.0))
		return
	if absf(axis.z) > 0.9:
		if pivot.x - from.x < SUPPORT_MIN_GAP:
			return
		var z_off := box.size.z * 0.5 + 0.015
		for side in [-1.0, 1.0]:
			_support_bar(Vector3(from.x, from.y, side * z_off),
				Vector3(pivot.x, pivot.y, side * z_off))
	elif absf(axis.x) > 0.9:
		var tail := Vector3(box.position.x + 0.01, pivot.y, pivot.z)
		if tail.x - from.x > SUPPORT_MIN_GAP:
			_support_bar(from, tail)


func _support_welded(part: BotPart) -> void:
	var box := _weapon_box(part)
	if box.size == Vector3.ZERO:
		return
	var nose := chassis_module.half_len() + ChassisBase.PLATE_PROUD
	if box.position.x - nose < 0.005:
		return
	var y := box.get_center().y
	for side in [-1.0, 1.0]:
		var z: float = side * box.size.z * 0.3
		_support_bar(Vector3(nose - 0.03, y, z), Vector3(box.position.x + 0.01, y, z))


## A dark bar between two bot-space points, on the chassis body.
func _support_bar(a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	if length < 0.005:
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(SUPPORT_BAR, SUPPORT_BAR, length)
	var bar := MeshInstance3D.new()
	bar.name = "WeaponSupport"
	bar.mesh = mesh
	bar.material_override = PartVisuals.slot_material("dark_metal", livery)
	var dir := (b - a) / length
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var basis := Basis.looking_at(dir, up)
	bar.transform = Transform3D(basis, (a + b) * 0.5)
	chassis.add_child(bar)


## The highest drawn hull or armour surface under (x, z) below `from_y`, in bot space
## (a vertical ray against the triangles). Falls back to the hull's floor line.
var _surface_tris: PackedVector3Array = PackedVector3Array()


func _surface_below(x: float, z: float, from_y: float) -> float:
	if _surface_tris.is_empty():
		var roots: Array[Node] = []
		if chassis_module.model != null:
			roots.append(chassis_module.model)
		for key in _panels.keys():
			for panel in _panels[key]:
				roots.append(panel)
		for root in roots:
			for mi in _mesh_instances_under(root):
				if mi.mesh == null:
					continue
				var t := _relative_to_bot(mi)
				for v in mi.mesh.get_faces():
					_surface_tris.append(t * v)
	var best := chassis_module.floor_y()
	var i := 0
	while i + 2 < _surface_tris.size():
		var a := _surface_tris[i]
		var b := _surface_tris[i + 1]
		var c := _surface_tris[i + 2]
		i += 3
		if x < minf(a.x, minf(b.x, c.x)) or x > maxf(a.x, maxf(b.x, c.x)):
			continue
		if z < minf(a.z, minf(b.z, c.z)) or z > maxf(a.z, maxf(b.z, c.z)):
			continue
		var den := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
		if absf(den) < 1e-12:
			continue
		var l0 := ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / den
		var l1 := ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / den
		var l2 := 1.0 - l0 - l1
		if l0 < 0.0 or l1 < 0.0 or l2 < 0.0:
			continue
		var y := l0 * a.y + l1 * b.y + l2 * c.y
		if y <= from_y and y > best:
			best = y
	return best


# ---------------------------------------------------------------------------
# Fitment pass 2: the rings (docs/wave-d-fitment2-notes.md, decisions 2026-09-30 §9)
# ---------------------------------------------------------------------------
## "Spinner rings (full body, vortex) are drawn to clear the hull and wheels (bigger or
## raised ring, no pass-through at any angle)." The ring is drawn BIGGER: its bore is
## sized to this machine, so everything the machine draws inside the ring's height band
## (hull, drive, deck parts, and the armour on a hull that keeps its own bodywork) stands
## RING_CLEAR inside the ring at every angle. Every vertex of the ring model is pushed out
## along its radius by the same distance, so the band keeps its depth and its teeth. A
## raised ring was measured and rejected: the wheels reach 0.11 m above the axle plane, so
## a ring clear of them would work 0.12 m above where the collider is (notes).
##
## PHYSICS: the ring's collision disc grows with the drawn teeth, so a blow lands where
## you see it. The catalogue reach (the shop's number, the AI's approach distance) stays.
## Moves every fight with a ring whose bore had to grow.
##
## Then what cannot sit inside the band on the machine's own terms is drawn inside the
## bore: armour plates on a hull that has handed its bodywork to the ring (the Shell and
## the Apex, whose plates leave the collision world while the ring is up) are narrowed,
## and the scoop, the rear wedge and the skirts are pulled in. Presentation only.
const RING_CLEAR := 0.012
const RING_BRACKET_GAP := 0.002
## The ring's inner furniture is not drawn: the vortex's spider and hub, and on both rings
## the drive ring and its bolts under the band (the ring rides on the roller brackets). A
## connected piece of the model whose OUTERMOST point is inside RING_KEEP x the collider's
## radius is left out. That keeps the bore as wide as the band itself.
const RING_KEEP := 0.75
const RING_STEP := 0.002
## Coordinator's cap (30 Sept, after pass 2): no ring's collision disc wider than this. A
## machine that needs more has what it draws inside the band shortened to fit instead.
const RING_MAX_RADIUS := 0.72
## A wheel whose tyre still stands past the bore is drawn this far inboard along its axle
## at most (a shift along the spin axis turns with the wheel).
const RING_WHEEL_SHIFT_MAX := 0.04

static var _points_cache: Dictionary = {}
static var _ring_cache: Dictionary = {}


func _fit_ring() -> void:
	if weapon == null or weapon.kind != "fbs":
		return
	var ring := weapon.get("ring") as BotPart
	if ring == null:
		return
	var model: Node3D = null
	for child in ring.get_children():
		if String(child.name).begins_with("Model_"):
			model = child as Node3D
	if model == null:
		return
	var centre: Vector3 = _relative_to_bot(ring).origin
	var ring_mis := _mesh_instances_under(model)
	var collider_r := 0.0
	for child in ring.get_children():
		var holder := child as CollisionShape3D
		if holder != null and holder.shape is CylinderShape3D:
			collider_r = maxf(collider_r, (holder.shape as CylinderShape3D).radius)
	var keep_r := RING_KEEP * collider_r
	var source := {}
	for mi in ring_mis:
		if mi.mesh == null:
			continue
		source[mi] = mi.mesh
		var local := _relative_to_bot(mi).affine_inverse() * centre
		mi.mesh = _ring_mesh(mi.mesh, Vector2(local.x, local.z), 0.0, keep_r)
	var y0 := INF
	var y1 := -INF
	var r_in := INF
	for mi in ring_mis:
		if mi.mesh == null:
			continue
		var t := _relative_to_bot(mi)
		for v in mi.mesh.get_faces():
			var p := t * v
			var r := Vector2(p.x - centre.x, p.z - centre.z).length()
			y0 = minf(y0, p.y)
			y1 = maxf(y1, p.y)
			r_in = minf(r_in, r)
	if r_in == INF:
		return
	var hull_gave_ring := chassis_module.has_method("has_own_ring") \
		and not bool(chassis_module.call("has_own_ring"))
	# What has to stand inside the ring on its own terms.
	var inside: Array[Node] = []
	if chassis_module.model != null:
		inside.append(chassis_module.model)
	inside.append_array(_drive_roots)
	if _srimech_mesh != null:
		inside.append(_srimech_mesh)
	for id in _utility_models.keys():
		if not (id in ["scoop", "rear_wedge", "skirts"]):
			inside.append(_utility_models[id])
	if not hull_gave_ring:
		for key in _panels.keys():
			for panel in _panels[key]:
				for child in (panel as Node).get_children():
					if child is Node3D and String(child.name) != "Model_scoop" \
							and child != _srimech_mesh:
						inside.append(child)
	var need := 0.0
	for root in inside:
		need = maxf(need, _band_reach(root, centre, y0, y1))
	var grow := maxf(need + RING_CLEAR - r_in, 0.0)
	grow = ceilf(grow / RING_STEP) * RING_STEP
	var grow_cap := floorf(maxf(RING_MAX_RADIUS - collider_r, 0.0) / RING_STEP) * RING_STEP
	if grow > grow_cap:
		grow = grow_cap
		_shorten_into_ring(inside, centre, r_in + grow - RING_CLEAR, y0, y1)
	for mi in ring_mis:
		if mi.mesh == null:
			continue
		var local := _relative_to_bot(mi).affine_inverse() * centre
		mi.mesh = _ring_mesh(source[mi], Vector2(local.x, local.z), grow, keep_r)
	if grow > 0.0:
		for child in ring.get_children():
			var holder := child as CollisionShape3D
			if holder != null and holder.shape is CylinderShape3D:
				(holder.shape as CylinderShape3D).radius += grow
	# Everything else is drawn inside the bore.
	var bore := r_in + grow - RING_CLEAR
	if hull_gave_ring:
		for key in _panels.keys():
			for panel in _panels[key]:
				for child in (panel as Node).get_children():
					if child is Node3D and child != _srimech_mesh \
							and String(child.name) != "Model_scoop":
						_narrow_into_bore(child as Node3D, panel as Node3D, centre, bore, y0, y1)
	for id in ["scoop", "rear_wedge", "skirts"]:
		var node: Node3D = _utility_models.get(id, null)
		if id == "scoop":
			node = _scoop_model()
		if node != null:
			_pull_into_bore(node, centre, bore, y0, y1)
	# The ring rides on roller brackets from the hull, fore and aft (the sides are the
	# wheels'): static bars on the chassis out to RING_BRACKET_GAP inside the bore, at the
	# ring's mid height or the hull's, whichever is lower, so it is carried by something.
	var hy := clampf((y0 + y1) * 0.5, chassis_module.floor_y() + 0.03, chassis_module.top_y() - 0.03)
	# the ring's bore at the brackets' height (its drive ring sits lower, further in)
	var r_at := INF
	for mi in ring_mis:
		if mi.mesh == null:
			continue
		var t := _relative_to_bot(mi)
		for v in _surface_samples(mi.mesh):
			var p := t * v
			var r := Vector2(p.x - centre.x, p.z - centre.z).length()
			if absf(p.y - hy) <= 0.02:
				r_at = minf(r_at, r)
	if r_at == INF:
		r_at = r_in + grow
	for dir in [Vector3.RIGHT, Vector3.LEFT]:
		var hub := minf(_extent_along(chassis_module.model, centre, dir, hy), bore - 0.02)
		_support_bar(centre + dir * maxf(hub - 0.03, 0.05) + Vector3(0.0, hy - centre.y, 0.0),
			centre + dir * (r_at - RING_BRACKET_GAP) + Vector3(0.0, hy - centre.y, 0.0))


## The coordinator's cap bit (RING_MAX_RADIUS): shorten what is drawn inside the band until
## it fits the bore. The hull model, the plates and chassis-borne drive units (tracks, legs,
## fans) are scaled in the floor plane about the ring's axis, all by the one factor, so the
## machine keeps its shape; deck parts and the srimech are MOVED in by it at their own
## size; wheel bodies cannot be drawn anywhere their physics is not, so a tyre still past
## the bore is drawn inboard along its own axle (a shift along the spin axis turns with it),
## by RING_WHEEL_SHIFT_MAX at most. Presentation only: no shape, body or joint moves.
func _shorten_into_ring(inside: Array[Node], centre: Vector3, bore: float, y0: float,
		y1: float) -> void:
	var wheel_roots := {}
	for w in drive_module.wheels:
		wheel_roots[w] = true
	var shrink: Array[Node3D] = []
	var move: Array[Node3D] = []
	var need := 0.0
	for root in inside:
		if wheel_roots.has(root) or not (root is Node3D):
			continue
		var n := root as Node3D
		if n == _srimech_mesh or (_utility_models.values().has(n)):
			move.append(n)
		else:
			shrink.append(n)
			need = maxf(need, _band_reach(n, centre, y0, y1))
	var k := clampf(bore / maxf(need, 0.001), 0.5, 1.0)
	for n in shrink + move:
		var at := _relative_to_bot(n)
		var parent_at := _relative_to_bot(n.get_parent() as Node3D) \
			if n.get_parent() is Node3D and n.get_parent() != self else Transform3D.IDENTITY
		# How each thing comes in: the hull and the top plate shrink in the floor plane;
		# a side plate or a chassis-borne drive unit (a track) moves in across the machine
		# only, so it stays in line with the wheel bodies it was cut round or runs on;
		# front and rear plates move in along it; deck parts move in at their own size.
		var along := Vector3(k, 1.0, k)
		var scaled := true
		var pname := String(n.get_parent().name) if n.get_parent() != null else ""
		if move.has(n):
			scaled = false
		elif pname.begins_with("PanelSides") or n.get_parent() == chassis and n != chassis_module.model:
			along = Vector3(1.0, 1.0, k)
			scaled = false
		elif pname == "PanelFront" or pname == "PanelRear":
			along = Vector3(k, 1.0, 1.0)
			scaled = false
		var in_bot: Transform3D
		if scaled:
			in_bot = Transform3D(Basis.from_scale(along),
				Vector3(centre.x * (1.0 - k), 0.0, centre.z * (1.0 - k))) * at
		else:
			var o := at.origin
			in_bot = Transform3D(at.basis, Vector3(centre.x + (o.x - centre.x) * along.x, o.y,
				centre.z + (o.z - centre.z) * along.z))
		n.transform = parent_at.affine_inverse() * in_bot
	for w in drive_module.wheels:
		if not inside.has(w):
			continue
		var reach := _band_reach(w, centre, y0, y1)
		if reach <= bore:
			continue
		var side := signf(_relative_to_bot(w).origin.z - centre.z)
		# the smallest inboard shift that brings the tyre inside the bore
		var shift := 0.0
		while shift < RING_WHEEL_SHIFT_MAX and _band_reach_shifted(w, centre, y0, y1,
				-side * shift) > bore:
			shift += 0.004
		var axle := (w as Node3D).transform.basis.inverse() * Vector3(0.0, 0.0, -side * shift)
		for child in w.get_children():
			if child is Node3D and not (child is CollisionShape3D):
				(child as Node3D).position += axle


func _band_reach_shifted(root: Node, centre: Vector3, y0: float, y1: float, dz: float) -> float:
	var best := 0.0
	for mi in _mesh_instances_under(root):
		if mi.mesh == null or not _drawn(mi):
			continue
		var t := _relative_to_bot(mi)
		for v in _mesh_points(mi.mesh):
			var p := t * v
			if p.y < y0 or p.y > y1:
				continue
			best = maxf(best, Vector2(p.x - centre.x, p.z + dz - centre.z).length())
	return best


## Fitment pass 2 (the Shell's wheels read as floating once its plates went into the ring's
## bore; wave C already noted them 20 to 28 mm off its hub): a wheel whose tyre stands clear
## of the drawn hull and plates gets a static axle stub from the hull out to its hub, on the
## axle line, so it turns on something. Wheel drives only. Presentation only.
const AXLE_STUB_MIN_GAP := 0.012


func _add_axle_stubs() -> void:
	if drive_module == null or not (str(_config.get("drive", "")) in ["2wd", "4wd", "6wd", "omni"]):
		return
	var supports: Array[Node] = []
	if chassis_module.model != null:
		supports.append(chassis_module.model)
	for key in _panels.keys():
		for panel in _panels[key]:
			supports.append(panel)
	var rows: Array = []
	for w in drive_module.wheels:
		if w == null or w.detached:
			continue
		var box := AABB()
		var first := true
		for mi in _mesh_instances_under(w):
			if mi.mesh == null or not _drawn(mi):
				continue
			var b := _relative_to_bot(mi) * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		if first:
			continue
		var c := _relative_to_bot(w).origin
		var side := signf(c.z)
		if side == 0.0:
			continue
		var inner := box.position.z if side > 0.0 else -box.end.z
		# the gap the way the fitment check sees it: from the hub face to the nearest
		# drawn support point, in 3D
		var hub := Vector3(c.x, c.y, side * inner)
		var gap := INF
		var reach := 0.0
		for root in supports:
			for mi in _mesh_instances_under(root):
				if mi.mesh == null or not _drawn(mi):
					continue
				var t := _relative_to_bot(mi)
				for v in _surface_samples(mi.mesh):
					var p := t * v
					gap = minf(gap, p.distance_to(hub))
					# how far out the support reaches along the axle line
					if absf(p.x - c.x) < 0.02 and absf(p.y - c.y) < 0.02 and p.z * side > 0.0:
						reach = maxf(reach, absf(p.z))
		rows.append({"x": c.x, "y": c.y, "side": side, "inner": inner, "reach": reach,
			"gap": gap})
	# Twins get the same stub (the machine is drawn symmetric): per axle station, the
	# shorter reach, the nearer hub, a stub on both sides when either needs one.
	for row in rows:
		var twin: Dictionary = {}
		for other in rows:
			if other != row and absf(float(other["x"]) - float(row["x"])) < 0.004 \
					and float(other["side"]) != float(row["side"]):
				twin = other
		var gap := float(row["gap"])
		var reach := float(row["reach"])
		var inner := float(row["inner"])
		if not twin.is_empty():
			gap = maxf(gap, float(twin["gap"]))
			reach = minf(reach, float(twin["reach"]))
			inner = minf(inner, float(twin["inner"]))
		if gap <= AXLE_STUB_MIN_GAP:
			continue
		reach = snappedf(minf(reach, inner - 0.02), 0.002)
		inner = snappedf(inner, 0.002)
		var sd := float(row["side"])
		_support_bar(Vector3(float(row["x"]), float(row["y"]), sd * maxf(reach - 0.01, 0.0)),
			Vector3(float(row["x"]), float(row["y"]), sd * (inner + 0.012)))


## How far the drawn hull reaches from the ring's axis along `dir` near height `y`.
func _extent_along(root: Node, centre: Vector3, dir: Vector3, y: float) -> float:
	var best := 0.05
	if root == null:
		return best
	for mi in _mesh_instances_under(root):
		if mi.mesh == null or not _drawn(mi):
			continue
		var t := _relative_to_bot(mi)
		for v in _surface_samples(mi.mesh):
			var p := t * v
			if absf(p.y - y) > 0.03:
				continue
			var d := p - centre
			var along := d.x * dir.x + d.z * dir.z
			var side := absf(d.x * dir.z - d.z * dir.x)
			if side < 0.04:
				best = maxf(best, along)
	return best


## Every vertex of a mesh, in its own space, once per mesh resource.
static func _mesh_points(mesh: Mesh) -> PackedVector3Array:
	var key := mesh.get_instance_id()
	if _points_cache.has(key):
		return _points_cache[key]
	var out := PackedVector3Array()
	for s in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(s)
		out.append_array(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)
	_points_cache[key] = out
	return out


## The furthest any drawn point under `root` stands from the ring's axis, inside the
## ring's height band.
func _band_reach(root: Node, centre: Vector3, y0: float, y1: float) -> float:
	var best := 0.0
	for mi in _mesh_instances_under(root):
		if mi.mesh == null or not _drawn(mi):
			continue
		var t := _relative_to_bot(mi)
		for v in _mesh_points(mi.mesh):
			var p := t * v
			if p.y < y0 or p.y > y1:
				continue
			best = maxf(best, Vector2(p.x - centre.x, p.z - centre.z).length())
	return best


## Visible, walking up to the bot (the workshop builds off tree, where
## is_visible_in_tree() is always false).
func _drawn(node: Node) -> bool:
	var walk := node
	while walk != null and walk != self:
		if walk is Node3D and not (walk as Node3D).visible:
			return false
		walk = walk.get_parent()
	return true


## The ring model pushed out along its radius by `grow`, the vortex's spider left out.
static func _ring_mesh(mesh: Mesh, c: Vector2, grow: float, keep_r: float) -> Mesh:
	var key := "%d:%d:%d:%d:%d" % [mesh.get_instance_id(), roundi(c.x * 1000.0),
		roundi(c.y * 1000.0), roundi(grow * 1000.0), roundi(keep_r * 1000.0)]
	if _ring_cache.has(key):
		return _ring_cache[key]
	var out := ArrayMesh.new()
	for s in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var radius := PackedFloat32Array()
		radius.resize(verts.size())
		var moved := PackedVector3Array()
		moved.resize(verts.size())
		for i in range(verts.size()):
			var v := verts[i]
			var off := Vector2(v.x - c.x, v.z - c.y)
			var r := off.length()
			radius[i] = r
			if r > 0.0001 and grow > 0.0:
				var k := off * (grow / r)
				v = Vector3(v.x + k.x, v.y, v.z + k.y)
			moved[i] = v
		arrays[Mesh.ARRAY_VERTEX] = moved
		var index: Variant = arrays[Mesh.ARRAY_INDEX]
		if index is PackedInt32Array and (index as PackedInt32Array).size() > 0:
			var tris: PackedInt32Array = index
			# Whole pieces go, never single triangles: a shell with a hole in it is not
			# a solid any more (the spider's arms, its hub). Pieces are the connected
			# sets of vertices, found by position so split normals do not split them.
			var parent := PackedInt32Array()
			parent.resize(verts.size())
			var by_pos := {}
			for i in range(verts.size()):
				var key_pos := Vector3i(roundi(verts[i].x * 10000.0), roundi(verts[i].y * 10000.0),
					roundi(verts[i].z * 10000.0))
				parent[i] = int(by_pos.get(key_pos, i))
				if not by_pos.has(key_pos):
					by_pos[key_pos] = i
			for t in range(0, tris.size() - 2, 3):
				var a := _root_of(parent, tris[t])
				for k in [1, 2]:
					var b := _root_of(parent, tris[t + k])
					if a != b:
						parent[b] = a
			var reach := {}
			for i in range(verts.size()):
				var root := _root_of(parent, i)
				reach[root] = maxf(float(reach.get(root, 0.0)), radius[i])
			var drop := {}
			for root in reach.keys():
				if float(reach[root]) < keep_r:
					drop[root] = true
			var kept := PackedInt32Array()
			for t in range(0, tris.size() - 2, 3):
				if drop.has(_root_of(parent, tris[t])):
					continue
				kept.append(tris[t])
				kept.append(tris[t + 1])
				kept.append(tris[t + 2])
			if kept.is_empty():
				kept = PackedInt32Array([0, 0, 0])
			arrays[Mesh.ARRAY_INDEX] = kept
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(s, mesh.surface_get_material(s))
		out.surface_set_name(s, mesh.surface_get_name(s))
	_ring_cache[key] = out
	return out


static func _root_of(parent: PackedInt32Array, i: int) -> int:
	var r := i
	while parent[r] != r:
		parent[r] = parent[parent[r]]
		r = parent[r]
	return r


## A plate piece on a hull that gave its bodywork to the ring: narrowed along the face,
## about its own middle, until every point of it inside the ring's band is inside the
## bore. A piece whose face stands outside the bore is not drawn.
func _narrow_into_bore(piece: Node3D, panel: Node3D, centre: Vector3, bore: float,
		y0: float, y1: float) -> void:
	var at_panel := _relative_to_bot(panel)
	var along := at_panel.basis.z.normalized()
	along.y = 0.0
	if along.length() < 0.5:
		return
	along = along.normalized()
	var pts := _band_points(piece, y0, y1)
	if pts.is_empty():
		return
	var box := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		box = box.expand(p)
	var mid := box.get_center()
	var s := 1.0
	for p in pts:
		var q := (p - mid).dot(along)
		var base := Vector2(p.x - q * along.x - centre.x, p.z - q * along.z - centre.z)
		s = minf(s, _max_scale(base, Vector2(along.x, along.z) * q, bore))
	if s >= 0.999:
		return
	if s <= 0.05:
		piece.visible = false
		return
	# The scale is along the panel's own z, about the piece's middle.
	var mid_panel := at_panel.affine_inverse() * mid
	var squeeze := Transform3D(Basis.from_scale(Vector3(1.0, 1.0, s)),
		Vector3(0.0, 0.0, mid_panel.z * (1.0 - s)))
	piece.transform = squeeze * piece.transform


## A part that sticks out past the hull (the scoop, the rear wedge, the skirts): scaled
## in the floor plane about its own origin until its band points are inside the bore.
func _pull_into_bore(node: Node3D, centre: Vector3, bore: float, y0: float, y1: float) -> void:
	var pts := _band_points(node, y0, y1)
	if pts.is_empty():
		return
	# About the part's point nearest the axis (its inner end stays where it was, so pulling
	# it in never buries more of it in the hull)
	var anchor := pts[0]
	for p in pts:
		if Vector2(p.x - centre.x, p.z - centre.z).length() \
				< Vector2(anchor.x - centre.x, anchor.z - centre.z).length():
			anchor = p
	var s := 1.0
	for p in pts:
		var base := Vector2(anchor.x - centre.x, anchor.z - centre.z)
		s = minf(s, _max_scale(base, Vector2(p.x - anchor.x, p.z - anchor.z), bore))
	if s >= 0.999:
		return
	if s <= 0.05:
		node.visible = false
		return
	var parent_at := _relative_to_bot(node.get_parent() as Node3D) \
		if node.get_parent() is Node3D and node.get_parent() != self else Transform3D.IDENTITY
	var in_bot := Transform3D(Basis.from_scale(Vector3(s, 1.0, s)),
		Vector3(anchor.x * (1.0 - s), 0.0, anchor.z * (1.0 - s)))
	node.transform = parent_at.affine_inverse() * in_bot * _relative_to_bot(node)


## Bot-space points of every drawn mesh under `root` inside a height band.
func _band_points(root: Node, y0: float, y1: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for mi in _mesh_instances_under(root):
		if mi.mesh == null or not _drawn(mi):
			continue
		var t := _relative_to_bot(mi)
		for v in _mesh_points(mi.mesh):
			var p := t * v
			if p.y >= y0 and p.y <= y1:
				out.append(p)
	return out


## The largest s in [0, 1] with |base + s * dir| <= r (1 when it already fits).
static func _max_scale(base: Vector2, dir: Vector2, r: float) -> float:
	if (base + dir).length() <= r:
		return 1.0
	if base.length() >= r:
		return 0.0
	# |base + s dir|^2 = r^2, the positive root
	var a := dir.dot(dir)
	var b := 2.0 * base.dot(dir)
	var c := base.dot(base) - r * r
	var disc := b * b - 4.0 * a * c
	if a < 1e-9 or disc < 0.0:
		return 0.0
	return clampf((-b + sqrt(disc)) / (2.0 * a), 0.0, 1.0)


## The scoop model, which rides on the front panel in place of its plate.
func _scoop_model() -> Node3D:
	for panel in _panels.get("armour_front", []):
		var found := (panel as Node).get_node_or_null("Model_scoop") as Node3D
		if found != null:
			return found
	return null


# ---------------------------------------------------------------------------
# Fitment pass 2: the scoop gives way to the front weapon
# ---------------------------------------------------------------------------
## Decisions 2026-09-30 §9: "with a scoop and a front weapon, the weapon wins and the scoop
## is drawn lower and narrower under it". The scoop is scaled about the middle of its back
## edge on the floor, lower first and narrower second (shorter only as the last resort),
## until no drawn point of it comes within SCOOP_WEAPON_CLEAR of anything the weapon draws
## at any point of its stroke (a spinner's whole turn, an arm's hinge range, the static
## mounts as they stand). PRESENTATION ONLY: the scoop's collision is the front plate's box
## and does not move. (A ring's scoop is pulled into its bore by _fit_ring instead.)
const SCOOP_WEAPON_CLEAR := 0.010
const SCOOP_CELL := 0.01
const SCOOP_MIN_Y := 0.15
const SCOOP_MIN_Z := 0.35


func _fit_scoop_under_weapon() -> void:
	if not _has_scoop or weapon == null or weapon.kind == "fbs":
		return
	var scoop := _scoop_model()
	if scoop == null:
		return
	var sweep := _weapon_sweep()
	var at := _relative_to_bot(scoop)
	var pts := PackedVector3Array()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for mi in _mesh_instances_under(scoop):
		if mi.mesh == null:
			continue
		var t := at * _under_node(mi, scoop)
		for v in _surface_samples(mi.mesh):
			var p := t * v
			pts.append(p)
			lo = lo.min(p)
			hi = hi.max(p)
	if pts.is_empty():
		return
	# the middle of the back edge, on the floor
	var anchor := Vector3(lo.x, lo.y, (lo.z + hi.z) * 0.5)
	var best := Vector3.ONE
	var found := false
	for sx in [1.0, 0.8, 0.6, 0.45]:
		for sz in [1.0, 0.85, 0.7, 0.55, SCOOP_MIN_Z]:
			for sy in [1.0, 0.8, 0.65, 0.5, 0.4, 0.32, 0.25, 0.2, SCOOP_MIN_Y]:
				var s := Vector3(sx, sy, sz)
				if _scoop_clear(pts, anchor, s, sweep):
					best = s
					found = true
					break
			if found:
				break
		if found:
			break
	if not found:
		# nothing of it fits under the weapon: the plate's box is the scoop, undrawn
		scoop.visible = false
		return
	if best.is_equal_approx(Vector3.ONE):
		return
	var squash := Transform3D(Basis.from_scale(best), anchor - Basis.from_scale(best) * anchor)
	var parent_at := _relative_to_bot(scoop.get_parent() as Node3D)
	scoop.transform = parent_at.affine_inverse() * squash * at


func _scoop_clear(pts: PackedVector3Array, anchor: Vector3, s: Vector3, sweep: Array) -> bool:
	for p in pts:
		var q := anchor + (p - anchor) * s
		for entry in sweep:
			if _in_sweep(entry, q):
				return false
	return true


## What the weapon draws over its stroke, as solids of revolution about each hinge: for
## every (height along the axis, distance from it) bin, the range of angles the drawn
## weapon passes through (every angle for a spinner). Static weapon parts (welded heads,
## the mounts on the chassis) are one entry with no hinge. Bins are SCOOP_CELL.
func _weapon_sweep() -> Array:
	var out: Array = []
	var moving := {}
	for joint_variant in _joints_root.get_children():
		var hinge := joint_variant as HingeJoint3D
		if hinge == null or String(hinge.name).begins_with("JointWheel"):
			continue
		var body := hinge.get_node_or_null(hinge.node_b) as BotPart
		if body == null or body.part_kind != "weapon":
			continue
		moving[body] = true
		var jt := _relative_to_bot(hinge)
		var axis := jt.basis.z.normalized()
		var pivot := jt.origin
		if body.has_meta("fit_draw_pivot"):
			pivot = body.get_meta("fit_draw_pivot")
		var full := not hinge.get_flag(HingeJoint3D.FLAG_USE_LIMIT)
		# Godot's hinge angle runs opposite to a right hand turn about the joint's +Z
		var a0 := -float(hinge.get_param(HingeJoint3D.PARAM_LIMIT_UPPER))
		var a1 := -float(hinge.get_param(HingeJoint3D.PARAM_LIMIT_LOWER))
		out.append(_sweep_entry(_drawn_points(body), pivot, axis, full, a0, a1))
	var still := PackedVector3Array()
	for part in _parts:
		if part.part_kind == "weapon" and not moving.has(part):
			still.append_array(_drawn_points(part))
	for mount_name in ["SawMount", "TwinSawMount", "FlipperMount", "LifterMount",
			"AxeMount", "CrusherMount"]:
		var mount := chassis.get_node_or_null(mount_name) as Node3D
		if mount != null:
			still.append_array(_drawn_points(mount))
	for child in chassis.get_children():
		if String(child.name).begins_with("WeaponSupport"):
			still.append_array(_drawn_points(child))
	if not still.is_empty():
		out.append(_sweep_entry(still, Vector3.ZERO, Vector3.UP, false, 0.0, 0.0))
	return out


func _sweep_entry(pts: PackedVector3Array, pivot: Vector3, axis: Vector3, full: bool,
		a0: float, a1: float) -> Dictionary:
	var ref := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
	var ref2 := axis.cross(ref)
	var bins := {}
	for p in pts:
		var d := p - pivot
		var h := d.dot(axis)
		var flat := d - axis * h
		var r := flat.length()
		var phi := atan2(flat.dot(ref2), flat.dot(ref))
		var key := Vector2i(floori(h / SCOOP_CELL), floori(r / SCOOP_CELL))
		var span: Vector2 = bins.get(key, Vector2(INF, -INF))
		bins[key] = Vector2(minf(span.x, phi), maxf(span.y, phi))
	# Dilated once here, so a query is one lookup: every bin takes the angle spans of
	# its neighbours within the clearance. (A span is kept as one arc; for an arm that
	# is what it is.)
	var reach := int(ceil(SCOOP_WEAPON_CLEAR / SCOOP_CELL)) + 1
	var grown := {}
	for key in bins.keys():
		var span: Vector2 = bins[key]
		for dh in range(-reach, reach + 1):
			for dr in range(-reach, reach + 1):
				var k2 := Vector2i(key.x + dh, key.y + dr)
				var old: Vector2 = grown.get(k2, Vector2(INF, -INF))
				grown[k2] = Vector2(minf(old.x, span.x), maxf(old.y, span.y))
	bins = grown
	return {"pivot": pivot, "axis": axis, "ref": ref, "ref2": ref2, "full": full,
		"a0": a0, "a1": a1, "bins": bins}


func _in_sweep(e: Dictionary, q: Vector3) -> bool:
	var d := q - (e["pivot"] as Vector3)
	var axis: Vector3 = e["axis"]
	var h := d.dot(axis)
	var flat := d - axis * h
	var r := flat.length()
	var phi := atan2(flat.dot(e["ref2"] as Vector3), flat.dot(e["ref"] as Vector3))
	var bins: Dictionary = e["bins"]
	var key := Vector2i(floori(h / SCOOP_CELL), floori(r / SCOOP_CELL))
	if not bins.has(key):
		return false
	if bool(e["full"]):
		return true
	var slack := (SCOOP_WEAPON_CLEAR + 2.0 * SCOOP_CELL) / maxf(r, 0.02)
	var span: Vector2 = bins[key]
	return _angle_within(phi, span.x + float(e["a0"]) - slack, span.y + float(e["a1"]) + slack)


static func _angle_within(phi: float, lo: float, hi: float) -> bool:
	if hi - lo >= TAU:
		return true
	var x := fposmod(phi - lo, TAU)
	return x <= hi - lo


func _drawn_points(root: Node) -> PackedVector3Array:
	var out := PackedVector3Array()
	for mi in _mesh_instances_under(root):
		if mi.mesh == null or not _drawn(mi):
			continue
		var t := _relative_to_bot(mi)
		for v in _surface_samples(mi.mesh):
			out.append(t * v)
	return out


## Points over a mesh's surface no further than SCOOP_CELL apart (its vertices, plus a
## barycentric grid on every triangle larger than a cell), once per mesh resource: a bar's
## long faces have vertices only at their ends.
static var _samples_cache: Dictionary = {}


static func _surface_samples(mesh: Mesh) -> PackedVector3Array:
	var key := mesh.get_instance_id()
	if _samples_cache.has(key):
		return _samples_cache[key]
	var out := PackedVector3Array()
	var seen := {}
	for f in mesh.get_faces():
		var k := Vector3i(roundi(f.x * 150.0), roundi(f.y * 150.0), roundi(f.z * 150.0))
		if not seen.has(k):
			seen[k] = true
			out.append(f)
	var faces := mesh.get_faces()
	var i := 0
	while i + 2 < faces.size():
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		i += 3
		var n := ceili(maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a))) \
			/ SCOOP_CELL)
		if n <= 1:
			continue
		for u in range(n + 1):
			for v in range(n + 1 - u):
				var p := a + (b - a) * (float(u) / n) + (c - a) * (float(v) / n)
				var k := Vector3i(roundi(p.x * 150.0), roundi(p.y * 150.0), roundi(p.z * 150.0))
				if not seen.has(k):
					seen[k] = true
					out.append(p)
	_samples_cache[key] = out
	return out


static func _under_node(node: Node3D, ancestor: Node) -> Transform3D:
	var t := node.transform
	var walk := node.get_parent()
	while walk != null and walk != ancestor:
		if walk is Node3D:
			t = (walk as Node3D).transform * t
		walk = walk.get_parent()
	return t


## `plate_<chassis>_<face>[_hdpe]` when that model exists, else "". Reactive armour
## keeps its cassette plate, which is a different object, not a different fit.
func _fitted_plate_id(face: String, material_name: String) -> String:
	if chassis_module == null:
		return ""
	var base := "plate_%s_%s" % [chassis_module.id, face]
	# Fitment pass 2: a hull may have a fitted reactive plate (the wedge's lid, the
	# pyramid's flank tiles); without one reactive keeps the generic cassette plate.
	if material_name == "reactive":
		return base + "_reactive" if PartVisuals.has_model(base + "_reactive") else ""
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
			"downforce":
				_fit_utility_visual(id, _belly_slot())
			_:
				_fit_utility_visual(id, _deck_slot())


## Wave C fitment (docs/wave-c-fitment-notes.md). The deck parts (the spare battery,
## the counterweight, the overcharge core) take the chassis' deck slots from
## Arena/data/fitment.json in fitting order: two per hull, either side of the srimech's
## centre line, their height measured off the drawn hull and plates. They used to take
## `utility_socket(0)`, the .glb's deck socket on the centre line, which (1) put them
## inside the srimech on five hulls, (2) left them floating 99 mm over the hero wedge,
## whose deck dropped under that socket in the hull pass (the owner's "the battery was
## floating in mid air"), and (3) sent a second deck part to `utility_socket(1)`, the
## BELLY socket, where it was drawn inside the hull.
func _deck_slot() -> Transform3D:
	var slots: Array = PartsCatalogue.fitment(chassis_module.id).get("deck", []) as Array
	var index := _deck_slots_used
	_deck_slots_used += 1
	if index < slots.size():
		var row: Dictionary = slots[index]
		var s := float(row.get("scale", 1.0))
		var y := float(row.get("y", chassis_module.top_y()))
		# Under a GENERIC top plate on a hull that has fitted ones (reactive armour on
		# the wedge: a flat plate over the whole deck) the deck is that plate.
		if row.has("y_generic_top") and _fitted_plate_id("top",
				str(_materials.get("top", "steel"))) == "":
			y = float(row["y_generic_top"])
		return Transform3D(Basis.from_scale(Vector3(s, s, s)), Vector3(
			float(row.get("x", 0.0)), y, float(row.get("z", 0.0))))
	# No fitment row: the old socket, mirrored across the centre line for the second.
	var at := chassis_module.utility_socket(0)
	var side := 0.16 if index % 2 == 0 else -0.16
	return Transform3D(at.basis, at.origin + Vector3(0.0, 0.0, side))


## Downforce magnets hang under the belly, between the wheels, recessed into the hull:
## a 0.11 m magnet block cannot hang below a 0.05 m ground clearance. The height is the
## .glb's belly socket; x is the fitment row's (the socket was under the nose, where
## every front weapon rests).
func _belly_slot() -> Transform3D:
	var at := chassis_module.utility_socket(1)
	var row: Dictionary = PartsCatalogue.fitment(chassis_module.id).get("belly", {}) as Dictionary
	if row.has("x"):
		at = Transform3D(at.basis, Vector3(float(row["x"]), at.origin.y, 0.0))
	return _above_floor("magnets", at)


## Wave C fitment: a part hung low on the hull (the belly magnets, the rear wedge) is
## lifted until its lowest drawn point clears the arena floor by FLOOR_CLEAR. The rear
## wedge used to be drawn 36 mm into the floor on the wedge, the magnets 12 mm.
## Presentation only: their collision (the rear wedge's box) is not moved.
const FLOOR_CLEAR := 0.004


func _above_floor(id: String, at: Transform3D) -> Transform3D:
	var mn: Array = PartsCatalogue.model(id).get("aabb_min", []) as Array
	if mn.size() < 3:
		return at
	var lowest := at.origin.y + float(mn[1]) * at.basis.get_scale().y
	var floor_line := -ride_height() + FLOOR_CLEAR
	if lowest >= floor_line:
		return at
	return Transform3D(at.basis, at.origin + Vector3(0.0, floor_line - lowest, 0.0))


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
	var at := Transform3D(Basis.IDENTITY, Vector3(chassis_module.rear_x(),
		chassis_module.floor_y() + 0.03, 0.0))
	_fit_utility_visual(id, _above_floor(id, at))
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.20, 0.06, chassis_module.half_wid() * 1.6)
	chassis_module.add_shape(shape, Transform3D(Basis.IDENTITY,
		at.origin + Vector3(-0.08, 0.0, 0.0)))


func _fit_skirts(id: String) -> void:
	# A thin lip all the way round, 0.02 m below the hull, so nothing gets under.
	var lip := Vector3(chassis_module.half_len() * 1.7, 0.02, chassis_module.half_wid() * 2.0)
	var lip_at := Vector3(0.0, chassis_module.floor_y() - 0.01, 0.0)
	var shape := BoxShape3D.new()
	shape.size = lip
	chassis_module.add_shape(shape, Transform3D(Basis.IDENTITY, lip_at))
	# Wave C fitment: the drawn skirt is that lip. It used to go on `utility_socket(1)`,
	# the belly socket 0.22 m forward of centre, at the model's own size, so it hung off
	# the nose and left the tail bare. Now it is centred on the collision lip, scaled to
	# it, its bottom edge on the lip's. Presentation only: the shape above is unchanged.
	var row := PartsCatalogue.model(id)
	var mn: Array = row.get("aabb_min", [-0.32, -0.068, -0.2885]) as Array
	var mx: Array = row.get("aabb_max", [0.32, 0.025, 0.2885]) as Array
	var scale := Vector3(lip.x / maxf(float(mx[0]) - float(mn[0]), 0.01), 1.0,
		lip.z / maxf(float(mx[2]) - float(mn[2]), 0.01))
	var bottom := lip_at.y - lip.y * 0.5
	_fit_utility_visual(id, Transform3D(Basis.from_scale(scale),
		Vector3(0.0, bottom - float(mn[1]), 0.0)))


func _fit_utility_visual(id: String, at: Transform3D) -> Node3D:
	var model := PartVisuals.instantiate(id)
	if model == null:
		return null
	model.transform = at
	chassis.add_child(model)
	PartVisuals.bind(model, livery)
	_utility_models[id] = model
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
	if _boost_ticks > 0:
		return _speed_factor * (1.0 + BOOST_SPEED_GAIN * boost_factor())
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
	# BOOST (wave B pacing): the level is in the record, the edge is derived here, exactly
	# as the fire button's is, so a replay boosts on the same tick the fight did.
	var boost := bool(inp.get("boost", false))
	if boost and not _boost_was:
		_try_boost(heading)
	_boost_was = boost
	if _boost_ticks > 0:
		heading = _boost_heading(heading)
		turn = 0.0
	if _disrupt_drive > 0.0:
		drive_module.stop()
	else:
		drive_module.drive(heading, secondary, _dt, turn)
		if _boost_ticks > 0:
			_boost_push()
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


# ---------------------------------------------------------------------------
# BOOST (wave B pacing, docs/wave-b-boost-notes.md)
#
# A short dash with a cooldown, so a ram, the set-up for a flip and the escape from a pin
# are timing skills. While it runs the drive's top speed is raised (speed_factor) and the
# hull is pushed along the nose (or the tail, when the stick asked to back) at BOOST_ACCEL,
# up to the raised top speed. The stick still steers it; a stick at rest dashes straight
# ahead. Everything is counted in simulation ticks from the recorded input, so a replay
# boosts on exactly the ticks its fight did. Per drive factor: tracks and legs are heavy
# and slow to wind up, 2WD, omni and hover are light and punchy.
# ---------------------------------------------------------------------------
const BOOST_TICKS := 21                 # 0.35 s at 60 Hz
const BOOST_COOLDOWN_TICKS := 240       # 4 s, counted from the moment it fires
const BOOST_SPEED_GAIN := 0.5           # top speed x (1 + gain x factor) while it runs
const BOOST_ACCEL := 10.0               # m/s^2 of extra push along the nose, x factor
## Past this angle between the stick and the nose the dash goes backwards (the drive's own
## reverse rule, DriveBase.REVERSE_ANGLE).
const BOOST_REVERSE_DEG := 135.0
## Catalogue `boost_factor` on a drive row wins; otherwise this table; otherwise 1.0.
const BOOST_FACTORS := {
	"2wd": 1.15, "4wd": 1.0, "6wd": 0.9, "tracks": 0.7, "adaptive_tracks": 0.75,
	"omni": 1.15, "legs": 0.6, "hover": 0.85,
}
var _boost_ticks := 0
var _boost_cool := 0
var _boost_was := false
var _boost_sign := 1.0
## World XZ direction of a strafing drive's dash, fixed when it fires.
var _boost_strafe_dir := Vector3.ZERO
## Boosts fired this fight, for the tests and the gauntlet.
var boosts_fired := 0


func boost_factor() -> float:
	if drive_module == null:
		return 1.0
	var spec: Dictionary = drive_module.spec
	if spec.has("boost_factor"):
		return float(spec["boost_factor"])
	return float(BOOST_FACTORS.get(drive_module.id, 1.0))


## 0 just fired, 1 ready. The HUD's charge ring and the AI read it.
func boost_charge() -> float:
	return 1.0 - float(_boost_cool) / float(BOOST_COOLDOWN_TICKS)


func boost_ready() -> bool:
	return _boost_cool <= 0 and not _frozen


func is_boosting() -> bool:
	return _boost_ticks > 0


func _try_boost(heading: Vector2) -> void:
	if _boost_cool > 0 or _frozen or _disrupt_drive > 0.0 or chassis == null:
		return
	if drive_module == null or drive_module.power_scale() <= 0.0:
		return
	# Upright only: on its back a machine's tool is the srimech.
	if chassis.global_basis.y.y < 0.5:
		return
	var fwd := _flat_nose()
	_boost_sign = 1.0
	if heading.length() > 0.2:
		var want := Vector3(heading.x, 0.0, heading.y).normalized()
		if fwd.angle_to(want) > deg_to_rad(BOOST_REVERSE_DEG):
			_boost_sign = -1.0
		_boost_strafe_dir = want
	else:
		_boost_strafe_dir = fwd
	_boost_ticks = BOOST_TICKS
	_boost_cool = BOOST_COOLDOWN_TICKS
	boosts_fired += 1
	boost_started.emit(_boost_sign)


## The heading while a dash runs: full throttle; a stick at rest (or barely off it) dashes
## straight along the nose, or the tail if it fired backing.
func _boost_heading(heading: Vector2) -> Vector2:
	if heading.length() > 0.5:
		return heading.normalized()
	var dir := _boost_strafe_dir if drive_module.strafes() else _flat_nose() * _boost_sign
	return Vector2(dir.x, dir.z)


func _boost_push() -> void:
	if chassis == null or not chassis.is_inside_tree():
		return
	# No air dash: a wheeled machine needs a wheel on the floor to push off.
	if not drive_module.bodiless():
		var grounded := false
		for c in drive_module.wheel_contacts():
			if c:
				grounded = true
				break
		if not grounded:
			return
	# Read through the physics server's direct state, never the node's cached velocity (the
	# srimech damping's lesson: the cache lags a step when a replay seek runs 16 a frame).
	var state := PhysicsServer3D.body_get_direct_state(chassis.get_rid())
	if state == null:
		return
	var dir := _boost_strafe_dir if drive_module.strafes() else _flat_nose() * _boost_sign
	var cap: float = drive_module.top_speed() * speed_factor()
	var along := state.linear_velocity.dot(dir)
	if along >= cap:
		return
	var scale := drive_module.power_scale()
	chassis.apply_central_force(dir * BOOST_ACCEL * boost_factor() * scale * total_mass())


func _flat_nose() -> Vector3:
	var state := PhysicsServer3D.body_get_direct_state(chassis.get_rid())
	var fwd := state.transform.basis.x if state != null else chassis.global_basis.x
	fwd.y = 0.0
	return fwd.normalized() if fwd.length_squared() > 1e-6 else Vector3.RIGHT


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
	_righting_ticks = RIGHTING_TICKS


## QA D1 (systems gauntlet): the kick alone gave 8 to 10 rad/s of roll and the hull went a
## full turn and landed on its back again. For RIGHTING_TICKS after a kick, every tick the hull
## is within RIGHTING_UP of upright its roll rate (about its own nose axis) is cut by
## RIGHTING_DAMP, on every attached body, so the roll is a half turn that stops upright.
const RIGHTING_TICKS := 60
const RIGHTING_UP := 0.35
const RIGHTING_DAMP := 0.6


func _damp_righting_roll() -> void:
	_righting_ticks -= 1
	if chassis == null or not chassis.is_inside_tree():
		return
	# Read and written through the physics server's direct state, never the node's cached
	# transform or velocity: those lag a step when a replay seek runs 16 steps a frame.
	var state := PhysicsServer3D.body_get_direct_state(chassis.get_rid())
	if state == null:
		return
	var basis := state.transform.basis
	if basis.y.y < RIGHTING_UP:
		return
	var axis := basis.x.normalized()
	var roll := state.angular_velocity.dot(axis)
	if absf(roll) < 0.05:
		return
	for part in _parts:
		if not is_instance_valid(part) or part.detached:
			continue
		var ps := PhysicsServer3D.body_get_direct_state(part.get_rid())
		if ps == null:
			continue
		ps.angular_velocity -= axis * ps.angular_velocity.dot(axis) * RIGHTING_DAMP


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
	if part.part_kind == "weapon":
		factor = 1.0 / _weapon_toughness
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
	# Boost clocks in simulation ticks (a hit-stop hold never ages them).
	if _boost_ticks > 0:
		_boost_ticks -= 1
	if _boost_cool > 0:
		_boost_cool -= 1
	_disrupt_weapon = maxf(_disrupt_weapon - delta, 0.0)
	_disrupt_drive = maxf(_disrupt_drive - delta, 0.0)
	if not _frozen:
		if weapon != null:
			weapon.physics_tick(delta)
		if _downforce > 0.0 and chassis != null:
			chassis.apply_central_force(Vector3.DOWN * total_mass() * 9.8 * _downforce)
		_flush_knockbacks()
		_cook_core(delta)
		if _righting_ticks > 0:
			_damp_righting_roll()
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


## Wave D (docs/wave-d-marshal-notes.md): the HOUSE BOT only, after the result has been built
## and sent. Undo `stop_for_result` so it can drive the finishing ritual (fight/mischief.gd).
## Never called on a competitor: they stay stopped, so no damage can land on them.
func resume_for_show() -> void:
	_frozen = false
	if weapon != null:
		weapon.set("jammed", _weapon_jammed)
	if drive_module != null and drive_module.has_method("thaw"):
		drive_module.call("thaw")


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
