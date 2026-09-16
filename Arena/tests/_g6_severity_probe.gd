extends SceneTree
## G6 measurement probe (skipped by test-arena.sh: leading underscore).
##
## Two jobs:
##   1. a histogram of damage_event severities over a real AI vs AI fight, so the BIG HIT
##      threshold in commentary.gd is derived from the damage model rather than guessed;
##   2. an end to end check that the commentary hooks in fight.gd really fire in a real
##      fight: it prints every line the commentary said and when.
##
##   Godot --headless --path Arena --script tests/_g6_severity_probe.gd -- --w0=axe --w1=axe

var fight: Node
var sev: Array[float] = []
var detached := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://fight/fight.tscn")
	fight = packed.instantiate()
	root.add_child(fight)
	await process_frame
	var cfg_text := FileAccess.get_file_as_string("res://fight/fixtures/stage3_config.json")
	var config: Dictionary = JSON.parse_string(cfg_text)
	config["debug"] = {"opponent_ai": "normal", "player_ai": "normal"}
	var secs := 180
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--w0="):
			config["bots"][0]["weapon"] = a.substr(5)
		if a.begins_with("--w1="):
			config["bots"][1]["weapon"] = a.substr(5)
		if a.begins_with("--arena="):
			config["arena"] = a.substr(8)
		if a.begins_with("--secs="):
			secs = int(a.substr(7))
		if a.begins_with("--enforcer="):
			var rules: Dictionary = config.get("rules", {})
			rules["enforcer"] = a.substr(11)
			config["rules"] = rules
	var rules_out: Dictionary = config.get("rules", {})
	rules_out["duration_s"] = float(secs)
	config["rules"] = rules_out
	fight.start_fight(config)
	await process_frame
	var bots: Array = fight.get("_bots")
	for i in range(2):
		var b = bots[i]
		if b == null:
			print("no bot ", i)
			quit(1)
			return
		b.damage_event.connect(func(info):
			sev.append(float(info.get("severity", 0.0)))
			if bool(info.get("detached", false)):
				detached += 1)
	var ticks := secs * 60 + 400
	var seen := 0
	var cue_reported := false
	for t in range(ticks):
		await physics_frame
		var c = fight.get("_commentary")
		if c != null and c.endgame_fired() and not cue_reported:
			cue_reported = true
			var fx = fight.get("_fx")
			var mix = fx.audio_mix() if fx != null and fx.has_method("audio_mix") else null
			if mix != null:
				print("  CUE: horn voices %d, drone loop %s, endgame_active %s, Ambience %.2f dB"
					% [mix.active_count("endgame_horn"), str(mix.has_loop(AudioMix.ENDGAME_LOOP_KEY)),
					str(mix.endgame_active()),
					AudioServer.get_bus_volume_db(AudioServer.get_bus_index(AudioMix.BUS_AMBIENCE))])
		if c != null:
			var lines: Array = c.said()
			while seen < lines.size():
				print("  [%6.2f s] %s" % [float(fight.get("_tick")) / 60.0, str(lines[seen])])
				seen += 1
		if fight.get("state") == 3:
			print("RESULT at tick ", t)
			break
	sev.sort()
	var n := sev.size()
	print("--- g6 severity probe: %d damage events, %d detached ---" % [n, detached])
	if n == 0:
		quit(0)
		return
	var total := 0.0
	for v in sev:
		total += v
	print("min %.4f  max %.4f  mean %.4f" % [sev[0], sev[n - 1], total / float(n)])
	for q in [0.5, 0.75, 0.9, 0.95, 0.98, 0.99]:
		print("p%02d %.4f" % [int(q * 100.0), sev[mini(int(floor(q * float(n))), n - 1)]])
	for cut in [0.05, 0.1, 0.15, 0.2, 0.3, 0.4, 0.5]:
		var over := 0
		for v in sev:
			if v >= cut:
				over += 1
		print("severity >= %.2f : %d events (%.1f%%)" % [cut, over, 100.0 * float(over) / float(n)])
	quit(0)
