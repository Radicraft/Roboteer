extends SceneTree
## Headless bridge contract test.
##   Godot --headless --path Arena --script tests/bridge_test.gd
## Loads main.tscn, injects the spec's FightConfig through the Bridge test seam
## and asserts the FightResult matches docs/bridge-spec.md. Exit code 0 = PASS.

const CONFIG_JSON := """
{
  "schema": 1,
  "seed": 123456789,
  "arena": "yard",
  "rules": { "duration_s": 90, "ko_count_s": 10 },
  "bots": [
    {
      "id": "player-1", "name": "Tinribs", "controller": "player",
      "chassis": "wedge", "drive": "4wd", "weapon": "flipper",
      "utility": ["srimech", "spare_battery"],
      "armour": {
        "front": { "material": "steel", "thickness": 3 },
        "sides": { "material": "hdpe",  "thickness": 2 },
        "rear":  { "material": "polycarbonate", "thickness": 1 },
        "top":   { "material": "titanium", "thickness": 2 }
      },
      "damage": { "wheels": [1.0, 1.0, 1.0, 1.0], "weapon": 1.0, "armour": {"front":1.0,"sides":1.0,"rear":1.0,"top":1.0}, "drive": 1.0, "core": 1.0 }
    },
    { "id": "ai-1", "name": "Scrapheap", "controller": "ai", "chassis": "box", "drive": "2wd", "weapon": "saw",
      "utility": ["srimech"], "armour": { "front": {"material":"steel","thickness":2}, "sides": {"material":"steel","thickness":2}, "rear": {"material":"steel","thickness":2}, "top": {"material":"steel","thickness":2} },
      "damage": { "wheels": [1.0, 1.0], "weapon": 1.0, "armour": {"front":1.0,"sides":1.0,"rear":1.0,"top":1.0}, "drive": 1.0, "core": 1.0 } }
  ]
}
"""

const RESULT_TOP_LEVEL_KEYS := [
	"schema", "outcome", "duration_s", "judges", "damage", "scrap", "replay", "diagnostics",
]

var _sent: Array = []
var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var bridge: Node = root.get_node_or_null("Bridge")
	if bridge == null:
		_fail("Bridge autoload is present")
		_finish()
		return
	_ok("Bridge autoload is present")
	bridge.message_sent.connect(_on_message_sent)

	var scene: PackedScene = load("res://main.tscn")
	if scene == null:
		_fail("main.tscn loads")
		_finish()
		return
	_ok("main.tscn loads")
	root.add_child(scene.instantiate())

	# main.gd waits longer for a host when it has a window (visible runs, owner rule 2026-09-27).
	await _frames(6 if DisplayServer.get_name() == "headless" else 186)

	_check(_type_sent("arena_ready"), "arena_ready was sent without a host attached")
	var ready_payload: Dictionary = _payload("arena_ready")
	_check(int(ready_payload.get("schema", 0)) == 1, "arena_ready schema is 1")
	_check(str(ready_payload.get("godot_version", "")) != "", "arena_ready carries godot_version")

	var parsed: Variant = JSON.parse_string(CONFIG_JSON)
	_check(parsed is Dictionary, "spec FightConfig literal is valid JSON")
	bridge.inject_from_host({"type": "fight_config", "json": CONFIG_JSON})

	await _frames(2)

	_check(_type_sent("arena_log"), "arena_log was sent")
	_check(str(_payload("arena_log").get("text", "")) == "config received", "arena_log says config received")
	_check(_type_sent("fight_result"), "fight_result was sent")

	var result: Dictionary = _payload("fight_result")
	for key in RESULT_TOP_LEVEL_KEYS:
		_check(result.has(key), "fight_result has top level key: " + str(key))

	_check(int(result.get("schema", 0)) == 1, "fight_result schema is 1")

	var outcome: Dictionary = result.get("outcome", {}) as Dictionary
	_check(str(outcome.get("type", "")) == "judges", "outcome.type is judges")
	_check(str(outcome.get("winner", "")) == "player-1", "outcome.winner is player-1")
	_check(str(outcome.get("loser", "")) == "ai-1", "outcome.loser is ai-1")
	_check(is_equal_approx(float(outcome.get("at_s", -1.0)), 90.0), "outcome.at_s is 90")
	_check(is_equal_approx(float(result.get("duration_s", -1.0)), 90.0), "duration_s is 90")

	var judges: Dictionary = result.get("judges", {}) as Dictionary
	_check(judges.has("player-1") and judges.has("ai-1"), "judges cover both bots")
	_check(int((judges.get("player-1", {}) as Dictionary).get("damage", -1)) == 0, "judges scores are zero")

	var config: Dictionary = parsed as Dictionary
	var bots: Array = config.get("bots", []) as Array
	var damage: Dictionary = result.get("damage", {}) as Dictionary
	for bot_variant in bots:
		var bot: Dictionary = bot_variant as Dictionary
		var id := str(bot.get("id", ""))
		_check(damage.get(id, {}) == bot.get("damage", {}), "damage for " + id + " matches the config")

	var scrap: Dictionary = result.get("scrap", {}) as Dictionary
	_check(int(scrap.get("player-1", -1)) == 0 and int(scrap.get("ai-1", -1)) == 0, "scrap is zero for both bots")

	var replay: Dictionary = result.get("replay", {}) as Dictionary
	_check(int(replay.get("seed", 0)) == 123456789, "replay.seed is the config seed")
	_check(int(replay.get("tick_hz", 0)) == 60, "replay.tick_hz is 60")
	_check((replay.get("inputs", null) as Array).is_empty(), "replay.inputs is empty")

	var diag: Dictionary = result.get("diagnostics", {}) as Dictionary
	for key in ["ticks_msec_at_config", "ticks_msec_at_result", "physics_ticks", "echo"]:
		_check(diag.has(key), "diagnostics has key: " + str(key))
	var echo: Dictionary = diag.get("echo", {}) as Dictionary
	_check(echo == {"arena": "yard", "bot_count": 2, "seed": 123456789}, "diagnostics.echo is exactly arena yard, bot_count 2, seed 123456789 (got " + JSON.stringify(echo) + ")")

	# The result must survive the wire format, which is JSON text.
	var round_tripped: Variant = JSON.parse_string(JSON.stringify(result))
	_check(round_tripped is Dictionary, "fight_result survives JSON.stringify")
	_check(int(((round_tripped as Dictionary).get("diagnostics", {}) as Dictionary).get("echo", {}).get("seed", 0)) == 123456789, "seed survives the JSON round trip")

	# Unknown types warn rather than crash.
	_sent.clear()
	bridge.inject_from_host({"type": "nonsense_type", "json": "{}"})
	await _frames(2)
	_check(_type_sent("arena_log") and str(_payload("arena_log").get("level", "")) == "warn", "unknown message type produces an arena_log warn")

	_finish()


func _on_message_sent(type: String, payload: Dictionary) -> void:
	_sent.append({"type": type, "payload": payload})


func _type_sent(type: String) -> bool:
	for entry in _sent:
		if entry["type"] == type:
			return true
	return false


func _payload(type: String) -> Dictionary:
	for entry in _sent:
		if entry["type"] == type:
			return entry["payload"]
	return {}


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		_ok(label)
	else:
		_fail(label)


func _ok(label: String) -> void:
	_checks += 1
	print("PASS  ", label)


func _fail(label: String) -> void:
	_checks += 1
	_failures += 1
	printerr("FAIL  ", label)
	print("FAIL  ", label)


func _finish() -> void:
	print("")
	if _failures == 0:
		print("PASS  bridge contract: %d checks, 0 failures" % _checks)
		quit(0)
	else:
		print("FAIL  bridge contract: %d checks, %d failures" % [_checks, _failures])
		quit(1)
