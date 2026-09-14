extends SceneTree
## Rumble measurement (docs/stage4-spec.md §6). Runs the fight headless with two bots and
## then with three and records the physics step time, so the Rumble decision is made on a
## number rather than a feeling. Skipped by scripts/test-arena.sh (underscore prefix).
##
##   Godot --headless --path Arena --script tests/_rumble_probe.gd -- --secs=30
##
## It runs at real time on purpose. `Performance.TIME_PHYSICS_PROCESS` is the time spent in
## one engine ITERATION, and an iteration can contain several physics steps, so speeding
## the clock up would silently report two or three steps added together as one. Capping
## `max_physics_steps_per_frame` at 1 makes one sample mean exactly one step. The price is
## that the measurement costs its own wall clock time: about a minute for both runs.

const SECS_DEFAULT := 30
const WARMUP_TICKS := 120          # let the bots settle and the countdown finish
const TIME_SCALE := 1.0
const MAX_STEPS := 1

var _fight: Node = null
var _extra_ai: RefCounted = null
var _extra_bot: Node = null


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	Engine.max_physics_steps_per_frame = MAX_STEPS
	Engine.time_scale = TIME_SCALE

	var secs := SECS_DEFAULT
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--secs="):
			secs = int(str(arg).substr(7))

	var two := await _measure(2, secs)
	var three := await _measure(3, secs)

	print("")
	print("--- rumble measurement (%d s each, %s) ---" % [secs, OS.get_name()])
	for row in [two, three]:
		print("%d bots: median %.3f ms, mean %.3f ms, p95 %.3f ms, p99 %.3f ms, worst %.3f ms, %d samples"
			% [int(row["bots"]), float(row["p50_ms"]), float(row["mean_ms"]),
				float(row["p95_ms"]), float(row["p99_ms"]), float(row["worst_ms"]),
				int(row["samples"])])
	print("ratio: median x%.2f, p95 x%.2f"
		% [float(three["p50_ms"]) / maxf(float(two["p50_ms"]), 0.0001),
			float(three["p95_ms"]) / maxf(float(two["p95_ms"]), 0.0001)])
	# The worst case is the spec's bar, but a single sample on a shared machine is noise:
	# another Godot process on the same Mac lands in it. p95 is the number to read, and
	# the median ratio is what says how much a third machine actually costs.
	print("verdict on p95: %s" % ("KEEP (3 bots p95 under 8 ms)"
		if float(three["p95_ms"]) < 8.0 else "CUT (3 bots p95 over 8 ms)"))
	print("verdict on worst: %s" % ("KEEP" if float(three["worst_ms"]) < 8.0 else "CUT"))
	quit(0)


func _measure(bot_count: int, secs: int) -> Dictionary:
	_fight = (load("res://fight/fight.tscn") as PackedScene).instantiate()
	root.add_child(_fight)
	await process_frame

	var config: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://fight/fixtures/stage3_config.json"))
	config["debug"] = {"opponent_ai": "normal", "player_ai": "normal"}
	config["rules"] = {"mode": "fight", "duration_s": 9999, "ko_count_s": 9999}
	_fight.call("start_fight", config)
	await process_frame

	if bot_count >= 3:
		_add_third_bot(config)

	var samples: Array[float] = []
	var target := secs * FightTypes.TICK_HZ
	var ticks := 0
	while ticks < target + WARMUP_TICKS:
		await physics_frame
		ticks += 1
		if _extra_bot != null and is_instance_valid(_extra_bot):
			_drive_third(ticks)
		if ticks > WARMUP_TICKS:
			samples.append(float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)

	root.remove_child(_fight)
	_fight.queue_free()
	_fight = null
	_extra_bot = null
	_extra_ai = null
	await process_frame
	await process_frame

	samples.sort()
	var total := 0.0
	for v in samples:
		total += v
	var count := maxi(samples.size(), 1)
	return {
		"bots": bot_count,
		"samples": samples.size(),
		"mean_ms": total / float(count),
		"worst_ms": samples[count - 1] if samples.size() > 0 else 0.0,
		"p50_ms": samples[int(float(count) * 0.50)] if samples.size() > 2 else 0.0,
		"p95_ms": samples[int(float(count) * 0.95) - 1] if samples.size() > 2 else 0.0,
		"p99_ms": samples[int(float(count) * 0.99) - 1] if samples.size() > 2 else 0.0,
	}


## A third machine, built and driven by the probe rather than by fight.gd. The orchestrator
## is a two bot machine by contract (brief §12 caps the bodies per bot and the bots per
## fight); this measures what a third one would COST before anyone commits to it.
func _add_third_bot(config: Dictionary) -> void:
	var holder: Node = _fight.get("_bots_holder")
	if holder == null:
		return
	var packed: PackedScene = load("res://bot/bot.tscn")
	var bot: Node = packed.instantiate()
	bot.name = "Bot2"
	holder.add_child(bot)
	var bot_config: Dictionary = ((config["bots"] as Array)[1] as Dictionary).duplicate(true)
	bot_config["id"] = "ai-2"
	bot_config["name"] = "Third"
	bot.call("setup", bot_config, 1, RandomNumberGenerator.new())
	bot.call("place_at", Vector3(0.0, 0.25, -3.2), Vector3(0, 0, 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	_extra_ai = (load("res://ai/opponent_ai.gd") as GDScript).new(rng, "normal")
	_extra_bot = bot


func _drive_third(tick: int) -> void:
	var bots: Array = _fight.get("_bots") as Array
	var target: Node = bots[0] if bots[0] != null else bots[1]
	if target == null or _extra_ai == null:
		return
	_extra_bot.call("apply_input", _extra_ai.call("think", _extra_bot, target, {
		"tick": tick, "spike_centre": Vector3.ZERO, "spike_rise_in_s": 999.0,
	}))
