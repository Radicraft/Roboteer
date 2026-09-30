class_name FightIntro extends Node
## The fight intro (wave B, docs/wave-b-intro-notes.md). Owner idea 2026-09-27: "before games
## the camera pans around the dangers of the arena as part of an intro".
##
## Before the 3 s countdown the camera flies past each of the arena's hazards in turn, each
## named in a Broadcast lower third and caught mid-demonstration (the spikes come up, a ram
## presses, the jets burn, the pit opens, the discs spin), then drops onto the player's
## machine and hands the picture back to the fight camera for the countdown.
##
##   full   the first time in an arena: an establishing orbit, one shot per hazard kind,
##          the drop. About 5 to 6 s.
##   short  an arena already seen: one sweep with the arena and its hazards named, the drop.
##          About 2 s.
##   none   replays, the test arena, quick restarts, and any configuration without the key.
##
## PRESENTATION ONLY. The fight holds the simulation for the whole intro (fight.gd
## `_physics_process`: the intro is one more reason not to take a tick, exactly the same
## mechanism as hit-stop), so no tick runs, no hazard phase moves and no body is touched.
## Everything moving on screen is either the arena's own presentation (the venue kit, which is
## hash-inert) or a GHOST built here: copies of the hazard meshes, fresh FlameCones, and the
## hazard warning layer painted through its preview seam. The real hazard meshes are hidden
## while their ghost plays and shown again after; the grinder discs and turntable tops (paint
## only, nothing reads them) are spun and put back exactly where they were.
## tests/intro_test.gd proves full = short = none, tick for tick.
##
## Skip: a tap anywhere, a click, any pad button or any key. A skip goes straight to a quick
## drop onto the player's machine.
##
## WALK-OUTS (wave D, docs/wave-d-walkout-notes.md): when the fight hands over a walk-out plan
## (`set_walkouts`, before `begin`), the intro opens with each machine rolling out of its venue
## gate (the opponent first, then the player) under the kit's entrance (`VenueKit.play_entrance`:
## the floods drop, the gate strip chases, the pyro fires), its tale of the tape on screen; in a
## full career intro the house bot on duty then gets a shot of its own in its corner. The
## machine on screen is a GHOST (copies of its meshes on a path from the gate); the real one
## stays exactly on its fight mark, hidden until its walk-out is over. No tick is taken, so the
## fight is the same fight (tests/walkout_test.gd). Then the hazard fly-past and the drop, as
## before.

signal beat(beat_name: String, info: Dictionary)
signal finished

const MODE_FULL := "full"
const MODE_SHORT := "short"
const MODE_NONE := "none"
const MODES := [MODE_FULL, MODE_SHORT, MODE_NONE]

## Full intro timings, seconds.
const OPEN_S := 1.3
const OPEN_S_CROWDED := 1.05         # four or more hazard kinds (the Coliseum)
const HAZARD_BUDGET_S := 3.4
const HAZARD_MIN_S := 0.95
const HAZARD_MAX_S := 1.6
const DROP_S := 1.2
## Short intro.
const SWEEP_S := 1.1
const SHORT_DROP_S := 0.9
## The HUD and YOU come back this far into the drop.
const LANDING_AT := 0.5
## After a skip.
const SKIP_DROP_S := 0.45
## Each shot flies in from wherever the camera was over this long.
const TRAVEL_S := 0.42
## The hazard acts at this share of its shot, after the warning has run.
const ACT_AT := 0.45
## The ghost goes back down this long after its shot ends, while the camera flies away.
const RETRACT_S := 0.3
const SHOT_FOV := 40.0
const OPEN_FOV := 44.0

## Walk-outs, seconds per machine: a career fight's first visit, a career fight after that, and
## a quick fight (the same, shorter). The house bot's shot is a full career intro only.
const WALK_CAREER_FULL_S := 2.2
const WALK_CAREER_SHORT_S := 1.0
const WALK_QUICK_FULL_S := 1.4
const WALK_QUICK_SHORT_S := 0.8
const HOUSE_SHOT_S := 1.3
const WALK_FOV := 40.0
## Share of the shot: the roll starts, the roll ends (it rocks to a stop after).
const ROLL_START := 0.06
const ROLL_END := 0.62
## The walk-out camera: this far in front of the machine's mark, this high.
const WALK_CAM_BACK := 2.5
const WALK_CAM_UP := 0.5
## The roll: at most this long (m), this fast on average (m per second of shot), and it stops
## this far short of the wall behind (the machine's half length and a little).
const WALK_ROLL_MAX := 2.0
const WALK_ROLL_PER_S := 1.1
const WALK_CLEAR := 0.62
## How far right of the machine the camera aims, per metre of distance (the machine stands
## in the left of the picture, the card on the right).
const WALK_AIM_SHIFT := 0.3
const WALK_SPOT_ENERGY := 9.0

## Tests only: the intro's own clock runs this many times faster. The simulation is held
## either way, so the speed of the intro cannot change the fight; the test proves it at 1x
## once and runs the other arenas faster.
static var test_speed := 1.0

## Names and one line each, in the Broadcast lower third. Plain words, capitals.
const HAZARD_TITLES := {
	"spikes": ["SPIKE PATCH", "RISES EVERY SIX SECONDS"],
	"pit": ["THE PIT", "OPENS MID FIGHT"],
	"flame": ["FLAME JETS", "BURN ON A TIMER"],
	"ram": ["WALL RAMS", "PRESS FROM THE WALLS"],
	"grinder": ["FLOOR GRINDERS", "ALWAYS SPINNING"],
	"turntable": ["SPINNING DISCS", "CARRY YOU ROUND"],
	"conveyor": ["CONVEYOR", "CARRIES YOU SOUTH"],
}
## A hazard built asleep until the round's wake stage (wave B pacing).
const LATER_SUB := "WAKES LATER IN THE ROUND"
const ARENA_TITLES := {
	"yard": "THE YARD",
	"grinder": "THE GRINDER",
	"drop_zone": "THE TRAPDOOR",
	"furnace": "FURNACE",
	"crush": "THE CRUSH",
	"coliseum": "COLISEUM",
}

var mode := MODE_NONE
var arena_id := ""

var _fight: Node = null
var _world: Node = null
var _arena: Node = null
var _rig: Node = null
var _kit: Node = null
var _telegraph: Node = null
var _overlay: IntroOverlay = null
var _camera: Camera3D = null
var _ghost_root: Node3D = null

var _shots: Array = []
var _index := -1
var _t := 0.0
var _elapsed := 0.0
var _running := false
var _skipped := false
var _from_pos := Vector3.ZERO
var _from_at := Vector3.ZERO
var _from_fov := SHOT_FOV
var _cur_pos := Vector3.ZERO
var _cur_at := Vector3.ZERO
var _cur_fov := SHOT_FOV

## Ghost demonstrations in flight: {kind, t, act_at, end_at, ghosts: [..], flames: [..],
## ids: [..]}
var _demos: Array = []
## Telegraph overrides for this frame, id -> {in_s, active, contact}.
var _preview := {}
## Everything touched that is not ours, to put back: [object, property, value].
var _restore: Array = []
## Paint-only spinners (grinder discs, turntable tops): [node, rad per s].
var _spinners: Array = []
var _kit_mode_was := Node.PROCESS_MODE_INHERIT
var _hazards: Array = []

## Walk-outs (wave D): [{side, team, bot, card}] in walking order, the house bot's
## {bot, card} (or {}), the style ("career" / "quick") and the card overlay.
var _walk_plan: Array = []
var _walk_house: Dictionary = {}
var _walk_style := TapeCards.STYLE_CAREER
var _tape: TapeCardOverlay = null
## The walk-out in progress: {team, ghost, basis, from, to, dur, t, pyro}.
var _walk: Dictionary = {}
## team -> the machine's own meshes hidden while it waits to walk out.
var _walk_hidden := {}
var _walks_done := false


# ---------------------------------------------------------------- public

## Which intro a fight gets. `config.intro` from the shell when present ("full", "short",
## "none"); no key means none, because a configuration without it is a replay, a test, an
## older shell or a desktop fixture. A replay and the test arena never get one, whatever
## the key says. `--roboteer-intro=full|short` sets it for a desktop run with no key.
static func mode_for(config: Dictionary, rules_mode: String, replaying: bool) -> String:
	if replaying or rules_mode == "test":
		return MODE_NONE
	var want := str(config.get("intro", ""))
	if want == "" and OS.has_feature("pc"):
		for raw in OS.get_cmdline_user_args():
			var arg := str(raw)
			if arg.begins_with("--roboteer-intro="):
				want = arg.get_slice("=", 1)
	return want if want in MODES else MODE_NONE


## The walk-outs to open with (wave D). Call before `begin`. `plan` is in walking order,
## each {side: "opponent" | "player", team: bot index, bot: Node, card: tape card}; `house`
## is {bot, card} or {}; `style` is TapeCards.STYLE_CAREER or STYLE_QUICK.
func set_walkouts(plan: Array, house: Dictionary, style: String, tape: TapeCardOverlay) -> void:
	_walk_plan = plan.duplicate()
	_walk_house = house
	_walk_style = style
	_tape = tape


## Seconds each machine walks out for, in this mode and style.
static func walk_seconds(p_mode: String, style: String) -> float:
	if p_mode == MODE_NONE:
		return 0.0
	if style == TapeCards.STYLE_QUICK:
		return WALK_QUICK_FULL_S if p_mode == MODE_FULL else WALK_QUICK_SHORT_S
	return WALK_CAREER_FULL_S if p_mode == MODE_FULL else WALK_CAREER_SHORT_S


## Build the shots and take the picture. `fight` is the Fight node (for the pause), `world`
## the fight's SubViewport, `rig` its camera rig.
func begin(p_mode: String, fight: Node, world: Node, arena: Node, rig: Node, overlay: IntroOverlay,
		p_arena_id: String) -> void:
	mode = p_mode
	arena_id = p_arena_id
	_fight = fight
	_world = world
	_arena = arena
	_rig = rig
	_overlay = overlay
	process_mode = Node.PROCESS_MODE_ALWAYS
	if mode == MODE_NONE or _world == null or _arena == null:
		_running = false
		return
	_kit = _find_kit()
	_telegraph = _arena.get_node_or_null("HazardTelegraph")
	_hazards = _collect_hazards()
	_ghost_root = Node3D.new()
	_ghost_root.name = "IntroGhosts"
	_ghost_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_world.add_child(_ghost_root)
	_camera = Camera3D.new()
	_camera.name = "IntroCamera"
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var rig_cam := _rig_camera()
	if rig_cam != null:
		_camera.cull_mask = rig_cam.cull_mask
		_camera.attributes = rig_cam.attributes
		_camera.environment = rig_cam.environment
		_camera.keep_aspect = rig_cam.keep_aspect
		_camera.near = rig_cam.near
		_camera.far = rig_cam.far
	_ghost_root.add_child(_camera)
	_collect_spinners()
	_build_shots()
	_build_walk_shots()
	if _kit != null:
		_kit_mode_was = _kit.process_mode
		_kit.process_mode = Node.PROCESS_MODE_ALWAYS
	_running = true
	_index = -1
	_elapsed = 0.0
	var first: Dictionary = _shots[0]
	_cur_pos = first["from0"]
	_cur_at = first["at0"]
	_cur_fov = float(first["fov"])
	_start_shot(0)
	_apply_camera()
	_camera.current = true
	if _overlay != null:
		_overlay.set_skip_hint(true)
	beat.emit("intro_start", {"mode": mode, "arena": arena_id,
		"hazards": _hazards.map(func(h: Dictionary) -> String: return str(h["kind"]))})


## True while the fight must hold its tick clock for the intro.
func holding() -> bool:
	return _running


## True once the camera is most of the way down onto the player's machine: the HUD comes back
## and YOU shows over the machine.
func dropping() -> bool:
	if not _running or _index < 0 or _index >= _shots.size():
		return false
	var shot: Dictionary = _shots[_index]
	return str(shot["kind"]) == "drop" and _t >= float(shot["dur"]) * LANDING_AT


func camera() -> Camera3D:
	return _camera


func elapsed() -> float:
	return _elapsed


## Seconds the intro takes if nobody skips it.
func planned_length() -> float:
	var total := 0.0
	for s in _shots:
		total += float((s as Dictionary)["dur"])
	return total


## The shots as data, for the tests and the contact sheet.
func shots() -> Array:
	return _shots.duplicate(true)


func hazards() -> Array:
	return _hazards.duplicate(true)


## Straight to a quick drop onto the player's machine.
func skip() -> void:
	if not _running or _skipped:
		return
	_skipped = true
	beat.emit("intro_skipped", {"at_s": _elapsed})
	# Wave D: every machine back on its mark at once, the cards and the entrance off.
	_end_walk()
	_show_all_machines()
	if _tape != null and is_instance_valid(_tape):
		_tape.clear()
	if _kit != null and is_instance_valid(_kit) and _kit.has_method("skip_entrance"):
		_kit.call("skip_entrance")
	var drop := _drop_shot(SKIP_DROP_S)
	_shots = _shots.slice(0, _index + 1)
	_shots.append(drop)
	_start_shot(_shots.size() - 1)


## Put everything back and give the picture to the fight camera. Safe to call twice.
func finish() -> void:
	if not _running and _ghost_root == null:
		return
	var was_running := _running
	_running = false
	_end_walk()
	_show_all_machines()
	if _tape != null and is_instance_valid(_tape):
		_tape.clear()
	if was_running and not _walk_plan.is_empty() and _kit != null and is_instance_valid(_kit) \
			and _kit.has_method("skip_entrance"):
		_kit.call("skip_entrance")
	for d in _demos:
		_free_demo(d)
	_demos.clear()
	if _telegraph != null and is_instance_valid(_telegraph) and _telegraph.has_method("end_preview"):
		_telegraph.call("end_preview")
	for r in _restore:
		var obj: Object = r[0]
		if obj != null and is_instance_valid(obj):
			obj.set(str(r[1]), r[2])
	_restore.clear()
	_spinners.clear()
	if _kit != null and is_instance_valid(_kit):
		_kit.process_mode = _kit_mode_was
	var rig_cam := _rig_camera()
	if rig_cam != null:
		rig_cam.current = true
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.hide_card()
		_overlay.set_skip_hint(false)
	if _ghost_root != null and is_instance_valid(_ghost_root):
		_ghost_root.queue_free()
	_ghost_root = null
	_camera = null
	if was_running:
		beat.emit("intro_end", {"skipped": _skipped, "at_s": _elapsed})
		finished.emit()


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	if not _running:
		return
	var paused := _fight != null and _fight.has_method("is_paused") and bool(_fight.call("is_paused"))
	if _kit != null and is_instance_valid(_kit):
		_kit.process_mode = _kit_mode_was if paused else Node.PROCESS_MODE_ALWAYS
	if paused:
		return
	step(delta * test_speed)


## One frame of the intro. Public so the tests can step it by hand.
func step(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	_t += delta
	var shot: Dictionary = _shots[_index]
	if _t >= float(shot["dur"]):
		if _index + 1 >= _shots.size():
			_pose_shot(shot, 1.0)
			_apply_camera()
			finish()
			return
		_start_shot(_index + 1)
		shot = _shots[_index]
	var u := clampf(_t / maxf(float(shot["dur"]), 0.0001), 0.0, 1.0)
	_pose_shot(shot, u)
	_apply_camera()
	_step_demos(delta)
	_step_spinners(delta)
	_paint_telegraph(delta)
	_step_walk(delta)


func _input(event: InputEvent) -> void:
	if not _running:
		return
	var press := false
	if event is InputEventScreenTouch:
		press = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton:
		press = (event as InputEventMouseButton).pressed
	elif event is InputEventJoypadButton:
		press = (event as InputEventJoypadButton).pressed
	elif event is InputEventKey:
		press = (event as InputEventKey).pressed and not (event as InputEventKey).echo
	if not press:
		return
	if _fight != null and _fight.has_method("is_paused") and bool(_fight.call("is_paused")):
		return
	skip()
	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()


# ---------------------------------------------------------------- shots

func _start_shot(i: int) -> void:
	_index = i
	_t = 0.0
	_from_pos = _cur_pos
	_from_at = _cur_at
	_from_fov = _cur_fov
	var shot: Dictionary = _shots[i]
	var kind := str(shot["kind"])
	# Wave D: the walk-out before this one is over (its machine is back on its mark).
	_end_walk()
	var walking := kind == "walkout" or kind == "house"
	if _overlay != null:
		if kind == "drop":
			_overlay.hide_card()
			_overlay.set_skip_hint(false)
		elif walking:
			_overlay.hide_card()
		else:
			_overlay.show_card(str(shot["title"]), str(shot["sub"]), kind == "hazard")
	if walking:
		_begin_walk(shot)
	elif not _walk_plan.is_empty() and not _walks_done:
		_walks_done = true
		if _tape != null and is_instance_valid(_tape):
			_tape.clear()
		beat.emit("walkouts_done", {"skipped": _skipped})
	if kind == "hazard":
		_start_demo(shot)
	var info := {"kind": kind, "title": str(shot.get("title", "")),
		"hazard": str(shot.get("hazard", "")), "at": shot.get("focus", Vector3.ZERO)}
	match kind:
		"walkout", "house":
			info["side"] = str(shot.get("side", ""))
			info["team"] = int(shot.get("team", -1))
			info["card"] = (shot.get("card", {}) as Dictionary).duplicate(true)
			beat.emit("walkout", info)
		"open", "sweep":
			beat.emit("intro_arena", info)
		"hazard":
			beat.emit("intro_hazard", info)
		"drop":
			beat.emit("intro_drop", info)


func _pose_shot(shot: Dictionary, u: float) -> void:
	var k := u * u * (3.0 - 2.0 * u)
	var want_pos: Vector3
	var want_at: Vector3
	var want_fov: float
	if str(shot["kind"]) == "drop":
		var rig_cam := _rig_camera()
		if rig_cam != null:
			want_pos = rig_cam.global_position
			want_at = rig_cam.global_position - rig_cam.global_transform.basis.z * 6.0
			want_fov = rig_cam.fov
		else:
			want_pos = shot["from1"]
			want_at = shot["at1"]
			want_fov = FightTypes.CAM_FOV
		# The drop is one eased move from wherever the camera was onto the fight camera.
		var e := _ease_in_out(u)
		_cur_pos = _from_pos.lerp(want_pos, e) + Vector3.UP * sin(PI * e) * 0.6
		_cur_at = _from_at.lerp(want_at, e)
		_cur_fov = lerpf(_from_fov, want_fov, e)
		if u >= 1.0 and rig_cam != null:
			_cur_pos = want_pos
			_cur_at = want_at
		return
	want_pos = (shot["from0"] as Vector3).lerp(shot["from1"], k)
	want_at = (shot["at0"] as Vector3).lerp(shot["at1"], k)
	want_fov = float(shot["fov"])
	# Fly in from the previous shot, arcing up so the move clears the walls and the crowd.
	var travel := clampf(_t / maxf(float(shot.get("travel", TRAVEL_S)), 0.0001), 0.0, 1.0)
	if _index == 0 or travel >= 1.0:
		_cur_pos = want_pos
		_cur_at = want_at
		_cur_fov = want_fov
		return
	var w := _ease_in_out(travel)
	_cur_pos = _from_pos.lerp(want_pos, w) + Vector3.UP * sin(PI * w) * 0.9
	_cur_at = _from_at.lerp(want_at, w)
	_cur_fov = lerpf(_from_fov, want_fov, w)


func _apply_camera() -> void:
	if _camera == null or not is_instance_valid(_camera) or not _camera.is_inside_tree():
		return
	var up := Vector3.UP
	var dir := _cur_at - _cur_pos
	if dir.length_squared() < 1.0e-6:
		return
	if absf(dir.normalized().dot(Vector3.UP)) > 0.995:
		up = Vector3.FORWARD
	_camera.look_at_from_position(_cur_pos, _cur_at, up)
	_camera.fov = _cur_fov


func _build_shots() -> void:
	_shots = []
	var half := _half()
	var name := str(ARENA_TITLES.get(arena_id, arena_id.to_upper().replace("_", " ")))
	if mode == MODE_SHORT:
		var names: Array = []
		for h in _hazards:
			names.append(str((HAZARD_TITLES.get(str(h["kind"]), [str(h["kind"]).to_upper()]) as Array)[0]))
		var sweep := _orbit_shot(half, -95.0, -140.0, 1.05, 0.92, SWEEP_S)
		sweep["kind"] = "sweep"
		sweep["title"] = name
		sweep["sub"] = "  /  ".join(names) if not names.is_empty() else "NO HAZARDS"
		_shots.append(sweep)
		_shots.append(_drop_shot(SHORT_DROP_S))
		return
	var crowded := _hazards.size() >= 4
	var open := _open_shot(half, OPEN_S_CROWDED if crowded else OPEN_S)
	open["title"] = name
	open["sub"] = "KNOW THE FLOOR" if not _hazards.is_empty() else "NO HAZARDS"
	_shots.append(open)
	if not _hazards.is_empty():
		var each := clampf(HAZARD_BUDGET_S / float(_hazards.size()), HAZARD_MIN_S, HAZARD_MAX_S)
		for i in _hazards.size():
			_shots.append(_hazard_shot(_hazards[i], each, i))
	_shots.append(_drop_shot(DROP_S))


## The establishing move. A venue's own flyover marks (VenueKit.intro_camera_marks) win;
## otherwise a high orbit over the near corner, the arena and its crowd in one frame.
func _open_shot(half: float, dur: float) -> Dictionary:
	var marks: Array = []
	if _kit != null and _kit.has_method("intro_camera_marks"):
		marks = _kit.call("intro_camera_marks")
	if marks.size() >= 1:
		var a: Transform3D = marks[0]
		var b: Transform3D = marks[1] if marks.size() >= 2 else a
		var reach := maxf(a.origin.length(), 4.0)
		return {"kind": "open", "dur": dur, "fov": OPEN_FOV, "travel": TRAVEL_S,
			"from0": a.origin, "at0": a.origin - a.basis.z * reach,
			"from1": b.origin, "at1": b.origin - b.basis.z * reach,
			"title": "", "sub": "", "focus": Vector3.ZERO}
	var shot := _orbit_shot(half, -160.0, -118.0, 1.2, 1.0, dur)
	shot["kind"] = "open"
	return shot


## An orbit about the centre from yaw a to yaw b (degrees, the fight camera's convention:
## -135 is the near corner), `k0` to `k1` times the arena's size away.
func _orbit_shot(half: float, yaw_a: float, yaw_b: float, k0: float, k1: float, dur: float) -> Dictionary:
	var at := Vector3(0.0, 0.2, 0.0)
	var pos := func(yaw: float, k: float) -> Vector3:
		var r := deg_to_rad(yaw)
		var d := half * 2.05 * k
		return Vector3(sin(r) * d * 0.83, d * 0.62, cos(r) * d * 0.83)
	return {"kind": "open", "dur": dur, "fov": OPEN_FOV, "travel": TRAVEL_S,
		"from0": pos.call(yaw_a, k0), "at0": at, "from1": pos.call(yaw_b, k1), "at1": at,
		"title": "", "sub": "", "focus": Vector3.ZERO}


## One hazard kind. The camera sits on the arena side of the hazard, three quarters on, and
## dollies in a little while it acts.
func _hazard_shot(h: Dictionary, dur: float, index: int) -> Dictionary:
	var p: Vector3 = h["position"]
	var size: Vector2 = h.get("size", Vector2.ONE)
	var extent := maxf(size.x, size.y)
	var flat := Vector2(p.x, p.z)
	var dir: Vector2
	if flat.length() < 0.8:
		# In the middle: from the player's side, where they will first meet it.
		var spawn := _spawn(0)
		dir = Vector2(spawn.x, spawn.z)
		if dir.length() < 0.5:
			dir = Vector2(-1.0, -1.0)
		dir = dir.normalized().rotated(deg_to_rad(18.0 if index % 2 == 0 else -18.0))
	else:
		# On a flank or a wall: from the middle, looking back at it with the wall behind.
		# Fire comes at the camera: stand well off to the side of it, higher and further.
		var swing := 58.0 if str(h["kind"]) == "flame" else 34.0
		dir = (-flat).normalized().rotated(deg_to_rad(swing if index % 2 == 0 else -swing))
	var dist := clampf(1.9 + extent * 0.55, 2.2, 3.6)
	var height := clampf(1.1 + extent * 0.28, 1.25, 2.0)
	if str(h["kind"]) == "flame":
		dist = 3.9
		height = 2.3
	var d3 := Vector3(dir.x, 0.0, dir.y)
	var side := Vector3(-dir.y, 0.0, dir.x)
	var focus := Vector3(p.x, 0.12, p.z)
	var titles: Array = HAZARD_TITLES.get(str(h["kind"]), [str(h["kind"]).to_upper(), ""])
	return {"kind": "hazard", "hazard": str(h["kind"]), "dur": dur, "fov": SHOT_FOV,
		"travel": minf(TRAVEL_S, dur * 0.4),
		"from0": focus + d3 * dist * 1.12 + side * 0.35 + Vector3.UP * height * 1.08,
		"at0": focus + Vector3.UP * 0.05,
		"from1": focus + d3 * dist * 0.9 - side * 0.25 + Vector3.UP * height * 0.92,
		"at1": focus,
		"title": str(titles[0]),
		"sub": LATER_SUB if bool(h.get("dormant", false)) else (str(titles[1]) if titles.size() > 1 else ""),
		"ids": h.get("ids", []), "groups": h.get("groups", []), "focus": focus}


func _drop_shot(dur: float) -> Dictionary:
	return {"kind": "drop", "dur": dur, "fov": FightTypes.CAM_FOV, "travel": 0.0,
		"from0": Vector3.ZERO, "at0": Vector3.ZERO, "from1": Vector3(0, 8, -8),
		"at1": Vector3.ZERO, "title": "", "sub": "", "focus": _spawn(0)}


# ---------------------------------------------------------------- the arena, read only

## One entry per hazard KIND, in the order the arena lists them: {kind, position, size,
## ids, groups}. The position is the first instance's (the one the shot frames).
func _collect_hazards() -> Array:
	var out: Array = []
	var by_kind := {}
	if _arena.has_method("hazard_schedule"):
		for entry_variant in _arena.call("hazard_schedule"):
			var e: Dictionary = entry_variant
			var kind := str(e.get("kind", ""))
			if kind == "":
				continue
			var asleep := bool(e.get("dormant", false))
			if not by_kind.has(kind):
				by_kind[kind] = {"kind": kind, "position": e["position"],
					"size": e.get("size", Vector2.ONE), "ids": [], "groups": [],
					"dormant": asleep}
				out.append(by_kind[kind])
			var h: Dictionary = by_kind[kind]
			# Frame an awake instance when there is one (wave B pacing builds some hazards
			# asleep until the wake stage); a kind that is all asleep is shown as what it
			# will be, and says so.
			if bool(h["dormant"]) and not asleep:
				h["dormant"] = false
				h["position"] = e["position"]
				h["size"] = e.get("size", Vector2.ONE)
				(h["groups"] as Array).push_front(str(e.get("group", "")))
			(h["ids"] as Array).append(str(e["id"]))
			var g := str(e.get("group", ""))
			if not (h["groups"] as Array).has(g):
				(h["groups"] as Array).append(g)
	# Awake first: the dangers of the opening, then what wakes later.
	var awake := out.filter(func(h: Dictionary) -> bool: return not bool(h["dormant"]))
	var later := out.filter(func(h: Dictionary) -> bool: return bool(h["dormant"]))
	out = awake + later
	# The Furnace's belt is a hazard with no clock, so the schedule does not list it.
	var belt: Variant = _arena.get("_belt")
	if belt is Node3D and is_instance_valid(belt):
		var at := (belt as Node3D).global_position
		out.insert(awake.size(), {"kind": "conveyor", "position": Vector3(at.x, 0.0, at.z),
			"size": Vector2(2.0, 4.0), "ids": [], "groups": [], "dormant": false})
	return out


func _half() -> float:
	if _arena != null and _arena.has_method("arena_half_extent"):
		return float(_arena.call("arena_half_extent"))
	return FightTypes.ARENA_SIZE * 0.5


func _spawn(team: int) -> Vector3:
	if _arena != null and _arena.has_method("spawn_position"):
		return _arena.call("spawn_position", team)
	return Vector3(-3.2, 0.0, -3.2) if team == 0 else Vector3(3.2, 0.0, 3.2)


func _find_kit() -> Node:
	var kit := _arena.get_node_or_null("VenueKit")
	if kit == null:
		for child in _arena.get_children():
			if child.is_in_group("venue_kit"):
				return child
	return kit


func _rig_camera() -> Camera3D:
	if _rig != null and is_instance_valid(_rig) and _rig.has_method("camera"):
		return _rig.call("camera") as Camera3D
	return null


func _const(name: String, fallback: float) -> float:
	var script: Script = _arena.get_script() if _arena != null else null
	while script != null:
		var map := script.get_script_constant_map()
		if map.has(name):
			return float(map[name])
		script = script.get_base_script()
	return fallback


# ---------------------------------------------------------------- demonstrations

## A hazard's act, without its simulation: ghosts of its moving meshes, fresh fire, and the
## warning layer run through warning -> strike on the intro's own clock.
func _start_demo(shot: Dictionary) -> void:
	var kind := str(shot["hazard"])
	var dur := float(shot["dur"])
	var demo := {"kind": kind, "t": 0.0, "act_at": dur * ACT_AT, "end_at": dur,
		"ghosts": [], "flames": [], "ids": shot.get("ids", []), "amount": 0.0}
	match kind:
		"spikes":
			var spikes: Variant = _arena.get("_spikes")
			if spikes is Array:
				var lift := _const("SPIKE_RISE", 0.25) + 0.2
				for body in spikes:
					_add_ghost(demo, body as Node3D, Vector3(0.0, lift, 0.0))
		"ram":
			var rams: Variant = _arena.get("_rams")
			if rams is Array:
				var stroke := _const("RAM_STROKE", 0.9)
				for ram_variant in rams:
					var ram: Dictionary = ram_variant
					_add_ghost(demo, ram.get("body") as Node3D,
						Vector3(float(ram.get("sign", 1.0)) * stroke, 0.0, 0.0))
		"pit":
			var pit := _const("PIT", 2.4)
			var slide := pit * 0.5 + 0.05
			_add_ghost(demo, _arena.get("_cover_west") as Node3D, Vector3(-slide, -0.12, 0.0))
			_add_ghost(demo, _arena.get("_cover_east") as Node3D, Vector3(slide, -0.12, 0.0))
			var light: Variant = _arena.get("_pit_light")
			if light is Light3D and is_instance_valid(light):
				demo["light"] = light
				_remember(light, "visible")
		"flame":
			var jets: Variant = _arena.get("_kit_jets")
			var groups: Array = shot.get("groups", [])
			var want := str(groups[0]) if not groups.is_empty() else ""
			if jets is Array:
				for i in (jets as Array).size():
					var jet: Dictionary = jets[i]
					if want != "" and str(jet.get("bank", "jet_%d" % i)) != want:
						continue
					_add_flame(demo, jet.get("holder") as Node3D, _const("FLAME_REACH", 2.5))
	_demos.append(demo)


## A copy of every mesh under `body`, drawn in its place, with the body's own meshes hidden
## until the demo is over. `offset` is where the copy goes at full travel.
func _add_ghost(demo: Dictionary, body: Node3D, offset: Vector3) -> void:
	if body == null or not is_instance_valid(body) or not body.is_inside_tree():
		return
	var root := Node3D.new()
	root.name = "Ghost_" + str(body.name)
	_ghost_root.add_child(root)
	var hidden: Array = []
	for mi in _top_meshes(body):
		var copy := mi.duplicate() as MeshInstance3D
		if copy == null:
			continue
		root.add_child(copy)
		copy.global_transform = mi.global_transform
		_remember(mi, "visible")
		mi.visible = false
		hidden.append(mi)
	(demo["ghosts"] as Array).append({"root": root, "offset": offset, "hidden": hidden})


func _top_meshes(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child is MeshInstance3D:
			if (child as MeshInstance3D).visible:
				out.append(child)
		elif child is Node3D and not (child is PhysicsBody3D):
			out.append_array(_top_meshes(child))
	return out


func _add_flame(demo: Dictionary, holder: Node3D, reach: float) -> void:
	if holder == null or not is_instance_valid(holder) or not holder.is_inside_tree():
		return
	var script := load("res://fx/flame_cone.gd") as GDScript
	if script == null:
		return
	var mount := Node3D.new()
	mount.name = "GhostFlame_" + str(holder.name)
	_ghost_root.add_child(mount)
	mount.global_transform = holder.global_transform * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
	var flame := script.new() as Node3D
	flame.set("external_clock", true)
	mount.add_child(flame)
	flame.call("set_length", reach)
	flame.call("set_active", false)
	(demo["flames"] as Array).append({"mount": mount, "flame": flame})


func _step_demos(delta: float) -> void:
	_preview = {}
	var keep: Array = []
	for d in _demos:
		var demo: Dictionary = d
		demo["t"] = float(demo["t"]) + delta
		var t := float(demo["t"])
		var act := float(demo["act_at"])
		var end := float(demo["end_at"])
		# Travel: up fast (a quarter second, the spikes' own stroke), held, back down once the
		# camera has left.
		var amount := 0.0
		if t >= act:
			amount = clampf((t - act) / 0.25, 0.0, 1.0)
		if t > end:
			amount = 1.0 - clampf((t - end) / RETRACT_S, 0.0, 1.0)
		amount = amount * amount * (3.0 - 2.0 * amount)
		demo["amount"] = amount
		for g in demo["ghosts"]:
			var ghost: Dictionary = g
			var root := ghost["root"] as Node3D
			if root != null and is_instance_valid(root):
				root.position = (ghost["offset"] as Vector3) * amount
		if demo.has("light"):
			var light := demo["light"] as Light3D
			if light != null and is_instance_valid(light):
				light.visible = amount > 0.02
		var firing := t >= act and t <= end
		for f in demo["flames"]:
			var flame := (f as Dictionary)["flame"] as Node3D
			if flame != null and is_instance_valid(flame):
				if bool(flame.call("is_active")) != firing:
					flame.call("set_active", firing)
				flame.call("step", delta)
				# The warning layer already lights the zone red; a flickering light per
				# ghost jet at this range only blows the frame out.
				var fl: Variant = flame.call("light") if flame.has_method("light") else null
				if fl is Light3D:
					(fl as Light3D).visible = false
		# The warning layer: counting down to the act, then striking, then letting go.
		for id in demo["ids"]:
			if t <= end:
				_preview[str(id)] = {"in_s": maxf(act - t, 0.0) * (ArenaBase.WARN_LEAD_S / maxf(act, 0.0001)),
					"active": t >= act, "contact": t >= act}
		if t > end + RETRACT_S + 0.5:
			_free_demo(demo)
		else:
			keep.append(demo)
	_demos = keep


func _free_demo(demo: Dictionary) -> void:
	for g in demo.get("ghosts", []):
		var ghost: Dictionary = g
		for mi in ghost["hidden"]:
			if mi != null and is_instance_valid(mi):
				_put_back(mi, "visible")
		var root := ghost["root"] as Node3D
		if root != null and is_instance_valid(root):
			root.queue_free()
	for f in demo.get("flames", []):
		var mount := (f as Dictionary)["mount"] as Node3D
		if mount != null and is_instance_valid(mount):
			mount.queue_free()
	if demo.has("light"):
		_put_back(demo["light"], "visible")
	demo["ghosts"] = []
	demo["flames"] = []


func _paint_telegraph(delta: float) -> void:
	if _telegraph != null and is_instance_valid(_telegraph) and _telegraph.has_method("preview_frame"):
		_telegraph.call("preview_frame", _preview, delta)


## The paint-only spinners: grinder discs and turntable tops. The simulation never reads
## either (the cut is an Area3D, the table's carry is the body's constant velocity).
func _collect_spinners() -> void:
	var grinders: Variant = _arena.get("_kit_grinders")
	if grinders is Array:
		var rate := _const("GRINDER_SPIN", 34.0)
		for g in grinders:
			var disc := (g as Dictionary).get("disc") as Node3D
			if disc != null and is_instance_valid(disc):
				_remember(disc, "transform")
				_spinners.append([disc, rate])
	var tables: Variant = _arena.get("_kit_tables")
	if tables is Array:
		for t in tables:
			var table: Dictionary = t
			var spin := table.get("spin") as Node3D
			var body := table.get("body") as StaticBody3D
			if spin != null and is_instance_valid(spin) and body != null:
				_remember(spin, "transform")
				_spinners.append([spin, body.constant_angular_velocity.y])


func _step_spinners(delta: float) -> void:
	for s in _spinners:
		var node := s[0] as Node3D
		if node != null and is_instance_valid(node):
			node.rotate_y(float(s[1]) * delta)


## Remember a property the first time it is touched, so finish() puts back what was there.
func _remember(obj: Object, prop: String) -> void:
	for r in _restore:
		if r[0] == obj and str(r[1]) == prop:
			return
	_restore.append([obj, prop, obj.get(prop)])


func _put_back(obj: Object, prop: String) -> void:
	for i in _restore.size():
		var r: Array = _restore[i]
		if r[0] == obj and str(r[1]) == prop:
			if obj != null and is_instance_valid(obj):
				obj.set(prop, r[2])
			_restore.remove_at(i)
			return


static func _ease_in_out(u: float) -> float:
	var x := clampf(u, 0.0, 1.0)
	return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0


# ---------------------------------------------------------------- walk-outs (wave D)

## The walk-out shots, put in front of the fly-past: the opponent, the player, then (a full
## career intro only) the house bot in its corner. The fly-past's first shot then cuts in
## rather than flying across the arena from a gate.
func _build_walk_shots() -> void:
	if _walk_plan.is_empty():
		return
	# The kit builds itself one frame after the arena (call_deferred in its _ready), and the
	# fight starts the intro in the same frame the arena was made: build it now so its gates
	# are there to walk out of. `_build` is idempotent and presentation only (venue_kit_test).
	if _kit != null and is_instance_valid(_kit) and _kit.get("_built") == false and _kit.has_method("_build"):
		_kit.call("_build")
	var dur := walk_seconds(mode, _walk_style)
	var walks: Array = []
	for entry_variant in _walk_plan:
		var entry: Dictionary = entry_variant
		var bot := entry.get("bot") as Node
		var chassis := _chassis_of(bot)
		if chassis == null:
			continue
		var team := int(entry.get("team", 0))
		var shot := _walk_shot(team, chassis.global_transform, dur)
		shot["side"] = str(entry.get("side", ""))
		shot["card"] = entry.get("card", {})
		shot["bot"] = bot
		shot["title"] = str((entry.get("card", {}) as Dictionary).get("name", ""))
		walks.append(shot)
		if bool(shot["gate"]):
			_hide_machine(team, bot)
	if not _walk_house.is_empty() and mode == MODE_FULL and _walk_style == TapeCards.STYLE_CAREER:
		var house_chassis := _chassis_of(_walk_house.get("bot") as Node)
		if house_chassis != null:
			var h := _house_shot(house_chassis.global_position)
			h["card"] = _walk_house.get("card", {})
			h["title"] = str((h["card"] as Dictionary).get("name", ""))
			h["side"] = "house"
			walks.append(h)
	if walks.is_empty():
		return
	if not _shots.is_empty():
		(_shots[0] as Dictionary)["travel"] = 0.0
	_shots = walks + _shots


func _chassis_of(bot: Node) -> Node3D:
	if bot == null or not is_instance_valid(bot) or not bot.is_inside_tree():
		return null
	var c: Variant = bot.get("chassis")
	if c is Node3D and is_instance_valid(c):
		return c as Node3D
	return bot as Node3D if bot is Node3D else null


## Where a team's gate mouth is, from the venue kit (read only). null when the venue has none.
func _gate_mark(team: int) -> Variant:
	if _kit == null or not is_instance_valid(_kit):
		return null
	var marks: Variant = _kit.get("_gate_marks")
	if marks is Array and (marks as Array).size() > team:
		var m: Vector3 = (marks as Array)[team]
		if m.length() > 0.5:
			return m
	return null


## A machine's walk-out. It comes out of its corner, under its gate (the lit portal and its
## pyro behind it, over the wall), and rolls onto its fight mark, ending exactly where the real
## machine stands, so the cut back to the real one is invisible. The camera is on the arena
## side, low, pushing in, aimed to the machine's right so it stands in the left of the
## picture, clear of its card. With no venue there is no gate to frame; it is the same shot.
func _walk_shot(team: int, spawn: Transform3D, dur: float) -> Dictionary:
	var mark: Variant = _gate_mark(team)
	var here := Vector3(spawn.origin.x, 0.0, spawn.origin.z)
	var back: Vector3
	if mark != null:
		back = Vector3((mark as Vector3).x, 0.0, (mark as Vector3).z) - here
	else:
		back = here
	back = back.normalized() if back.length() > 0.1 else Vector3(-1, 0, -1).normalized()
	# As far back toward the corner as the walls allow, less the machine's own length.
	var reach := _room_behind(here, back) - WALK_CLEAR
	var length := clampf(minf(reach, WALK_ROLL_PER_S * dur), 0.4, WALK_ROLL_MAX)
	var fwd := -back
	var side := fwd.cross(Vector3.UP).normalized()
	var from := spawn.origin + back * length
	var shot := {"kind": "walkout", "team": team, "dur": dur, "fov": WALK_FOV, "travel": 0.0,
		"sub": "", "gate": true, "has_venue_gate": mark != null, "basis": spawn.basis,
		"from": from, "to": spawn.origin}
	var mid := here + back * length * 0.5
	shot["from0"] = here + fwd * WALK_CAM_BACK * 1.1 + side * 0.9 + Vector3.UP * WALK_CAM_UP * 1.15
	shot["at0"] = mid + Vector3.UP * 0.7 - side * WALK_CAM_BACK * 1.1 * WALK_AIM_SHIFT
	shot["from1"] = here + fwd * WALK_CAM_BACK * 0.85 + side * 0.6 + Vector3.UP * WALK_CAM_UP * 0.85
	shot["at1"] = here + Vector3.UP * 0.55 - side * WALK_CAM_BACK * 0.85 * WALK_AIM_SHIFT
	shot["focus"] = here
	return shot


## Metres from `p` along `dir` (flat, unit) to the arena's inner wall.
func _room_behind(p: Vector3, dir: Vector3) -> float:
	var half := _half()
	var best := 99.0
	for axis in [0, 2]:
		var d := dir[axis]
		if absf(d) < 0.001:
			continue
		var t := (signf(d) * half - p[axis]) / d
		if t > 0.0:
			best = minf(best, t)
	return best if best < 99.0 else 2.0


## The house bot on its mark in its corner, from the arena side.
func _house_shot(at: Vector3) -> Dictionary:
	var ground := Vector3(at.x, 0.0, at.z)
	var fwd := Vector3(-at.x, 0.0, -at.z)
	fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
	var side := fwd.cross(Vector3.UP).normalized()
	return {"kind": "house", "team": -1, "dur": HOUSE_SHOT_S, "fov": WALK_FOV, "travel": 0.0,
		"sub": "", "gate": false,
		"from0": ground + fwd * 2.9 - side * 1.0 + Vector3.UP * 1.35,
		"at0": ground + Vector3.UP * 0.3 - side * 2.9 * WALK_AIM_SHIFT,
		"from1": ground + fwd * 2.35 - side * 0.7 + Vector3.UP * 0.95,
		"at1": ground + Vector3.UP * 0.22 - side * 2.35 * WALK_AIM_SHIFT,
		"focus": ground}


func _begin_walk(shot: Dictionary) -> void:
	if _tape != null and is_instance_valid(_tape):
		_tape.show_card(shot.get("card", {}) as Dictionary)
	if str(shot["kind"]) == "house":
		if _kit != null and is_instance_valid(_kit) and _kit.has_method("excite"):
			_kit.call("excite", 0.7)
		return
	var team := int(shot["team"])
	if not bool(shot.get("gate", false)):
		return
	_walk = {"team": team, "t": 0.0, "dur": float(shot["dur"]), "from": shot["from"], "to": shot["to"],
		"basis": shot["basis"], "pyro": false, "ghost": _machine_ghost(shot.get("bot") as Node, team),
		"spot": _follow_spot(shot)}
	if bool(shot.get("has_venue_gate", false)) and _kit != null and is_instance_valid(_kit):
		if _kit.has_method("play_entrance"):
			_kit.call("play_entrance", team)
	_place_walk(0.0)


## One frame of the walk-out in progress: the ghost rolls, stops and rocks on its suspension;
## a short walk-out fires the gate's pyro itself (the kit's own fires at 1.0 s).
func _step_walk(delta: float) -> void:
	if _walk.is_empty():
		return
	_walk["t"] = float(_walk["t"]) + delta
	var dur := float(_walk["dur"])
	if not bool(_walk["pyro"]) and dur < 1.2 and float(_walk["t"]) >= dur * 0.22:
		_walk["pyro"] = true
		if _kit != null and is_instance_valid(_kit):
			if _kit.has_method("fire_pyro"):
				_kit.call("fire_pyro", "gate%d" % int(_walk["team"]))
			if _kit.has_method("excite"):
				_kit.call("excite", 1.0)
	_place_walk(float(_walk["t"]) / maxf(dur, 0.0001))


func _place_walk(u: float) -> void:
	var ghost := _walk.get("ghost") as Node3D
	if ghost == null or not is_instance_valid(ghost):
		return
	var roll := clampf((u - ROLL_START) / (ROLL_END - ROLL_START), 0.0, 1.0)
	var e := 1.0 - pow(1.0 - roll, 3.0)
	var from: Vector3 = _walk["from"]
	var to: Vector3 = _walk["to"]
	var p := from.lerp(to, e)
	var basis: Basis = _walk["basis"]
	var dir := (to - from).normalized()
	var axis := dir.cross(Vector3.UP).normalized()
	# Nose up a touch while it pulls away, then a rock forward as it brakes and settles.
	var pitch := 0.0
	var dur := float(_walk["dur"])
	if roll > 0.0 and roll < 1.0:
		pitch = -0.035 * sin(PI * minf(roll * 3.0, 1.0))
	elif roll >= 1.0:
		var after := (u - ROLL_END) * dur
		pitch = 0.05 * sin(after * 16.0) * exp(-after * 6.0)
	ghost.global_transform = Transform3D(Basis(axis, pitch) * basis, p)
	var spot := _walk.get("spot") as SpotLight3D
	if spot != null and is_instance_valid(spot):
		spot.look_at(p + Vector3.UP * 0.1, Vector3.UP)


func _end_walk() -> void:
	if _walk.is_empty():
		return
	var ghost := _walk.get("ghost") as Node3D
	if ghost != null and is_instance_valid(ghost):
		ghost.queue_free()
	var spot := _walk.get("spot") as Node3D
	if spot != null and is_instance_valid(spot):
		spot.queue_free()
	_show_machine(int(_walk["team"]))
	if _kit != null and is_instance_valid(_kit) and _kit.has_method("skip_entrance"):
		_kit.call("skip_entrance")
	_walk = {}


## A copy of every mesh the machine is drawn with, arranged about its chassis, to drive
## along the walk-out path. Built from the machine as it stands, so it wears the same paint.
func _machine_ghost(bot: Node, team: int) -> Node3D:
	var chassis := _chassis_of(bot)
	if chassis == null or _ghost_root == null:
		return null
	var root := Node3D.new()
	root.name = "WalkGhost_%d" % team
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_ghost_root.add_child(root)
	var inv := chassis.global_transform.affine_inverse()
	var meshes: Array = _walk_hidden.get(team, [])
	if meshes.is_empty():
		meshes = _machine_meshes(bot)
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi == null or not is_instance_valid(mi) or mi.mesh == null:
			continue
		var copy := MeshInstance3D.new()
		copy.mesh = mi.mesh
		copy.material_override = mi.material_override
		copy.material_overlay = mi.material_overlay
		for s in mi.get_surface_override_material_count():
			copy.set_surface_override_material(s, mi.get_surface_override_material(s))
		copy.cast_shadow = mi.cast_shadow
		copy.layers = mi.layers
		copy.transparency = mi.transparency
		copy.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		root.add_child(copy)
		copy.transform = inv * mi.global_transform
	return root


## Every mesh the machine is drawn with right now.
func _machine_meshes(bot: Node) -> Array:
	var out: Array = []
	if bot == null or not is_instance_valid(bot):
		return out
	for n in bot.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.is_visible_in_tree() and mi.mesh != null:
			out.append(mi)
	return out


## The real machine out of sight until its walk-out is over. It never moves.
func _hide_machine(team: int, bot: Node) -> void:
	var meshes := _machine_meshes(bot)
	_walk_hidden[team] = meshes
	for mi in meshes:
		_remember(mi, "visible")
		(mi as MeshInstance3D).visible = false


func _show_machine(team: int) -> void:
	if not _walk_hidden.has(team):
		return
	for mi in _walk_hidden[team]:
		if mi != null and is_instance_valid(mi):
			_put_back(mi, "visible")
	_walk_hidden.erase(team)


func _show_all_machines() -> void:
	for team in _walk_hidden.keys():
		_show_machine(int(team))


## The walk-out's follow spot: the floods are down for the entrance, so a spot from above the
## camera picks the machine out of the gate's dark. Presentation only, like the ghost.
func _follow_spot(shot: Dictionary) -> SpotLight3D:
	if _ghost_root == null:
		return null
	var spot := SpotLight3D.new()
	spot.name = "WalkSpot"
	spot.light_color = Color(1.0, 0.95, 0.86)
	spot.light_energy = WALK_SPOT_ENERGY
	spot.spot_range = 14.0
	spot.spot_angle = 17.0
	spot.spot_attenuation = 0.6
	spot.shadow_enabled = false
	var cam: Vector3 = shot["from0"]
	var to: Vector3 = shot["to"]
	_ghost_root.add_child(spot)
	spot.global_position = cam.lerp(to, 0.15) + Vector3.UP * 2.6
	return spot
