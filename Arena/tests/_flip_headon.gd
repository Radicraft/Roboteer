extends SceneTree
## Head-on flip probe (hull engineer, 2026-09-27; skipped by test-arena.sh: leading underscore).
## docs/wave-a-hull-notes.md, "the flip question".
##
##   Godot --headless --fixed-fps 60 --path Arena --script tests/_flip_headon.gd -- \
##       [--victims=flipper,shock_prod] [--out=X.jsonl]
##
## A real flipper (the fixture's wedge flipper, player side) drives straight at the subject
## (a legal wedge build of each victim weapon, AI idle), and fires the moment the victim sits
## on its arm, exactly as the AI does. Scenarios: victim facing the flipper (head-on) at yaw
## offsets 0/10/20/30 deg and lateral offsets 0/0.15 m, from two run-up distances; plus
## flank (90 deg) and rear (180 deg) for scale. Result per try: thrown (fired with a target),
## victim inverted 1.5 s after the throw, victim peak height.

const FIGHT_SCENE := "res://fight/fight.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"
const GAUNTLET := "res://qa/weapons_gauntlet.gd"

var fight: Node
var _out := ""


func _init() -> void:
	call_deferred("_run")


func _emit(row: Dictionary) -> void:
	var line := JSON.stringify(row)
	print("FLIPHEAD ", line)
	if _out != "":
		var f: FileAccess
		if FileAccess.file_exists(_out):
			f = FileAccess.open(_out, FileAccess.READ_WRITE)
			f.seek_end()
		else:
			f = FileAccess.open(_out, FileAccess.WRITE)
		f.store_line(line)
		f.close()


func _run() -> void:
	var victims := ["flipper", "shock_prod", "lifter", "twin_saw"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--victims="):
			victims = Array(a.substr(10).split(","))
		elif a.begins_with("--out="):
			_out = a.substr(6)
	var g: Script = load(GAUNTLET)
	var scen := []
	for dist in [1.4, 0.9]:
		for yaw in [0.0, 10.0, -10.0, 20.0, -20.0, 30.0]:
			for lat in [0.0, 0.15]:
				scen.append([dist, yaw, lat])
	if "--flank" in OS.get_cmdline_user_args():
		scen = []
	for w in victims:
		var victim: Dictionary = g.call("legal_build", str(w), "ai-1", "Victim", "wedge", "")
		victim["controller"] = "ai"
		var tally := {"head": [0, 0], "flank": [0, 0], "rear": [0, 0]}
		for s in scen:
			var r := await _try(victim, float(s[0]), float(s[1]), float(s[2]))
			r["victim"] = w
			r["kind"] = "head"
			_emit(r)
			_count(tally["head"], r)
		var side := [[90.0, 1.4, 0.0], [-90.0, 1.4, 0.0], [180.0, 1.4, 0.0], [90.0, 0.9, 0.0], [-90.0, 0.9, 0.0], [180.0, 0.9, 0.0]]
		if "--flank" in OS.get_cmdline_user_args():
			scen = []
			side = []
			for yaw in [60.0, -60.0, 90.0, -90.0, 120.0, -120.0]:
				for dist in [0.9, 1.2]:
					for lat in [0.0, 0.15]:
						side.append([yaw, dist, lat])
		for sd in side:
			var yaw: float = sd[0]
			var dist: float = sd[1]
			if true:
				var r := await _try(victim, dist, yaw, float(sd[2]))
				r["victim"] = w
				r["kind"] = "rear" if absf(yaw) > 150.0 else "flank"
				_emit(r)
				_count(tally[r["kind"]], r)
		print("FLIPSUM %s head %d/%d  flank %d/%d  rear %d/%d  (inverted / thrown)" % [w,
			tally["head"][0], tally["head"][1], tally["flank"][0], tally["flank"][1],
			tally["rear"][0], tally["rear"][1]])
	quit(0)


func _count(t: Array, r: Dictionary) -> void:
	if bool(r["thrown"]):
		t[1] += 1
		if bool(r["inverted"]):
			t[0] += 1


func _try(victim: Dictionary, dist: float, yaw_deg: float, lat: float) -> Dictionary:
	if fight != null:
		fight.queue_free()
		await process_frame
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	config["arena"] = "yard"
	config["rules"] = {"duration_s": 60.0, "ko_count_s": 10, "mode": "test"}
	config["debug"] = {"opponent_ai": "idle"}
	var v := victim.duplicate(true)
	config["bots"] = [config["bots"][0], v]
	var rows := []
	for t in range(62, 400):
		rows.append([t, 1.0, 0.0, 0, 0, 0.0])
	fight = (load(FIGHT_SCENE) as PackedScene).instantiate()
	root.add_child(fight)
	await process_frame
	fight.start_fight(config, rows)
	await process_frame
	var bots: Array = fight.bots()
	var atk: Node = bots[0]
	var vic: Node = bots[1]
	var guard := 0
	while int(fight.get("_tick")) < 58 and guard < 2000:
		await physics_frame
		guard += 1
	atk.call("place_at", Vector3(-dist - 0.4, 0.25, lat), Vector3.RIGHT)
	var yaw := deg_to_rad(yaw_deg)
	# Victim nose toward -x (the attacker), turned by yaw.
	var face := Vector3(-cos(yaw), 0.0, sin(yaw))
	vic.call("place_at", Vector3(0.4, 0.25, 0.0), face)
	var thrown := false
	var t_throw := -1
	var peak := 0.0
	var inverted := false
	var ticks := 0
	var ar: Object = atk.get("weapon")
	var scale := -1.0
	while ticks < 420:
		await physics_frame
		ticks += 1
		var vy: float = vic.chassis.global_position.y
		peak = maxf(peak, vy)
		if not thrown and ar != null and ar.has_method("_wedge_target") and ticks < 240:
			var tgt: RigidBody3D = ar.call("_wedge_target")
			if tgt != null and float(ar.get("_cooldown")) <= 0.0:
				scale = float(ar.call("_launch_scale", vic, tgt))
				ar.call("apply_input", true, true, 1.0 / 60.0)
				thrown = int(ar.get("_throws")) > 0
				if thrown:
					t_throw = ticks
				ar.call("apply_input", false, false, 1.0 / 60.0)
		if thrown and ticks == t_throw + 90:
			inverted = bool(vic.call("is_inverted"))
			break
	return {"dist": dist, "yaw": yaw_deg, "lat": lat, "thrown": thrown,
		"inverted": inverted, "peak": snappedf(peak, 0.01), "scale": snappedf(scale, 0.01),
		"vic_mass": snappedf(float(vic.call("total_mass")), 0.1),
		"vic_chassis": snappedf(float(vic.chassis.mass), 0.1)}
