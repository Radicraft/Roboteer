class_name CameraRig extends Node3D
## Fight camera. Spec: docs/stage3-spec.md section 10, brief-v3.md section 11.
##
## Default framing is authoritative: yaw 45, pitch 50, and DEFAULT_ZOOM of the distance
## at which the whole floor plus the walls fit the current viewport. That fit distance
## is recomputed every frame so the framing is correct at any aspect. The player may
## pinch out to CAM_ZOOM_MAX, which is the walls on screen limit; after
## CAM_EASE_BACK_AFTER_S of no input the rig eases back to the default pose.
##
## Presentation only. Everything runs in _process and nothing here is read by the
## simulation. The Camera3D child is created if the scene does not already carry one.

const ORBIT_DEG_PER_PX := 0.12
const TILT_DEG_PER_PX := 0.09
## A little slack so the walls are not flush with the screen edge at zoom 1.0.
const FIT_MARGIN := 1.05

## Fraction of the fit distance the camera rests at. Fitting the whole 10 m arena
## (zoom 1.0) puts a 0.9 m bot at about 35 px on a 556 px tall viewport, which is not
## readable, so the default sits closer and lets the player pinch out to see the walls.
## CAM_ZOOM_MAX stays the walls on screen limit, it is just not the resting pose.
const DEFAULT_ZOOM := 0.6

## RESULT state, the director cut.
const WRECKAGE_DISTANCE := 2.6
const WRECKAGE_PITCH_DEG := 35.0
const WRECKAGE_ORBIT_DEG_PER_S := 20.0
const WRECKAGE_EASE_S := 1.0

## Modes (docs/stage4-spec.md section 5). "fight" is everything above and is the
## default; "workshop" is the builder turntable; "menu" is the cinematic drift behind
## the AAA menu screens. Only "fight" reads the arena fit distance.
const MODE_FIGHT := "fight"
const MODE_WORKSHOP := "workshop"
const MODE_MENU := "menu"

## Workshop: a fixed base distance rather than a fit, because the subject is one bot
## on a 3 m stage and not a 10 m arena.
const WORKSHOP_BASE_DISTANCE := 2.4
const WORKSHOP_ZOOM_MIN := 0.4
const WORKSHOP_ZOOM_MAX := 1.5
const WORKSHOP_PITCH_MIN := 5.0
const WORKSHOP_PITCH_MAX := 85.0
const WORKSHOP_YAW_DEG := 45.0
const WORKSHOP_PITCH_DEG := 22.0
## Aim height above the stage top: the middle of a bot, not its shadow.
const WORKSHOP_LOOK_HEIGHT := 0.15

## Menu: a slow yaw drift from MENU_YAW_MIN to MENU_YAW_MAX and back, no input.
const MENU_YAW_MIN := 20.0
const MENU_YAW_MAX := 40.0
const MENU_PITCH_DEG := 18.0
## One sweep takes half of this, so 20 s from MENU_YAW_MIN to MENU_YAW_MAX.
const MENU_PERIOD_S := 40.0
## Wider and aimed higher than the workshop. Measured: at 2.9 m aimed at 0.15 m the
## near side of the floor is only visible out to radius 1.08 m, which is INSIDE the
## 1.5 m disc, so no low fog bank can ever appear at the bottom of the frame and every
## dry ice emitter beyond the rim projects behind the bot at mid frame instead. At
## 4.8 m aimed at 0.28 m the floor is visible out to radius 1.74 m, the fog at the rim
## lands in the bottom 13 % of the frame, the bot's top plate sits 42 % down and the
## bot is 40 % of the frame height, which is the key art's composition and leaves room
## for the SwiftUI panels.
const MENU_DISTANCE := 4.8
const MENU_LOOK_HEIGHT := 0.28

## Desktop QA overrides (spec section 14), read from OS.get_cmdline_user_args().
const ARG_ZOOM := "--roboteer-zoom="
const ARG_YAW := "--roboteer-yaw="
const ARG_PITCH := "--roboteer-pitch="
const ARG_ZOOM_MIN := 0.3
const ARG_ZOOM_MAX := 1.0

var yaw_deg: float = FightTypes.CAM_YAW_DEG
var pitch_deg: float = FightTypes.CAM_PITCH_DEG
## Fraction of the fit distance. CAM_ZOOM_MAX (1.0) keeps the walls on screen.
var zoom: float = DEFAULT_ZOOM

## The pose the rig rests at and eases back to. QA arguments override these.
var _default_yaw: float = FightTypes.CAM_YAW_DEG
var _default_pitch: float = FightTypes.CAM_PITCH_DEG
var _default_zoom: float = DEFAULT_ZOOM
## Widened only if a QA argument asks for a closer default than CAM_ZOOM_MIN.
var _zoom_min: float = FightTypes.CAM_ZOOM_MIN

var _camera: Camera3D
var _arena_half: float = FightTypes.ARENA_SIZE * 0.5 + FightTypes.WALL_THICKNESS
var _floor_half: float = FightTypes.ARENA_SIZE * 0.5
var _arena_top: float = FightTypes.WALL_HEIGHT
var _target_a: Node3D
var _target_b: Node3D
var _wreckage: Node3D
var _director_cut: bool = true
var _input_enabled: bool = true

var _idle_s: float = 0.0
var _easing: bool = false
var _ease_t: float = 0.0
var _ease_from := Vector3.ZERO   # yaw, pitch, zoom at the moment the ease started
var _distance: float = 12.0
var _look := Vector3.ZERO

var _wreck_t: float = 0.0
var _wreck_from_pos := Vector3.ZERO
var _wreck_from_look := Vector3.ZERO

var _mode: String = MODE_FIGHT
## Fraction of WORKSHOP_BASE_DISTANCE. Larger is further away.
var _workshop_zoom: float = 1.0
var _workshop_centre := Vector3.ZERO
var _menu_t: float = 0.0
## Live touches while the rig owns input itself (workshop only): index -> position.
var _touches: Dictionary = {}


func _ready() -> void:
	_ensure_camera()
	_read_qa_arguments()
	set_process(true)
	set_process_unhandled_input(_mode == MODE_WORKSHOP)


func _ensure_camera() -> void:
	if _camera != null:
		return
	_camera = get_node_or_null("Camera") as Camera3D
	if _camera == null:
		for child in get_children():
			if child is Camera3D:
				_camera = child as Camera3D
				break
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "Camera"
		add_child(_camera)
	_camera.fov = FightTypes.CAM_FOV
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.near = 0.1
	_camera.far = 200.0
	_camera.current = true


## --roboteer-zoom=0.45 --roboteer-yaw=20 --roboteer-pitch=25 for desktop close ups.
## Desktop only, so a device build can never be posed by an argument.
func _read_qa_arguments() -> void:
	if not OS.has_feature("pc"):
		return
	for raw in OS.get_cmdline_user_args():
		var arg := str(raw)
		if arg.begins_with(ARG_ZOOM):
			_default_zoom = clampf(arg.substr(ARG_ZOOM.length()).to_float(), ARG_ZOOM_MIN, ARG_ZOOM_MAX)
			_zoom_min = minf(FightTypes.CAM_ZOOM_MIN, _default_zoom)
		elif arg.begins_with(ARG_YAW):
			_default_yaw = wrapf(arg.substr(ARG_YAW.length()).to_float(), -180.0, 180.0)
		elif arg.begins_with(ARG_PITCH):
			_default_pitch = clampf(arg.substr(ARG_PITCH.length()).to_float(),
				FightTypes.CAM_PITCH_MIN, FightTypes.CAM_PITCH_MAX)
	yaw_deg = _default_yaw
	pitch_deg = _default_pitch
	zoom = _default_zoom


# ---------------------------------------------------------------- public API

## Called once by the rules layer with the arena's floor size in metres.
func fit_arena(size_m: float) -> void:
	_floor_half = size_m * 0.5
	_arena_half = _floor_half + FightTypes.WALL_THICKNESS
	_arena_top = FightTypes.WALL_HEIGHT
	_apply(0.0)


## The two bots. Below zoom 1.0 the look-at point biases toward their midpoint.
func set_targets(a: Node3D, b: Node3D) -> void:
	_target_a = a
	_target_b = b


## "fight" (everything the Stage 3 rig did), "workshop" (turntable orbit) or "menu"
## (the cinematic drift). Anything else is treated as "fight". R2 calls this when the
## host switches between fight_config and workshop_config.
func set_mode(mode: String) -> void:
	var want := mode.strip_edges().to_lower()
	if want != MODE_WORKSHOP and want != MODE_MENU:
		want = MODE_FIGHT
	_mode = want
	_easing = false
	_wreckage = null
	_idle_s = 0.0
	_touches.clear()
	match _mode:
		MODE_WORKSHOP:
			yaw_deg = WORKSHOP_YAW_DEG
			pitch_deg = WORKSHOP_PITCH_DEG
			_workshop_zoom = 1.0
		MODE_MENU:
			_menu_t = 0.0
			yaw_deg = MENU_YAW_MIN
			pitch_deg = MENU_PITCH_DEG
		_:
			yaw_deg = _default_yaw
			pitch_deg = _default_pitch
			zoom = _default_zoom
	set_process_unhandled_input(_mode == MODE_WORKSHOP)
	_apply(0.0)


func mode() -> String:
	return _mode


## The stage the workshop and menu cameras orbit. Defaults to the world origin, which
## is where WorkshopStage puts its turntable.
func set_workshop_centre(centre: Vector3) -> void:
	_workshop_centre = centre
	if _mode != MODE_FIGHT:
		_apply(0.0)


## Fraction of WORKSHOP_BASE_DISTANCE the workshop camera sits at, 0.4 to 1.5.
func workshop_zoom() -> float:
	return _workshop_zoom


## factor > 1 means the fingers moved apart, which moves the camera closer.
func pinch(factor: float) -> void:
	if not _input_enabled or factor <= 0.0 or _mode == MODE_MENU:
		return
	_note_input()
	if _mode == MODE_WORKSHOP:
		_workshop_zoom = clampf(_workshop_zoom / factor, WORKSHOP_ZOOM_MIN, WORKSHOP_ZOOM_MAX)
		return
	zoom = clampf(zoom / factor, _zoom_min, FightTypes.CAM_ZOOM_MAX)


## delta is the drag in viewport pixels: the two finger centroid in the fight, one
## finger on the workshop turntable (there are no driving controls there).
func orbit(delta_px: Vector2) -> void:
	if not _input_enabled or _mode == MODE_MENU:
		return
	_note_input()
	yaw_deg = wrapf(yaw_deg - delta_px.x * ORBIT_DEG_PER_PX, -180.0, 180.0)
	# Dragging up raises the camera toward the top down clamp.
	if _mode == MODE_WORKSHOP:
		pitch_deg = clampf(pitch_deg - delta_px.y * TILT_DEG_PER_PX,
			WORKSHOP_PITCH_MIN, WORKSHOP_PITCH_MAX)
		return
	pitch_deg = clampf(pitch_deg - delta_px.y * TILT_DEG_PER_PX,
		FightTypes.CAM_PITCH_MIN, FightTypes.CAM_PITCH_MAX)


func reset_to_default() -> void:
	yaw_deg = _default_yaw
	pitch_deg = _default_pitch
	zoom = _default_zoom
	_easing = false
	_idle_s = 0.0
	_wreckage = null
	_apply(0.0)


## Open question 4 in the spec: the director cut is A/B testable.
func set_director_cut(enabled: bool) -> void:
	_director_cut = enabled
	if not enabled:
		_wreckage = null


## RESULT state. Eases in over WRECKAGE_EASE_S from wherever the camera is, then holds
## WRECKAGE_DISTANCE from the node at WRECKAGE_PITCH_DEG, looking straight at it, and
## orbits at WRECKAGE_ORBIT_DEG_PER_S until the player touches the screen.
func begin_wreckage_orbit(center: Node3D) -> void:
	if not _director_cut or center == null:
		return
	_wreckage = center
	_easing = false
	_idle_s = 0.0
	_wreck_t = 0.0
	_wreck_from_pos = global_position if is_inside_tree() else _look + _offset_direction() * _distance
	_wreck_from_look = _look


func set_input_enabled(on: bool) -> void:
	_input_enabled = on


## Subscribe to a FightControls node. Either side may do the wiring.
func bind_controls(c: FightControls) -> void:
	if c == null:
		return
	if not c.camera_pinch.is_connected(pinch):
		c.camera_pinch.connect(pinch)
	if not c.camera_orbit.is_connected(orbit):
		c.camera_orbit.connect(orbit)


# ---------------------------------------------------------------- workshop input
#
# The workshop has no driving controls, so there is no FightControls to route touches
# and the rig takes them itself: one finger orbits, two pinch. Only connected while
# the mode is "workshop", so the fight routing is untouched.

func _unhandled_input(event: InputEvent) -> void:
	if _mode != MODE_WORKSHOP:
		return
	if handle_event(event) and is_inside_tree():
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()


## The seam _unhandled_input delegates to. Public so a headless test can feed
## synthetic events, exactly as FightControls.handle_event does.
func handle_event(event: InputEvent) -> bool:
	if event is InputEventMagnifyGesture:
		pinch((event as InputEventMagnifyGesture).factor)
		return true
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touches[touch.index] = touch.position
		else:
			_touches.erase(touch.index)
		return true
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if not _touches.has(drag.index):
			return false
		var was: Vector2 = _touches[drag.index]
		_touches[drag.index] = drag.position
		var moved := drag.position - was
		if _touches.size() <= 1:
			orbit(moved)
			return true
		# Two or more fingers: the first two drive a pinch, and the centroid still
		# orbits so a two finger drag behaves the same as it does in the fight.
		var other := _other_touch(drag.index)
		var before := was.distance_to(other)
		var after := drag.position.distance_to(other)
		if before > 1.0 and after > 1.0:
			pinch(after / before)
		orbit(moved * 0.5)
		return true
	return false


func _other_touch(index: int) -> Vector2:
	for key in _touches.keys():
		if int(key) != index:
			return _touches[key]
	return Vector2.ZERO


func camera() -> Camera3D:
	_ensure_camera()
	return _camera


func distance() -> float:
	return _distance


## The point the camera is aimed at this frame.
func look_target() -> Vector3:
	return _look


func default_zoom() -> float:
	return _default_zoom


## The closest the player may pinch. CAM_ZOOM_MIN unless a QA argument asked for a
## closer default pose, in which case it widens to that.
func zoom_min() -> float:
	return _zoom_min


func is_easing_back() -> bool:
	return _easing


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	_apply(delta)


func _apply(delta: float) -> void:
	_ensure_camera()
	if not is_inside_tree():
		return
	if _mode != MODE_FIGHT:
		_apply_stage(delta)
		return
	if _wreckage != null and is_instance_valid(_wreckage):
		_apply_wreckage(delta)
		return

	_idle_s += delta
	if not _easing and _idle_s >= FightTypes.CAM_EASE_BACK_AFTER_S and not _at_default():
		_easing = true
		_ease_t = 0.0
		# Take the short way round in yaw.
		var short := _default_yaw + wrapf(yaw_deg - _default_yaw, -180.0, 180.0)
		_ease_from = Vector3(short, pitch_deg, zoom)
	if _easing:
		_ease_t += delta / maxf(FightTypes.CAM_EASE_BACK_S, 0.0001)
		if _ease_t >= 1.0:
			yaw_deg = _default_yaw
			pitch_deg = _default_pitch
			zoom = _default_zoom
			_easing = false
		else:
			var k := _ease_out_cubic(_ease_t)
			yaw_deg = lerpf(_ease_from.x, _default_yaw, k)
			pitch_deg = lerpf(_ease_from.y, _default_pitch, k)
			zoom = lerpf(_ease_from.z, _default_zoom, k)

	var dir := _offset_direction()
	# The fit distance is measured about the arena centre so it is a stable scale for
	# the zoom fraction; moving the look-at point must not push the camera back out.
	_distance = _fit_distance(Vector3.ZERO, dir) * clampf(zoom, _zoom_min, FightTypes.CAM_ZOOM_MAX)
	_look = _biased_look(dir, _distance)
	global_position = _look + dir * _distance
	look_at(_look, Vector3.UP)
	_camera.transform = Transform3D.IDENTITY


## Workshop and menu. One subject on a small stage, so the distance is a fixed base
## rather than an arena fit, the aim never moves, and nothing eases back.
func _apply_stage(delta: float) -> void:
	if _mode == MODE_MENU:
		_menu_t = fposmod(_menu_t + delta, MENU_PERIOD_S)
		var k := 0.5 * (1.0 - cos(TAU * _menu_t / MENU_PERIOD_S))
		yaw_deg = lerpf(MENU_YAW_MIN, MENU_YAW_MAX, k)
		pitch_deg = MENU_PITCH_DEG
		_distance = MENU_DISTANCE
		_look = _workshop_centre + Vector3(0.0, MENU_LOOK_HEIGHT, 0.0)
		var menu_dir := _direction(yaw_deg, pitch_deg)
		global_position = _look + menu_dir * _distance
		look_at(_look, Vector3.UP)
		_camera.transform = Transform3D.IDENTITY
		return
	else:
		pitch_deg = clampf(pitch_deg, WORKSHOP_PITCH_MIN, WORKSHOP_PITCH_MAX)
		_distance = WORKSHOP_BASE_DISTANCE * clampf(
			_workshop_zoom, WORKSHOP_ZOOM_MIN, WORKSHOP_ZOOM_MAX)
	_look = _workshop_centre + Vector3(0.0, WORKSHOP_LOOK_HEIGHT, 0.0)
	var dir := _direction(yaw_deg, pitch_deg)
	global_position = _look + dir * _distance
	look_at(_look, Vector3.UP)
	_camera.transform = Transform3D.IDENTITY


func _apply_wreckage(delta: float) -> void:
	yaw_deg = wrapf(yaw_deg + WRECKAGE_ORBIT_DEG_PER_S * delta, -180.0, 180.0)
	pitch_deg = WRECKAGE_PITCH_DEG
	_wreck_t = minf(_wreck_t + delta / maxf(WRECKAGE_EASE_S, 0.0001), 1.0)
	var k := _ease_out_cubic(_wreck_t)
	var centre := _wreckage.global_position
	var want := centre + _direction(yaw_deg, WRECKAGE_PITCH_DEG) * WRECKAGE_DISTANCE
	var pos := _wreck_from_pos.lerp(want, k)
	_look = _wreck_from_look.lerp(centre, k)
	_distance = pos.distance_to(_look)
	global_position = pos
	look_at(_look, Vector3.UP)
	_camera.transform = Transform3D.IDENTITY


func _at_default() -> bool:
	return absf(wrapf(yaw_deg - _default_yaw, -180.0, 180.0)) < 0.001 \
		and absf(pitch_deg - _default_pitch) < 0.001 \
		and absf(zoom - _default_zoom) < 0.0001


func _note_input() -> void:
	_idle_s = 0.0
	_easing = false
	_wreckage = null


func _ease_out_cubic(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


## Unit vector from a look target toward the camera.
func _direction(yaw_d: float, pitch_d: float) -> Vector3:
	var yaw := deg_to_rad(yaw_d)
	var pitch := deg_to_rad(pitch_d)
	var horizontal := cos(pitch)
	return Vector3(sin(yaw) * horizontal, sin(pitch), cos(yaw) * horizontal).normalized()


func _offset_direction() -> Vector3:
	return _direction(yaw_deg, clampf(pitch_deg, FightTypes.CAM_PITCH_MIN, FightTypes.CAM_PITCH_MAX))


## Below zoom 1.0 the aim slides from the arena centre toward the midpoint of the two
## bots, clamped so the visible ground footprint never leaves the floor rectangle. When
## the footprint already covers the floor the clamp collapses to the centre, which is
## what keeps zoom 1.0 framed on the whole arena.
func _biased_look(dir: Vector3, dist: float) -> Vector3:
	var centre := Vector3.ZERO
	if _target_a == null or _target_b == null:
		return centre
	if not is_instance_valid(_target_a) or not is_instance_valid(_target_b):
		return centre
	var t := clampf(inverse_lerp(FightTypes.CAM_ZOOM_MAX, _zoom_min, zoom), 0.0, 1.0)
	if t <= 0.0:
		return centre
	var mid := (_target_a.global_position + _target_b.global_position) * 0.5
	mid.y = 0.0
	var want := centre.lerp(mid, t)
	var limit := _look_limit(dir, dist)
	return Vector3(clampf(want.x, -limit.x, limit.x), 0.0, clampf(want.z, -limit.y, limit.y))


## Half extents the look-at point may move to in world x and z before the visible
## ground footprint runs off the floor. Returns (x limit, z limit), never negative.
## The footprint is a trapezoid, so the binding edge is the far one: it is measured
## where the top of the frustum meets the floor and that extent is used in both
## directions, which is conservative and keeps the invariant true rather than close.
func _look_limit(dir: Vector3, dist: float) -> Vector2:
	var tans := _frustum_tangents()
	var w := -dir
	var right := w.cross(Vector3.UP)
	if right.length_squared() < 0.000001:
		return Vector2.ZERO
	right = right.normalized()
	var forward := Vector3(w.x, 0.0, w.z)
	if forward.length_squared() < 0.000001:
		return Vector2.ZERO
	forward = forward.normalized()

	var pitch := deg_to_rad(clampf(pitch_deg, FightTypes.CAM_PITCH_MIN, FightTypes.CAM_PITCH_MAX))
	var half_fov_v := atan(tans.y)
	var height := dist * sin(pitch)
	# The ray along the top of the frustum, never allowed to approach the horizon.
	var far_angle := maxf(pitch - half_fov_v, deg_to_rad(3.0))
	var half_forward: float = height / tan(far_angle) - height / tan(pitch)
	var half_right: float = (height / sin(far_angle)) * tans.x

	var ax := absf(right.x) * half_right + absf(forward.x) * half_forward
	var az := absf(right.z) * half_right + absf(forward.z) * half_forward
	return Vector2(maxf(_floor_half - ax, 0.0), maxf(_floor_half - az, 0.0))


## Distance at which every corner of the arena box sits inside the frustum, for the
## current viewport aspect. Derived from the camera's own projection so it is correct
## whichever axis the FOV is applied to.
func _fit_distance(target: Vector3, dir: Vector3) -> float:
	var tans := _frustum_tangents()
	var tan_h: float = maxf(tans.x, 0.0001)
	var tan_v: float = maxf(tans.y, 0.0001)
	var w := -dir
	var right := w.cross(Vector3.UP)
	if right.length_squared() < 0.000001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(w).normalized()

	var h := _arena_half
	var d := 0.0
	for sx: float in [-h, h]:
		for sz: float in [-h, h]:
			for sy: float in [0.0, _arena_top]:
				var u := Vector3(sx, sy, sz) - target
				var need_x: float = absf(u.dot(right)) / tan_h - u.dot(w)
				var need_y: float = absf(u.dot(up)) / tan_v - u.dot(w)
				d = maxf(d, maxf(need_x, need_y))
	return maxf(d * FIT_MARGIN, _camera.near + 0.5)


## Returns (tan of half horizontal FOV, tan of half vertical FOV).
func _frustum_tangents() -> Vector2:
	if is_inside_tree() and _camera.is_inside_tree():
		var p := _camera.get_camera_projection()
		if absf(p.x.x) > 0.000001 and absf(p.y.y) > 0.000001:
			return Vector2(1.0 / absf(p.x.x), 1.0 / absf(p.y.y))
	var tan_v := tan(deg_to_rad(_camera.fov) * 0.5)
	return Vector2(tan_v * _aspect(), tan_v)


func _aspect() -> float:
	if is_inside_tree():
		var vp := get_viewport()
		if vp != null:
			var s := vp.get_visible_rect().size
			if s.x > 1.0 and s.y > 1.0:
				return s.x / s.y
	return 16.0 / 9.0
