extends SceneTree
## `camera_track`: the fight camera FOLLOWS THE PLAYER (brief v4 section 5, agent G4).
##   Godot --headless --path Arena --script tests/camera_track_test.gd
##
## The owner's first hands-on session on a phone: "the camera does not follow the player".
## Everything here is measured through a real SubViewport and the camera's own
## unproject_position, never through the rig's own arithmetic, because the rig believing it
## framed the player is exactly the thing that was wrong before.
##
## The brief's own test, verbatim: with the opponent parked 6 m away and the player driving
## a square, the player's projected position stays inside the centre 60 % of the frame for
## the whole run. Plus the lead cap, the zoom hold, the player-size floor and the endgame
## reveal.

## iPhone 17 landscape at 1 point per unit, which is the screen this is for.
const VIEW := Vector2i(1206, 556)
const DT := 1.0 / 60.0
## The brief: "the player is never further than 30 % of the frame from centre".
const CENTRE_BAND := 0.30
## Wave V, agent V4 (docs/wave-v-v4-notes.md). The owner played on the phone: "the bot
## feels a bit small on screen". The machine must read as a machine through an exchange,
## which is where a fight actually lives: the two are 0.9 m apart when they are touching
## and rarely past 2 m while they are trading. These are measured through the camera's own
## unproject_position of a BOT_SIZE_M vertical at the player, so they are what the screen
## shows and not what _distance_for_screen_fraction predicts (the two differ by about a
## tenth, because the player sits nearer the camera than the aim point does).
const EXCHANGE_MIN_FRACTION := 0.17
const EXCHANGE_MAX_FRACTION := 0.27
## Separation out to which the opponent must be wholly inside the frame, in metres, on the
## WORST bearing (straight up or down the camera's own ground axis, where the frame is only
## 556 pt tall). Past it `is_player_floored()` is true and fight.gd draws the arrow. It is
## less than TRACK_PAIR_RANGE_M and that is a measured trade, not an oversight: see the
## note on PLAYER_MIN_FRACTION in camera_rig.gd.
const OPPONENT_FRAMED_TO_M := 2.6

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var scene: PackedScene = load("res://ui/camera_rig.tscn") as PackedScene
	if scene == null:
		print("SKIP  camera track: ui/camera_rig.tscn is absent")
		quit(0)
		return

	await _test_square_drive(scene)
	await _test_zoom_hold(scene)
	await _test_exchange_size(scene)
	await _test_endgame_reveal(scene)
	await _test_manual_orbit_survives(scene)
	_finish()


# ------------------------------------------------------- the brief's own test

## The opponent is parked 6 m away, well past TRACK_PAIR_RANGE_M, so the camera is holding
## and the only thing keeping the player in frame is the tracking. The player drives a
## square at a real machine's speed and every single frame is measured.
func _test_square_drive(scene: PackedScene) -> void:
	var world := await _world(scene)
	var rig: CameraRig = world["rig"]
	var player: Node3D = world["player"]
	var foe: Node3D = world["foe"]
	var cam := rig.camera()

	# A 3 m square walked at 2.5 m/s, which is about a fast chassis, plus a lap and a bit
	# so every corner is taken twice and the ease has to keep up through each turn.
	var corners := [
		Vector3(-1.5, 0.25, -1.5), Vector3(1.5, 0.25, -1.5),
		Vector3(1.5, 0.25, 1.5), Vector3(-1.5, 0.25, 1.5),
	]
	player.position = corners[0]
	foe.position = Vector3(-1.5, 0.25, -1.5) + Vector3(6.0, 0.0, 0.0)
	rig.set_targets(player, foe)
	rig.reset_to_default()
	rig.fit_arena(FightTypes.ARENA_SIZE)

	var speed := 2.5
	var worst := 0.0
	var worst_at := Vector2.ZERO
	var worst_lead := 0.0
	var smallest := 1.0
	var frames := 0
	var leg := 0
	while leg < 8:
		var from: Vector3 = corners[leg % 4]
		var to: Vector3 = corners[(leg + 1) % 4]
		var travelled := 0.0
		var length := from.distance_to(to)
		while travelled < length:
			travelled = minf(travelled + speed * DT, length)
			player.position = from.lerp(to, travelled / length)
			# The opponent stays parked 6 m from where the square started, which is the
			# brief's setup: it is a mark on the floor, not a sparring partner.
			rig._process(DT)
			frames += 1
			worst_lead = maxf(worst_lead, rig.look_lead())
			var frac := _frame_offset(cam, player.global_position)
			if frac > worst:
				worst = frac
				worst_at = cam.unproject_position(player.global_position)
			smallest = minf(smallest, _player_fraction(cam, rig, player))
		leg += 1

	_check(frames > 400, "the square is driven for %d frames at 60 Hz" % frames)
	_check(worst <= CENTRE_BAND,
		"the player never leaves the centre %.0f %% of the frame (worst %.1f %% at %s)"
			% [CENTRE_BAND * 200.0, worst * 100.0, str(worst_at)])
	# A camera that simply sat on the player would pass that too, so prove it is not: the
	# aim is the player PLUS a lead, and the opponent is off to one side the whole run.
	_check(worst_lead > 0.05,
		"and the aim is carrying a lead toward the opponent, not sitting on the player (%.2f m)"
			% worst_lead)
	_check(worst_lead <= CameraRig.LOOK_LEAD_MAX_M + 0.0001,
		"the lead never exceeds the %.1f m cap (worst %.3f m)"
			% [CameraRig.LOOK_LEAD_MAX_M, worst_lead])
	_check(rig.is_player_floored(),
		"with the opponent 6 m away the camera is holding, not fitting the pair")
	_check(smallest >= CameraRig.PLAYER_MIN_FRACTION - 0.005,
		"and the player never projects smaller than PLAYER_MIN_FRACTION (%.1f %% at worst)"
			% (smallest * 100.0))

	# The opponent is where the brief says the arrow takes over: off the frame or near its
	# edge. This is the other half of "the zoom holds".
	var foe_frac := _frame_offset(cam, foe.global_position)
	_check(foe_frac > CENTRE_BAND,
		"the opponent 6 m away is out past the centre band, which is the arrow's job (%.0f %%)"
			% (foe_frac * 100.0))

	_free(world)


# ------------------------------------------------------- the zoom rule

## Both bots fit while the opponent is inside TRACK_PAIR_RANGE_M; past that the zoom holds.
func _test_zoom_hold(scene: PackedScene) -> void:
	var world := await _world(scene)
	var rig: CameraRig = world["rig"]
	var player: Node3D = world["player"]
	var foe: Node3D = world["foe"]
	var cam := rig.camera()
	rig.set_targets(player, foe)
	player.position = Vector3(0.0, 0.25, 0.0)

	var distances := {}
	for gap: float in [1.5, 3.0, 4.0, 6.0, 9.0]:
		foe.position = Vector3(gap, 0.25, 0.0)
		rig.reset_to_default()
		rig.fit_arena(FightTypes.ARENA_SIZE)
		_step(rig, 3.0)
		distances[gap] = rig.distance()

	_check(float(distances[3.0]) > float(distances[1.5]) + 0.05,
		"inside %.0f m the camera pulls back as the pair separates (%.2f m at 1.5 m, %.2f m at 3 m)"
			% [CameraRig.TRACK_PAIR_RANGE_M, distances[1.5], distances[3.0]])
	# Past the range the opponent is clamped to it for the fit, so the distance holds.
	_check(absf(float(distances[9.0]) - float(distances[6.0])) < 0.02,
		"past %.0f m the zoom holds (%.2f m at 6 m, %.2f m at 9 m)"
			% [CameraRig.TRACK_PAIR_RANGE_M, distances[6.0], distances[9.0]])
	_check(absf(float(distances[6.0]) - float(distances[4.0])) < 0.02,
		"and it holds at exactly the value it had at the range (%.2f m at 4 m)"
			% distances[4.0])

	# The floor: whatever the pair asks for, the player is never a dot.
	foe.position = Vector3(9.0, 0.25, 0.0)
	rig.reset_to_default()
	rig.fit_arena(FightTypes.ARENA_SIZE)
	_step(rig, 3.0)
	var fraction := _player_fraction(cam, rig, player)
	_check(fraction >= CameraRig.PLAYER_MIN_FRACTION - 0.005,
		"the player never projects smaller than %.0f %% of the frame (%.1f %%)"
			% [CameraRig.PLAYER_MIN_FRACTION * 100.0, fraction * 100.0])
	_check(fraction <= CameraRig.NEAR_BOT_FRACTION + 0.02,
		"nor closer than the near clamp (%.1f %%)" % (fraction * 100.0))

	# Defaults, which brief v4 keeps: behind the player's spawn.
	_check(is_equal_approx(rig.yaw_deg, FightTypes.CAM_YAW_DEG)
		and is_equal_approx(rig.pitch_deg, FightTypes.CAM_PITCH_DEG),
		"the fight camera still rests at yaw %.0f and pitch %.0f"
			% [FightTypes.CAM_YAW_DEG, FightTypes.CAM_PITCH_DEG])

	_free(world)


# ------------------------------------------------------- how big the machine is

## Wave V, agent V4. The whole point of the pass: through an exchange the player's machine
## is a machine, not a chip, and the opponent is on screen while it is close enough to be
## the thing you are fighting.
func _test_exchange_size(scene: PackedScene) -> void:
	var world := await _world(scene)
	var rig: CameraRig = world["rig"]
	var player: Node3D = world["player"]
	var foe: Node3D = world["foe"]
	var cam := rig.camera()
	rig.set_targets(player, foe)

	var smallest := 1.0
	var largest := 0.0
	var report := ""
	for gap: float in [0.9, 1.2, 1.5, 2.0]:
		player.position = Vector3(-gap * 0.5, 0.25, 0.0)
		foe.position = Vector3(gap * 0.5, 0.25, 0.0)
		rig.reset_to_default()
		rig.fit_arena(FightTypes.ARENA_SIZE)
		_step(rig, 3.0)
		var fraction := _player_fraction(cam, rig, player)
		smallest = minf(smallest, fraction)
		largest = maxf(largest, fraction)
		report += "%.1f m: %.1f %%  " % [gap, fraction * 100.0]
	_check(smallest >= EXCHANGE_MIN_FRACTION,
		"through an exchange the player is never under %.0f %% of the frame height (%s)"
			% [EXCHANGE_MIN_FRACTION * 100.0, report])
	_check(largest <= EXCHANGE_MAX_FRACTION,
		"and never over %.0f %%, so two machines in contact still both fit (%.1f %%)"
			% [EXCHANGE_MAX_FRACTION * 100.0, largest * 100.0])

	# The opponent, on the worst bearing there is. The camera looks down its own ground
	# axis at yaw -135, and a machine placed along that axis has only the 556 pt of frame
	# height to fit in, where one placed across it has 1206 pt.
	var framed_to := 0.0
	var gap := 0.4
	while gap <= 5.0:
		var worst := 0.0
		for deg in range(0, 360, 5):
			player.position = Vector3(0.0, 0.25, 0.0)
			foe.position = Vector3(cos(deg_to_rad(deg)), 0.0, sin(deg_to_rad(deg))) * gap \
				+ Vector3(0.0, 0.25, 0.0)
			rig.reset_to_default()
			rig.fit_arena(FightTypes.ARENA_SIZE)
			_step(rig, 3.0)
			worst = maxf(worst, _frame_offset(cam, foe.global_position))
		if worst <= 0.5:
			framed_to = gap
		gap += 0.2
	_check(framed_to >= OPPONENT_FRAMED_TO_M - 0.001,
		"the opponent is wholly in frame on every bearing out to %.1f m of separation (%.1f m asked)"
			% [framed_to, OPPONENT_FRAMED_TO_M])
	# And once it is not, the HUD is told, which is the whole contract for the arrow.
	player.position = Vector3(0.0, 0.25, 0.0)
	foe.position = Vector3(0.0, 0.25, 4.0)
	rig.reset_to_default()
	rig.fit_arena(FightTypes.ARENA_SIZE)
	_step(rig, 3.0)
	_check(rig.is_player_floored(),
		"and past that the rig reports it is holding, which is what fight.gd draws the arrow on")

	_free(world)


# ------------------------------------------------------- the endgame reveal

## 0.6 s out to the arena fit, 0.8 s back to tracking, no input, no cut.
func _test_endgame_reveal(scene: PackedScene) -> void:
	var world := await _world(scene)
	var rig: CameraRig = world["rig"]
	var player: Node3D = world["player"]
	var foe: Node3D = world["foe"]
	rig.set_targets(player, foe)
	player.position = Vector3(-2.0, 0.25, -2.0)
	foe.position = Vector3(0.0, 0.25, 0.0)
	rig.reset_to_default()
	rig.fit_arena(FightTypes.ARENA_SIZE)
	_step(rig, 3.0)

	var tracking := rig.distance()
	var tracking_look := rig.look_target()
	_check(not rig.is_revealing(), "there is no reveal running in a normal fight")

	rig.endgame_reveal()
	_check(rig.is_revealing(), "endgame_reveal() starts the move")

	# Out. Nothing jumps: the largest single frame is a fraction of the whole move.
	var biggest_step := 0.0
	var previous := rig.distance()
	var steps := int(round(CameraRig.REVEAL_OUT_S / DT))
	for i in steps:
		rig._process(DT)
		biggest_step = maxf(biggest_step, absf(rig.distance() - previous))
		previous = rig.distance()
	var out_distance := rig.distance()
	_check(out_distance > tracking + 1.0,
		"%.1f s later the camera has pulled back to show the floor (%.1f m then %.1f m)"
			% [CameraRig.REVEAL_OUT_S, tracking, out_distance])
	_check(rig.look_target().length() < tracking_look.length() + 0.001,
		"and the aim has come back to the middle of the arena " + str(rig.look_target()))
	var travel := out_distance - tracking
	_check(biggest_step < travel * 0.12,
		"no cut: the biggest single frame is %.0f %% of the move (%.3f m of %.2f m)"
			% [100.0 * biggest_step / maxf(travel, 0.001), biggest_step, travel])

	# Back, with no input of any kind.
	previous = rig.distance()
	steps = int(round(CameraRig.REVEAL_BACK_S / DT))
	for i in steps:
		rig._process(DT)
		biggest_step = maxf(biggest_step, absf(rig.distance() - previous))
		previous = rig.distance()
	_check(not rig.is_revealing(),
		"after %.1f s more it is back in the tracking state with no input"
			% CameraRig.REVEAL_BACK_S)
	_check(is_equal_approx(rig.reveal_blend(), 0.0), "and nothing of the move is left mixed in")
	_check(absf(rig.distance() - tracking) < 0.05,
		"the camera is back where it was tracking (%.2f m then %.2f m)"
			% [tracking, rig.distance()])
	_check(rig.look_target().distance_to(tracking_look) < 0.05,
		"aimed where it was tracking " + str(rig.look_target()))
	_check(biggest_step < travel * 0.12,
		"and the return does not cut either (biggest frame %.3f m)" % biggest_step)

	# It picks the tracking back up: move the player and the camera follows again.
	player.position = Vector3(2.5, 0.25, 2.0)
	_step(rig, 1.5)
	_check(rig.look_target().distance_to(tracking_look) > 1.0,
		"and it is tracking the player again afterwards " + str(rig.look_target()))

	# The workshop and the menu have no endgame.
	rig.set_mode(CameraRig.MODE_WORKSHOP)
	rig.endgame_reveal()
	_check(not rig.is_revealing(), "endgame_reveal() does nothing outside a fight")
	rig.set_mode(CameraRig.MODE_FIGHT)

	_free(world)


# ------------------------------------------------------- what brief v4 keeps

## "Manual orbit and tilt stay, easing back after 3 s as now."
func _test_manual_orbit_survives(scene: PackedScene) -> void:
	var world := await _world(scene)
	var rig: CameraRig = world["rig"]
	var player: Node3D = world["player"]
	var foe: Node3D = world["foe"]
	rig.set_targets(player, foe)
	player.position = Vector3(-1.0, 0.25, 0.0)
	foe.position = Vector3(1.0, 0.25, 0.0)
	rig.reset_to_default()
	rig.fit_arena(FightTypes.ARENA_SIZE)
	_step(rig, 1.0)

	rig.orbit(Vector2(300.0, -100.0))
	_check(absf(wrapf(rig.yaw_deg - FightTypes.CAM_YAW_DEG, -180.0, 180.0)) > 10.0,
		"a drag still orbits the fight camera (yaw %.1f)" % rig.yaw_deg)
	_check(rig.pitch_deg > FightTypes.CAM_PITCH_DEG,
		"and still tilts it (pitch %.1f)" % rig.pitch_deg)
	_step(rig, FightTypes.CAM_EASE_BACK_AFTER_S + FightTypes.CAM_EASE_BACK_S + 0.3)
	_check(is_equal_approx(rig.yaw_deg, FightTypes.CAM_YAW_DEG)
		and is_equal_approx(rig.pitch_deg, FightTypes.CAM_PITCH_DEG),
		"and it eases back to the default pose after %.0f s of no input"
			% FightTypes.CAM_EASE_BACK_AFTER_S)
	_check(rig.is_resting(), "and the rig is on the auto framing again")

	# Tracking through a manual orbit: the player is still held near the middle.
	var cam := rig.camera()
	rig.orbit(Vector2(-200.0, 0.0))
	player.position = Vector3(3.0, 0.25, -3.0)
	_step(rig, 1.5)
	_check(_frame_offset(cam, player.global_position) <= CENTRE_BAND,
		"the player stays in the centre band even while the camera is turned by hand (%.0f %%)"
			% (_frame_offset(cam, player.global_position) * 100.0))

	_free(world)


# ------------------------------------------------------- helpers

## A rig in a real viewport with two bodies to frame.
func _world(scene: PackedScene) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = VIEW
	root.add_child(vp)
	var rig: CameraRig = scene.instantiate() as CameraRig
	vp.add_child(rig)
	var player := Node3D.new()
	var foe := Node3D.new()
	vp.add_child(player)
	vp.add_child(foe)
	await process_frame
	await process_frame
	rig.set_process(false)          # stepped by hand, so nothing depends on the frame rate
	rig.set_mode(CameraRig.MODE_FIGHT)
	rig.fit_arena(FightTypes.ARENA_SIZE)
	return {"vp": vp, "rig": rig, "player": player, "foe": foe}


func _free(world: Dictionary) -> void:
	(world["rig"] as Node).queue_free()
	(world["vp"] as Node).queue_free()


## How far a world point projects from the centre of the frame, as a fraction of the WHOLE
## frame on its worst axis. 0.30 is the edge of the centre 60 % band.
func _frame_offset(cam: Camera3D, at: Vector3) -> float:
	if cam.is_position_behind(at):
		return 1.0
	var screen := cam.unproject_position(at)
	return maxf(absf(screen.x / float(VIEW.x) - 0.5), absf(screen.y / float(VIEW.y) - 0.5))


## How tall a nominal machine standing at the player is, as a fraction of the frame height.
func _player_fraction(cam: Camera3D, _rig: CameraRig, player: Node3D) -> float:
	var base := player.global_position
	base.y = 0.0
	var top := cam.unproject_position(base + Vector3(0.0, CameraRig.BOT_SIZE_M, 0.0))
	var foot := cam.unproject_position(base)
	return absf(top.y - foot.y) / float(VIEW.y)


func _step(rig: CameraRig, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		rig._process(DT)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS  ", label)
	else:
		_failures += 1
		printerr("FAIL  ", label)
		print("FAIL  ", label)


func _finish() -> void:
	print("")
	if _failures == 0:
		print("PASS  camera track: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  camera track: %d checks, %d failures" % [_checks, _failures])
		quit(1)
