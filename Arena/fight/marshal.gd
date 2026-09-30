class_name FightMarshal extends Node3D
## The Marshal (wave D, docs/wave-d-marshal-notes.md): Roboteer's own neutral arena official.
## A four-duct hover drone with a light bar across its nose. Owner decision 30 Sept 2026
## (docs/aaa/decisions-2026-09-30.md): it shows the start lights, counts a knockout with its
## lights, tows stuck machines apart, sprays out fires, calls POWER DOWN and cards a house bot
## that oversteps. Never a striped humanoid, never the show's referee name or shape.
##
## PRESENTATION ONLY. The Marshal has no body, no collider and no area; nothing in the fight
## reads it; it draws nothing from the fight's rng. It is told what the rules are doing
## (`step`'s facts, read by fight.gd off the simulation) and acts it out. The lock-up break
## and the unstick nudge are the SAME impulses on the SAME tick they always were: fight.gd
## applies them and then tells the Marshal, which flies in beforehand (the rules' own timers
## say one is coming) and draws the tow line when it lands. tests/marshal_test.gd proves the
## fight hashes the same with it and without it.
##
## Time: `step(delta, facts)` is called from fight.gd's presentation drain with the wall
## delta already multiplied by the hit-stop pace, so it slows with the slow motion and stops
## with a stop, and never runs while the fight is paused.

signal beat(beat_name: String, info: Dictionary)

const MODEL := "res://assets/marshal/marshal.glb"
const SEGMENTS := 10
## The model is authored at 0.63 m across the ducts; drawn at 0.85 m so the light bar reads
## at the fight camera's distance (a 10 segment bar is ~45 px wide on a phone at this size).
const MODEL_SCALE := 1.35
const TEX := "res://assets/textures/"

# --- what it is doing, in priority order when two want it at once
const MODE_IDLE := "idle"          # no fight: parked, dark
const MODE_START := "start"        # the countdown, over the centre
const MODE_LIFT := "lift"          # FIGHT: flash green and climb away
const MODE_PATROL := "patrol"      # watching from high on the far side
const MODE_COUNT := "count"        # a knockout count, over the machine
const MODE_TOW := "tow"            # two machines locked: in between them, tow line ready
const MODE_UNSTICK := "unstick"    # one machine wedged: over it, tow line ready
const MODE_SPRAY := "spray"        # a machine burning: nozzle on it
const MODE_STOP := "stop"          # POWER DOWN: red bar, steady hover
const MODE_CARD := "card"          # a house bot hit after the bell: over it, card out

# --- the light bar's colours (lit energy is per mode)
const COL_START := Color(1.0, 0.62, 0.16)
const COL_GO := Color(0.25, 1.0, 0.42)
const COL_COUNT := Color(1.0, 0.58, 0.12)
const COL_COUNT_LOW := Color(1.0, 0.16, 0.08)
const COL_IDLE := Color(0.86, 0.92, 1.0)
const COL_TOW := Color(0.86, 0.94, 1.0)
const COL_STOP := Color(1.0, 0.1, 0.06)
const COL_CARD := Color(1.0, 0.86, 0.1)
const LIT_ENERGY := 5.0
const DIM_ENERGY := 1.4

# --- flight
const MAX_SPEED := 7.0                # m/s
const ACCEL := 13.0                   # m/s^2
const GAIN := 2.6                     # desired speed per metre of error
const LEAN_PER_MS := 0.09             # radians of lean per m/s
const LEAN_MAX := 0.38
const YAW_RATE := 5.0                 # per second, slerp rate
const START_HEIGHT := 1.7             # over the centre for the countdown
const PATROL_HEIGHT := 2.7
const COUNT_HEIGHT := 1.15            # above the counted machine's chassis
const TOW_HEIGHT := 0.95
const SPRAY_HEIGHT := 0.8
const BEHIND_M := 0.55                # sits this far beyond its machine from the camera
const LIFT_S := 0.9
const GO_FLASH_S := 0.7
const TOW_LINE_S := 0.55              # the tow line is drawn this long after the impulse
const TOW_ARM_PROGRESS := 0.35        # of the rules' own timer: fly in from here
const SPRAY_HOLD_S := 1.4             # keeps spraying this long after the last burn
const CARD_S := 1.8
const WOBBLE_RADIUS_M := 0.6
const WOBBLE_MIN_SPEED := 1.6         # m/s: a slower thing drifting by is not a hit
const WOBBLE_GAP_S := 1.4
## Show spots: screen offsets from the subject (fractions of the frame, +x right, +y down),
## chosen clear of the HUD: the timer and names along the top, the knockout band across the
## middle, the ticker and the thumbs along the bottom.
const SPOT_START := Vector2(0.22, -0.2)
const SPOT_COUNT := Vector2(0.26, -0.1)
const SPOT_TOW := Vector2(0.2, -0.24)
const SPOT_SPRAY := Vector2(-0.12, -0.12)
const SPOT_STOP := Vector2(0.26, -0.22)
const SPOT_CARD := Vector2(0.2, -0.2)
const SAFE_X := Vector2(0.2, 0.8)
const SAFE_Y := Vector2(0.34, 0.66)
const SPOT_BEHIND_M := 0.3
## In the finish beat the camera orbits the wreck from 2.6 m: stay well back from the lens.
const SPOT_BEHIND_FINISH_M := 0.6
## A camera nearer its subject than this is a close-up the Marshal keeps out of.
const CLOSE_SHOT_M := 3.6
const PATROL_BEYOND_M := 3.2

var mode: String = MODE_IDLE
## The arena's half extent (m), for the patrol spot. Set by `configure`.
var half_extent: float = 5.0

var _model: Node3D = null
var _rotors: Array[Node3D] = []
var _blur_discs: Array[MeshInstance3D] = []
var _segs: Array[MeshInstance3D] = []
var _seg_mats: Array[StandardMaterial3D] = []
var _beacon_mat: StandardMaterial3D = null
var _light: OmniLight3D = null
var _tethers: Array[MeshInstance3D] = []
var _tether_mat: StandardMaterial3D = null
var _spray: GPUParticles3D = null
var _card: Node3D = null
var _card_mat: StandardMaterial3D = null
var _nozzle: Node3D = null
var _card_slot: Node3D = null
var _tether_origin: Node3D = null

var _pos := Vector3.ZERO
var _vel := Vector3.ZERO
var _yaw := 0.0
var _target := Vector3.ZERO
var _look := Vector3.ZERO
var _clock := 0.0
var _lean := Vector2.ZERO             # x pitch, y roll
var _wobble_t := -1.0                 # seconds since the knock, -1 none
var _wobble_axis := Vector3.RIGHT
var _wobble_gap := 0.0
var _flicker := 0.0

# --- the bar
var _pattern: Array = []              # SEGMENTS floats 0..1, VIEWER order (left to right)
var _bar_colour := COL_IDLE
var _bar_energy := DIM_ENERGY
var _count_shown := -1
var _count_flash := 0.0

# --- timed beats
var _mode_t := 0.0
var _tow_line_t := -1.0
var _tow_points: Array = []           # world points the tow line runs to
var _spray_left := 0.0
var _spray_at := Vector3.ZERO
var _card_t := -1.0
var _card_at := Vector3.ZERO
var _last_step_facts: Dictionary = {}
var _cam_xform := Transform3D()
var _placed := false
var _cam_fov := 0.0
var _cam_aspect := 16.0 / 9.0

## For the tests: every beat said, in order.
var beats_said: Array = []


func _ready() -> void:
	_build()
	_pattern = _fill_pattern(0.0)
	_apply_bar()


# ---------------------------------------------------------------- public: fight.gd drives it

## The arena's size. Put it on the start spot, dark.
func configure(arena_half_extent: float) -> void:
	half_extent = maxf(arena_half_extent, 2.0)
	_pos = Vector3(0.0, START_HEIGHT, 0.0)
	_vel = Vector3.ZERO
	_target = _pos
	mode = MODE_START
	_mode_t = 0.0
	_count_shown = -1
	_card_t = -1.0
	_tow_line_t = -1.0
	_spray_left = 0.0
	_wobble_t = -1.0
	_placed = false
	beats_said.clear()
	if _spray != null:
		_spray.emitting = false
	_apply_transform(0.0)


## One presentation frame. `delta` is already the SIMULATION's pace of the wall clock.
## `facts` (all optional, all read only off the fight):
##   state          "countdown" | "fighting" | "result" | ""
##   countdown_left seconds of the countdown still to run
##   camera         the fight camera's world position
##   bots           [{pos: Vector3, vel: Vector3, live: bool}] per machine
##   ko             {index, seconds_left, show}   the rules' knockout count on display
##   lockup         {progress 0..1, a: Vector3, b: Vector3}   the rules' lock-up timer
##   wedged         {index, progress 0..1, pos}   the rules' unstick timer, most advanced
##   burning        {index, pos}   a machine that took burn damage lately (-1 none)
##   debris         [{pos, vel}]  things flying about, for the knock
##   card           {pos}  a house bot to card (set by fight.gd after a late hit)
func step(delta: float, facts: Dictionary) -> void:
	_last_step_facts = facts
	var dt := maxf(delta, 0.0)
	_clock += dt
	_mode_t += dt
	_count_flash = maxf(0.0, _count_flash - dt)
	_wobble_gap = maxf(0.0, _wobble_gap - dt)
	_flicker = maxf(0.0, _flicker - dt)
	_choose_mode(facts, dt)
	_aim(facts)
	if not _placed and _cam_fov > 0.0:
		# The first frame it knows the camera: drop in from above its spot, so the start
		# lights are in shot for the whole countdown however short it is.
		_placed = true
		_pos = _clamp_target(_target) + Vector3.UP * 1.6
		_vel = Vector3.DOWN * 2.0
	_fly(dt)
	_check_knock(facts)
	_update_bar(facts)
	_update_tow(dt)
	_update_spray(dt)
	_update_card(dt, facts)
	_apply_transform(dt)
	_apply_bar()


## The bell: FIGHT. Flash green, then climb away.
func on_fight_start() -> void:
	mode = MODE_LIFT
	_mode_t = 0.0
	_say("fight_start", {})


## The rules broke a lock-up this tick (`_tick_lockup`'s impulse, already applied).
func on_lockup_break(a: Vector3, b: Vector3) -> void:
	_tow_points = [a, b]
	_tow_line_t = 0.0
	_vel += Vector3.UP * 1.2          # the kick of hauling two machines apart
	_say("tow", {"kind": "lockup"})


## The rules nudged a wedged machine this tick (`_nudge`'s impulse, already applied).
func on_unstick(at: Vector3) -> void:
	_tow_points = [at]
	_tow_line_t = 0.0
	_vel += Vector3.UP * 0.8
	_say("tow", {"kind": "unstick"})


## The fight is over: POWER DOWN. The bar goes red and stays red.
func on_stop() -> void:
	mode = MODE_STOP
	_mode_t = 0.0
	_spray_left = 0.0
	_tow_line_t = -1.0
	_say("stop", {})


## A house bot hit a beaten machine after the bell: fly over it and show the card.
func show_card(at: Vector3) -> void:
	_card_at = at
	mode = MODE_CARD
	_mode_t = 0.0
	_card_t = 0.0


## A knock for the comic beat, from anything moving fast through its space (or a test).
func knock(from_velocity: Vector3) -> void:
	if _wobble_gap > 0.0:
		return
	_wobble_gap = WOBBLE_GAP_S
	_wobble_t = 0.0
	var flat := Vector3(from_velocity.x, 0.0, from_velocity.z)
	_wobble_axis = flat.cross(Vector3.UP).normalized() if flat.length() > 0.01 else Vector3.RIGHT
	_vel += from_velocity.limit_length(3.0) * 0.45 + Vector3.UP * 0.6
	_flicker = 0.45
	_say("wobble", {})


# ---------------------------------------------------------------- read only, for tests and captures

func position_now() -> Vector3:
	return _pos


func bar_colour() -> Color:
	return _bar_colour


## How many segments are lit (above half brightness) right now.
func bar_lit() -> int:
	var n := 0
	for v in _pattern:
		if float(v) > 0.5:
			n += 1
	return n


## The pattern in viewer order, 0..1 per segment.
func bar_pattern() -> Array:
	return _pattern.duplicate()


func tow_line_visible() -> bool:
	return not _tethers.is_empty() and _tethers[0].visible


func spraying() -> bool:
	return _spray != null and _spray.emitting


func card_out() -> bool:
	return _card != null and _card.visible


func wobbling() -> bool:
	return _wobble_t >= 0.0


func triangle_count() -> int:
	var tris := 0
	for mi in _meshes(self):
		var m := (mi as MeshInstance3D).mesh
		if m == null:
			continue
		for s in m.get_surface_count():
			var arrays := m.surface_get_arrays(s)
			var idx: Variant = arrays[Mesh.ARRAY_INDEX]
			if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
				tris += (idx as PackedInt32Array).size() / 3
			else:
				tris += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return tris


# ---------------------------------------------------------------- behaviour

func _choose_mode(facts: Dictionary, _dt: float) -> void:
	var state := str(facts.get("state", ""))
	if state == "":
		mode = MODE_IDLE
		return
	if state == "countdown":
		if mode != MODE_START:
			mode = MODE_START
			_mode_t = 0.0
		return
	if state == "result":
		if mode == MODE_CARD:
			if _card_t >= CARD_S:
				mode = MODE_STOP
				_mode_t = 0.0
			return
		if mode != MODE_STOP:
			on_stop()
		return
	# fighting
	if mode == MODE_LIFT and _mode_t < LIFT_S:
		return
	if mode == MODE_START:
		# a fight that started without the bell reaching us (a replay seek, a test)
		mode = MODE_PATROL
	var ko: Dictionary = facts.get("ko", {}) as Dictionary
	var lockup: Dictionary = facts.get("lockup", {}) as Dictionary
	var wedged: Dictionary = facts.get("wedged", {}) as Dictionary
	var burning: Dictionary = facts.get("burning", {}) as Dictionary
	var want := MODE_PATROL
	if bool(ko.get("show", false)) and int(ko.get("index", -1)) >= 0:
		want = MODE_COUNT
	elif float(lockup.get("progress", 0.0)) >= TOW_ARM_PROGRESS or _tow_line_t >= 0.0 \
			and _tow_points.size() == 2:
		want = MODE_TOW
	elif float(wedged.get("progress", 0.0)) >= TOW_ARM_PROGRESS or _tow_line_t >= 0.0 \
			and _tow_points.size() == 1:
		want = MODE_UNSTICK
	elif int(burning.get("index", -1)) >= 0 or _spray_left > 0.0:
		want = MODE_SPRAY
	if want != mode:
		if want == MODE_COUNT:
			_count_shown = -1
		if want == MODE_SPRAY and mode != MODE_SPRAY:
			_say("spray", {"index": int(burning.get("index", -1))})
		mode = want
		_mode_t = 0.0


func _aim(facts: Dictionary) -> void:
	var cam: Vector3 = facts.get("camera", Vector3(0.0, 8.0, 8.0))
	_cam_xform = facts.get("camera_xform", Transform3D(Basis(), cam)) as Transform3D
	_cam_fov = float(facts.get("camera_fov", 0.0))
	_cam_aspect = float(facts.get("aspect", 16.0 / 9.0))
	var bots: Array = facts.get("bots", []) as Array
	var action := _action_point(bots)
	match mode:
		MODE_IDLE:
			_target = Vector3(0.0, PATROL_HEIGHT + 2.0, 0.0)
			_look = cam
		MODE_START:
			# Beside the player's machine, in the fight camera's frame, clear of the big
			# numeral in the middle: the player sees the lights count with the HUD.
			_target = _show_spot(_bot_pos(bots, 0, action), SPOT_START, cam, 1.3)
			_look = cam
		MODE_LIFT:
			# hold the spot while the bar flashes green, then climb up and out of shot
			var up := clampf((_mode_t - GO_FLASH_S * 0.5) / LIFT_S, 0.0, 1.0)
			var from := _show_spot(_bot_pos(bots, 0, action), SPOT_START, cam, 1.3)
			_target = from.lerp(_patrol_spot(cam, action), up * up) + Vector3.UP * up * 0.8
			_look = cam
		MODE_PATROL:
			_target = _patrol_spot(cam, action)
			_look = action
		MODE_COUNT:
			var ko: Dictionary = facts.get("ko", {}) as Dictionary
			var at := _bot_pos(bots, int(ko.get("index", -1)), action)
			_target = _show_spot(at, SPOT_COUNT, cam, COUNT_HEIGHT)
			_look = cam
		MODE_TOW:
			var lockup: Dictionary = facts.get("lockup", {}) as Dictionary
			var a: Vector3 = lockup.get("a", _tow_points[0] if _tow_points.size() > 0 else action)
			var b: Vector3 = lockup.get("b", _tow_points[1] if _tow_points.size() > 1 else action)
			if _tow_line_t >= 0.0 and _tow_points.size() == 2:
				a = _live_point(bots, _tow_points[0])
				b = _live_point(bots, _tow_points[1])
				_tow_points = [a, b]
			_target = _show_spot((a + b) * 0.5, SPOT_TOW, cam, TOW_HEIGHT)
			_look = cam
		MODE_UNSTICK:
			var wedged: Dictionary = facts.get("wedged", {}) as Dictionary
			var at2: Vector3 = wedged.get("pos", _tow_points[0] if _tow_points.size() > 0 else action)
			if _tow_line_t >= 0.0 and _tow_points.size() == 1:
				at2 = _live_point(bots, _tow_points[0])
				_tow_points = [at2]
			_target = _show_spot(at2, SPOT_TOW, cam, TOW_HEIGHT)
			_look = cam
		MODE_SPRAY:
			var burning: Dictionary = facts.get("burning", {}) as Dictionary
			if int(burning.get("index", -1)) >= 0:
				_spray_at = burning.get("pos", _spray_at)
				_spray_left = SPRAY_HOLD_S
			_target = _show_spot(_spray_at, SPOT_SPRAY, cam, SPRAY_HEIGHT)
			_look = _spray_at
		MODE_STOP:
			# POWER DOWN: red bar to the lens. In shot when the camera is far enough back to
			# have it in without filling the frame; in the finish beat's close orbit of the
			# wreck (2.6 m) it holds where it is, out of that shot, and the HUD says it.
			var subject: Vector3 = facts.get("subject", action)
			if _depth_of(subject) >= CLOSE_SHOT_M:
				_target = _show_spot(subject, SPOT_STOP, cam, 1.0, SPOT_BEHIND_FINISH_M)
			elif _mode_t < 0.05:
				_target = _pos
			_look = cam
		MODE_CARD:
			_target = _show_spot(_card_at, SPOT_CARD, cam, 0.9, SPOT_BEHIND_FINISH_M)
			_look = cam


## Where to hover for a beat about `subject`: in the fight camera's frame at `spot` (screen
## offset from the subject, in fractions of the frame), at about the subject's depth (`behind`: past it, from the lens), clamped clear of the HUD's corners and bands. Without a camera (the unit test)
## it is the plain world placement: beyond the subject from the camera, `height` above it.
func _show_spot(subject: Vector3, spot: Vector2, cam: Vector3, height: float,
		behind: float = SPOT_BEHIND_M) -> Vector3:
	var world := _beside(subject, cam, BEHIND_M) + Vector3.UP * height
	if _cam_fov <= 0.0:
		return world
	var inv := _cam_xform.affine_inverse()
	var v := inv * subject
	var depth := -v.z
	if depth < 0.5:
		return world
	var t := tan(deg_to_rad(_cam_fov) * 0.5)
	var sx := 0.5 + 0.5 * v.x / (depth * t * _cam_aspect)
	var sy := 0.5 - 0.5 * v.y / (depth * t)
	sx = clampf(sx + spot.x, SAFE_X.x, SAFE_X.y)
	sy = clampf(sy + spot.y, SAFE_Y.x, SAFE_Y.y)
	# The ray through that screen point, cut at `height` above the subject: the spot is in
	# frame AND at the height the beat wants, however steep or far the camera is.
	var ray := (_cam_xform.basis * Vector3((sx - 0.5) * 2.0 * t * _cam_aspect,
		(0.5 - sy) * 2.0 * t, -1.0)).normalized()
	var origin := _cam_xform.origin
	var h := subject.y + height
	if ray.y < -0.02 and origin.y > h:
		# never nearer the lens than the subject's own depth allows (`behind` sets how far
		# past it in the finish beat's close orbit), never far beyond it
		var near := maxf(1.6, depth * 0.72) if behind <= SPOT_BEHIND_M else depth + behind
		var dist := clampf((h - origin.y) / ray.y, near, depth + maxf(behind, 2.5))
		return origin + ray * dist
	return origin + ray * maxf(depth + behind, 1.6)


## How far in front of the fight camera a point is (0 with no camera).
func _depth_of(p: Vector3) -> float:
	if _cam_fov <= 0.0:
		return 99.0
	return -(_cam_xform.affine_inverse() * p).z


## Stay inside the walls and above the floor.
func _clamp_target(p: Vector3) -> Vector3:
	var lim := half_extent - 0.35
	return Vector3(clampf(p.x, -lim, lim), clampf(p.y, 0.55, 5.0), clampf(p.z, -lim, lim))


func _fly(dt: float) -> void:
	if dt <= 0.0:
		return
	var goal := _clamp_target(_target)
	var bob := Vector3(0.0, sin(_clock * 2.3) * 0.025, 0.0)
	var err := goal + bob - _pos
	var want := err * GAIN
	if want.length() > MAX_SPEED:
		want = want.normalized() * MAX_SPEED
	_vel = _vel.move_toward(want, ACCEL * dt)
	_pos += _vel * dt
	# yaw to face what it is looking at (its nose is -Z)
	var d := Vector3(_look.x - _pos.x, 0.0, _look.z - _pos.z)
	if d.length() > 0.05:
		var want_yaw := atan2(-d.x, -d.z)
		_yaw = lerp_angle(_yaw, want_yaw, clampf(YAW_RATE * dt, 0.0, 1.0))
	# lean into the motion: pitch with forward speed, roll with sideways
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var want_lean := Vector2(-_vel.dot(fwd) * LEAN_PER_MS, -_vel.dot(right) * LEAN_PER_MS)
	want_lean = want_lean.limit_length(LEAN_MAX)
	_lean = _lean.lerp(want_lean, clampf(6.0 * dt, 0.0, 1.0))
	if _wobble_t >= 0.0:
		_wobble_t += dt
		if _wobble_t > 1.6:
			_wobble_t = -1.0


func _apply_transform(dt: float) -> void:
	var basis := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _lean.x) * Basis(Vector3.BACK, _lean.y)
	if _wobble_t >= 0.0:
		var amp := 0.55 * exp(-2.6 * _wobble_t) * sin(_wobble_t * 17.0)
		basis = Basis(_wobble_axis, amp) * basis
	transform = Transform3D(basis, _pos)
	# rotors: always turning while it flies; faster when it works
	var spin := 38.0 if mode in [MODE_TOW, MODE_UNSTICK, MODE_LIFT, MODE_CARD] else 30.0
	for i in _rotors.size():
		var r := _rotors[i]
		r.rotate_object_local(Vector3.UP, (spin if i % 2 == 0 else -spin) * maxf(dt, 0.0))


func _check_knock(facts: Dictionary) -> void:
	if _wobble_gap > 0.0 or mode in [MODE_IDLE, MODE_START]:
		return
	var things: Array = []
	for b in facts.get("bots", []) as Array:
		things.append(b)
	for d in facts.get("debris", []) as Array:
		things.append(d)
	for thing_v in things:
		var thing: Dictionary = thing_v as Dictionary
		var p: Vector3 = thing.get("pos", Vector3(0, -100, 0))
		var v: Vector3 = thing.get("vel", Vector3.ZERO)
		if v.length() < WOBBLE_MIN_SPEED:
			continue
		if p.distance_to(_pos) <= WOBBLE_RADIUS_M:
			knock(v)
			return


# ---------------------------------------------------------------- the light bar

func _update_bar(facts: Dictionary) -> void:
	var pattern := _fill_pattern(0.0)
	var colour := COL_IDLE
	var energy := DIM_ENERGY
	match mode:
		MODE_IDLE:
			energy = 0.0
		MODE_START:
			var left := float(facts.get("countdown_left", 3.0))
			if left > FightTypes.COUNTDOWN_S + 0.01:
				# the intro is still flying past: standing by, not counting yet
				_pattern = _idle_pattern()
				_bar_colour = COL_START
				_bar_energy = DIM_ENERGY
				return
			var step := int(ceil(left))
			var groups := {3: [0, 1, 4, 5, 8, 9], 2: [1, 2, 7, 8], 1: [4, 5]}
			for s in groups.get(clampi(step, 1, 3), []):
				pattern[int(s)] = 1.0
			# each number lands with a flash that settles
			var frac: float = left - floor(left) if step > 0 else 0.0
			colour = COL_START
			energy = LIT_ENERGY * (0.8 + 0.6 * clampf((frac - 0.75) * 4.0, 0.0, 1.0))
			if left <= 0.0:
				pattern = _fill_pattern(1.0)
				colour = COL_GO
				energy = LIT_ENERGY * 1.3
		MODE_LIFT:
			if _mode_t < GO_FLASH_S:
				pattern = _fill_pattern(1.0 if fmod(_mode_t, 0.24) < 0.16 else 0.3)
				colour = COL_GO
				energy = LIT_ENERGY * 1.3
			else:
				pattern = _idle_pattern()
		MODE_PATROL:
			pattern = _idle_pattern()
		MODE_COUNT:
			var ko: Dictionary = facts.get("ko", {}) as Dictionary
			var n := clampi(int(ko.get("seconds_left", SEGMENTS)), 0, SEGMENTS)
			if n != _count_shown:
				if _count_shown == -1:
					_say("count", {"index": int(ko.get("index", -1))})
				_count_shown = n
				_count_flash = 0.22
			for s in n:
				pattern[s] = 1.0
			# the one that just went out flashes white
			if _count_flash > 0.0 and n < SEGMENTS:
				pattern[n] = _count_flash / 0.22
			colour = COL_COUNT_LOW if n <= 3 else COL_COUNT
			energy = LIT_ENERGY
		MODE_TOW, MODE_UNSTICK:
			# a chaser runs toward the machines while it waits; on the pull, all lit
			if _tow_line_t >= 0.0:
				pattern = _fill_pattern(1.0)
				energy = LIT_ENERGY * 1.2
			else:
				var head := int(fmod(_clock * 16.0, float(SEGMENTS)))
				pattern[head] = 1.0
				pattern[(head + SEGMENTS - 1) % SEGMENTS] = 0.45
				energy = LIT_ENERGY
			colour = COL_TOW
		MODE_SPRAY:
			pattern = _fill_pattern(0.55 + 0.45 * sin(_clock * 12.0))
			colour = COL_IDLE
			energy = LIT_ENERGY * 0.8
		MODE_STOP:
			pattern = _fill_pattern(1.0)
			colour = COL_STOP
			# on hard, then settles to a steady red
			energy = LIT_ENERGY * (1.4 if _mode_t < 0.5 and fmod(_mode_t, 0.2) < 0.12 else 1.0)
		MODE_CARD:
			pattern = _fill_pattern(1.0 if fmod(_mode_t, 0.3) < 0.2 else 0.2)
			colour = COL_CARD
			energy = LIT_ENERGY * 1.2
	if _flicker > 0.0:
		for s in SEGMENTS:
			if (s * 7 + int(_clock * 30.0)) % 3 == 0:
				pattern[s] = 0.0
	_pattern = pattern
	_bar_colour = colour
	_bar_energy = energy


func _idle_pattern() -> Array:
	var p := _fill_pattern(0.0)
	var breathe := 0.35 + 0.25 * sin(_clock * 2.0)
	p[4] = breathe
	p[5] = breathe
	return p


func _fill_pattern(v: float) -> Array:
	var p: Array = []
	p.resize(SEGMENTS)
	p.fill(v)
	return p


## Segment s sits at x < 0 for small s, which is the VIEWER's right when the Marshal faces
## the camera, so the viewer order is reversed onto the segments.
func _apply_bar() -> void:
	if _seg_mats.is_empty():
		return
	for s in SEGMENTS:
		var v := clampf(float(_pattern[SEGMENTS - 1 - s]) if _pattern.size() == SEGMENTS else 0.0, 0.0, 1.0)
		var m := _seg_mats[s]
		m.emission = _bar_colour
		m.emission_energy_multiplier = _bar_energy * v
		m.albedo_color = Color(0.05, 0.05, 0.055).lerp(_bar_colour * 0.5, v)
	if _light != null:
		var lit := 0.0
		for v in _pattern:
			lit += float(v)
		_light.light_color = _bar_colour
		_light.light_energy = 0.12 * _bar_energy * lit / float(SEGMENTS)
		_light.visible = _light.light_energy > 0.02
	if _beacon_mat != null:
		var on := mode != MODE_IDLE and fmod(_clock, 1.1) < 0.12
		_beacon_mat.emission_energy_multiplier = 6.0 if on else 0.4


# ---------------------------------------------------------------- the tow line, the spray, the card

func _update_tow(dt: float) -> void:
	if _tethers.is_empty():
		return
	if _tow_line_t < 0.0:
		for t in _tethers:
			t.visible = false
		return
	_tow_line_t += dt
	if _tow_line_t > TOW_LINE_S:
		_tow_line_t = -1.0
		for t in _tethers:
			t.visible = false
		return
	var from := _tether_origin.global_position if _tether_origin != null and _tether_origin.is_inside_tree() \
		else _pos + Vector3.DOWN * 0.1
	# a pulse runs down the line as it pulls, then it fades
	var k := _tow_line_t / TOW_LINE_S
	_tether_mat.albedo_color = FxMaterials.hdr(COL_TOW, 3.0 * (1.0 - k * 0.8))
	for i in _tethers.size():
		var t := _tethers[i]
		if i >= _tow_points.size():
			t.visible = false
			continue
		var to: Vector3 = (_tow_points[i] as Vector3) + Vector3.UP * 0.12
		_stretch(t, from, to)
		t.visible = true


func _stretch(t: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var d := to - from
	var length := d.length()
	if length < 0.01:
		t.visible = false
		return
	var y := d / length
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	# tethers live in world space (top_level), so the drone's own wobble cannot bend them
	t.global_transform = Transform3D(Basis(x, y * length, z), from + d * 0.5)


func _update_spray(dt: float) -> void:
	if _spray == null:
		return
	if mode != MODE_SPRAY:
		_spray.emitting = false
		return
	_spray_left = maxf(0.0, _spray_left - dt)
	var from := _nozzle.global_position if _nozzle != null and _nozzle.is_inside_tree() else _pos
	var aim := (_spray_at + Vector3.UP * 0.1) - from
	if aim.length() > 0.05:
		_spray.global_transform = Transform3D(Basis.looking_at(aim.normalized(), Vector3.UP), from)
	# on while it is close enough to reach
	_spray.emitting = aim.length() < 2.2 and _spray_left > 0.0
	if _spray_left <= 0.0:
		mode = MODE_PATROL
		_mode_t = 0.0
		_say("spray_done", {})


func _update_card(dt: float, facts: Dictionary) -> void:
	if _card == null:
		return
	if _card_t < 0.0 or mode != MODE_CARD:
		_card.visible = false
		return
	_card_t += dt
	var out := clampf((_card_t - 0.15) / 0.2, 0.0, 1.0)
	_card.visible = out > 0.0
	if _card_t >= 0.35 and not beats_said.has("card"):
		_say("card", {})
	var cam: Vector3 = facts.get("camera", Vector3(0.0, 8.0, 8.0))
	var slot := _card_slot.global_position if _card_slot != null and _card_slot.is_inside_tree() else _pos
	var side := global_transform.basis.x.normalized()
	var at := slot + side * (0.1 * out) + Vector3.UP * 0.1 * out
	var face := cam - at
	if face.length() > 0.05:
		_card.global_transform = Transform3D(Basis.looking_at(-face.normalized(), Vector3.UP), at)
	_card.scale = Vector3.ONE * (0.4 + 0.6 * out) * (1.0 + 0.12 * sin(_card_t * 20.0) * exp(-3.0 * _card_t))
	var flash := 1.0 if fmod(_card_t, 0.36) < 0.24 else 0.55
	_card_mat.emission_energy_multiplier = 2.6 * flash


# ---------------------------------------------------------------- geometry helpers

## A point `m` beyond `at` as seen from the camera (on the far side, so the machine stays
## in front of the Marshal), or toward it for a negative `m`.
func _beside(at: Vector3, cam: Vector3, m: float) -> Vector3:
	var away := Vector3(at.x - cam.x, 0.0, at.z - cam.z)
	away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	return Vector3(at.x, 0.0, at.z) + away * m + Vector3(0.0, at.y, 0.0)


## Watching: high on the far side of the floor from the camera, drifting, which in the fight
## camera is just out of the top of the frame. It drops in for a beat and leaves again.
func _patrol_spot(cam: Vector3, action: Vector3) -> Vector3:
	var away := Vector3(action.x - cam.x, 0.0, action.z - cam.z)
	away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
	var side := away.cross(Vector3.UP)
	var drift := side * sin(_clock * 0.37) * 1.2 + away * sin(_clock * 0.23) * 0.3
	var base := Vector3(action.x, 0.0, action.z) + away * PATROL_BEYOND_M + drift
	return Vector3(base.x, PATROL_HEIGHT, base.z)


func _action_point(bots: Array) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for b in bots:
		var d := b as Dictionary
		if d != null and bool(d.get("live", true)):
			sum += d.get("pos", Vector3.ZERO) as Vector3
			n += 1
	return sum / float(n) if n > 0 else Vector3.ZERO


func _bot_pos(bots: Array, index: int, fallback: Vector3) -> Vector3:
	if index < 0 or index >= bots.size():
		return fallback
	return (bots[index] as Dictionary).get("pos", fallback)


## The machine nearest a remembered point: the tow line follows the machine it hooked.
func _live_point(bots: Array, near: Vector3) -> Vector3:
	var best := near
	var best_d := 0.8
	for b in bots:
		var p: Vector3 = (b as Dictionary).get("pos", near)
		var d := p.distance_to(near)
		if d < best_d:
			best_d = d
			best = p
	return best


func _say(beat_name: String, info: Dictionary) -> void:
	beats_said.append(beat_name)
	beat.emit(beat_name, info)


# ---------------------------------------------------------------- build

func _build() -> void:
	if _model != null:
		return
	var packed: PackedScene = load(MODEL) as PackedScene if ResourceLoader.exists(MODEL) else null
	if packed != null:
		_model = packed.instantiate() as Node3D
	else:
		# The asset is missing: a plain lozenge keeps every behaviour testable.
		_model = Node3D.new()
		var body := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.3, 0.12, 0.36)
		body.mesh = box
		_model.add_child(body)
	_model.name = "Model"
	_model.scale = Vector3.ONE * MODEL_SCALE
	add_child(_model)
	var mats := _materials()
	for mi in _meshes(_model):
		var mesh_instance := mi as MeshInstance3D
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var slot := KitMaterials.surface_slot(mesh, s)
			if mats.has(slot):
				mesh_instance.set_surface_override_material(s, mats[slot])
	for i in 4:
		var r := _model.find_child("Rotor%d" % i, true, false) as Node3D
		if r != null:
			_rotors.append(r)
			_blur_discs.append(_blur_disc(r))
	for s in SEGMENTS:
		var seg := _model.find_child("BarSeg%d" % s, true, false) as MeshInstance3D
		if seg == null:
			continue
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.05, 0.05, 0.055)
		m.roughness = 0.25
		m.emission_enabled = true
		m.emission = COL_IDLE
		m.emission_energy_multiplier = 0.0
		seg.set_surface_override_material(0, m)
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_segs.append(seg)
		_seg_mats.append(m)
	var beacon := _model.find_child("Beacon", true, false) as MeshInstance3D
	if beacon != null:
		_beacon_mat = StandardMaterial3D.new()
		_beacon_mat.albedo_color = Color(1.0, 0.55, 0.12)
		_beacon_mat.emission_enabled = true
		_beacon_mat.emission = Color(1.0, 0.55, 0.12)
		beacon.set_surface_override_material(0, _beacon_mat)
	_nozzle = _model.find_child("Nozzle", true, false) as Node3D
	_card_slot = _model.find_child("CardSlot", true, false) as Node3D
	_tether_origin = _model.find_child("Tether", true, false) as Node3D
	if _tether_origin == null:
		_tether_origin = _nozzle
	# the bar's own glow on whatever is under it
	_light = OmniLight3D.new()
	_light.name = "BarLight"
	_light.omni_range = 1.8
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 0.12, -0.12)
	add_child(_light)
	_build_tethers()
	_build_spray()
	_build_card()


func _materials() -> Dictionary:
	# The kit's PBR sets, in OBJECT space: a world-space triplanar swims on a moving thing.
	var shell := _textured("hdpe_moulded", Color(0.82, 0.82, 0.79), 0.0, 0.5, 2.5)
	var frame := _textured("brushed_steel", Color(0.16, 0.165, 0.18), 0.75, 0.5, 3.0)
	var duct := _textured("hdpe_moulded", Color(0.09, 0.09, 0.1), 0.1, 0.55, 3.0)
	var steel := _textured("brushed_steel", Color(0.72, 0.73, 0.76), 0.9, 0.32, 4.0)
	var rubber := _textured("tyre_rubber", Color(0.45, 0.45, 0.47), 0.0, 0.85, 4.0)
	var rotor := StandardMaterial3D.new()
	rotor.albedo_color = Color(0.05, 0.05, 0.055)
	rotor.roughness = 0.5
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.02, 0.03, 0.04)
	glass.metallic = 0.3
	glass.roughness = 0.06
	var housing := StandardMaterial3D.new()
	housing.albedo_color = Color(0.02, 0.02, 0.022)
	housing.roughness = 0.3
	return {"shell": shell, "frame": frame, "duct": duct, "steel": steel, "rubber": rubber,
		"rotor": rotor, "glass": glass, "bar_housing": housing}


func _textured(set_name: String, tint: Color, metal: float, rough: float, scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.metallic = metal
	m.roughness = rough
	var base := TEX + set_name + "/" + set_name
	if ResourceLoader.exists(base + "_albedo.png"):
		m.albedo_texture = load(base + "_albedo.png") as Texture2D
		if ResourceLoader.exists(base + "_normal.png"):
			m.normal_enabled = true
			m.normal_texture = load(base + "_normal.png") as Texture2D
			m.normal_scale = 0.6
		m.uv1_triplanar = true
		m.uv1_world_triplanar = false
		m.uv1_scale = Vector3.ONE * scale
		m.uv1_triplanar_sharpness = 6.0
	return m


func _blur_disc(rotor: Node3D) -> MeshInstance3D:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.105
	mesh.bottom_radius = 0.105
	mesh.height = 0.002
	mesh.radial_segments = 20
	mesh.rings = 1
	disc.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.08, 0.08, 0.09, 0.32)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	disc.material_override = m
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.position = rotor.position
	rotor.get_parent().add_child(disc)
	return disc


func _build_tethers() -> void:
	_tether_mat = StandardMaterial3D.new()
	_tether_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tether_mat.albedo_color = FxMaterials.hdr(COL_TOW, 3.0)
	_tether_mat.disable_receive_shadows = true
	for i in 2:
		var t := MeshInstance3D.new()
		t.name = "TowLine%d" % i
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.009
		mesh.bottom_radius = 0.009
		mesh.height = 1.0
		mesh.radial_segments = 6
		mesh.rings = 1
		t.mesh = mesh
		t.material_override = _tether_mat
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.top_level = true
		t.visible = false
		add_child(t)
		_tethers.append(t)


func _build_spray() -> void:
	_spray = GPUParticles3D.new()
	_spray.name = "Extinguisher"
	_spray.top_level = true
	_spray.amount = 48
	_spray.lifetime = 0.75
	_spray.local_coords = false
	_spray.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.0, 0.0, -1.0)      # the emitter looks down -Z at the fire
	pm.spread = 11.0
	pm.initial_velocity_min = 2.6
	pm.initial_velocity_max = 3.6
	pm.gravity = Vector3(0.0, -1.2, 0.0)
	pm.damping_min = 2.0
	pm.damping_max = 3.5
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.25))
	curve.add_point(Vector2(0.5, 1.0))
	curve.add_point(Vector2(1.0, 1.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(0.95, 0.97, 1.0, 0.85))
	grad.set_color(1, Color(0.85, 0.87, 0.9, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	_spray.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.22)
	quad.material = FxMaterials.soft_smoke(FxMaterials.texture("dust_soft.png"))
	_spray.draw_pass_1 = quad
	_spray.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	add_child(_spray)


func _build_card() -> void:
	_card = Node3D.new()
	_card.name = "Card"
	_card.top_level = true
	_card.visible = false
	add_child(_card)
	var rim := MeshInstance3D.new()
	var rim_mesh := QuadMesh.new()
	rim_mesh.size = Vector2(0.16, 0.22)
	rim.mesh = rim_mesh
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.03, 0.03, 0.035)
	rim_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	rim.material_override = rim_mat
	rim.position = Vector3(0.0, 0.0, 0.002)
	_card.add_child(rim)
	var face := MeshInstance3D.new()
	var face_mesh := QuadMesh.new()
	face_mesh.size = Vector2(0.14, 0.2)
	face.mesh = face_mesh
	_card_mat = StandardMaterial3D.new()
	_card_mat.albedo_color = COL_CARD
	_card_mat.emission_enabled = true
	_card_mat.emission = COL_CARD
	_card_mat.emission_energy_multiplier = 2.6
	_card_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	face.material_override = _card_mat
	_card.add_child(face)


static func _meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out
