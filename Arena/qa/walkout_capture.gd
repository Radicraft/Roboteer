extends SceneTree
## QA only (wave D walk-outs, docs/wave-d-walkout-notes.md). Plays the fight intro with its
## walk-outs in a real window and saves frames, for the review page:
##
##   Godot --path Arena --audio-driver Dummy --resolution 1206x556 \
##     --script qa/walkout_capture.gd -- --walk-shots=DIR [--walk-arenas=yard,coliseum] \
##     [--walk-mode=full|short] [--walk-style=career|quick] [--walk-house=thresher] \
##     [--walk-sequence=15] [--walk-only] [--walk-safe=l,t,r,b] [--walk-house-card]
##
## The fight is the desktop fixture with a rival across the floor (Clatterbox, as the shell
## would send it: roboteer, record, written lines, the builder's pips) and the player's own
## lines typed in. Per arena: three frames per walk-out (coming out of the gate, mid roll, the
## card settled), one of the house bot's shot, then the fly-past's first frame. Files are
## <arena>_<nn>_<label>.png. `--walk-sequence=FPS` also saves every 1/FPS s of intro time as
## <arena>_seq_<nnn>.png (the clips); `--walk-only` stops once the walk-outs are over.
## Not referenced by any shipped scene.

const FIGHT_SCENE := "res://fight/fight.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"
const ORDER := ["yard", "grinder", "drop_zone", "furnace", "crush", "coliseum"]

var _dir := ""
var _arenas: Array = ORDER.duplicate()
var _mode := "full"
var _style := "career"
var _house := ""
var _seq_fps := 0.0
var _walk_only := false
var _safe := {}
var _overview := false
var _house_card := false
var _debug_cam: Camera3D = null
var _fight: Node = null


func _initialize() -> void:
	for raw in OS.get_cmdline_user_args():
		var a := str(raw)
		if a.begins_with("--walk-shots="):
			_dir = a.get_slice("=", 1)
		elif a.begins_with("--walk-arenas="):
			_arenas = Array(a.get_slice("=", 1).split(","))
		elif a.begins_with("--walk-mode="):
			_mode = a.get_slice("=", 1)
		elif a.begins_with("--walk-style="):
			_style = a.get_slice("=", 1)
		elif a.begins_with("--walk-house="):
			_house = a.get_slice("=", 1)
		elif a.begins_with("--walk-sequence="):
			_seq_fps = float(a.get_slice("=", 1))
		elif a == "--walk-house-card":
			_house_card = true
		elif a == "--walk-overview":
			_overview = true
		elif a == "--walk-only":
			_walk_only = true
		elif a.begins_with("--walk-safe="):
			var p := a.get_slice("=", 1).split(",")
			if p.size() == 4:
				_safe = {"left": float(p[0]), "top": float(p[1]), "right": float(p[2]), "bottom": float(p[3])}
	if _dir != "":
		DirAccess.make_dir_recursive_absolute(_dir)
	_run()


func _run() -> void:
	await process_frame
	_fight = (load(FIGHT_SCENE) as PackedScene).instantiate()
	root.add_child(_fight)
	for i in 5:
		await process_frame
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	for arena_id in _arenas:
		await _shoot(fixture, str(arena_id))
	quit(0)


## The fixture with Clatterbox across the floor and the tape the shell would send.
static func demo_config(fixture: Dictionary, arena_id: String, mode: String, style: String,
		house: String, safe: Dictionary = {}) -> Dictionary:
	var config := fixture.duplicate(true)
	config["arena"] = arena_id
	config["intro"] = mode
	var rules: Dictionary = config["rules"]
	rules["duration_s"] = 180
	rules["mode"] = "fight"
	if house != "":
		rules["enforcer"] = house
		rules["enforcer_mode"] = "zone"
		rules["enforcer_speed"] = 0.6
	var rival: Dictionary = (PartsCatalogue.parts()["rivals"] as Dictionary)["clatterbox"]
	var opp: Dictionary = (config["bots"] as Array)[1]
	var build: Dictionary = rival["build"]
	for k in ["chassis", "drive", "weapon", "utility", "armour"]:
		opp[k] = build[k].duplicate(true) if build[k] is Dictionary or build[k] is Array else build[k]
	opp["name"] = rival["name"]
	opp["livery"] = rival["livery"]
	var wheels := int(PartsCatalogue.drive(str(opp["drive"])).get("wheels", 4))
	var dmg: Dictionary = opp["damage"]
	var ws: Array = []
	for i in wheels:
		ws.append(1.0)
	dmg["wheels"] = ws
	(config["bots"] as Array)[0]["livery"] = "#d9a21b"
	if not safe.is_empty():
		(config["presentation"] as Dictionary)["safe_area_px"] = safe
	var me: Dictionary = (config["bots"] as Array)[0]
	var mass_o := TapeCards.kg(BuildRules.total_weight(opp))
	var mass_p := TapeCards.kg(BuildRules.total_weight(me))
	var arm_o := TapeCards.kg(float(BuildRules.category_weights(opp)["armour"]))
	var arm_p := TapeCards.kg(float(BuildRules.category_weights(me)["armour"]))
	config["tape"] = {"style": style, "cards": [
		{"side": "opponent", "label": "OPPONENT", "name": "Clatterbox", "roboteer": "Dot Ferris",
			"mass": mass_o, "drive": "4WD", "weapon": "Saw",
			"stats": [{"label": "SPEED", "value": "3/5"}, {"label": "HIT", "value": "4/5"}, {"label": "ARMOUR", "value": arm_o}],
			"record": "Won 1, lost 2 against you",
			"strength": str(rival["strength"]), "weakness": str(rival["weakness"])},
		{"side": "player", "label": "YOUR MACHINE", "name": "Tinribs", "roboteer": "",
			"mass": mass_p, "drive": "4WD", "weapon": "Flipper",
			"stats": [{"label": "SPEED", "value": "3/5"}, {"label": "HIT", "value": "3/5"}, {"label": "ARMOUR", "value": arm_p}],
			"record": "Won 2, lost 1 against Clatterbox",
			"strength": "16 kg of flipper.", "weakness": "It knows it."},
	]}
	return config


func _shoot(fixture: Dictionary, arena_id: String) -> void:
	var config := demo_config(fixture, arena_id, _mode, _style, _house, _safe)
	# Freeze the intro while the venue builds and the shaders compile, then run it at 1x.
	FightIntro.test_speed = 0.0
	_fight.call("start_fight", config)
	for i in 45:
		await process_frame
	var intro: FightIntro = _fight.call("intro")
	if intro == null:
		print("walkout_capture: no intro in ", arena_id)
		return
	var plan: Array = []          # [time, label]
	var t := 0.0
	var n := 0
	var walk_end := 0.0
	for s in intro.shots():
		var shot: Dictionary = s
		var dur := float(shot["dur"])
		var kind := str(shot["kind"])
		if kind == "walkout":
			var side := str(shot.get("side", ""))
			plan.append([t + dur * 0.18, "%02d_%s_a_gate" % [n, side]])
			plan.append([t + dur * 0.42, "%02d_%s_b_roll" % [n, side]])
			plan.append([t + dur * 0.9, "%02d_%s_c_card" % [n, side]])
			walk_end = t + dur
		elif kind == "house":
			plan.append([t + dur * 0.85, "%02d_house" % n])
			walk_end = t + dur
		elif n > 0 and walk_end > 0.0 and t <= walk_end + 0.01:
			plan.append([t + 0.12, "%02d_after_%s" % [n, kind]])
		t += dur
		n += 1
	print("walkout_capture: %s %s %s, %.2f s total, walk-outs %.2f s, %d shots" % [arena_id, _mode, _style, t, walk_end, n])
	FightIntro.test_speed = 1.0
	# The kit's own clock ran while the intro was frozen for the warm-up: start the first
	# entrance again so the capture shows it from the top, as a player sees it.
	var kit: Node = _fight.get("_arena").get_node_or_null("VenueKit")
	if kit != null and kit.has_method("play_entrance"):
		kit.call("play_entrance", 1)
	var next_seq := 0.0
	var seq_n := 0
	while intro != null and is_instance_valid(intro) and intro.holding():
		var now := intro.elapsed()
		if _walk_only and now > walk_end + 0.3:
			break
		if _overview and intro.camera() != null:
			# Debug: a high three-quarter view over the gate being walked out of.
			if _debug_cam == null:
				_debug_cam = Camera3D.new()
				intro.camera().get_parent().get_parent().add_child(_debug_cam)
			var team := 1 if now < walk_end * 0.5 else 0
			var g := Vector3(7.0, 0, 7.0) * (1.0 if team == 1 else -1.0)
			var marks: Variant = _fight.get("_arena").get_node("VenueKit").get("_gate_marks")
			if marks is Array and (marks as Array).size() > team:
				g = (marks as Array)[team]
			var eye := g * 0.92 + Vector3.UP * 9.0
			_debug_cam.current = true
			_debug_cam.fov = 55.0
			_debug_cam.look_at_from_position(eye, g * 0.92, Vector3(0, 0, -1))
		if not plan.is_empty() and now >= float(plan[0][0]):
			_save("%s_%s" % [arena_id, str(plan[0][1])])
			plan.pop_front()
		if _seq_fps > 0.0 and now >= next_seq:
			_save("%s_seq_%03d" % [arena_id, seq_n])
			seq_n += 1
			next_seq += 1.0 / _seq_fps
		await process_frame
	if intro != null and is_instance_valid(intro) and intro.holding():
		intro.skip()
		for i in 60:
			await process_frame
	if _house_card and _house != "":
		# The house bot's small card, as it shows when it comes out of its corner mid-fight.
		for i in 20:
			await process_frame
		_fight.call("_tape_house_bot_out")
		for i in 40:
			await process_frame
		_save("%s_zz_house_out" % arena_id)


func _save(file_name: String) -> void:
	if _dir == "":
		return
	var img := root.get_texture().get_image()
	if img != null:
		img.save_png(_dir.path_join(file_name + ".png"))
