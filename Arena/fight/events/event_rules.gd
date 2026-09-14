extends RefCounted
class_name EventRules
## The base every side event is written against (docs/stage6-spec.md §4, brief §10:
## "Side events, a direct nod to the original's trial modes, reworked as physics
## challenges": Sumo, Gauntlet, Pinball, Football, Wall Smash).
##
## An event replaces the FIGHT'S rules, not its machinery. `fight.gd` still owns the
## state machine, the countdown, the physics tick order, the replay log, the shared RNG,
## the camera and the HUD; an event owns the clock, what counts as winning and what the
## player is told. So `physics_tick` is called from inside `fight.gd`'s FIGHTING tick,
## after the inputs are applied and the tallies are updated, and before the ordinary win
## conditions, which are skipped entirely while an event is running.
##
## Subclasses live in `Arena/fight/events/<mode>.gd` and are loaded by that path and
## nothing else, so adding an event is adding one file.
##
## Determinism (docs/stage3-rules-notes.md): an event runs inside the fixed physics tick
## like everything else. Draw from `fight._rng` if you need randomness and draw at a fixed
## cadence; never call `randf`, never read the wall clock, never decide anything in
## `_process`. `hud_lines()` is presentation and is called from `_process`, so it must read
## state the tick already wrote and must not write any.

## The Fight node. Untyped to avoid a cyclic dependency; everything an event needs from it
## is public (`bots()`, `arena()`, `fight_time()`, `rng()`, `bot_id(i)`).
var fight: Node = null
## The FightConfig this event was started from.
var config: Dictionary = {}
## Fight seconds since the bell. `fight.gd` keeps this in step; an event may read it.
var time_s: float = 0.0


## Called once, after the bots are built and placed and before the countdown. Read the
## configuration, cache what you need, place any props. Do not start a clock here: the
## countdown has not run yet and `physics_tick` is not called until the bell.
func setup(owner_fight: Node, event_config: Dictionary) -> void:
	fight = owner_fight
	config = event_config
	time_s = 0.0


## One physics tick of the event, from inside `fight.gd`'s FIGHTING tick. This is the only
## place an event may change anything.
func physics_tick(delta: float) -> void:
	time_s += delta


## True once the event has resolved, however it resolves: cleared, failed or timed out.
## `fight.gd` checks this every tick and stops the moment it turns true.
func is_over() -> bool:
	return false


## The payload for the `event_result` message, merged into
## `{mode, score, cleared, time_s, details}` by `fight.gd`. Return whichever of those you
## own; anything else you return travels in `details`.
##   score:   int, the number the player is chasing
##   cleared: bool, did they beat it
##   details: Dictionary, anything the shell wants to show
func result() -> Dictionary:
	return {"score": 0, "cleared": false, "details": {}}


## Which arena this event happens in, as a `res://` path. Empty means "whatever the
## configuration asked for", which is the right answer for an event that is happy in any
## arena. `fight.gd` builds this instead of the configured arena when it is not empty.
func arena_scene_path() -> String:
	return ""


## What the HUD should say, one plain sentence or short phrase per line, in the order they
## should be read. Called from `_process`, so read only; no em dashes.
func hud_lines() -> Array[String]:
	return []


# ---------------------------------------------------------------- helpers for subclasses

## The player's machine, or null.
func player_bot() -> Node:
	if fight == null or not fight.has_method("bots"):
		return null
	var list: Array = fight.call("bots")
	return list[0] if list.size() > 0 else null


## Every machine on the floor, player first.
func bots() -> Array:
	if fight == null or not fight.has_method("bots"):
		return []
	return fight.call("bots")


## The arena node, for props, markers and `hazard_helpers()`.
func arena() -> Node:
	return fight.call("arena") if fight != null and fight.has_method("arena") else null


## The shared, seeded RNG. Draw at a fixed cadence or the event will not replay.
func rng() -> RandomNumberGenerator:
	return fight.call("rng") if fight != null and fight.has_method("rng") else null


## A bot's flat world position, or Vector3.ZERO.
static func bot_position(bot: Node) -> Vector3:
	if bot == null:
		return Vector3.ZERO
	var chassis: Variant = bot.get("chassis")
	if chassis is Node3D and (chassis as Node3D).is_inside_tree():
		return (chassis as Node3D).global_position
	return Vector3.ZERO


## mm:ss, the HUD's format, for a countdown line.
static func clock(seconds: float) -> String:
	var whole := int(ceil(maxf(0.0, seconds)))
	return "%d:%02d" % [whole / 60, whole % 60]
