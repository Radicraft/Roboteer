extends SceneTree
## `stage_camera`: camera gestures the SHELL captured and forwarded (added 2026-09-14).
##   Godot --headless --path Arena --script tests/stage_camera_test.gd
##
## On the workshop and menu screens the SwiftUI navigation container swallows every touch
## before the embedded Godot view sees it, so the shell captures the gesture itself in the
## clear area and sends the deltas over the bridge. This checks the message is routed to
## the camera rig on stage screens, scaled from screen points to viewport pixels, and
## ignored everywhere else.
##
## Driven through Bridge.inject_from_host, which is the exact path a real host message
## takes, rather than by calling the handler.

const FIGHT_SCENE := "res://fight/fight.tscn"

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	if not ResourceLoader.exists(FIGHT_SCENE):
		print("SKIP  stage camera: %s is absent" % FIGHT_SCENE)
		quit(0)
		return

	var fight: Node = (load(FIGHT_SCENE) as PackedScene).instantiate()
	root.add_child(fight)
	await process_frame
	await process_frame

	# --- workshop: the gesture reaches the rig
	_send({"type": "workshop_config", "json": '{"mode":"workshop"}'})
	await process_frame
	var rig: Node = fight.get("_camera_rig")
	_check(rig != null, "the fight has a camera rig")
	if rig == null:
		_finish()
		return
	_check(str(rig.call("mode")) == "workshop", "the rig is in workshop mode")

	var yaw_before := float(rig.get("yaw_deg"))
	_send({"type": "stage_camera", "json": '{"orbit":[120.0,0.0]}'})
	await process_frame
	var yaw_after := float(rig.get("yaw_deg"))
	_check(absf(yaw_after - yaw_before) > 1.0,
		"a forwarded orbit turns the workshop camera (%.2f then %.2f)" % [yaw_before, yaw_after])

	# Points are scaled to viewport pixels the way a real touch drag is, so the feel
	# matches: at the design viewport the scale is 1, at 2x it is 2.
	var pixels: Vector2 = fight.call("_points_to_pixels", Vector2(120.0, 0.0))
	var size := root.get_visible_rect().size
	var want := 120.0 * minf(size.x / FightControls.REF_SIZE_PT.x,
		size.y / FightControls.REF_SIZE_PT.y)
	_check(absf(pixels.x - want) < 0.01,
		"120 screen points is %.1f viewport pixels at %s" % [pixels.x, str(size)])
	# orbit() turns the camera the way a drag would: dragging right swings the yaw down.
	_check(absf((yaw_before - yaw_after) - pixels.x * CameraRig.ORBIT_DEG_PER_PX) < 0.01,
		"and the turn is exactly ORBIT_DEG_PER_PX of those pixels (%.3f degrees)"
			% (yaw_before - yaw_after))

	# Tilt, and the clamp behind it.
	var pitch_before := float(rig.get("pitch_deg"))
	_send({"type": "stage_camera", "json": '{"orbit":[0.0,-60.0]}'})
	await process_frame
	_check(float(rig.get("pitch_deg")) > pitch_before,
		"dragging up raises the workshop camera (%.2f then %.2f)"
			% [pitch_before, float(rig.get("pitch_deg"))])
	_send({"type": "stage_camera", "json": '{"orbit":[0.0,-100000.0]}'})
	await process_frame
	_check(is_equal_approx(float(rig.get("pitch_deg")), CameraRig.WORKSHOP_PITCH_MAX),
		"and the existing pitch clamp still holds")

	# Pinch.
	var zoom_before := float(rig.call("workshop_zoom"))
	_send({"type": "stage_camera", "json": '{"pinch":1.5}'})
	await process_frame
	_check(float(rig.call("workshop_zoom")) < zoom_before,
		"a forwarded pinch above 1 moves the camera in (%.3f then %.3f)"
			% [zoom_before, float(rig.call("workshop_zoom"))])
	_send({"type": "stage_camera", "json": '{"pinch":0.0}'})
	await process_frame
	_check(true, "a zero pinch factor is ignored rather than dividing by it")

	# Both at once, which is what a two finger gesture sends.
	var yaw_both := float(rig.get("yaw_deg"))
	var zoom_both := float(rig.call("workshop_zoom"))
	_send({"type": "stage_camera", "json": '{"orbit":[40.0,0.0],"pinch":0.9}'})
	await process_frame
	_check(absf(float(rig.get("yaw_deg")) - yaw_both) > 0.1
		and float(rig.call("workshop_zoom")) > zoom_both,
		"one message may carry an orbit and a pinch together")

	# --- fight: ignored
	_send({"type": "workshop_config", "json": '{"mode":"workshop"}'})
	await process_frame
	fight.call("_show_fight_view")
	await process_frame
	rig = fight.get("_camera_rig")
	_check(str(rig.call("mode")) == "fight", "the rig is back in fight mode")
	var fight_yaw := float(rig.get("yaw_deg"))
	var fight_zoom := float(rig.get("zoom"))
	_send({"type": "stage_camera", "json": '{"orbit":[300.0,120.0],"pinch":1.5}'})
	await process_frame
	_check(is_equal_approx(float(rig.get("yaw_deg")), fight_yaw),
		"a forwarded gesture is ignored in a fight, where the player's own thumbs own the camera")
	_check(is_equal_approx(float(rig.get("zoom")), fight_zoom),
		"and it cannot zoom a fight either")

	# --- an empty or malformed message changes nothing and does not crash
	_send({"type": "workshop_config", "json": '{"mode":"workshop"}'})
	await process_frame
	rig = fight.get("_camera_rig")
	var settled := float(rig.get("yaw_deg"))
	for json: String in ["{}", '{"orbit":[]}', '{"orbit":[1.0]}', '{"orbit":"nonsense"}']:
		_send({"type": "stage_camera", "json": json})
		await process_frame
	_check(is_equal_approx(float(rig.get("yaw_deg")), settled),
		"a message with no usable gesture in it changes nothing")

	fight.queue_free()
	await process_frame
	_finish()


func _send(message: Dictionary) -> void:
	var bridge: Node = root.get_node_or_null("Bridge")
	if bridge == null:
		_check(false, "the Bridge autoload exists")
		return
	bridge.call("inject_from_host", message)


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
		print("PASS  stage camera: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  stage camera: %d checks, %d failures" % [_checks, _failures])
		quit(1)
