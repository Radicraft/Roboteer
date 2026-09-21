class_name FightHaptics extends RefCounted
## Rate limited haptic sender. Presentation only (docs/stage3-spec.md §3, §11).
##
## The phone's haptic engine is only reachable from Swift, so every tick is a
## bridge message. The bridge contract caps them at FightTypes.HAPTIC_MAX_PER_S,
## so this holds a sliding one second window and DROPS the overflow. It never
## queues: a late tick is worse than no tick, and a bolt stream can easily ask
## for more ticks in a second than the engine can play.

var enabled: bool = true

## Send timestamps inside the current one second window, in presentation seconds.
var _window: PackedFloat64Array = PackedFloat64Array()
var _dropped: int = 0
var _sent: int = 0
var _bridge: Node = null


## The Bridge autoload is NOT available as a global identifier here: a headless run
## started with --script compiles this file before autoloads are registered, and the
## compile fails with "Identifier not found: Bridge". Look it up in the tree instead.
func _bridge_node() -> Node:
	if _bridge != null and is_instance_valid(_bridge):
		return _bridge
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		_bridge = (loop as SceneTree).root.get_node_or_null("Bridge")
	return _bridge


## now is the fight's presentation clock in seconds (FightFx owns it, so the
## headless test can step it at a fixed delta). Returns true if it went out.
func send(kind: String, now: float) -> bool:
	if not enabled:
		return false
	_prune(now)
	if _window.size() >= FightTypes.HAPTIC_MAX_PER_S:
		_dropped += 1
		return false
	var bridge := _bridge_node()
	if bridge == null:
		return false
	_window.append(now)
	_sent += 1
	bridge.send(FightTypes.MSG_HAPTIC, {"kind": kind})
	return true


func sent_count() -> int:
	return _sent


func dropped_count() -> int:
	return _dropped


func reset() -> void:
	_window = PackedFloat64Array()
	_dropped = 0
	_sent = 0


func _prune(now: float) -> void:
	var cutoff := now - 1.0
	var keep := 0
	while keep < _window.size() and _window[keep] <= cutoff:
		keep += 1
	if keep > 0:
		_window = _window.slice(keep)
