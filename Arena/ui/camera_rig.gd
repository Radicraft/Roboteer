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

## Fallback resting zoom, as a fraction of the arena fit distance, used only when there
## are no bots to frame (before a fight is spawned, and in the headless fit checks).
##
## CHANGED 2026-09-14: a fixed fraction of the ARENA fit is the wrong resting pose. On a
## live device run at DEFAULT_ZOOM the bots were about 20 pt tall on a 402 pt screen:
## the whole floor fitted and both machines were dots. The resting distance now frames
## the BOTS (see `_subject_distance`), clamped between NEAR_BOT_FRACTION of the viewport
## height and the walls-on-screen fit. `zoom` still means "fraction of the arena fit
## distance", so every clamp, every gesture and CAM_ZOOM_MAX are unchanged; what changed
## is the value it rests at, which is now computed per frame rather than constant.
const DEFAULT_ZOOM := 0.6

## Framing the bots. A nominal machine is BOT_SIZE_M across and tall enough to read at
## NEAR_BOT_FRACTION of the viewport height, which is the closest the auto framing will
## ever go. SUBJECT_MARGIN_BOTS is the breathing room left around the pair, in bot
## lengths, on every side, so a charge does not start off screen.
const BOT_SIZE_M := 0.9
const NEAR_BOT_FRACTION := 0.30
const SUBJECT_MARGIN_BOTS := 1.0
## PLAYER PRIORITY (added 2026-09-14). At the opening bell the two machines are 8 m
## apart and fitting the pair means fitting most of the arena, which put each bot at
## about 20 pt on a 402 pt screen. The player's own machine may never project smaller
## than this fraction of the viewport height: past it the camera stops pulling back,
## holds the distance, and leans the aim toward the player instead. As the two close,
## the pair fit comes back inside the floor and frames both again.
const PLAYER_MIN_FRACTION := 0.10
## How the aim is split between the player and the opponent while the floor is holding.
const PLAYER_LOOK_WEIGHT := 0.65
## The auto framing eases rather than tracking exactly, so a bot being thrown or flipping
## does not snap the camera. Seconds to close most of the gap.
const SUBJECT_EASE_S := 0.35

## RESULT state, the director cut.
const WRECKAGE_DISTANCE := 2.6
const WRECKAGE_PITCH_DEG := 35.0
const WRECKAGE_ORBIT_DEG_PER_S := 20.0
const WRECKAGE_EASE_S := 1.0

## Camera kick source, agent G4's ImpactShake (docs/graphics-fx-notes.md section 4).
## Looked up by group rather than by class so Arena/ui keeps no dependency on
## Arena/fx: delete the whole FX subtree and the lookup simply finds nothing.
const IMPACT_SHAKE_GROUP := "roboteer_impact_shake"

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

## Frame bias (workshop and menu only). `workshop_config.frame` says where across the
## screen the stage centre should land, 0 hard left, 0.5 centred, 1 hard right, so the
## SwiftUI panels can own one side of the screen and the bot still be framed in what is
## left. Implemented as Camera3D.h_offset, which translates the camera along its own
## right axis, so a point at the look distance moves by exactly minus that offset.
const FRAME_CENTRE := 0.5
## Clamped: past this the stage leaves the frustum entirely and there is nothing to see.
const FRAME_MIN := 0.12
const FRAME_MAX := 0.88
## Seconds to glide the bias across the WHOLE screen, so switching screens does not jump.
## A shorter move takes proportionally less time (the ease is a constant rate).
const FRAME_EASE_S := 0.35

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
## The resting zoom the auto framing wants this frame, as a fraction of the arena fit.
var _rest_zoom: float = DEFAULT_ZOOM
## True while the player-priority floor is holding the camera in rather than fitting
## the pair. The HUD's off-screen arrow exists for exactly this case.
var _floored: bool = false
## Share of the aim that belongs to the player: 0.5 normally, PLAYER_LOOK_WEIGHT floored.
var _look_weight: float = 0.5
## True while the camera is sitting on the auto framing and the player has not touched it.
var _resting: bool = true

var _wreck_t: float = 0.0
var _wreck_from_pos := Vector3.ZERO
var _wreck_from_look := Vector3.ZERO

var _mode: String = MODE_FIGHT
## The ImpactShake node, found by group. Null until a fight world exists, and looked
## up again whenever it is null because R rebuilds that world for every fight.
var _shake: Node = null
## Fraction of WORKSHOP_BASE_DISTANCE. Larger is further away.
var _workshop_zoom: float = 1.0
var _workshop_centre := Vector3.ZERO
var _menu_t: float = 0.0
## Live touches while the rig owns input itself (workshop only): index -> position.
var _touches: Dictionary = {}
## Where the stage centre should project across the screen, and where it currently does.
var _frame: float = FRAME_CENTRE
var _frame_now: float = FRAME_CENTRE


func _ready() -> void:
	_ensure_camera()
	_read_qa_arguments()
	_find_shake()
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
			_rest_zoom = _default_zoom
			_resting = true
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


## Where the stage centre should land across the screen, 0 to 1. The shell sends this as
## `workshop_config.frame` when a SwiftUI panel covers one side; 0.5 is centred, which is
## what every caller that says nothing gets. Fight mode ignores it: the arena frames
## itself and the HUD is drawn around it, not beside it.
func set_frame_bias(frame: float) -> void:
	_frame = clampf(frame, FRAME_MIN, FRAME_MAX)


## The requested bias.
func frame_bias() -> float:
	return _frame


## The bias actually applied this frame, which eases toward the requested one.
func frame_bias_now() -> float:
	return _frame_now


## Half the visible width in world units at the current look distance, for the current
## viewport aspect. Godot keeps the vertical FOV (keep_aspect = KEEP_HEIGHT), so this is
## distance * tan(fov / 2) * aspect, taken from the camera's own projection.
func half_frame_width() -> float:
	return _distance * _frustum_tangents().x


## factor > 1 means the fingers moved apart, which moves the camera closer.
func pinch(factor: float) -> void:
	if not _input_enabled or factor <= 0.0 or _mode == MODE_MENU:
		return
	_note_input()
	if _mode == MODE_WORKSHOP:
		_workshop_zoom = clampf(_workshop_zoom / factor, WORKSHOP_ZOOM_MIN, WORKSHOP_ZOOM_MAX)
		return
	zoom = clampf(zoom / factor, zoom_min(), FightTypes.CAM_ZOOM_MAX)


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
	_rest_zoom = _default_zoom
	_easing = false
	_resting = true
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
## closer default pose, or the auto framing wants closer still (two bots nose to nose
## on a 10 m floor are a long way inside the walls-on-screen fit), in which case it
## widens to whichever is nearest.
func zoom_min() -> float:
	return minf(_zoom_min, _rest_zoom)


## The zoom the auto framing wants this frame, as a fraction of the arena fit distance.
func resting_zoom() -> float:
	return _rest_zoom


## True while the camera is sitting on the auto framing rather than where a gesture left
## it. Any pinch or orbit clears it; the ease back sets it again.
func is_resting() -> bool:
	return _resting


func is_easing_back() -> bool:
	return _easing


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	_apply(delta)


func _apply(delta: float) -> void:
	_ensure_camera()
	if not is_inside_tree():
		return
	# The bias glides whatever the mode, so switching screens does not snap; fight mode
	# then ignores the result and sits dead centre.
	_frame_now = move_toward(_frame_now, _frame, delta / maxf(FRAME_EASE_S, 0.0001))
	if _mode != MODE_FIGHT:
		_apply_stage(delta)
		_apply_frame_bias()
		return
	_camera.h_offset = 0.0
	if _wreckage != null and is_instance_valid(_wreckage):
		_apply_wreckage(delta)
		return

	# The resting pose frames the BOTS, so it is recomputed every frame from where they
	# are. `zoom` still means "fraction of the arena fit distance"; only its resting
	# value is dynamic.
	var dir := _offset_direction()
	var fit := _fit_distance(Vector3.ZERO, dir)
	_rest_zoom = _compute_rest_zoom(dir, fit)

	_idle_s += delta
	if not _easing and not _resting and _idle_s >= FightTypes.CAM_EASE_BACK_AFTER_S:
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
			zoom = _rest_zoom
			_easing = false
			_resting = true
		else:
			var k := _ease_out_cubic(_ease_t)
			yaw_deg = lerpf(_ease_from.x, _default_yaw, k)
			pitch_deg = lerpf(_ease_from.y, _default_pitch, k)
			zoom = lerpf(_ease_from.z, _rest_zoom, k)
	elif _resting:
		# Sitting on the auto framing: follow it as the bots move.
		zoom = _rest_zoom

	# The fit distance is measured about the arena centre so it is a stable scale for
	# the zoom fraction; moving the look-at point must not push the camera back out.
	var want_distance := fit * clampf(zoom, zoom_min(), FightTypes.CAM_ZOOM_MAX)
	var want_look := _biased_look(dir, want_distance)
	# Ease both, so a bot flipping or being thrown across the floor never snaps the
	# camera. A zero delta (fit_arena, reset_to_default, the headless checks) snaps, so
	# every pose set by hand is exact.
	var k_ease := 1.0 if delta <= 0.0 else 1.0 - exp(-delta / maxf(SUBJECT_EASE_S, 0.0001))
	_distance = lerpf(_distance, want_distance, k_ease)
	_look = _look.lerp(want_look, k_ease)
	global_position = _look + dir * _distance
	look_at(_look, Vector3.UP)
	_camera.transform = Transform3D(Basis(), _shake_offset())


## Workshop and menu. One subject on a small stage, so the distance is a fixed base
## rather than an arena fit, the aim never moves, and nothing eases back. The camera
## transform stays identity here: the impact shake is a fight effect only.
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


## Slide the whole camera along its own right axis so the point it is looking at lands
## at `_frame_now` across the screen instead of dead centre.
##
## Camera3D.h_offset translates the camera by that many world units along its local X
## (it is not a frustum skew), so a point at the look distance moves the other way by
## the same amount. Half the frame is `distance * tan(fov / 2) * aspect` wide in world
## units, and a point that should sit at normalised x `f` is `(f - 0.5) * 2 * half`
## off the axis, so the camera has to go the other way: `(0.5 - f) * 2 * half`. The
## sign is checked against the real projection with unproject_position in ui_test.
func _apply_frame_bias() -> void:
	if absf(_frame_now - FRAME_CENTRE) < 0.0005:
		_camera.h_offset = 0.0
		return
	_camera.h_offset = (FRAME_CENTRE - _frame_now) * 2.0 * half_frame_width()


## Camera local kick from ImpactShake, zero outside fight mode and zero when there is
## no FX tree. The offset goes on the Camera3D child, never on the rig, so it cannot
## disturb the rig's own look_at. Peak travel is ImpactShake.MAX_OFFSET (7 cm).
func _shake_offset() -> Vector3:
	if _mode != MODE_FIGHT:
		return Vector3.ZERO
	if _shake == null or not is_instance_valid(_shake):
		_find_shake()
	if _shake == null:
		return Vector3.ZERO
	var value: Variant = _shake.call("offset")
	return value if value is Vector3 else Vector3.ZERO


func _find_shake() -> void:
	_shake = null
	if not is_inside_tree():
		return
	var node := get_tree().get_first_node_in_group(IMPACT_SHAKE_GROUP)
	if node != null and node.has_method("offset"):
		_shake = node


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
	_camera.transform = Transform3D(Basis(), _shake_offset())


func _at_default() -> bool:
	return absf(wrapf(yaw_deg - _default_yaw, -180.0, 180.0)) < 0.001 \
		and absf(pitch_deg - _default_pitch) < 0.001 \
		and absf(zoom - _default_zoom) < 0.0001


func _note_input() -> void:
	_idle_s = 0.0
	_easing = false
	_resting = false
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
	var t := clampf(inverse_lerp(FightTypes.CAM_ZOOM_MAX, zoom_min(), zoom), 0.0, 1.0)
	if t <= 0.0:
		return centre
	# _target_a is the player. Normally the aim is the midpoint; while the floor is
	# holding it leans PLAYER_LOOK_WEIGHT of the way onto the player, so the machine the
	# player is driving stays near the middle of the frame and the opponent stays in it
	# for as long as the geometry allows.
	var mid := _target_a.global_position.lerp(_target_b.global_position, 1.0 - _look_weight)
	mid.y = 0.0
	var want := centre.lerp(mid, t)
	var limit := _look_limit(dir, dist)
	if _floored:
		# The footprint rule (keep every visible metre of ground on the floor) collapses
		# to "never move" at this distance, which would make the bias do nothing. While
		# the floor is holding, the aim is instead only kept on the floor itself; both
		# machines are on it, so the aim always is.
		limit = Vector2(maxf(limit.x, _floor_half), maxf(limit.y, _floor_half))
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
## whichever axis the FOV is applied to. This is the walls-on-screen limit, and the far
## end of the auto framing.
func _fit_distance(target: Vector3, dir: Vector3) -> float:
	var half := Vector3(_arena_half, _arena_top * 0.5, _arena_half)
	var centre := Vector3(0.0, _arena_top * 0.5, 0.0)
	return maxf(_fit_box(target, dir, centre, half) * FIT_MARGIN, _camera.near + 0.5)


## Distance at which every corner of an axis aligned box sits inside the frustum, looking
## from `dir` at `target`. The one fitting routine: the arena box and the pair of bots
## both go through it.
func _fit_box(target: Vector3, dir: Vector3, centre: Vector3, half: Vector3) -> float:
	var tans := _frustum_tangents()
	var tan_h: float = maxf(tans.x, 0.0001)
	var tan_v: float = maxf(tans.y, 0.0001)
	var w := -dir
	var right := w.cross(Vector3.UP)
	if right.length_squared() < 0.000001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(w).normalized()

	var d := 0.0
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var u := centre + Vector3(sx * half.x, sy * half.y, sz * half.z) - target
				var need_x: float = absf(u.dot(right)) / tan_h - u.dot(w)
				var need_y: float = absf(u.dot(up)) / tan_v - u.dot(w)
				d = maxf(d, maxf(need_x, need_y))
	return maxf(d, _camera.near + 0.5)


## The distance at which a BOT_SIZE_M machine PROJECTS as `fraction` of the viewport
## height. Godot keeps the vertical FOV, so the viewport is 2 * distance * tan(fov / 2)
## tall in world units at the look distance; a standing machine seen at `pitch_deg` is
## foreshortened by cos(pitch), and leaving that out reports a bot half again as tall as
## the screen actually shows.
func _distance_for_screen_fraction(fraction: float) -> float:
	var tan_v := maxf(_frustum_tangents().y, 0.0001)
	var pitch := deg_to_rad(clampf(pitch_deg, FightTypes.CAM_PITCH_MIN, FightTypes.CAM_PITCH_MAX))
	var apparent := BOT_SIZE_M * maxf(cos(pitch), 0.05)
	return apparent / (2.0 * maxf(fraction, 0.01) * tan_v)


## The distance that frames both machines plus about one bot length of margin on every
## side. Falls back to the arena fit when there are no targets yet.
func _subject_distance(dir: Vector3) -> float:
	if _target_a == null or _target_b == null:
		return -1.0
	if not is_instance_valid(_target_a) or not is_instance_valid(_target_b):
		return -1.0
	var a := _target_a.global_position
	var b := _target_b.global_position
	var pad := BOT_SIZE_M * (0.5 + SUBJECT_MARGIN_BOTS)
	var centre := Vector3((a.x + b.x) * 0.5, BOT_SIZE_M * 0.5, (a.z + b.z) * 0.5)
	var half := Vector3(
		absf(a.x - b.x) * 0.5 + pad,
		BOT_SIZE_M * 0.5,
		absf(a.z - b.z) * 0.5 + pad)
	return _fit_box(centre, dir, centre, half)


## The resting zoom, as a fraction of the arena fit distance: the bot framing distance
## clamped between the near readability limit and the walls-on-screen fit.
func _compute_rest_zoom(dir: Vector3, fit: float) -> float:
	_floored = false
	_look_weight = 0.5
	var want := _subject_distance(dir)
	if want < 0.0:
		return _default_zoom
	var near := minf(_distance_for_screen_fraction(NEAR_BOT_FRACTION), fit)
	# The player-priority floor. Never further than this, whatever the pair needs.
	var ceiling := clampf(_distance_for_screen_fraction(PLAYER_MIN_FRACTION), near, fit)
	if want > ceiling:
		_floored = true
		_look_weight = PLAYER_LOOK_WEIGHT
		want = ceiling
	return clampf(clampf(want, near, fit) / maxf(fit, 0.001), 0.0001, FightTypes.CAM_ZOOM_MAX)


## True while the camera is holding the player-priority floor instead of fitting both
## machines, which is when the opponent may be off the edge of the frame.
func is_player_floored() -> bool:
	return _floored


## The share of the aim that belongs to the player this frame.
func look_weight() -> float:
	return _look_weight


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
