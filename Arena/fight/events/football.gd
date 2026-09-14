extends "res://fight/events/event_rules.gd"
## FOOTBALL (side event 4, docs/stage6-spec.md §1, brief §10).
##
## Ninety seconds on a 12 x 8 m pitch with a three kilo ball and one AI machine that wants
## it as much as you do. Most goals wins; a draw is not a clear.
##
## The opponent is driven by `FootballDriver` below, which is `OpponentAI` with its target
## swapped: it goes for the BALL rather than for you, and it lines up behind the ball
## before it commits, so it pushes toward its goal instead of shoving the ball into its
## own. Everything else about it (the inversion recovery, the fixed rng cadence, the
## heading convention) is inherited, which is the point of putting it on top of OpponentAI
## rather than writing a second driver from scratch.
##
## HOW THE OPPONENT IS STEERED, and why it is not `apply_input`.
## `fight.gd` has already called `apply_input` on both machines by the time an event's
## `physics_tick` runs, and `Bot.apply_input` does two things: it sets the drive's motor
## targets, which is idempotent, and it advances the WEAPON'S clock by `dt`, which is not.
## Calling it a second time in the same tick would run the opponent's weapon at double
## speed for the whole event. So this drives `bot.drive_module` directly and leaves the
## weapon under the fight's own driver. If a later stage wants an event to own the whole
## input record, the clean change is in `fight.gd`: ask the rules first and skip the
## ordinary driver for any index it claims.
##
## Determinism: the driver draws from the shared rng on exactly the cadence `OpponentAI`
## draws on, once every `JITTER_TICKS` ticks before any branching, so a replay consumes
## the same numbers in the same order. The goal test is polled off the arena inside the
## physics tick, never off a signal.

const ARENA_SCENE := "res://arena/events/football.tscn"

var _duration := FightTypes.FIGHT_DURATION_S
var _goals := [0, 0]
var _driver: FootballDriver = null
var _tick := 0
var _connected := false
var _armed := false
## Ticks of dead ball after a goal, while the ball is put back on the spot.
const RESTART_TICKS := 36
var _restart_tick := 0


func setup(owner_fight: Node, event_config: Dictionary) -> void:
	super(owner_fight, event_config)
	var rules: Dictionary = event_config.get("rules", {}) as Dictionary
	_duration = float(rules.get("duration_s", FightTypes.FIGHT_DURATION_S))
	_goals = [0, 0]
	_tick = 0
	_restart_tick = 0
	_driver = null
	_armed = false


func arena_scene_path() -> String:
	return ARENA_SCENE


func physics_tick(delta: float) -> void:
	super(delta)
	if not _armed:
		_arm()
	_tick += 1
	if not _connected:
		_connect_pitch()
	_drive_opponent(delta)


func is_over() -> bool:
	return time_s >= _duration


func result() -> Dictionary:
	var for_us := int(_goals[0])
	var against := int(_goals[1])
	return {
		"score": for_us,
		"cleared": for_us > against,
		"goals_for": for_us,
		"goals_against": against,
		"details": {
			"goals_for": for_us,
			"goals_against": against,
			"outcome": "win" if for_us > against else ("draw" if for_us == against else "loss"),
		},
	}


func hud_lines() -> Array[String]:
	var lines: Array[String] = [
		"GOALS %d - %d" % [int(_goals[0]), int(_goals[1])],
		clock(_duration - time_s),
	]
	if _tick < _restart_tick:
		lines.append("BALL ON THE SPOT")
	return lines


# --------------------------------------------------------------------------------------

## Everything that needs the ARENA or the MACHINES happens here, on the first tick, not in
## `setup`. `fight.gd` builds the event before it builds the world (`_load_event` runs from
## `start_fight` ahead of `_build_world` and `_spawn_bots`), so at `setup` time `arena()` is
## still the last fight's arena and `bots()` is still the last fight's machines. Reading
## either one there is reading the wrong world. `setup` is for the configuration; this is
## for the fight.
func _arm() -> void:
	_armed = true
	var pitch := arena()
	var target := Vector3(-5.7, 0.0, 0.0)
	if pitch != null and pitch.has_method("attack_goal"):
		target = pitch.call("attack_goal", 1) as Vector3
	# The driver is built here and not in `setup` for one more reason on top of the arena:
	# it draws from the shared rng, and a driver built against the previous fight's rng
	# would put this event's first draw in the wrong place in the sequence.
	_driver = FootballDriver.new(rng(), target)
	if pitch != null and pitch.has_method("reset_ball"):
		pitch.call("reset_ball")
	_connect_pitch()


func _connect_pitch() -> void:
	var pitch := arena()
	if pitch == null or not pitch.has_signal("goal_scored"):
		return
	if not pitch.is_connected("goal_scored", _on_goal):
		pitch.connect("goal_scored", _on_goal)
	_connected = true


func _on_goal(team: int, _at: Vector3) -> void:
	if team < 0 or team > 1:
		return
	_goals[team] = int(_goals[team]) + 1
	_restart_tick = _tick + RESTART_TICKS
	var pitch := arena()
	if pitch != null and pitch.has_method("reset_ball"):
		pitch.call("reset_ball")


func _drive_opponent(delta: float) -> void:
	var list := bots()
	if list.size() < 2 or list[1] == null or _driver == null:
		return
	var opponent: Node = list[1]
	var pitch := arena()
	var ball := pitch.call("ball_position") as Vector3 if pitch != null \
		and pitch.has_method("ball_position") else Vector3.ZERO
	var record := _driver.think(opponent, list[0], {"tick": _tick, "ball": ball})
	var drive: Variant = opponent.get("drive_module")
	if drive == null:
		return
	if opponent.has_method("is_disrupted") and bool(opponent.call("is_disrupted", "drive")):
		drive.call("stop")
		return
	drive.call("drive", record.get("heading", Vector2.ZERO) as Vector2,
		bool(record.get("secondary", false)), delta, float(record.get("turn", 0.0)))


# --------------------------------------------------------------------------------------
# The driver
# --------------------------------------------------------------------------------------
## `OpponentAI` with a ball for a target. It keeps the base's inversion recovery and the
## base's rng cadence and replaces only the question "where do I want to be".
class FootballDriver extends OpponentAI:
	## How far behind the ball, on the line from the goal through the ball, the approach
	## point sits. A little under a machine length, so arriving at it puts the nose on the
	## ball rather than on top of it.
	const APPROACH_M := 0.80
	## Inside this the driver stops lining up and just shoves.
	const COMMIT_M := 1.10
	## How square to the goal the machine has to be before it stops lining up. cos(55 deg).
	const COMMIT_DOT := 0.57

	var goal: Vector3 = Vector3.ZERO

	func _init(random: RandomNumberGenerator, attack_goal: Vector3) -> void:
		super(random, MODE_NORMAL)
		goal = Vector3(attack_goal.x, 0.0, attack_goal.z)

	func think(me: Object, _foe: Object, ctx: Dictionary) -> Dictionary:
		var tick := int(ctx.get("tick", 0))
		# The same draw, on the same cadence, before any branching, as the base class.
		# A driver that draws a different NUMBER of times is a driver that desyncs a
		# replay, whatever it does with the values.
		if tick % JITTER_TICKS == 0:
			_jitter = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * JITTER_MAX
		if me == null:
			return FightTypes.empty_input()

		var my_position := _position(me)
		var forward := _flat(_forward(me))
		if _is_inverted(me):
			return _recover(me, forward, tick)

		var ball: Vector3 = ctx.get("ball", Vector3.ZERO)
		ball = Vector3(ball.x, 0.0, ball.z)
		var ball_to_goal := _flat(goal - ball)
		if ball_to_goal.length() < 0.0001:
			ball_to_goal = Vector3.RIGHT
		ball_to_goal = ball_to_goal.normalized()

		var to_ball := _flat(ball - my_position)
		var range_m := to_ball.length()
		var to_ball_dir := to_ball.normalized() if range_m > 0.0001 else forward

		# Lined up when the machine is on the far side of the ball from the goal, which is
		# the only way a push sends the ball the right way. Off the line, drive to the
		# approach point instead: it is behind the ball, so the path there curls round it
		# rather than through it.
		var lined_up := to_ball_dir.dot(ball_to_goal) >= COMMIT_DOT
		if lined_up or range_m <= COMMIT_M:
			# Aim THROUGH the ball at the goal, not at the ball: a nose that stops on the
			# ball stops the ball.
			var through := _flat(ball + ball_to_goal * 0.6 - my_position)
			var want := through.normalized() if through.length() > 0.0001 else to_ball_dir
			return _input(_jittered(heading_from_world_dir(want)), range_m <= 0.9, false)

		var approach := ball - ball_to_goal * APPROACH_M
		var to_approach := _flat(approach - my_position)
		var head := to_approach.normalized() if to_approach.length() > 0.0001 else to_ball_dir
		return _input(_jittered(heading_from_world_dir(head)), false, false)
