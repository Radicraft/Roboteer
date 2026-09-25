class_name StageDirector extends Node3D
## The stage's own camera, for the wave A front end shots (docs/wave-a-stage-notes.md).
##
## The legacy `menu` and `workshop` cameras live in `res://ui/camera_rig.gd` and are
## untouched. This director only takes the picture when a `workshop_config` carries a
## `shot` (docs/bridge-spec.md, "workshop_config.shot"), and hands it straight back to
## whichever camera was current before the moment the shot is cleared or the stage goes
## dark for a fight. So a shell that never sends `shot` sees exactly the old stage.
##
## Shots (numbers from docs/look/reference-study.md sections 3.2 and 3.6):
##
## | shot | lens | what it frames |
## |---|---|---|
## | `showroom` (M1) | 50 mm | the hero alone, turning at 5 deg/s, a slow three sine drift |
## | `faceoff` (M2) | 50 mm | the hero large and low on the left in warm light, the opponent across the floor on the right in cold light |
## | `garage` (G1) | 40 mm | the hero in the left of the frame on the lit turntable, drag to orbit |
## | `part` (G2) | 70 mm | one category of parts pulled out of the machine, shallow depth of field |
##
## Every framing is SOLVED from the hero's bounds rather than stored as a pose, so a
## bigger or smaller machine lands at the same share of the frame. Moves between shots
## take MOVE_S with an in-out cubic, and the focus distance is pulled on the same curve.
##
## Presentation only: nothing here touches physics or the fight.

signal attract_cue(kind: String, at: Vector3)

const SHOT_NONE := ""
const SHOT_SHOWROOM := "showroom"
const SHOT_FACEOFF := "faceoff"
const SHOT_GARAGE := "garage"
const SHOT_PART := "part"
const SHOTS := [SHOT_SHOWROOM, SHOT_FACEOFF, SHOT_GARAGE, SHOT_PART]

## Vertical field of view for a 36 x 24 mm frame, 2 x atan(12 / f).
const FOV_40MM := 33.4
const FOV_50MM := 27.0
const FOV_70MM := 19.5

## Section to section move, and its focus pull.
const MOVE_S := 0.75

## M1 showroom. The hero's bounding circle takes this share of the frame WIDTH (the
## circle is the widest the machine ever gets as it turns, so the turning machine never
## clips), its centre sits HERO_CENTRE_FROM_TOP down the frame, and the camera looks
## down SHOWROOM_PITCH.
const SHOWROOM_WIDTH_SHARE := 0.58
const SHOWROOM_PITCH := 8.0
const SHOWROOM_YAW := 28.0
const HERO_CENTRE_FROM_TOP := 0.42

## M2 face-off. The hero's projected width is FACEOFF_WIDTH_SHARE of the frame (owner:
## 40 to 50 %), its centre lands at FACEOFF_HERO_X across the frame and the opponent's at
## FACEOFF_OPPONENT_X. The lens sits FACEOFF_EYE_HEIGHT above the floor, far lower than
## the legacy menu camera's 1.6 m, which is what makes the machine loom.
const FACEOFF_WIDTH_SHARE := 0.52
const FACEOFF_HERO_X := 0.34
const FACEOFF_OPPONENT_X := 0.76
const FACEOFF_EYE_HEIGHT := 0.26
const FACEOFF_HERO_FROM_TOP := 0.50
## The lens stays on the front left of the hero, between the key and the fill. The
## opponent slot (WorkshopStage.OPPONENT_AT) is placed so the solve lands near -12 deg.
const FACEOFF_BEARING_MIN := -35.0
const FACEOFF_BEARING_MAX := 10.0

## G1 garage overview.
const GARAGE_WIDTH_SHARE := 0.56
const GARAGE_PITCH := 11.0
const GARAGE_YAW := 38.0
const GARAGE_FRAME := 0.31
const ORBIT_DEG_PER_PT := 0.25
const ORBIT_PITCH_MIN := 2.0
const ORBIT_PITCH_MAX := 35.0
const ORBIT_DECAY_S := 0.35
const ZOOM_MIN := 0.7
const ZOOM_MAX := 1.35
## Turntable: pause on touch, resume after RESUME_AFTER_S with an ease of RESUME_EASE_S.
const RESUME_AFTER_S := 4.0
const RESUME_EASE_S := 1.2
const TURN_DEG_PER_S := 5.0
## Where the turntable starts when the stage first comes up on a showroom or garage shot:
## nose three quarters towards the lens, as M1 and G1 are drawn, so the first second the
## player sees is the flattering angle and not a flat side profile.
const OPENING_TURN_DEG := -15.0

## G2 part focus.
const PART_HEIGHT_SHARE := 0.42
const PART_DISTANCE_MIN := 0.9
const PART_DISTANCE_MAX := 1.8
const PART_PITCH := 16.0
const PART_SIDE_DEG := 28.0

## Drift (camera, not bot): yaw, height and dolly on unrelated sine periods.
const DRIFT_YAW_DEG := 7.0
const DRIFT_YAW_PERIOD := 23.0
const DRIFT_HEIGHT_M := 0.04
const DRIFT_HEIGHT_PERIOD := 17.0
const DRIFT_DOLLY := 0.03
const DRIFT_DOLLY_PERIOD := 29.0
## The face-off is a composition, not a turntable, so it breathes at a third of that.
const FACEOFF_DRIFT_SCALE := 0.35

## Depth of field (CameraAttributesPractical). Far blur starts just behind the subject.
const DOF_MENU_BEHIND := 0.7
const DOF_MENU_TRANSITION := 2.5
const DOF_MENU_AMOUNT := 0.07
const DOF_FACEOFF_BEHIND := 1.6
const DOF_FACEOFF_TRANSITION := 5.0
const DOF_FACEOFF_AMOUNT := 0.05
const DOF_PART_BEHIND := 0.35
const DOF_PART_TRANSITION := 1.2
const DOF_PART_AMOUNT := 0.09

## Attract: after ATTRACT_AFTER_S with no touch the director starts calling cues, one
## every ATTRACT_MIN_S to ATTRACT_MAX_S. The stage draws the test-fire spark; anything
## else listening to `attract_cue` (a weapon idle, a sound) may join in.
const ATTRACT_AFTER_S := 6.0
const ATTRACT_MIN_S := 9.0
const ATTRACT_MAX_S := 14.0
const ATTRACT_SEED := 20260924

var _stage: Node3D = null
var _camera: Camera3D = null
var _attrs: CameraAttributesPractical = null
var _previous: Camera3D = null
var _dof_enabled := true

var _shot := SHOT_NONE
var _focus := ""
var _frame := 0.5
var _t := 0.0

## Pose blending: where the move started and how far through it we are.
var _from_pos := Vector3.ZERO
var _from_look := Vector3.ZERO
var _from_fov := FOV_50MM
var _from_focus := 3.0
var _blend := 1.0
var _has_pose := false
var _pos := Vector3.ZERO
var _look := Vector3.ZERO
var _fov := FOV_50MM
var _focus_distance := 3.0

## Garage orbit state.
var _orbit_yaw := 0.0
var _orbit_pitch := 0.0
var _orbit_velocity := Vector2.ZERO
var _zoom := 1.0
var _idle_s := 99.0

var _attract_timer := 0.0
var _attract_rng := RandomNumberGenerator.new()
var _attract_count := 0


func _init() -> void:
	name = "Director"
	_attract_rng.seed = ATTRACT_SEED
	_attract_timer = ATTRACT_MIN_S


func _ready() -> void:
	_ensure_camera()
	set_process(true)


## `stage` is the WorkshopStage this director frames. Kept loose (a Node3D and has_method)
## so this script compiles on its own in a `--script` test.
func bind_stage(stage: Node3D) -> void:
	_stage = stage


func camera() -> Camera3D:
	_ensure_camera()
	return _camera


func shot() -> String:
	return _shot


func focus_category() -> String:
	return _focus


func is_directing() -> bool:
	return _shot != SHOT_NONE


func attract_count() -> int:
	return _attract_count


## Where the camera is and what it looks at, for the tests and the notes.
func pose() -> Dictionary:
	return {"position": _pos, "look": _look, "fov": _fov, "focus": _focus_distance,
		"blend": _blend, "shot": _shot}


## Depth of field on or off for this device tier. Off on the compatibility renderer,
## which has no DOF pass at all.
func set_dof_enabled(on: bool) -> void:
	_dof_enabled = on
	_ensure_camera()
	_apply_dof(_focus_distance)


## Take the picture with `shot`, or hand it back with SHOT_NONE. `options`:
##   focus: a part category for SHOT_PART (weapon, drive, armour, chassis, utility, paint)
##   frame: 0..1, where across the screen the hero's centre should land (garage and part)
##   snap:  true to cut instead of move (the first shot after the stage comes up)
func set_shot(value: String, options: Dictionary = {}) -> void:
	_ensure_camera()
	var want := value if value in SHOTS else SHOT_NONE
	if want == SHOT_NONE:
		release()
		return
	var changed := want != _shot or str(options.get("focus", "")) != _focus
	_focus = str(options.get("focus", "")) if want == SHOT_PART else ""
	if options.has("frame"):
		_frame = clampf(float(options["frame"]), 0.12, 0.88)
	else:
		_frame = GARAGE_FRAME if (want == SHOT_GARAGE or want == SHOT_PART) else 0.5
	var snap: bool = bool(options.get("snap", false)) or not _has_pose or _shot == SHOT_NONE
	if changed:
		if want != SHOT_GARAGE and want != SHOT_PART:
			_orbit_yaw = 0.0
			_orbit_pitch = 0.0
			_zoom = 1.0
		_from_pos = _pos
		_from_look = _look
		_from_fov = _fov
		_from_focus = _focus_distance
		_blend = 0.0
	_shot = want
	_take_camera()
	if snap:
		_blend = 1.0
		_has_pose = false
		if (want == SHOT_SHOWROOM or want == SHOT_GARAGE) and _stage != null \
				and is_instance_valid(_stage) and _stage.has_method("set_turntable_angle"):
			_stage.call("set_turntable_angle", OPENING_TURN_DEG)
	_update_stage_turn()
	_process(0.0)


## Give the picture back to the camera that had it, and stop driving the turntable.
func release() -> void:
	if _shot == SHOT_NONE and (_camera == null or not _camera.current):
		return
	_shot = SHOT_NONE
	_focus = ""
	if _stage != null and is_instance_valid(_stage) and _stage.has_method("director_released"):
		_stage.call("director_released")
	if _camera != null and _camera.current:
		if _previous != null and is_instance_valid(_previous) and _previous.is_inside_tree():
			_previous.make_current()
		else:
			# Whatever other camera is in this viewport (the rig's) takes over.
			_camera.clear_current(true)
	_previous = null
	_has_pose = false


## A drag forwarded by the shell (`stage_camera.orbit`, in POINTS). Garage and part only;
## the menu shots are a composition and ignore it, as the legacy menu camera does.
func orbit(delta_pt: Vector2) -> void:
	if _shot != SHOT_GARAGE and _shot != SHOT_PART:
		return
	_note_touch()
	_orbit_yaw -= delta_pt.x * ORBIT_DEG_PER_PT
	_orbit_pitch += delta_pt.y * ORBIT_DEG_PER_PT
	_orbit_velocity = Vector2(-delta_pt.x, delta_pt.y) * ORBIT_DEG_PER_PT * 60.0
	_clamp_orbit()


func pinch(factor: float) -> void:
	if (_shot != SHOT_GARAGE and _shot != SHOT_PART) or factor <= 0.0:
		return
	_note_touch()
	_zoom = clampf(_zoom / factor, ZOOM_MIN, ZOOM_MAX)


## Seconds since the last forwarded gesture.
func idle_seconds() -> float:
	return _idle_s


func _note_touch() -> void:
	_idle_s = 0.0
	_update_stage_turn()


func _clamp_orbit() -> void:
	var base := GARAGE_PITCH if _shot == SHOT_GARAGE else PART_PITCH
	_orbit_pitch = clampf(_orbit_pitch, ORBIT_PITCH_MIN - base, ORBIT_PITCH_MAX - base)


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	if _shot == SHOT_NONE or _stage == null or not is_instance_valid(_stage):
		return
	_t += delta
	_idle_s += delta
	if _blend < 1.0:
		_blend = minf(_blend + delta / MOVE_S, 1.0)
	# Orbit inertia: the flick keeps going and decays over ORBIT_DECAY_S.
	if _orbit_velocity.length_squared() > 0.0001 and _idle_s > 0.05:
		_orbit_yaw += _orbit_velocity.x * delta
		_orbit_pitch += _orbit_velocity.y * delta
		_orbit_velocity *= exp(-delta / ORBIT_DECAY_S)
		_clamp_orbit()
	_update_stage_turn()
	_tick_attract(delta)

	var want := _solve()
	var pos: Vector3 = want["position"]
	var look: Vector3 = want["look"]
	var fov: float = want["fov"]
	var focus: float = want["focus"]
	if not _has_pose:
		_has_pose = true
		_blend = 1.0
	if _blend < 1.0:
		var k := _ease_in_out_cubic(_blend)
		pos = _from_pos.lerp(pos, k)
		look = _from_look.lerp(look, k)
		fov = lerpf(_from_fov, fov, k)
		focus = lerpf(_from_focus, focus, k)
	_pos = pos
	_look = look
	_fov = fov
	_focus_distance = focus
	_camera.fov = fov
	if pos.distance_squared_to(look) > 1e-6:
		_camera.look_at_from_position(pos, look, Vector3.UP)
	_camera.h_offset = float(want.get("h_offset", 0.0))
	_apply_dof(focus)


## The turntable follows the shot: turning slowly in the showroom and the garage (paused
## while a finger is on it), parked facing the opponent in the face-off, held still while
## a part is pulled out.
func _update_stage_turn() -> void:
	if _stage == null or not is_instance_valid(_stage) or not _stage.has_method("set_turn"):
		return
	if _stage.has_method("set_platform"):
		_stage.call("set_platform", _shot != SHOT_FACEOFF)
	match _shot:
		SHOT_SHOWROOM:
			_stage.call("set_turn", TURN_DEG_PER_S, NAN)
		SHOT_GARAGE:
			var speed := TURN_DEG_PER_S
			if _idle_s < RESUME_AFTER_S:
				speed = 0.0
			elif _idle_s < RESUME_AFTER_S + RESUME_EASE_S:
				var k := (_idle_s - RESUME_AFTER_S) / RESUME_EASE_S
				speed = TURN_DEG_PER_S * k * k
			_stage.call("set_turn", speed, NAN)
		SHOT_FACEOFF:
			var park := NAN
			if _stage.has_method("faceoff_hero_yaw_deg"):
				park = float(_stage.call("faceoff_hero_yaw_deg"))
			_stage.call("set_turn", 0.0, park)
		SHOT_PART:
			_stage.call("set_turn", 0.0, NAN)


func _tick_attract(delta: float) -> void:
	if _shot != SHOT_SHOWROOM and _shot != SHOT_FACEOFF:
		return
	if _idle_s < ATTRACT_AFTER_S:
		return
	_attract_timer -= delta
	if _attract_timer > 0.0:
		return
	_attract_timer = _attract_rng.randf_range(ATTRACT_MIN_S, ATTRACT_MAX_S)
	var at := Vector3.ZERO
	if _stage.has_method("weapon_point"):
		at = _stage.call("weapon_point")
	_attract_count += 1
	emit_signal("attract_cue", "test_fire", at)


# ---------------------------------------------------------------- solving the shots

func _aspect() -> float:
	var vp := get_viewport() if is_inside_tree() else null
	if vp != null:
		var size := vp.get_visible_rect().size
		if size.y > 1.0:
			return size.x / size.y
	return 2412.0 / 1112.0


## Half the horizontal field of view in radians, for a vertical fov in degrees.
func _half_h(fov_v: float) -> float:
	return atan(tan(deg_to_rad(fov_v) * 0.5) * _aspect())


func _hero_bounds() -> Dictionary:
	if _stage != null and _stage.has_method("hero_bounds"):
		return _stage.call("hero_bounds")
	return {"centre": Vector3(0.0, 0.3, 0.0), "radius": 0.45, "height": 0.35,
		"length": 0.7, "width": 0.5}


func _solve() -> Dictionary:
	match _shot:
		SHOT_FACEOFF:
			return _solve_faceoff()
		SHOT_GARAGE:
			return _solve_garage()
		SHOT_PART:
			return _solve_part()
	return _solve_showroom()


func _drift(scale: float) -> Vector3:
	return Vector3(
		DRIFT_YAW_DEG * scale * sin(TAU * _t / DRIFT_YAW_PERIOD),
		DRIFT_HEIGHT_M * scale * sin(TAU * _t / DRIFT_HEIGHT_PERIOD + 1.3),
		DRIFT_DOLLY * scale * sin(TAU * _t / DRIFT_DOLLY_PERIOD + 2.1))


## M1: the hero centred, its bounding circle SHOWROOM_WIDTH_SHARE of the frame width.
func _solve_showroom() -> Dictionary:
	var b := _hero_bounds()
	var centre: Vector3 = b["centre"]
	var radius: float = b["radius"]
	var fov := FOV_50MM
	var distance := (2.0 * radius) / (SHOWROOM_WIDTH_SHARE * 2.0 * tan(_half_h(fov)))
	var d := _drift(1.0)
	distance *= 1.0 + d.z
	return _orbit_pose(centre, distance, SHOWROOM_YAW + d.x, SHOWROOM_PITCH, fov,
		HERO_CENTRE_FROM_TOP, d.y, DOF_MENU_BEHIND, 0.0)


func _solve_garage() -> Dictionary:
	var b := _hero_bounds()
	var centre: Vector3 = b["centre"]
	var radius: float = b["radius"]
	var fov := FOV_40MM
	var distance := (2.0 * radius) / (GARAGE_WIDTH_SHARE * 2.0 * tan(_half_h(fov))) * _zoom
	var d := _drift(0.4)
	var pose := _orbit_pose(centre, distance * (1.0 + d.z), GARAGE_YAW + _orbit_yaw + d.x,
		GARAGE_PITCH + _orbit_pitch, fov, 0.5, d.y, DOF_MENU_BEHIND, 0.0)
	pose["h_offset"] = _h_offset_for(_frame, distance, fov)
	return pose


## A camera on a sphere round `centre`, then the aim lowered so the centre lands
## `from_top` of the way down the frame.
func _orbit_pose(centre: Vector3, distance: float, yaw_deg: float, pitch_deg: float,
		fov: float, from_top: float, lift: float, dof_behind: float, _unused: float) -> Dictionary:
	var dir := _direction(yaw_deg, pitch_deg)
	var pos := centre + dir * distance + Vector3(0.0, lift, 0.0)
	var frame_h := 2.0 * distance * tan(deg_to_rad(fov) * 0.5)
	var look := centre - Vector3(0.0, (0.5 - from_top) * frame_h, 0.0)
	return {"position": pos, "look": look, "fov": fov, "focus": distance,
		"dof_behind": dof_behind}


## M2: solve the camera so the hero lands at FACEOFF_HERO_X and the opponent at
## FACEOFF_OPPONENT_X, with the hero's width FACEOFF_WIDTH_SHARE of the frame and the lens
## FACEOFF_EYE_HEIGHT off the floor. One unknown is searched (the camera's bearing round
## the hero); the look direction then follows from the hero's screen position.
func _solve_faceoff() -> Dictionary:
	var b := _hero_bounds()
	var hero: Vector3 = b["centre"]
	var opponent := hero + Vector3(3.1, 0.3, -2.5)
	if _stage != null and _stage.has_method("opponent_point"):
		opponent = _stage.call("opponent_point")
	var fov := FOV_50MM
	var half_h := _half_h(fov)
	var tan_h := tan(half_h)
	# The hero seen three quarters on shows roughly its diagonal.
	var seen_width: float = maxf(float(b["length"]), float(b["width"])) * 0.92 \
		+ minf(float(b["length"]), float(b["width"])) * 0.38
	var distance := seen_width / (FACEOFF_WIDTH_SHARE * 2.0 * tan_h)
	var d := _drift(FACEOFF_DRIFT_SCALE)
	distance *= 1.0 + d.z

	var eye_y := _floor_y() + FACEOFF_EYE_HEIGHT + d.y
	var hero_x_ndc := FACEOFF_HERO_X * 2.0 - 1.0
	var opp_x_ndc := FACEOFF_OPPONENT_X * 2.0 - 1.0
	var best_bearing := 0.0
	var best_err := INF
	# Bearing of the camera FROM the hero, 0 = +Z (the front of the room, where the key and
	# the fill are), searched in half degrees between FACEOFF_BEARING_MIN and _MAX so the
	# lens always stays on the lit side. Cheap: under 100 evaluations of a few dot products.
	var steps := int((FACEOFF_BEARING_MAX - FACEOFF_BEARING_MIN) * 2.0)
	for i in steps + 1:
		var bearing := deg_to_rad(FACEOFF_BEARING_MIN + float(i) * 0.5)
		var cam := _faceoff_camera(hero, distance, bearing, eye_y)
		var yaw := _faceoff_yaw(cam, hero, hero_x_ndc, tan_h)
		var x := _screen_x(cam, yaw, opponent, tan_h)
		var err := absf(x - opp_x_ndc)
		if err < best_err:
			best_err = err
			best_bearing = bearing
	var pos := _faceoff_camera(hero, distance, best_bearing, eye_y)
	var look_yaw := _faceoff_yaw(pos, hero, hero_x_ndc, tan_h) + deg_to_rad(d.x)
	# Pitch: put the hero's centre FACEOFF_HERO_FROM_TOP down the frame.
	var flat := Vector2(hero.x - pos.x, hero.z - pos.z).length()
	var hero_elev := atan2(hero.y - pos.y, maxf(flat, 0.001))
	var tan_v := tan(deg_to_rad(fov) * 0.5)
	var pitch := hero_elev + atan((FACEOFF_HERO_FROM_TOP - 0.5) * 2.0 * tan_v)
	var fwd := Vector3(sin(look_yaw) * cos(pitch), sin(pitch), -cos(look_yaw) * cos(pitch))
	var focus := pos.distance_to(hero)
	return {"position": pos, "look": pos + fwd * focus, "fov": fov, "focus": focus,
		"dof_behind": DOF_FACEOFF_BEHIND}


func _floor_y() -> float:
	return _stage.global_position.y if _stage != null else 0.0


func _faceoff_camera(hero: Vector3, distance: float, bearing: float, eye_y: float) -> Vector3:
	var flat := sqrt(maxf(distance * distance - pow(hero.y - eye_y, 2.0), 0.01))
	return Vector3(hero.x + sin(bearing) * flat, eye_y, hero.z + cos(bearing) * flat)


## The look yaw (0 = looking down -Z, positive turns towards +X) that puts `hero` at
## `x_ndc` across the frame from `cam`.
func _faceoff_yaw(cam: Vector3, hero: Vector3, x_ndc: float, tan_h: float) -> float:
	var to := hero - cam
	var direct := atan2(to.x, -to.z)
	return direct - atan(x_ndc * tan_h)


func _screen_x(cam: Vector3, yaw: float, point: Vector3, tan_h: float) -> float:
	var to := point - cam
	var fwd := Vector2(sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), sin(yaw))
	var flat := Vector2(to.x, to.z)
	var depth := flat.dot(fwd)
	if depth <= 0.01:
		return 99.0
	return (flat.dot(right) / depth) / tan_h


## G2: aim at the category's own centre from the side it faces, at 70 mm.
func _solve_part() -> Dictionary:
	var b := _hero_bounds()
	var hero: Vector3 = b["centre"]
	var part := {"centre": hero, "radius": float(b["radius"]) * 0.5, "outward": Vector3(0, 0, 1)}
	if _stage != null and _stage.has_method("part_focus"):
		part = _stage.call("part_focus", _focus)
	var centre: Vector3 = part["centre"]
	var radius: float = maxf(float(part["radius"]), 0.06)
	var outward: Vector3 = part["outward"]
	var fov := FOV_70MM
	var frame_h_needed := (2.0 * radius) / PART_HEIGHT_SHARE
	var distance := clampf(frame_h_needed / (2.0 * tan(deg_to_rad(fov) * 0.5)),
		PART_DISTANCE_MIN, PART_DISTANCE_MAX) * _zoom
	var flat := Vector3(outward.x, 0.0, outward.z)
	if flat.length_squared() < 0.01:
		flat = Vector3(0.0, 0.0, 1.0)
	flat = flat.normalized()
	# Keep the camera on the front half of the room, where the key and the softbox are.
	if flat.z < -0.2:
		flat = Vector3(flat.x, 0.0, -flat.z * 0.4).normalized()
	var yaw := rad_to_deg(atan2(flat.x, flat.z)) + PART_SIDE_DEG + _orbit_yaw
	var pose := _orbit_pose(centre, distance, yaw, PART_PITCH + _orbit_pitch, fov, 0.5,
		0.0, DOF_PART_BEHIND, 0.0)
	pose["h_offset"] = _h_offset_for(_frame, distance, fov)
	return pose


func _h_offset_for(frame: float, distance: float, fov: float) -> float:
	if absf(frame - 0.5) < 0.0005:
		return 0.0
	var half_w := distance * tan(deg_to_rad(fov) * 0.5) * _aspect()
	return (0.5 - frame) * 2.0 * half_w


func _direction(yaw_d: float, pitch_d: float) -> Vector3:
	var yaw := deg_to_rad(yaw_d)
	var pitch := deg_to_rad(pitch_d)
	return Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)).normalized()


func _ease_in_out_cubic(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) * 0.5


# ---------------------------------------------------------------- camera

func _ensure_camera() -> void:
	if _camera != null:
		return
	_camera = Camera3D.new()
	_camera.name = "DirectorCamera"
	# Moved in _process, never on the physics tick, so it must draw exactly where it is
	# put. Left to inherit, a stage parked under an interpolated branch drew (and
	# unprojected) a stale pose one tick behind: the face-off hero read 0.50 across the
	# frame when the solved pose puts it at 0.33.
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.near = 0.05
	_camera.far = 60.0
	_camera.fov = FOV_50MM
	_camera.current = false
	_attrs = CameraAttributesPractical.new()
	# Exposure is locked: the lights are tuned to it, never the reverse (Insomniac order).
	_attrs.auto_exposure_enabled = false
	_attrs.exposure_multiplier = 1.0
	_attrs.dof_blur_near_enabled = false
	_attrs.dof_blur_far_enabled = true
	_camera.attributes = _attrs
	add_child(_camera)


func _take_camera() -> void:
	if _camera == null or not is_inside_tree():
		return
	if _camera.current:
		return
	var vp := get_viewport()
	var current := vp.get_camera_3d() if vp != null else null
	if current != null and current != _camera:
		_previous = current
	_camera.make_current()


func _apply_dof(focus: float) -> void:
	if _attrs == null:
		return
	var behind := DOF_MENU_BEHIND
	var transition := DOF_MENU_TRANSITION
	var amount := DOF_MENU_AMOUNT
	var near := false
	match _shot:
		SHOT_FACEOFF:
			behind = DOF_FACEOFF_BEHIND
			transition = DOF_FACEOFF_TRANSITION
			amount = DOF_FACEOFF_AMOUNT
		SHOT_PART:
			behind = DOF_PART_BEHIND
			transition = DOF_PART_TRANSITION
			amount = DOF_PART_AMOUNT
			near = true
	_attrs.dof_blur_far_enabled = _dof_enabled
	_attrs.dof_blur_far_distance = focus + behind
	_attrs.dof_blur_far_transition = transition
	_attrs.dof_blur_amount = amount
	_attrs.dof_blur_near_enabled = _dof_enabled and near
	_attrs.dof_blur_near_distance = maxf(focus - 0.45, 0.05)
	_attrs.dof_blur_near_transition = 0.3
