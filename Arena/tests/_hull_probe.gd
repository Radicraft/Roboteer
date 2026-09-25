extends SceneTree
## Hero hull probe (skipped by test-arena.sh: leading underscore). docs/wave-a-hull-notes.md.
##
##   Godot --headless --fixed-fps 60 --path Arena --script tests/_hull_probe.gd -- [--flip]
##
## Boots the Tinribs fixture in the test arena (the Yard with no hazard), the opponent idle,
## and measures the player's machine:
##   static : resting heights (axle, lip, underside, crest), mass, chassis-floor contact;
##   drive  : a 90 degree turn from rest, then full throttle: turn time, time to 2 / 3 m/s,
##            top speed;
##   pivot  : yaw rate on the spot;
##   flip   : (--flip) the smallest upward impulse under the flank / under the nose that
##            leaves the machine inverted 3 s later, by bisection, one fresh fight a try.

const FIGHT_SCENE := "res://fight/fight.tscn"
const FIXTURE := "res://fight/fixtures/stage3_config.json"

var fight: Node
const IMPULSES_TRACE := [85.0]
var _chassis_override := ""


func _init() -> void:
	call_deferred("_run")


func _config() -> Dictionary:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	config["rules"] = {"duration_s": 60.0, "ko_count_s": 10, "mode": "test"}
	config["debug"] = {"opponent_ai": "idle"}
	return config


func _boot(rows: Array) -> Node:
	if fight != null:
		fight.queue_free()
		await process_frame
	var packed: PackedScene = load(FIGHT_SCENE)
	fight = packed.instantiate()
	root.add_child(fight)
	await process_frame
	fight.start_fight(_config(), rows)
	await process_frame
	return fight.bots()[0]


func _ticks(n: int) -> void:
	for i in n:
		await physics_frame


## Wait until the fight's own tick clock (which starts after the countdown) reaches n.
func _until_tick(n: int) -> void:
	var guard := 0
	while int(fight.get("_tick")) < n and guard < 2000:
		await physics_frame
		guard += 1


func _yaw(bot: Node) -> float:
	var f: Vector3 = bot.chassis.global_basis.x
	return atan2(-f.z, f.x)


func _run() -> void:
	var flip := "--flip" in OS.get_cmdline_user_args()
	if "--right-only" in OS.get_cmdline_user_args():
		await _self_right()
		quit(0)
		return
	await _static_and_drive()
	await _pivot()
	if flip:
		await _flip("flank")
		await _flip("nose")
		await _self_right()
	quit(0)


func _self_right() -> void:
	# Put it on its back with a big flank impulse, let it settle, fire the srimech.
	var ok := 0
	var tries := 0
	for impulse in (IMPULSES_TRACE if OS.get_cmdline_user_args().has("--trace-right") else [75.0, 85.0, 95.0, 110.0, 130.0, 200.0]):
		var bot: Node = await _boot([])
		await _until_tick(60)
		var c: RigidBody3D = bot.chassis
		var cm: ChassisBase = bot.chassis_module
		c.apply_impulse(Vector3.UP * impulse, c.global_basis * Vector3(-0.05, cm.floor_y(), cm.half_wid()))
		await _ticks(150)
		if not bot.is_inverted():
			continue
		tries += 1
		var rest_y := c.global_position.y
		var righted := false
		var peak := 0.0
		var presses := 0
		var upright_run := 0
		var t_right := -1.0
		# The player keeps pressing: the srimech fires whenever its cooldown allows, for up
		# to 10 s. Righted = upright and staying upright for a full second.
		for k in 600:
			if bot.is_inverted() and float(bot.get("_srimech_cooldown")) <= 0.0:
				bot.call("_try_secondary")
				presses += 1
			await physics_frame
			if OS.get_cmdline_user_args().has("--trace-right") and k % 6 == 0 and k < 160:
				print("  k %d y %.2f up.y %.2f right.y %.2f fwd.y %.2f angvel %s" % [k, c.global_position.y, c.global_basis.y.y, c.global_basis.z.y, c.global_basis.x.y, str(c.angular_velocity.snapped(Vector3.ONE * 0.1))])
			peak = maxf(peak, c.global_position.y)
			upright_run = 0 if bot.is_inverted() else upright_run + 1
			if upright_run >= 60:
				righted = true
				t_right = (k - 59) / 60.0
				break
		if righted:
			ok += 1
		print("SELFRIGHT impulse %.0f: inverted rest chassis y %.3f, righted %s at %.2f s after %d presses (peak y %.2f)" % [impulse, rest_y, str(righted), t_right, presses, peak])
	print("SELFRIGHT %d of %d" % [ok, tries])


func _rows(from: int, to: int, heading: Vector2, turn := 0.0) -> Array:
	var rows := []
	for t in range(from, to):
		rows.append([t, snappedf(heading.x, 0.0001), snappedf(heading.y, 0.0001), 0, 0, turn])
	return rows


func _static_and_drive() -> void:
	# Settle 90 ticks, then ask for a heading 90 degrees LEFT of the spawn facing.
	var probe_bot: Node = await _boot([])
	var facing: Vector3 = probe_bot.chassis.global_basis.x
	var left := Vector3(facing.z, 0.0, -facing.x)   # 90 deg left (yaw +)
	var rows := _rows(91, 900, Vector2(left.x, left.z))
	var bot: Node = await _boot(rows)
	await _until_tick(90)
	var c: RigidBody3D = bot.chassis
	var cm: ChassisBase = bot.chassis_module
	var floor_y := 0.0
	var lip: Vector3 = c.global_transform * cm.front_lip_point()
	var under: float = (c.global_transform * Vector3(0.0, cm.floor_y(), 0.0)).y
	var crest := -INF
	for holder in c.get_children():
		if holder is CollisionShape3D and (holder as CollisionShape3D).shape is ConvexPolygonShape3D:
			for p in ((holder as CollisionShape3D).shape as ConvexPolygonShape3D).points:
				crest = maxf(crest, (c.global_transform * (holder as CollisionShape3D).transform * p).y)
	var low := INF
	for holder in c.get_children():
		if holder is CollisionShape3D and (holder as CollisionShape3D).shape is ConvexPolygonShape3D:
			for p in ((holder as CollisionShape3D).shape as ConvexPolygonShape3D).points:
				low = minf(low, (c.global_transform * (holder as CollisionShape3D).transform * p).y)
	var wheel_r: float = bot.drive_module.radius
	var wheel_y := 0.0
	for w in bot.drive_module.wheels:
		wheel_y += (w as Node3D).global_position.y
	wheel_y /= float(bot.drive_module.wheels.size())
	print("STATIC wheel_r %.3f  axle %.4f (sink %.1f mm)  lip %.4f  underside %.4f  hull_low %.4f  crest %.4f  crest/D %.2f  mass %.1f  pitch %.2f deg  com_local %s"
		% [wheel_r, wheel_y, (wheel_r - wheel_y) * 1000.0, lip.y - floor_y, under, low, crest,
		crest / (2.0 * wheel_r), bot.total_mass(), rad_to_deg(asin(clampf(c.global_basis.x.y, -1, 1))),
		str(c.center_of_mass)])
	for w in bot.drive_module.wheels:
		print("  wheel %s y %.4f" % [(w as Node).name, (w as Node3D).global_position.y])
	for part in bot.get("_parts"):
		if not is_instance_valid(part):
			continue
		var lowp := INF
		for holder in (part as Node).get_children():
			if holder is CollisionShape3D:
				var sh: Shape3D = (holder as CollisionShape3D).shape
				var xf: Transform3D = (part as Node3D).global_transform * (holder as CollisionShape3D).transform
				if sh is BoxShape3D:
					var h: Vector3 = (sh as BoxShape3D).size * 0.5
					for sx in [-1, 1]:
						for sy in [-1, 1]:
							for sz in [-1, 1]:
								lowp = minf(lowp, (xf * Vector3(h.x * sx, h.y * sy, h.z * sz)).y)
				elif sh is ConvexPolygonShape3D:
					for q in (sh as ConvexPolygonShape3D).points:
						lowp = minf(lowp, (xf * q).y)
		print("  part %s low %.4f" % [(part as Node).name, lowp])
	# Drive: log until 300 ticks after the command started.
	var yaw0 := _yaw(bot)
	var want := yaw0 + PI * 0.5
	var t_turn := -1.0
	var t2 := -1.0
	var t3 := -1.0
	var vmax := 0.0
	var dist_at_2s := 0.0
	var start_pos: Vector3 = c.global_position
	for i in range(1, 260):
		await physics_frame
		var err := absf(wrapf(want - _yaw(bot), -PI, PI))
		if t_turn < 0.0 and err < deg_to_rad(5.0):
			t_turn = i / 60.0
		var v := Vector2(c.linear_velocity.x, c.linear_velocity.z).length()
		vmax = maxf(vmax, v)
		if t2 < 0.0 and v >= 2.0:
			t2 = i / 60.0
		if t3 < 0.0 and v >= 3.0:
			t3 = i / 60.0
		if i == 120:
			dist_at_2s = (c.global_position - start_pos).length()
	print("DRIVE turn90 %.2f s  to2ms %.2f s  to3ms %.2f s  vmax %.2f m/s  dist@2s %.2f m  inverted %s"
		% [t_turn, t2, t3, vmax, dist_at_2s, str(bot.is_inverted())])


func _pivot() -> void:
	var rows := _rows(91, 300, Vector2.ZERO, 1.0)
	var bot: Node = await _boot(rows)
	await _until_tick(150)
	var y0 := _yaw(bot)
	var total := 0.0
	var last := y0
	for i in 60:
		await physics_frame
		var y := _yaw(bot)
		total += wrapf(y - last, -PI, PI)
		last = y
	print("PIVOT %.1f deg/s" % rad_to_deg(total))


func _flip_try(where: String, impulse: float) -> bool:
	var bot: Node = await _boot([])
	await _until_tick(60)
	var c: RigidBody3D = bot.chassis
	var cm: ChassisBase = bot.chassis_module
	var at := Vector3.ZERO
	if where == "flank":
		# Under the right flank at the floor, like a flipper lip under the side.
		at = c.global_basis * Vector3(-0.05, cm.floor_y(), cm.half_wid())
	else:
		at = c.global_basis * Vector3(cm.half_len(), cm.floor_y(), 0.0)
	c.apply_impulse(Vector3.UP * impulse, at)
	# Srimech must not right it inside the window: judge at 1.2 s (it lands in ~0.6 s).
	var inverted := false
	for i in 72:
		await physics_frame
	inverted = c.global_basis.y.dot(Vector3.UP) < 0.0
	return inverted


func _flip(where: String) -> void:
	var lo := 0.0
	var hi := 200.0
	if not await _flip_try(where, hi):
		print("FLIP %s > %.0f N s (never inverted)" % [where, hi])
		return
	for i in 8:
		var mid := (lo + hi) * 0.5
		if await _flip_try(where, mid):
			hi = mid
		else:
			lo = mid
	print("FLIP %s threshold %.1f N s (between %.1f and %.1f)" % [where, (lo + hi) * 0.5, lo, hi])
