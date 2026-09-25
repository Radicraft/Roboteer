extends SceneTree
## QA (systems gauntlet, 2026-09-25): every drive on a legal hull, driven by a SCRIPT (not
## the AI) through a fixed bench in the Workshop Test Arena: rest height and sink, straight
## line top speed and 0-to-top, pivot and heading turn rates, a wall run and back off,
## 12 and 22 degree ramps and a 4 cm lip, and a forced inversion with the srimech held.
## Not a test: nothing passes or fails. One JSON line per bench goes to stdout ("DRIVE ...").
##
##   Godot --headless --fixed-fps 60 --path Arena --script qa/drives_gauntlet.gd -- \
##       [--drives=4wd,legs] [--weapon=flipper] [--hull=wedge] [--benches=rest,straight]
##
## The real AI fights for each drive are the weapons gauntlet with `--drive=`:
##   Godot ... --script qa/weapons_gauntlet.gd -- --weapons=flipper --drive=legs --opps=plain,w:flipper

const FIGHT_SCENE := "res://fight/fight.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"
const WG := preload("res://qa/weapons_gauntlet.gd")
const OAI := preload("res://ai/opponent_ai.gd")

const ALL_DRIVES := ["2wd", "4wd", "6wd", "tracks", "omni", "legs", "hover", "adaptive_tracks"]
const ALL_BENCHES := ["rest", "straight", "pivot", "heading", "strafe", "wall", "ramp12", "ramp22", "lip", "flip"]

var _drives: Array = ALL_DRIVES.duplicate()
var _benches: Array = ALL_BENCHES.duplicate()
var _weapon := "flipper"
var _hull := ""


## A driver the fight treats as the player's AI, but whose input is whatever the bench says.
class Scripted extends OpponentAI:
	var input: Dictionary = {"heading": Vector2.ZERO, "fire": false, "secondary": false, "turn": 0.0}
	func think(_me: Object, _foe: Object, _ctx: Dictionary) -> Dictionary:
		return input.duplicate()


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--drives="):
			_drives = Array(a.substr(9).split(","))
		elif a.begins_with("--benches="):
			_benches = Array(a.substr(10).split(","))
		elif a.begins_with("--weapon="):
			_weapon = a.substr(9)
		elif a.begins_with("--hull="):
			_hull = a.substr(7)
	_run()


func _run() -> void:
	await process_frame
	for d in _drives:
		var cfg := _build_for(str(d))
		if cfg.is_empty():
			print("DRIVE ", JSON.stringify({"drive": d, "error": "no legal build"}))
			continue
		for b in _benches:
			var row := await _bench(cfg, str(b))
			row["drive"] = d
			row["bench"] = b
			row["build"] = "%s/%s/%s" % [cfg["chassis"], cfg["drive"], cfg["weapon"]]
			print("DRIVE ", JSON.stringify(row))
	quit(0)


func _build_for(drive: String) -> Dictionary:
	var hulls: Array = [_hull] if _hull != "" else ["wedge", "box", "pyramid", "long_low"]
	for h in hulls:
		var cfg: Dictionary = WG.legal_build(_weapon, "player-1", "Subject", str(h), drive)
		if not cfg.is_empty():
			return cfg
	return {}


func _bodies(bot: Node) -> Array:
	var out: Array = []
	for n in bot.find_children("*", "RigidBody3D", true, false):
		out.append(n)
	return out


## Carry the whole machine by the rigid transform that takes the chassis to `target`.
func _move_all(bot: Node, target: Transform3D) -> void:
	var chassis: RigidBody3D = bot.get("chassis")
	var fix := target * chassis.global_transform.affine_inverse()
	var list := _bodies(bot)
	var targets: Array = []
	for b in list:
		targets.append(fix * (b as Node3D).global_transform)
	for i in list.size():
		var rb: RigidBody3D = list[i]
		rb.global_transform = targets[i]
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO


func _place(fight: Node, bot: Node, pos: Vector3, facing: Vector3) -> void:
	fight.call("set_down", bot, pos, facing)
	for b in _bodies(bot):
		(b as RigidBody3D).linear_velocity = Vector3.ZERO
		(b as RigidBody3D).angular_velocity = Vector3.ZERO


func _add_box(fight: Node, centre: Vector3, size: Vector3, pitch_deg: float) -> void:
	var arena: Node3D = fight.get("_arena")
	var body := StaticBody3D.new()
	body.collision_layer = FightTypes.LAYER_ARENA
	body.collision_mask = FightTypes.LAYER_BOT | FightTypes.LAYER_DEBRIS
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	body.physics_material_override = pm
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	arena.add_child(body)
	# pitch about Z: a ramp rising toward +x
	body.global_transform = Transform3D(Basis(Vector3.BACK, deg_to_rad(pitch_deg)), centre)


func _planar_speed(rb: RigidBody3D) -> float:
	return Vector2(rb.linear_velocity.x, rb.linear_velocity.z).length()


func _yaw(rb: RigidBody3D) -> float:
	var f := rb.global_basis.x
	return atan2(-f.z, f.x)


func _bench(subject: Dictionary, bench: String) -> Dictionary:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var opp: Dictionary = WG.opponent_for("flipper", "plain")
	opp["controller"] = "dummy"
	config["seed"] = 11
	config["arena"] = "yard"
	config["rules"] = {"mode": "test"}
	config["debug"] = {"opponent_ai": "idle", "player_ai": "normal"}
	config["bots"] = [subject.duplicate(true), opp]

	var fight: Node = (load(FIGHT_SCENE) as PackedScene).instantiate()
	root.add_child(fight)
	await process_frame
	fight.call("start_fight", config)
	await process_frame
	var drv := Scripted.new(RandomNumberGenerator.new())
	fight.set("_player_ai", drv)
	var bots: Array = fight.get("_bots") as Array
	var me: Node = bots[0]
	var foe: Node = bots[1]
	# wait out the countdown
	var guard := 0
	while int(fight.get("state")) != 2 and guard < 600:
		await physics_frame
		guard += 1
	# park the dummy in the far corner, out of every bench's way
	_place(fight, foe, Vector3(3.8, 0.3, 3.8), Vector3.RIGHT)
	var ch: RigidBody3D = me.get("chassis")
	var dm: Object = me.get("drive_module")
	var row := {}
	var cat: Dictionary = PartsCatalogue.drive(str(subject["drive"]))
	row["cat_top"] = cat.get("top_speed", 0)
	row["cat_turn"] = cat.get("turn_rate", 0)
	row["mass"] = snappedf(float(me.call("total_mass")), 0.1)

	match bench:
		"rest":
			_place(fight, me, Vector3(0, 0.3, 0), Vector3.RIGHT)
			for i in 120:
				await physics_frame
			var ys: Array = []
			var sinks: Array = []
			for i in 60:
				await physics_frame
				ys.append(ch.global_position.y)
			var wheels: Array = dm.get("wheels") if dm != null else []
			var r := float(dm.get("radius")) if dm != null else FightTypes.WHEEL_RADIUS
			for w in wheels:
				sinks.append(snappedf((r - (w as Node3D).global_position.y) * 1000.0, 0.1))
			row["chassis_y"] = snappedf(_mean(ys), 0.001)
			row["chassis_y_range_mm"] = snappedf((ys.max() - ys.min()) * 1000.0, 0.1)
			row["wheel_sink_mm"] = sinks
			row["wheel_radius"] = r
			row["up"] = snappedf(ch.global_basis.y.dot(Vector3.UP), 0.001)
			row["contacts"] = str(me.call("wheel_contacts"))
			var touching := []
			for b in ch.get_colliding_bodies():
				touching.append(str(b.name))
			row["chassis_touching"] = touching
			row["bodiless"] = bool(dm.call("bodiless")) if dm != null else false
		"straight":
			_place(fight, me, Vector3(-4.2, 0.3, 0.0), Vector3.RIGHT)
			for i in 30:
				await physics_frame
			drv.input["heading"] = Vector2(1, 0)
			var sp: Array = []
			var x0 := ch.global_position.x
			for i in 150:
				await physics_frame
				sp.append(_planar_speed(ch))
				if ch.global_position.x > 3.4:
					break
			var top := 0.0
			for i in range(5, sp.size()):
				var m := (float(sp[i]) + float(sp[i - 1]) + float(sp[i - 2]) + float(sp[i - 3]) + float(sp[i - 4])) / 5.0
				top = maxf(top, m)
			var t90 := -1.0
			for i in sp.size():
				if float(sp[i]) >= 0.9 * top:
					t90 = i / 60.0
					break
			row["top_speed"] = snappedf(top, 0.01)
			row["t90_s"] = snappedf(t90, 0.01)
			row["dist_m"] = snappedf(ch.global_position.x - x0, 0.01)
			row["drift_z_m"] = snappedf(ch.global_position.z, 0.01)
			row["up_end"] = snappedf(ch.global_basis.y.dot(Vector3.UP), 0.01)
			row["peak_y"] = snappedf(0.0, 0.01)
		"pivot":
			_place(fight, me, Vector3(0, 0.3, 0), Vector3.RIGHT)
			for i in 30:
				await physics_frame
			drv.input["turn"] = 1.0
			var total := 0.0
			var last := _yaw(ch)
			var p0 := ch.global_position
			for i in 180:
				await physics_frame
				var y := _yaw(ch)
				if i >= 60:
					total += wrapf(y - last, -PI, PI)
				last = y
			row["pivot_deg_s"] = snappedf(rad_to_deg(total) / 2.0, 0.1)
			row["pivot_wander_m"] = snappedf(Vector2(ch.global_position.x - p0.x, ch.global_position.z - p0.z).length(), 0.01)
		"heading":
			# from rest, ask for a heading 90 degrees left of the nose and then 180 behind
			_place(fight, me, Vector3(-2.0, 0.3, 0), Vector3.RIGHT)
			for i in 30:
				await physics_frame
			var want := Vector2(0, -1)
			drv.input["heading"] = want
			var t_90 := -1.0
			for i in 240:
				await physics_frame
				var f := ch.global_basis.x
				var ang := rad_to_deg(Vector2(f.x, f.z).angle_to(want))
				if absf(ang) < 10.0:
					t_90 = i / 60.0
					break
			row["turn90_s"] = snappedf(t_90, 0.01)
			row["travel_during_turn_m"] = snappedf(Vector2(ch.global_position.x + 2.0, ch.global_position.z).length(), 0.01)
		"strafe":
			# stick 90 degrees and 45 degrees off the nose for 1.5 s each, from rest
			_place(fight, me, Vector3(-2.0, 0.3, 0), Vector3.RIGHT)
			for i in 30:
				await physics_frame
			drv.input["heading"] = Vector2(0, 1)
			var p0 := ch.global_position
			for i in 90:
				await physics_frame
			row["side_90_m"] = snappedf(ch.global_position.z - p0.z, 0.01)
			row["fwd_90_m"] = snappedf(ch.global_position.x - p0.x, 0.01)
			row["yaw_90_deg"] = snappedf(rad_to_deg(_yaw(ch)), 0.1)
			_place(fight, me, Vector3(-2.0, 0.3, 0), Vector3.RIGHT)
			drv.input["heading"] = Vector2.ZERO
			for i in 30:
				await physics_frame
			drv.input["heading"] = Vector2(0.7071, 0.7071)
			p0 = ch.global_position
			for i in 90:
				await physics_frame
			row["diag_travel_m"] = snappedf(Vector2(ch.global_position.x - p0.x, ch.global_position.z - p0.z).length(), 0.01)
			row["diag_yaw_deg"] = snappedf(rad_to_deg(_yaw(ch)), 0.1)
		"wall":
			_place(fight, me, Vector3(-2.0, 0.3, 0.0), Vector3.LEFT)
			for i in 30:
				await physics_frame
			drv.input["heading"] = Vector2(-1, 0)
			var max_tilt := 0.0
			var peak := 0.0
			for i in 240:
				await physics_frame
				max_tilt = maxf(max_tilt, rad_to_deg(acos(clampf(ch.global_basis.y.dot(Vector3.UP), -1, 1))))
				peak = maxf(peak, ch.global_position.y)
			var x_wall := ch.global_position.x
			row["wall_x"] = snappedf(x_wall, 0.01)
			row["wall_max_tilt_deg"] = snappedf(max_tilt, 0.1)
			row["wall_peak_y"] = snappedf(peak, 0.01)
			row["inverted_at_wall"] = bool(me.call("is_inverted"))
			# now drive away
			drv.input["heading"] = Vector2(1, 0)
			for i in 180:
				await physics_frame
			row["off_wall_m"] = snappedf(ch.global_position.x - x_wall, 0.01)
			row["inverted_after"] = bool(me.call("is_inverted"))
			# glancing run along the wall: 30 degrees into it
			_place(fight, me, Vector3(-3.0, 0.3, -3.0), Vector3(-0.5, 0, 0.866))
			drv.input["heading"] = Vector2(-0.5, 0.866)
			for i in 30:
				await physics_frame
			var z0 := ch.global_position.z
			for i in 180:
				await physics_frame
			row["glance_along_m"] = snappedf(ch.global_position.z - z0, 0.01)
			row["glance_inverted"] = bool(me.call("is_inverted"))
		"ramp12", "ramp22", "lip":
			var ang := 12.0 if bench == "ramp12" else 22.0
			var top_h := 0.30
			if bench == "lip":
				# a 4 cm step across the lane, 1 m deep
				_add_box(fight, Vector3(0.5, 0.02, 0.0), Vector3(1.0, 0.04, 3.0), 0.0)
				top_h = 0.04
			else:
				var run := top_h / tan(deg_to_rad(ang))
				var len := top_h / sin(deg_to_rad(ang))
				# slab centred so its top surface rises from x=-run/2 at y=0 to x=+run/2 at y=top_h
				var n := Vector3(-sin(deg_to_rad(ang)), cos(deg_to_rad(ang)), 0)
				var c := Vector3(0.0, top_h * 0.5, 0.0) - n * 0.05
				_add_box(fight, c, Vector3(len, 0.1, 3.0), ang)
				# a flat deck at the top, 1 m long
				_add_box(fight, Vector3(run * 0.5 + 0.5, top_h - 0.05, 0.0), Vector3(1.0, 0.1, 3.0), 0.0)
			await physics_frame
			_place(fight, me, Vector3(-3.2, 0.3, 0.0), Vector3.RIGHT)
			for i in 30:
				await physics_frame
			drv.input["heading"] = Vector2(1, 0)
			var peak := 0.0
			var t_top := -1.0
			var min_up := 1.0
			for i in 300:
				await physics_frame
				peak = maxf(peak, ch.global_position.y)
				min_up = minf(min_up, ch.global_basis.y.dot(Vector3.UP))
				if t_top < 0.0 and ch.global_position.x > (1.2 if bench == "lip" else 0.6) \
						and (bench == "lip" or ch.global_position.y > top_h * 0.8):
					t_top = i / 60.0
			row["top_h"] = top_h
			row["peak_chassis_y"] = snappedf(peak, 0.01)
			row["end_x"] = snappedf(ch.global_position.x, 0.01)
			row["reached_top_s"] = snappedf(t_top, 0.01)
			row["min_up"] = snappedf(min_up, 0.01)
			row["inverted_end"] = bool(me.call("is_inverted"))
		"flip":
			_place(fight, me, Vector3(0, 0.5, 0), Vector3.RIGHT)
			for i in 10:
				await physics_frame
			var t := ch.global_transform
			var flipped := Transform3D(Basis(Vector3.RIGHT, PI) * t.basis, t.origin + Vector3(0, 0.35, 0))
			_move_all(me, flipped)
			for i in 60:
				await physics_frame
			row["landed_inverted"] = bool(me.call("is_inverted"))
			# first: can it drive on its back? (invertible hulls should)
			drv.input["heading"] = Vector2(1, 0)
			var x0 := ch.global_position.x
			for i in 60:
				await physics_frame
			row["inverted_drive_m"] = snappedf(absf(ch.global_position.x - x0), 0.01)
			drv.input["heading"] = Vector2.ZERO
			# press the srimech every third of a second while inverted, as a player would
			var t_right := -1.0
			var presses := 0
			var flips := 0
			var was_inv := bool(me.call("is_inverted"))
			var ups: Array = []
			for i in 480:
				var inv := bool(me.call("is_inverted"))
				drv.input["secondary"] = inv and (i % 20) < 2
				if inv and i % 20 == 0:
					presses += 1
				await physics_frame
				inv = bool(me.call("is_inverted"))
				if inv != was_inv:
					flips += 1
				was_inv = inv
				ups.append(ch.global_basis.y.dot(Vector3.UP))
				if OS.get_environment("QA_TRACE") != "" and i % 4 == 0:
					print("FLIPTRACE i=%d up=%.2f y=%.2f angv=%s press=%s" % [i, ch.global_basis.y.dot(Vector3.UP), ch.global_position.y, str(ch.angular_velocity.snappedf(0.1)), str(drv.input["secondary"])])
				if not inv and ch.global_basis.y.dot(Vector3.UP) > 0.7 and t_right < 0.0:
					t_right = i / 60.0
			drv.input["secondary"] = false
			row["self_right_s"] = snappedf(t_right, 0.01)
			row["srimech_presses"] = presses
			row["state_changes"] = flips
			var upright_end := 0
			for i in range(ups.size() - 120, ups.size()):
				if float(ups[i]) > 0.7:
					upright_end += 1
			row["upright_last_2s"] = snappedf(upright_end / 120.0, 0.01)
			row["up_end"] = snappedf(ch.global_basis.y.dot(Vector3.UP), 0.01)
			# drive after righting
			drv.input["heading"] = Vector2(-1, 0)
			var x1 := ch.global_position.x
			for i in 60:
				await physics_frame
			row["drive_after_m"] = snappedf(absf(ch.global_position.x - x1), 0.01)
	root.remove_child(fight)
	fight.queue_free()
	await process_frame
	await process_frame
	return row


static func _mean(a: Array) -> float:
	var s := 0.0
	for v in a:
		s += float(v)
	return s / maxf(float(a.size()), 1.0)
