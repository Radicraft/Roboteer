extends SceneTree
## The thirteen wave P part models and materials (agent E).
##   Godot --headless --path Arena --script tests/parts_p_test.gd
##
## What this can prove headlessly, and what it deliberately does not claim:
##
## It CAN prove that every one of the thirteen ids of brief v5 section 9.5 has art
## rather than a fallback, that each model is the size of the collision body the
## gameplay actually uses (a model that does not match its body is a machine whose
## hits land nowhere near where the player aimed), that the sockets D1 and D2 asked
## for by name exist and sit where they said, that the two armour faces are real
## PBR material sets and not flat colours, that the belt's sprockets are set up to
## turn, that the hover carries the glow node agent F lights, and that a machine
## built on each new part actually wears the model when it is assembled.
##
## It CANNOT prove what any of it LOOKS like: --headless has no renderer. The look
## was judged from EEVEE review renders (Art/review/parts-contact-sheet.png, built
## by Tools/blender/render_contact_sheet.py) and cannot be settled short of a
## phone under Forward+. docs/wave-p-e-notes.md.

const BOT := "res://bot/bot.tscn"
const LIVERY := Color(0.20, 0.34, 0.63)

## id -> the envelope the gameplay gives it, from D1's and D2's collision bodies,
## and how much the model is allowed to stand outside it. The slack is not
## sloppiness: a muzzle, a tooth tip and an electrode are all SUPPOSED to be proud
## of the box that does the hitting, and every one of these numbers was read off
## the weapon script it belongs to.
const ENVELOPE := {
	"shock_prod": {"size": Vector3(0.10, 0.14, 0.26), "slack": 0.02,
		"origin": "back"},
	"tesla_arc": {"size": Vector3(0.14, 0.18, 0.22), "slack": 0.03,
		"origin": "back"},
	"drill_lance": {"size": Vector3(0.30, 0.15, 0.15), "slack": 0.02,
		"origin": "centre"},
	"twin_saw": {"size": Vector3(0.38, 0.38, 0.020), "slack": 0.03,
		"origin": "centre"},
	"napalm_cannon": {"size": Vector3(0.18, 0.16, 0.18), "slack": 0.03,
		"origin": "back"},
	"vortex_spinner": {"size": Vector3(0.96, 0.21, 0.96), "slack": 0.03,
		"origin": "centre"},
}

## Sockets each new part has to carry, because something reads them by name.
const SOCKETS := {
	"shock_prod": ["socket_pivot", "socket_tip"],
	"tesla_arc": ["socket_pivot", "socket_spark", "socket_tip"],
	"drill_lance": ["socket_pivot", "socket_tip"],
	"twin_saw": ["socket_pivot", "socket_tip"],
	"napalm_cannon": ["socket_pivot", "socket_muzzle", "socket_tip"],
	"vortex_spinner": ["socket_pivot", "socket_tip"],
	"legs": ["socket_hip", "socket_tip"],
	"overcharge_core": ["socket_pivot", "socket_tip"],
	"apex": ["socket_weapon_front", "socket_weapon_top", "socket_armour_front",
		"socket_armour_rear", "socket_armour_sides_l", "socket_armour_sides_r",
		"socket_armour_top", "socket_utility_0", "socket_utility_1",
		"socket_srimech", "socket_wheel_fr", "socket_wheel_fl",
		"socket_wheel_4wd_fr", "socket_wheel_2wd_rr"],
}

## The eleven ids that must have a .glb, plus the reactive plate, which is a model
## too: reactive armour is a grid of cassettes, not a sheet.
const MODELS := ["shock_prod", "tesla_arc", "drill_lance", "twin_saw",
	"napalm_cannon", "vortex_spinner", "legs", "hover", "adaptive_tracks",
	"apex", "overcharge_core", "plate_flat_reactive"]

## The two armour faces, which are material sets rather than meshes.
const ARMOUR_MATERIALS := ["reinforced", "reactive"]

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	_check_models_exist()
	_check_envelopes()
	_check_sockets()
	_check_armour_materials()
	_check_copper()
	_check_moving_parts()
	await _check_machines_wear_them()
	_finish()


# ---------------------------------------------------------------------------
# 1. There is art, not a fallback
# ---------------------------------------------------------------------------
func _check_models_exist() -> void:
	for id in MODELS:
		_check(PartVisuals.has_model(id), "%s: has a model" % id)
		var row := PartsCatalogue.model(id)
		_check(not row.is_empty() and int(row.get("tris", 0)) > 0,
			"%s: is in the manifest with triangles (%d)"
			% [id, int(row.get("tris", 0))])
		_check(bool(row.get("uv0", false)), "%s: is unwrapped" % id)


# ---------------------------------------------------------------------------
# 2. The model is the size of the thing that hits
# ---------------------------------------------------------------------------
func _check_envelopes() -> void:
	for id in ENVELOPE.keys():
		var want: Dictionary = ENVELOPE[id]
		var size: Vector3 = want["size"]
		var slack: float = want["slack"]
		var row := PartsCatalogue.model(id)
		if row.is_empty():
			_fail("%s: no manifest row to measure" % id)
			continue
		var lo := _vec(row.get("aabb_min", []))
		var hi := _vec(row.get("aabb_max", []))
		var expect_lo: Vector3
		var expect_hi: Vector3
		if str(want["origin"]) == "back":
			# authored from the back face forward, centred across and up
			expect_lo = Vector3(0.0, -size.y * 0.5, -size.z * 0.5)
			expect_hi = Vector3(size.x, size.y * 0.5, size.z * 0.5)
		else:
			expect_lo = -size * 0.5
			expect_hi = size * 0.5
		var out := maxf(_worst(expect_lo - lo), _worst(hi - expect_hi))
		_check(out <= slack,
			"%s: the model sits inside its collision body plus %.0f mm (worst %.0f mm)"
			% [id, slack * 1000.0, out * 1000.0])
		# and it is not a stub either: it has to fill most of the body
		var fill := (hi - lo)
		_check(fill.x >= size.x * 0.6 and fill.y >= size.y * 0.35
				and fill.z >= size.z * 0.6,
			"%s: and fills it, rather than rattling around inside it" % id)


func _worst(v: Vector3) -> float:
	return maxf(maxf(v.x, v.y), maxf(v.z, 0.0))


func _vec(raw: Variant) -> Vector3:
	var a: Array = raw as Array
	if a == null or a.size() < 3:
		return Vector3.ZERO
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


# ---------------------------------------------------------------------------
# 3. The sockets D1 and D2 asked for, by name, where they said
# ---------------------------------------------------------------------------
func _check_sockets() -> void:
	for id in SOCKETS.keys():
		var model := PartVisuals.instantiate(str(id))
		if model == null:
			_fail("%s: will not instantiate" % id)
			continue
		var live := PartVisuals.read_sockets(model)
		var promised := PartsCatalogue.model_sockets(str(id))
		for name in SOCKETS[id]:
			_check(live.has(name), "%s: carries %s" % [id, name])
			if live.has(name) and promised.has(name):
				_check((live[name] as Vector3).distance_to(
						promised[name] as Vector3) < 0.001,
					"%s: %s reads back where the manifest says" % [id, name])
		model.free()

	# The two that have a stated position, not merely a name.
	var arc := PartVisuals.instantiate("tesla_arc")
	if arc != null:
		var s := PartVisuals.read_sockets(arc)
		var spark: Vector3 = s.get("socket_spark", Vector3.ZERO)
		_check(spark.y > 0.06,
			"tesla_arc: socket_spark is up at the electrode, not on the base (%.3f)"
			% spark.y)
		arc.free()
	var cannon := PartVisuals.instantiate("napalm_cannon")
	if cannon != null:
		var s := PartVisuals.read_sockets(cannon)
		var muzzle: Vector3 = s.get("socket_muzzle", Vector3.ZERO)
		_check(muzzle.x > 0.15,
			"napalm_cannon: socket_muzzle is at the mouth, not the breech (%.3f)"
			% muzzle.x)
		cannon.free()

	# The apex's weapon mounts must still be the numbers ChassisBase was already
	# handing out, or landing this model silently moves a weapon D2 measured.
	var apex := PartVisuals.instantiate("apex")
	if apex != null:
		var s := PartVisuals.read_sockets(apex)
		var spec := PartsCatalogue.chassis("apex")
		var hl := float((spec.get("footprint", [1.0, 0.7]) as Array)[0]) * 0.5
		var floor_y := -0.11 + float(spec.get("clearance_front", 0.025))
		var height := float(spec.get("height", 0.22))
		var front: Vector3 = s.get("socket_weapon_front", Vector3.ZERO)
		var top: Vector3 = s.get("socket_weapon_top", Vector3.ZERO)
		_check(front.distance_to(Vector3(hl * 0.85, floor_y + height * 0.3, 0.0))
				< 0.001,
			"apex: socket_weapon_front is exactly the fallback it replaced")
		_check(top.distance_to(Vector3(hl * 0.1, floor_y + height, 0.0)) < 0.001,
			"apex: socket_weapon_top is exactly the fallback it replaced")
		apex.free()


# ---------------------------------------------------------------------------
# 4. The two armour faces are real material sets
# ---------------------------------------------------------------------------
func _check_armour_materials() -> void:
	var steel := PartVisuals.armour_material("steel", LIVERY)
	for name in ARMOUR_MATERIALS:
		var material := PartVisuals.armour_material(name, LIVERY)
		var standard := material as StandardMaterial3D
		_check(standard != null, "%s: is a StandardMaterial3D" % name)
		if standard == null:
			continue
		_check(standard.albedo_texture != null,
			"%s: has an albedo map, not a flat colour" % name)
		_check(standard.normal_enabled and standard.normal_texture != null,
			"%s: has a normal map and it is switched on" % name)
		_check(standard.roughness_texture != null,
			"%s: has a roughness map" % name)
		_check(standard != steel, "%s: is not just the steel material" % name)
	# and the two are not each other: reinforced is metal, reactive is a coating
	var reinforced := PartVisuals.armour_material("reinforced", LIVERY) as StandardMaterial3D
	var reactive := PartVisuals.armour_material("reactive", LIVERY) as StandardMaterial3D
	if reinforced != null and reactive != null:
		_check(reinforced.metallic > 0.5 and reactive.metallic < 0.5,
			"reinforced reads as bare hardened steel and reactive as a matt coating")


# ---------------------------------------------------------------------------
# 5. The ninth material slot
# ---------------------------------------------------------------------------
func _check_copper() -> void:
	var copper := PartVisuals.slot_material("copper", LIVERY) as StandardMaterial3D
	_check(copper != null, "copper: the slot resolves to a material")
	if copper == null:
		return
	_check(copper.metallic > 0.5, "copper: is metallic")
	_check(copper.albedo_color.r > copper.albedo_color.b + 0.2,
		"copper: is warm, which is the whole reason it exists")
	# every part that uses it says so in the manifest
	for id in ["shock_prod", "tesla_arc", "napalm_cannon", "overcharge_core"]:
		var mats: Dictionary = PartsCatalogue.model(id).get("materials", {}) as Dictionary
		_check(mats.has("copper"), "%s: actually carries copper geometry" % id)


# ---------------------------------------------------------------------------
# 6. The things that move
# ---------------------------------------------------------------------------
func _check_moving_parts() -> void:
	# the belt's sprockets and road wheels are their own nodes, on their own axes
	var belt := PartVisuals.instantiate("adaptive_tracks")
	if belt == null:
		_fail("adaptive_tracks: will not instantiate")
	else:
		var spinners := _named(belt, "spin_")
		_check(spinners.size() == 6,
			"adaptive_tracks: six spin_ nodes, two sprockets and four road wheels (%d)"
			% spinners.size())
		var off_axis := 0
		for node in spinners:
			# a node authored at the part origin cannot turn about its own axle
			if absf(node.position.x) > 0.001 or absf(node.position.y) > 0.001:
				off_axis += 1
		_check(off_axis == spinners.size(),
			"adaptive_tracks: every spin_ node sits on its own axle (%d of %d)"
			% [off_axis, spinners.size()])
		_check(belt.find_child("PartAnim", false, false) != null,
			"adaptive_tracks: PartVisuals gave it a PartAnim")
		belt.free()

	# the hover carries the glow node agent F lights
	var hover := PartVisuals.instantiate("hover")
	if hover == null:
		_fail("hover: will not instantiate")
	else:
		PartVisuals.bind(hover, LIVERY)
		var glow := _named(hover, "glow")
		_check(glow.size() == 1, "hover: carries a glow node (%d)" % glow.size())
		if not glow.is_empty():
			var mesh := glow[0] as MeshInstance3D
			var material := mesh.get_surface_override_material(0) as StandardMaterial3D
			_check(material != null and material.emission_enabled,
				"hover: the glow node binds to an emissive material")
		_check(hover.find_child("PartAnim", false, false) == null,
			"hover: is NOT given the roller animation, which is the belt's")
		hover.free()

	# the leg is authored hanging from its own origin, which is what legs.gd
	# places on the hull underside before scaling it to the drop
	var row := PartsCatalogue.model("legs")
	var lo := _vec(row.get("aabb_min", []))
	var hi := _vec(row.get("aabb_max", []))
	_check(hi.y <= 0.02 and lo.y < -0.08,
		"legs: hangs below its origin (%.3f .. %.3f)" % [lo.y, hi.y])
	_check(hi.x - lo.x < 0.20 and hi.z - lo.z < 0.16,
		"legs: stays inside the foot's collision footprint")


func _named(node: Node, prefix: String) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if node is Node3D and String(node.name).begins_with(prefix):
		out.append(node as Node3D)
	for child in node.get_children():
		out.append_array(_named(child, prefix))
	return out


# ---------------------------------------------------------------------------
# 7. A machine built on each one actually wears it
# ---------------------------------------------------------------------------
func _check_machines_wear_them() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var cases := [
		{"chassis": "apex", "drive": "4wd", "weapon": "flipper",
			"want": ["Model_apex"]},
		# The three drives RENAME the node they hang the model on ("Leg0",
		# "HoverSkirt", "TrackSkinL"), and two of them give the FALLBACK the same
		# name, so the name alone proves nothing. `deep` asks for a node only the
		# real model can produce: a leg's hip socket, the hover's lit pod, the
		# belt's sprocket on its own axle.
		{"chassis": "wedge", "drive": "legs", "weapon": "shock_prod",
			"want": ["Leg0", "Leg3", "Model_shock_prod"],
			"deep": ["socket_hip", "Stride"]},
		{"chassis": "wedge", "drive": "hover", "weapon": "tesla_arc",
			"want": ["HoverSkirt", "Model_tesla_arc"],
			"deep": ["glow", "Cushion"]},
		{"chassis": "box", "drive": "adaptive_tracks", "weapon": "drill_lance",
			"want": ["TrackSkinL", "TrackSkinR", "Model_drill_lance"],
			"deep": ["spin_sprocket_f", "spin_roller_0", "PartAnim"]},
		{"chassis": "box", "drive": "4wd", "weapon": "twin_saw",
			"want": ["Model_twin_saw"]},
		{"chassis": "box", "drive": "4wd", "weapon": "napalm_cannon",
			"want": ["Model_napalm_cannon"]},
		{"chassis": "shell", "drive": "4wd", "weapon": "vortex_spinner",
			"want": ["Model_vortex_spinner"]},
		{"chassis": "box", "drive": "4wd", "weapon": "flipper",
			"utility": "overcharge_core", "want": ["Model_overcharge_core"]},
		{"chassis": "box", "drive": "4wd", "weapon": "flipper",
			"armour": "reactive", "want": ["Model_plate_flat_reactive"]},
	]
	for case_variant in cases:
		var case: Dictionary = case_variant
		var bot: Bot = (load(BOT) as PackedScene).instantiate()
		host.add_child(bot)
		bot.setup(_config(case), 0, RandomNumberGenerator.new())
		var names := {}
		_gather(bot, names)
		for wanted in case["want"]:
			_check(names.has(wanted), "%s on %s: wears %s"
				% [case["weapon"], case["chassis"], wanted])
		for wanted in case.get("deep", []):
			_check(names.has(wanted),
				"%s on %s: and it is the real model, not the fallback (%s)"
				% [case["weapon"], case["chassis"], wanted])
		host.remove_child(bot)
		bot.free()
		await process_frame
	await _check_apex_hands_over_its_body(host)
	root.remove_child(host)
	host.free()
	await process_frame


## The Apex is the second hull whose bodywork IS the weapon (D2, wave P): with a
## full body spinner on it, `levels()` pulls the collision hull in to
## CORE_FRACTION. The model has to come in with it, or the hull stands proud of
## its own ring at all four corners with nothing solid behind the overhang. This
## is the check that `apex.gd`'s `_on_model_bound` is still doing that.
func _check_apex_hands_over_its_body(host: Node3D) -> void:
	for case_variant in [
		{"weapon": "flipper", "shrunk": false},
		{"weapon": "vortex_spinner", "shrunk": true},
	]:
		var case: Dictionary = case_variant
		var bot: Bot = (load(BOT) as PackedScene).instantiate()
		host.add_child(bot)
		bot.setup(_config({"chassis": "apex", "drive": "4wd",
			"weapon": case["weapon"]}), 0, RandomNumberGenerator.new())
		var model := bot.chassis_module.model
		if model == null:
			_fail("apex with a %s: no model on the hull" % case["weapon"])
		else:
			var shrunk: bool = model.scale.x < 0.99
			_check(shrunk == bool(case["shrunk"]),
				"apex with a %s: the hull model %s (scale %.2f)"
				% [case["weapon"],
					"comes in with the ring" if case["shrunk"] else "stays full size",
					model.scale.x])
			if bool(case["shrunk"]):
				_check(is_equal_approx(model.scale.x, model.scale.y)
						and is_equal_approx(model.scale.y, model.scale.z),
					"apex with a %s: and it comes in uniformly, so the undercut keeps its shape"
					% case["weapon"])
		host.remove_child(bot)
		bot.free()
		await process_frame


func _config(case: Dictionary) -> Dictionary:
	var material := str(case.get("armour", "steel"))
	var utility: Array = []
	if case.has("utility"):
		utility.append(str(case["utility"]))
	if not bool(PartsCatalogue.chassis(str(case["chassis"])).get("invertible", false)):
		utility.append("srimech")
	return {
		"chassis": case["chassis"],
		"drive": case["drive"],
		"weapon": case["weapon"],
		"utility": utility,
		"livery": [LIVERY.r, LIVERY.g, LIVERY.b],
		"armour": {
			"front": {"material": material, "thickness": 2},
			"sides": {"material": material, "thickness": 1},
			"rear": {"material": material, "thickness": 1},
			"top": {"material": material, "thickness": 1},
		},
	}


func _gather(node: Node, out: Dictionary) -> void:
	out[String(node.name)] = true
	for child in node.get_children():
		_gather(child, out)


# ---------------------------------------------------------------------------
func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS  ", label)
	else:
		_failures += 1
		printerr("FAIL  ", label)
		print("FAIL  ", label)


func _fail(label: String) -> void:
	_checks += 1
	_failures += 1
	printerr("FAIL  ", label)
	print("FAIL  ", label)


func _finish() -> void:
	PartVisuals.reset_cache()
	print("")
	if _failures == 0:
		print("PASS  wave P parts: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  wave P parts: %d checks, %d failures" % [_checks, _failures])
		quit(1)
